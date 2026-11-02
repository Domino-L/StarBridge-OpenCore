using System.Net.Http;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading.Channels;

namespace StarBridge.HostRuntime.Auth;

internal sealed class ScmRealtimeClient(
    OAuthPkceClient oauthClient,
    ScmOAuthOptions options,
    string deviceId,
    Action<long, ScmOAuthSession> sessionUpdated,
    Action<long, int> statusUpdated,
    Action<long, string?> forcedLogout,
    Action<long, string, long, long> fleetBroadcastInvalidated,
    Func<CancellationToken, Task<ScmWebSocketTicketResult>>? issueTicket = null,
    Action<long>? disconnected = null,
    Action<long>? marketplaceInvalidated = null,
    Action<long, JsonElement>? tradeNotice = null,
    Func<IScmChatTransport>? transportFactory = null,
    Action<long>? inboxInvalidated = null) : IAsyncDisposable
{
    private static readonly TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan AckTimeout = TimeSpan.FromSeconds(10);
    private CancellationTokenSource? _lifetime;
    private Task? _runTask;
    private Task _stopCompletion = Task.CompletedTask;
    internal Task StopCompletion => _stopCompletion;
    private ScmOAuthSession? _session;
    private readonly object _fleetBroadcastScopeGate = new();
    private ScmFleetBroadcastScope? _fleetBroadcastScope;
    private long _fleetBroadcastScopeRevision;
    private long _generation;

    internal void Start(ScmOAuthSession session)
    {
        if (_session is not null &&
            string.Equals(_session.Subject, session.Subject, StringComparison.Ordinal) &&
            string.Equals(_session.AuthorityId, session.AuthorityId, StringComparison.Ordinal) &&
            _runTask is { IsCompleted: false })
        {
            _session = session;
            return;
        }

        Stop();
        _session = session;
        _lifetime = new CancellationTokenSource();
        var generation = ++_generation;
        _runTask = RunAsync(generation, _lifetime.Token);
    }

    internal void Stop()
    {
        var retiring = _runTask;
        _generation++;
        _lifetime?.Cancel();
        _lifetime?.Dispose();
        _lifetime = null;
        _runTask = null;
        _session = null;
        lock (_fleetBroadcastScopeGate)
        {
            _fleetBroadcastScope = null;
            _fleetBroadcastScopeRevision++;
        }
        if (retiring is not null)
            _stopCompletion = Task.WhenAll(_stopCompletion, ObserveStopAsync(retiring));
    }

    private static async Task ObserveStopAsync(Task task)
    {
        try { await task.ConfigureAwait(false); }
        catch (OperationCanceledException) { }
    }

    internal void SetFleetBroadcastScope(ScmFleetBroadcastScope? scope)
    {
        lock (_fleetBroadcastScopeGate)
        {
            if (Equals(_fleetBroadcastScope, scope))
            {
                return;
            }

            _fleetBroadcastScope = scope;
            _fleetBroadcastScopeRevision++;
        }
    }

    private async Task RunAsync(long generation, CancellationToken cancellationToken)
    {
        var attempt = 0;
        while (!cancellationToken.IsCancellationRequested)
        {
            var probePhase = SessionProbePhase.Ticket;
            var probeStatus = 0;
            var connected = false;
            try
            {
                var session = _session ?? throw new InvalidOperationException("SCM session is unavailable.");
                var result = issueTicket is null
                    ? await oauthClient.IssueWebSocketTicketAsync(session, cancellationToken)
                    : await issueTicket(cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                _session = result.ActiveSession;
                sessionUpdated(generation, result.ActiveSession);
                await using var transport = transportFactory?.Invoke() ?? new ClientWebSocketChatTransport(realtime: true);
                var endpoint = TicketUri(options.WebSocketEndpoint, result.Ticket.Ticket);
                using var connectTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                connectTimeout.CancelAfter(AckTimeout);
                probePhase = SessionProbePhase.Connect;
                try { await transport.ConnectAsync(endpoint, connectTimeout.Token); connected = true; }
                catch
                {
                    probeStatus = (int)((transport as ClientWebSocketChatTransport)?.HttpStatusCode ?? 0);
                    throw;
                }
                probeStatus = (int)((transport as ClientWebSocketChatTransport)?.HttpStatusCode ?? 0);
                ScmSessionProbeDiagnostics.Realtime(probePhase, options.WebSocketEndpoint, probeStatus, attempt + 1, null);
                probePhase = SessionProbePhase.Heartbeat;
                attempt = 0;
                // Reconcile events missed while disconnected, including the initial connection.
                marketplaceInvalidated?.Invoke(generation);
                // This socket is the StarBridge relay (/infra/ws/starbridge). It accepts only
                // member-online-heartbeat, fleet-broadcast-(un)subscribe and ping, and closes on anything
                // else before the first heartbeat registers the device. Never send message-subscribe
                // here (hotfix 10-29); the inbox stays on its periodic REST read.
                await HeartbeatLoopAsync(transport, generation, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception) when (exception is WebSocketException or HttpRequestException
                                               or TimeoutException or InvalidOperationException or JsonException
                                               or OperationCanceledException)
            {
                ScmSessionProbeDiagnostics.Realtime(probePhase, options.WebSocketEndpoint, probeStatus, attempt + 1, exception);
                ScmAuthDiagnostics.Write(
                    _session?.CorrelationId ?? "realtime",
                    "presence-websocket",
                    "reconnecting",
                    $"exceptionType={exception.GetType().Name} attempt={attempt + 1}");
            }
            // Failed ticket/connect attempts are not additional disconnects.
            // Otherwise each retry would trigger another full marketplace read.
            finally { if (connected) disconnected?.Invoke(generation); }

            attempt++;
            var delaySeconds = Math.Min(30, 2 * Math.Pow(1.5, Math.Max(0, attempt - 1)));
            await Task.Delay(TimeSpan.FromSeconds(delaySeconds), cancellationToken);
        }
    }

    private async Task HeartbeatLoopAsync(
        IScmChatTransport socket,
        long generation,
        CancellationToken cancellationToken)
    {
        using var connectionLifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var connectionToken = connectionLifetime.Token;
        var acknowledgements = Channel.CreateBounded<int>(new BoundedChannelOptions(1)
        {
            FullMode = BoundedChannelFullMode.DropOldest,
            SingleReader = true,
            SingleWriter = true
        });
        var receiveTask = ReceiveLoopAsync(
            socket, generation, acknowledgements.Writer, connectionToken);
        ScmFleetBroadcastScope? activeBroadcastScope = null;
        var activeBroadcastScopeRevision = -1L;
        var nextHeartbeatAt = DateTimeOffset.MinValue;
        try
        {
            while (!connectionToken.IsCancellationRequested)
            {
                (activeBroadcastScope, activeBroadcastScopeRevision) =
                    await SynchronizeFleetBroadcastSubscriptionAsync(
                        socket,
                        activeBroadcastScope,
                        activeBroadcastScopeRevision,
                        connectionToken);
                if (receiveTask.IsCompleted)
                {
                    await receiveTask;
                    throw new WebSocketException("SCM Presence receiver stopped.");
                }
                if (DateTimeOffset.UtcNow < nextHeartbeatAt)
                {
                    await Task.Delay(TimeSpan.FromSeconds(1), connectionToken);
                    continue;
                }

                var payload = JsonSerializer.SerializeToUtf8Bytes(new
                {
                    type = "member-online-heartbeat",
                    timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds(),
                    deviceId
                });
                await socket.SendAsync(Encoding.UTF8.GetString(payload), connectionToken);
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(connectionToken);
                timeout.CancelAfter(AckTimeout);
                try
                {
                    statusUpdated(generation, await acknowledgements.Reader.ReadAsync(timeout.Token));
                }
                catch (OperationCanceledException) when (!connectionToken.IsCancellationRequested)
                {
                    throw new TimeoutException("SCM Presence heartbeat was not acknowledged.");
                }
                nextHeartbeatAt = DateTimeOffset.UtcNow.Add(HeartbeatInterval);
            }
        }
        finally
        {
            connectionLifetime.Cancel();
            try
            {
                await receiveTask;
            }
            catch (OperationCanceledException) when (connectionToken.IsCancellationRequested)
            {
            }
        }
    }

    private async Task ReceiveLoopAsync(
        IScmChatTransport socket,
        long generation,
        ChannelWriter<int> acknowledgements,
        CancellationToken cancellationToken)
    {
        while (!cancellationToken.IsCancellationRequested)
        {
            var text = await socket.ReceiveAsync(cancellationToken);
            if (text is null) throw new WebSocketException("SCM Presence connection closed.");
            if (Encoding.UTF8.GetByteCount(text) > 65536) { DiscardFrame(); continue; }
            JsonDocument document;
            try { document = JsonDocument.Parse(text); }
            catch (JsonException) { DiscardFrame(); continue; }
            using var frame = document;
            var root = document.RootElement;
            if (root.ValueKind != JsonValueKind.Object ||
                !root.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.String)
            {
                continue;
            }
            if (type.GetString() == "new-message")
            {
                if (TryNotice(root, out var notice)) tradeNotice?.Invoke(generation, notice);
                else DiscardFrame();
                continue;
            }
            // The initial unread frame is the subscription acknowledgement. No payload
            // identifiers or counts cross the bridge; REST remains authoritative.
            if (type.GetString() == "unread-count-update")
            {
                if (_session?.Capabilities.Contains("profile.read", StringComparer.Ordinal) == true &&
                    TryContent(root, out var unread) && unread.TryGetProperty("total", out var count) &&
                    count.ValueKind == JsonValueKind.Number && count.TryGetInt64(out var total) && total >= 0)
                    inboxInvalidated?.Invoke(generation);
                continue;
            }
            if (type.GetString() == "transaction-event")
            {
                // Only invalidate. The authenticated REST read supplies current roles and state.
                marketplaceInvalidated?.Invoke(generation);
                continue;
            }
            if (type.GetString() == "member-status-update" &&
                root.TryGetProperty("content", out var statusContent) &&
                statusContent.TryGetProperty("signInStatus", out var status) &&
                status.TryGetInt32(out var value) && value is >= 0 and <= 3)
            {
                await acknowledgements.WriteAsync(value, cancellationToken);
                continue;
            }
            if (type.GetString() == "device-force-logout" &&
                root.TryGetProperty("content", out var logoutContent))
            {
                var targetDeviceId = logoutContent.TryGetProperty("deviceId", out var target)
                    ? target.GetString()
                    : null;
                if (targetDeviceId == "*" || string.Equals(targetDeviceId, deviceId, StringComparison.Ordinal))
                {
                    var reason = logoutContent.TryGetProperty("reason", out var reasonElement)
                        ? reasonElement.GetString()
                        : null;
                    forcedLogout(generation, reason);
                    return;
                }
            }
            if (type.GetString() == "fleet-broadcast-invalidated" &&
                root.TryGetProperty("content", out var invalidationContent) &&
                invalidationContent.TryGetProperty("scopeType", out var scopeType) &&
                invalidationContent.TryGetProperty("scopeId", out var scopeId) &&
                invalidationContent.TryGetProperty("resourceVersion", out var resourceVersion) &&
                !string.IsNullOrWhiteSpace(scopeType.GetString()) &&
                scopeId.TryGetInt64(out var scopeIdValue) && scopeIdValue > 0 &&
                resourceVersion.TryGetInt64(out var resourceVersionValue) && resourceVersionValue > 0)
            {
                fleetBroadcastInvalidated(
                    generation,
                    scopeType.GetString()!,
                    scopeIdValue,
                    resourceVersionValue);
            }
        }
    }

    // Never log payloads, identifiers or parser exceptions from an untrusted notice.
    private static void DiscardFrame() =>
        ScmAuthDiagnostics.Write("realtime", "presence-websocket", "frame-discarded", "invalidFrame=true");

    private static bool TryNotice(JsonElement root, out JsonElement notice)
    {
        notice = default;
        try
        {
            if (!TryContent(root, out var content) ||
                !content.TryGetProperty("id", out var id) || id.ValueKind != JsonValueKind.Number ||
                !id.TryGetInt64(out var number) || number <= 0 ||
                !content.TryGetProperty("type", out var type) || type.ValueKind != JsonValueKind.Number ||
                !type.TryGetInt32(out var kind)) return false;
            if (kind == 1 && (!content.TryGetProperty("subType", out var subType) ||
                subType.ValueKind != JsonValueKind.Number || !subType.TryGetInt32(out _))) return false;
            notice = content.Clone();
            return true;
        }
        catch (JsonException) { return false; }
    }

    private static bool TryContent(JsonElement root, out JsonElement content)
    {
        content = default;
        try
        {
            if (!root.TryGetProperty("content", out content)) return false;
            if (content.ValueKind == JsonValueKind.String)
            {
                using var parsed = JsonDocument.Parse(content.GetString()!);
                content = parsed.RootElement.Clone();
            }
            return content.ValueKind == JsonValueKind.Object;
        }
        catch (JsonException) { return false; }
    }

    private async Task<(ScmFleetBroadcastScope? Scope, long Revision)> SynchronizeFleetBroadcastSubscriptionAsync(
        IScmChatTransport socket,
        ScmFleetBroadcastScope? activeScope,
        long activeRevision,
        CancellationToken cancellationToken)
    {
        ScmFleetBroadcastScope? desiredScope;
        long desiredRevision;
        lock (_fleetBroadcastScopeGate)
        {
            desiredScope = _fleetBroadcastScope;
            desiredRevision = _fleetBroadcastScopeRevision;
        }

        if (desiredRevision == activeRevision)
        {
            return (activeScope, activeRevision);
        }

        if (activeScope is not null)
        {
            await SendFleetBroadcastSubscriptionAsync(
                socket,
                "fleet-broadcast-unsubscribe",
                activeScope,
                cancellationToken);
        }
        if (desiredScope is not null)
        {
            await SendFleetBroadcastSubscriptionAsync(
                socket,
                "fleet-broadcast-subscribe",
                desiredScope,
                cancellationToken);
        }

        return (desiredScope, desiredRevision);
    }

    private static Task SendFleetBroadcastSubscriptionAsync(
        IScmChatTransport socket,
        string type,
        ScmFleetBroadcastScope scope,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            type,
            content = new { scopeType = scope.ScopeType, scopeId = scope.ScopeId }
        });
        return socket.SendAsync(Encoding.UTF8.GetString(payload), cancellationToken);
    }

    private static Uri TicketUri(Uri endpoint, string ticket)
    {
        var builder = new UriBuilder(endpoint) { Query = $"ticket={Uri.EscapeDataString(ticket)}" };
        return builder.Uri;
    }

    internal bool IsCurrentGeneration(long generation) =>
        _generation == generation && _runTask is { IsCompleted: false };

    public ValueTask DisposeAsync()
    {
        Stop();
        return new(StopCompletion);
    }
}
