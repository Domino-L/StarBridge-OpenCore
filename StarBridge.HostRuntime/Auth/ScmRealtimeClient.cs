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
    Action<long, string, long, long> fleetBroadcastInvalidated) : IAsyncDisposable
{
    private static readonly TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(15);
    private static readonly TimeSpan AckTimeout = TimeSpan.FromSeconds(10);
    private CancellationTokenSource? _lifetime;
    private Task? _runTask;
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
            try
            {
                var session = _session ?? throw new InvalidOperationException("SCM session is unavailable.");
                var result = await oauthClient.IssueWebSocketTicketAsync(session, cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                _session = result.ActiveSession;
                sessionUpdated(generation, result.ActiveSession);
                using var socket = new ClientWebSocket();
                var endpoint = TicketUri(options.WebSocketEndpoint, result.Ticket.Ticket);
                await socket.ConnectAsync(endpoint, cancellationToken);
                attempt = 0;
                await HeartbeatLoopAsync(socket, generation, cancellationToken);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception) when (exception is WebSocketException or HttpRequestException
                                               or TimeoutException or InvalidOperationException)
            {
                ScmAuthDiagnostics.Write(
                    _session?.CorrelationId ?? "realtime",
                    "presence-websocket",
                    "reconnecting",
                    $"exceptionType={exception.GetType().Name} attempt={attempt + 1}");
            }

            attempt++;
            var delaySeconds = Math.Min(30, 2 * Math.Pow(1.5, Math.Max(0, attempt - 1)));
            await Task.Delay(TimeSpan.FromSeconds(delaySeconds), cancellationToken);
        }
    }

    private async Task HeartbeatLoopAsync(
        ClientWebSocket socket,
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
            while (socket.State == WebSocketState.Open && !connectionToken.IsCancellationRequested)
            {
                (activeBroadcastScope, activeBroadcastScopeRevision) =
                    await SynchronizeFleetBroadcastSubscriptionAsync(
                        socket,
                        activeBroadcastScope,
                        activeBroadcastScopeRevision,
                        connectionToken);
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
                await socket.SendAsync(payload, WebSocketMessageType.Text, true, connectionToken);
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
        ClientWebSocket socket,
        long generation,
        ChannelWriter<int> acknowledgements,
        CancellationToken cancellationToken)
    {
        var buffer = new byte[4096];
        while (socket.State == WebSocketState.Open && !cancellationToken.IsCancellationRequested)
        {
            var result = await socket.ReceiveAsync(buffer, cancellationToken);
            if (result.MessageType == WebSocketMessageType.Close)
            {
                throw new WebSocketException("SCM Presence connection closed.");
            }
            if (!result.EndOfMessage)
            {
                throw new InvalidOperationException("SCM Presence message exceeds the supported size.");
            }
            using var document = JsonDocument.Parse(buffer.AsMemory(0, result.Count));
            var root = document.RootElement;
            if (!root.TryGetProperty("type", out var type))
            {
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

    private async Task<(ScmFleetBroadcastScope? Scope, long Revision)> SynchronizeFleetBroadcastSubscriptionAsync(
        ClientWebSocket socket,
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
        ClientWebSocket socket,
        string type,
        ScmFleetBroadcastScope scope,
        CancellationToken cancellationToken)
    {
        var payload = JsonSerializer.SerializeToUtf8Bytes(new
        {
            type,
            content = new { scopeType = scope.ScopeType, scopeId = scope.ScopeId }
        });
        return socket.SendAsync(payload, WebSocketMessageType.Text, true, cancellationToken);
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
        return ValueTask.CompletedTask;
    }
}
