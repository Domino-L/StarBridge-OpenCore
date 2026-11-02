using System.Net.WebSockets;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

/// <summary>One text WebSocket; the fixture replaces it in tests.</summary>
internal interface IScmChatTransport : IAsyncDisposable
{
    Task ConnectAsync(Uri endpoint, CancellationToken token);
    Task SendAsync(string text, CancellationToken token);
    /// <summary>The next text frame, or null when the server closed.</summary>
    Task<string?> ReceiveAsync(CancellationToken token);
}

internal sealed class ClientWebSocketChatTransport : IScmChatTransport
{
    // No Origin header: SCM only checks Origin when a browser sends one.
    private readonly ClientWebSocket _socket = new();
    internal System.Net.HttpStatusCode HttpStatusCode => _socket.HttpStatusCode;
    private readonly bool _realtime;
    internal ClientWebSocketChatTransport(bool realtime = false) {
        _realtime = realtime;
        if (realtime) ScmSessionProbeDiagnostics.Configure(_socket);
    }

    public Task ConnectAsync(Uri endpoint, CancellationToken token) => _socket.ConnectAsync(endpoint, token);

    public Task SendAsync(string text, CancellationToken token) =>
        _socket.SendAsync(Encoding.UTF8.GetBytes(text), WebSocketMessageType.Text, true, token);

    public async Task<string?> ReceiveAsync(CancellationToken token)
    {
        var buffer = new byte[8192];
        using var message = new MemoryStream();
        var discarded = false;
        while (true)
        {
            var result = await _socket.ReceiveAsync(buffer, token);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            if (_realtime && message.Length + result.Count > 65536) discarded = true;
            if (!discarded)
            {
                if (message.Length + result.Count > 262144) throw new InvalidOperationException("SCM chat frame too large.");
                message.Write(buffer, 0, result.Count);
            }
            if (result.EndOfMessage)
            {
                if (!discarded) return Encoding.UTF8.GetString(message.ToArray());
                ScmAuthDiagnostics.Write("realtime", "presence-websocket", "frame-discarded", "oversizedFrame=true");
                message.SetLength(0);
                discarded = false;
            }
        }
    }

    public ValueTask DisposeAsync()
    {
        _socket.Dispose();
        return ValueTask.CompletedTask;
    }
}

/// <summary>One live push from SCM: <c>message</c> (from the other member), <c>echo</c> (sent by this
/// member elsewhere, e.g. the SCM site), <c>sent</c> (sent from here), <c>unread</c>, or <c>resync</c>
/// after (re)connecting, when anything may have been missed.</summary>
internal sealed record ScmChatPush(string Kind, JsonElement Content);

/// <summary>The outcome of one send: SCM accepted it, refused it, or the answer never came.</summary>
internal sealed record ScmChatSendResult(string Status, JsonElement Message, string? Reason);

/// <summary>SCM trade-message socket (0.7.2 G9): <c>/infra/ws/chat?ticket=</c> with a one-time
/// ticket, <c>chat-subscribe</c> for the open conversation, <c>chat-heartbeat</c>, reconnect with
/// backoff. Pushes carry the message itself so the client shows it at once; REST reads only reconcile.
/// Stays connected for the whole signed-in session. A send goes out once and is never replayed.</summary>
internal sealed class ScmChatConnection : IAsyncDisposable
{
    internal static TimeSpan HeartbeatInterval = TimeSpan.FromSeconds(25);
    internal static TimeSpan ReplyTimeout = TimeSpan.FromSeconds(10);
    private static readonly TimeSpan SilenceLimit = TimeSpan.FromSeconds(75);

    private readonly Uri _endpoint;
    private readonly Func<CancellationToken, Task<string>> _issueTicket;
    private readonly Func<IScmChatTransport> _transport;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly object _gate = new();
    private readonly Dictionary<string, TaskCompletionSource<ScmChatSendResult>> _pending = new(StringComparer.Ordinal);
    private TaskCompletionSource<IScmChatTransport> _open = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private readonly Task _run;
    private long? _focus;
    private Action<ScmChatPush> _pushed;

    internal ScmChatConnection(Uri endpoint, Func<CancellationToken, Task<string>> issueTicket,
        Func<IScmChatTransport> transport, Action<ScmChatPush> pushed)
    {
        _endpoint = endpoint;
        _issueTicket = issueTicket;
        _transport = transport;
        _pushed = pushed;
        _run = Task.Run(() => RunAsync(_lifetime.Token));
    }

    internal void OnPush(Action<ScmChatPush> pushed) => Volatile.Write(ref _pushed, pushed);

    private void Push(string kind, JsonElement content = default)
    {
        try { Volatile.Read(ref _pushed)(new ScmChatPush(kind, content)); }
        catch (Exception exception) when (exception is not OperationCanceledException)
        {
            ScmAuthDiagnostics.Write("chat", "chat-websocket", "push-failed", $"kind={kind} exceptionType={exception.GetType().Name}");
        }
    }

    internal bool Faulted { get; private set; }

    private static string Frame(string type, object content) =>
        JsonSerializer.Serialize(new { type, content = JsonSerializer.Serialize(content) });

    /// <summary>Which conversation is open. SCM marks incoming messages from that member read.</summary>
    internal async Task FocusAsync(long? peer, CancellationToken token)
    {
        lock (_gate) _focus = peer;
        var socket = await WaitOpenAsync(token);
        await socket.SendAsync(Frame("chat-subscribe", new { otherUserId = peer }), token);
    }

    internal static void ValidateClientMessageId(string? id)
    {
        if (id is not null && (id.Length is < 8 or > 64 ||
            id.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-')))
            throw new Account.AccountBridgeHostException("marketplace.invalid_request");
    }

    internal async Task<ScmChatSendResult> SendAsync(long toUserId, string content, string? quoteType,
        string? quoteId, CancellationToken token, string? clientMessageId = null)
    {
        ValidateClientMessageId(clientMessageId);
        clientMessageId ??= Guid.NewGuid().ToString("N");
        TaskCompletionSource<ScmChatSendResult> reply;
        bool ownsSend;
        lock (_gate)
        {
            ownsSend = !_pending.TryGetValue(clientMessageId, out reply!);
            if (ownsSend)
                _pending.Add(clientMessageId, reply = new(TaskCreationOptions.RunContinuationsAsynchronously));
        }
        // Register before waiting for a connection: concurrent callers share even the connect failure.
        if (!ownsSend) return await reply.Task;
        try
        {
            var socket = await WaitOpenAsync(token);
            if (reply.Task.IsCompleted) return await reply.Task;
            await socket.SendAsync(Frame("chat-send", new { clientMessageId, toUserId, content, quoteType, quoteId }), token);
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
            timeout.CancelAfter(ReplyTimeout);
            try { await reply.Task.WaitAsync(timeout.Token); }
            catch (OperationCanceledException) when (!token.IsCancellationRequested)
            {
                reply.TrySetResult(new ScmChatSendResult("uncertain", default, null));
            }
        }
        catch (OperationCanceledException) { reply.TrySetCanceled(token); }
        catch (Exception exception) { reply.TrySetException(exception); }
        finally { lock (_gate) _pending.Remove(clientMessageId); }
        return await reply.Task;
    }

    private async Task<IScmChatTransport> WaitOpenAsync(CancellationToken token)
    {
        Task<IScmChatTransport> open;
        lock (_gate) open = _open.Task;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
        timeout.CancelAfter(ReplyTimeout);
        try { return await open.WaitAsync(timeout.Token); }
        catch (OperationCanceledException) when (!token.IsCancellationRequested)
        {
            throw new Account.AccountBridgeHostException("marketplace.unavailable");
        }
    }

    // Stable business outcomes emitted by OAuthPkceClient.TradeRejection.
    // Do not infer refusal from a generic Host exception (e.g. unavailable).
    private static bool IsTicketBusinessRejection(string code) => code is
        "marketplace.trade_rejected" or "marketplace.account_unbound" or
        "marketplace.trade_time_required" or "marketplace.contact_required" or
        "marketplace.account_abnormal" or "marketplace.account_banned" or
        "marketplace.own_listing" or "marketplace.listing_limit" or
        "marketplace.listing_same_item_limit" or "marketplace.listing_manifest_limit" or
        "marketplace.listing_item_invalid" or "marketplace.listing_invalid" or
        "marketplace.listing_has_ongoing" or "marketplace.listing_cannot_publish" or
        "marketplace.listing_quantity_below_ongoing" or "marketplace.checklist_invalid" or
        "marketplace.template_limit" or "marketplace.template_system" or "marketplace.not_owner";

    private async Task RunAsync(CancellationToken lifetime)
    {
        var attempt = 0;
        while (!lifetime.IsCancellationRequested)
        {
            var transport = _transport();
            var ticketIssued = false;
            try
            {
                var ticket = await _issueTicket(lifetime);
                ticketIssued = true;
                var builder = new UriBuilder(_endpoint) { Query = "ticket=" + Uri.EscapeDataString(ticket) };
                using var connect = CancellationTokenSource.CreateLinkedTokenSource(lifetime);
                connect.CancelAfter(ReplyTimeout);
                await transport.ConnectAsync(builder.Uri, connect.Token);
                long? focus;
                lock (_gate) focus = _focus;
                await transport.SendAsync(Frame("chat-subscribe", new { otherUserId = focus }), lifetime);
                attempt = 0;
                lock (_gate) _open.TrySetResult(transport);
                // Messages may have arrived while disconnected.
                Push("resync");
                await PumpAsync(transport, lifetime);
            }
            catch (OperationCanceledException) when (lifetime.IsCancellationRequested) { return; }
            catch (Account.AccountBridgeHostException exception) when ((!ticketIssued && IsTicketBusinessRejection(exception.Code)) || exception.Code is "marketplace.reauthorize_required" or "marketplace.sign_in_required" or "marketplace.forbidden")
            {
                // Only explicit ticket refusals stop reconnecting; temporary failures use backoff.
                // A later explicit chat request may start a new connection after a terminal refusal.
                Faulted = true;
                FailPending();
                return;
            }
            catch (Exception exception) when (exception is WebSocketException or HttpRequestException or TimeoutException
                                               or InvalidOperationException or JsonException or OperationCanceledException
                                               or Account.AccountBridgeHostException)
            {
                ScmAuthDiagnostics.Write("chat", "chat-websocket", "reconnecting",
                    $"exceptionType={exception.GetType().Name} attempt={attempt + 1}");
            }
            finally
            {
                lock (_gate)
                {
                    if (_open.Task.IsCompleted)
                        _open = new(TaskCreationOptions.RunContinuationsAsynchronously);
                }
                FailPending();
                await transport.DisposeAsync();
            }
            attempt++;
            var delay = Math.Min(30, 2 * Math.Pow(1.5, attempt - 1));
            try { await Task.Delay(TimeSpan.FromSeconds(delay), lifetime); }
            catch (OperationCanceledException) { return; }
        }
    }

    // A send whose socket dropped may or may not have reached SCM.
    private void FailPending()
    {
        lock (_gate)
            foreach (var reply in _pending.Values)
                reply.TrySetResult(new ScmChatSendResult("uncertain", default, null));
    }

    private async Task PumpAsync(IScmChatTransport transport, CancellationToken lifetime)
    {
        using var connection = CancellationTokenSource.CreateLinkedTokenSource(lifetime);
        var heartbeat = Task.Run(async () =>
        {
            while (!connection.IsCancellationRequested)
            {
                await Task.Delay(HeartbeatInterval, connection.Token);
                await transport.SendAsync(Frame("chat-heartbeat", new { timestamp = DateTimeOffset.UtcNow.ToUnixTimeMilliseconds() }), connection.Token);
            }
        });
        try
        {
            while (true)
            {
                using var silence = CancellationTokenSource.CreateLinkedTokenSource(connection.Token);
                silence.CancelAfter(SilenceLimit);
                string? text;
                try { text = await transport.ReceiveAsync(silence.Token); }
                catch (OperationCanceledException) when (!lifetime.IsCancellationRequested)
                {
                    throw new TimeoutException("SCM chat went silent.");
                }
                if (text is null) throw new WebSocketException("SCM chat closed.");
                Dispatch(text);
                if (heartbeat.IsFaulted) await heartbeat;
            }
        }
        finally
        {
            connection.Cancel();
            try { await heartbeat; } catch (OperationCanceledException) { } catch (WebSocketException) { }
        }
    }

    private void Dispatch(string text)
    {
        using var document = JsonDocument.Parse(text);
        var root = document.RootElement;
        if (root.ValueKind != JsonValueKind.Object || !root.TryGetProperty("type", out var typeElement)) return;
        var content = root.TryGetProperty("content", out var c) ? c : default;
        if (content.ValueKind == JsonValueKind.String)
        {
            try { content = JsonDocument.Parse(content.GetString()!).RootElement.Clone(); }
            catch (JsonException) { content = default; }
        }
        switch (typeElement.GetString())
        {
            case "chat-send-result":
            {
                if (content.ValueKind != JsonValueKind.Object ||
                    !content.TryGetProperty("clientMessageId", out var idElement) || idElement.GetString() is not { } id) return;
                TaskCompletionSource<ScmChatSendResult>? reply;
                lock (_gate) _pending.TryGetValue(id, out reply);
                var accepted = content.TryGetProperty("success", out var ok) && ok.ValueKind == JsonValueKind.True;
                var reason = content.TryGetProperty("error", out var e) && e.ValueKind == JsonValueKind.String ? e.GetString() : null;
                reply?.TrySetResult(accepted
                    ? new ScmChatSendResult("sent", content.TryGetProperty("message", out var m) ? m.Clone() : default, null)
                    : new ScmChatSendResult("rejected", default, reason is { Length: > 200 } ? reason[..200] : reason));
                if (accepted && content.TryGetProperty("message", out var sent) && sent.ValueKind == JsonValueKind.Object) Push("sent", sent.Clone());
                return;
            }
            case "new-chat-message":
                if (content.ValueKind == JsonValueKind.Object) Push("message", content.Clone());
                return;
            // Proposed SCM addition: a member's own message, sent from another device, echoed back.
            case "chat-message-echo":
                if (content.ValueKind == JsonValueKind.Object) Push("echo", content.Clone());
                return;
            case "chat-unread-count":
                if (content.ValueKind == JsonValueKind.Number) Push("unread", content.Clone());
                return;
        }
    }

    public async ValueTask DisposeAsync()
    {
        _lifetime.Cancel();
        try { await _run; } catch (OperationCanceledException) { }
        _lifetime.Dispose();
    }
}
