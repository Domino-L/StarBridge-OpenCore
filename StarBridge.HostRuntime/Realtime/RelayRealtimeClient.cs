using System.Net;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Text.Json;

namespace StarBridge.HostRuntime.Realtime;

/// <summary>Host side of realtime event protocol v1
/// (docs/STARBRIDGE_REALTIME_EVENT_PROTOCOL_2026-10-20.md). One connection per
/// signed-in relay credential. While connected it answers the existing
/// <c>social.wait</c>/<c>communities.wait</c> cursors immediately on change; when
/// the gateway is absent (older relay, switch off) or unhealthy, callers keep
/// using the HTTP long polls unchanged.</summary>
internal sealed partial class RelayRealtimeClient : IDisposable
{
    internal enum State { Idle, Connecting, Connected, Unsupported, Backoff }

    private static readonly TimeSpan[] Backoff =
        [TimeSpan.FromSeconds(1), TimeSpan.FromSeconds(2), TimeSpan.FromSeconds(4),
         TimeSpan.FromSeconds(8), TimeSpan.FromSeconds(16), TimeSpan.FromSeconds(30)];
    internal static readonly TimeSpan UnsupportedRetry = TimeSpan.FromMinutes(10);

    private readonly HttpClient _http;
    private readonly Uri _origin;
    private readonly Func<ClientWebSocket> _socketFactory;
    private readonly object _gate = new();
    private readonly Random _jitter = new();
    private CancellationTokenSource? _loop;
    private string? _bearer;
    private State _state = State.Idle;
    // Local cursor exposed to Flutter. A new instance (or a higher version) makes
    // Flutter re-read exactly as with the HTTP activity endpoints.
    private string _instance = Guid.NewGuid().ToString("N");
    private long _socialVersion, _communityVersion;
    private TaskCompletionSource _changed = NewSignal();
    private string? _serverInstance;
    private long _lastSeq = -1;
    private bool _disposed;

    internal RelayRealtimeClient(Uri origin, HttpMessageHandler? handler = null, Func<ClientWebSocket>? socketFactory = null)
    {
        _origin = origin;
        _http = new HttpClient(handler ?? new HttpClientHandler { AllowAutoRedirect = false }, handler is null)
            { Timeout = TimeSpan.FromSeconds(12) };
        _socketFactory = socketFactory ?? (() => new ClientWebSocket());
        EventReceived += ObserveDirectMessageHint;
    }

    internal State CurrentState { get { lock (_gate) return _state; } }

    /// <summary>Local lifecycle codes only (kind, value): ticket status or
    /// failure type, state changes, unexpected attempt failures. Never a
    /// credential, ticket, URL or message body.</summary>
    internal Action<string, string>? Diagnostic { get; set; }

    private void Diag(string kind, string value)
    {
        try { Diagnostic?.Invoke(kind, value); } catch { /* Diagnostics never break the stream. */ }
    }

    /// <summary>Raised for pushed hints after the transport cursor moved.
    /// Consumers invalidate existing reads; direct-message content remains on
    /// the authorized REST history path.</summary>
    internal event Action<string, JsonElement>? EventReceived;

    /// <summary>Starts or keeps the connection for this credential and returns the
    /// current cursor when connected. Returns null when the HTTP long poll must be
    /// used instead.</summary>
    internal async Task<(string Instance, long Version)?> TryWaitAsync(string bearer, bool community,
        string instance, long version, TimeSpan wait, CancellationToken token)
    {
        Task pending;
        lock (_gate)
        {
            token.ThrowIfCancellationRequested();
            if (_disposed) return null;
            if (!string.Equals(_bearer, bearer, StringComparison.Ordinal)) RestartLocked(bearer);
            else if (_state == State.Idle) StartLocked();
            if (_state != State.Connected) return null;
            var current = community ? _communityVersion : _socialVersion;
            if (!string.Equals(instance, _instance, StringComparison.Ordinal) || version < current)
                return (_instance, current);
            pending = _changed.Task;
        }
        try { await pending.WaitAsync(wait, token); }
        catch (TimeoutException) { }
        lock (_gate)
        {
            token.ThrowIfCancellationRequested();
            if (_bearer != bearer) return null;
            // A connection that dropped while waiting still answers with its last
            // cursor; the next wait falls back to HTTP.
            return (_instance, community ? _communityVersion : _socialVersion);
        }
    }

    internal void Stop()
    {
        lock (_gate)
        {
            _loop?.Cancel();
            _loop = null;
            _bearer = null;
            _state = State.Idle;
            ResetCursorLocked();
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            if (_disposed) return;
            _disposed = true;
            _loop?.Cancel();
            _loop = null;
        }
        _http.Dispose();
    }

    private void RestartLocked(string bearer)
    {
        _loop?.Cancel();
        _bearer = bearer;
        // Another account: never reuse cursors or resume another credential's log.
        ResetCursorLocked();
        StartLocked();
    }

    private void ResetCursorLocked()
    {
        _instance = Guid.NewGuid().ToString("N");
        _socialVersion = _communityVersion = 0;
        _serverInstance = null;
        _lastSeq = -1;
        ResetDirectMessageHints();
        if (_directTargetOwner != _bearer || _bearer is null) {
            _directTargets.Clear();
            _directTargetOwner = null;
        }
        Signal();
    }

    private void StartLocked()
    {
        if (_bearer is null) return;
        _loop = new CancellationTokenSource();
        _state = State.Connecting;
        var token = _loop.Token;
        var bearer = _bearer;
        _ = Task.Run(() => RunAsync(bearer, token), CancellationToken.None);
    }

    private async Task RunAsync(string bearer, CancellationToken token)
    {
        var attempt = 0;
        try
        {
            while (!token.IsCancellationRequested)
            {
                Outcome outcome;
                try { outcome = await ConnectOnceAsync(bearer, token); }
                catch (Exception error) when (!token.IsCancellationRequested)
                {
                    // 2026-10-21: any other failure inside one attempt (a malformed
                    // reply, a body cut off by a relay restart) used to end this loop
                    // silently and the Host never asked for a ticket again. It is one
                    // failed attempt; the backoff below retries it.
                    Diag("attempt", error.GetType().Name);
                    outcome = Outcome.Failed;
                }
                if (token.IsCancellationRequested) return;
                TimeSpan delay;
                lock (_gate)
                {
                    token.ThrowIfCancellationRequested();
                    if (outcome == Outcome.Unsupported)
                    {
                        _state = State.Unsupported;
                        delay = UnsupportedRetry;
                        attempt = 0;
                    }
                    else
                    {
                        _state = State.Backoff;
                        if (outcome == Outcome.Reauthenticate) attempt = 0;
                        var baseDelay = outcome == Outcome.Reauthenticate ? TimeSpan.Zero : Backoff[Math.Min(attempt++, Backoff.Length - 1)];
                        delay = baseDelay + TimeSpan.FromMilliseconds(baseDelay.TotalMilliseconds * 0.2 * _jitter.NextDouble());
                    }
                }
                Diag("state", outcome == Outcome.Unsupported ? "unsupported" : outcome == Outcome.Reauthenticate ? "reauthenticate" : "backoff");
                try { await Task.Delay(delay, token); }
                catch (OperationCanceledException) { return; }
                lock (_gate) if (!token.IsCancellationRequested && _state != State.Connected) _state = State.Connecting;
            }
        }
        finally
        {
            // A loop that ends without being cancelled must not leave a stale
            // Connecting state: the next wait starts a new one.
            lock (_gate) if (!token.IsCancellationRequested) _state = State.Idle;
        }
    }

    private enum Outcome { Unsupported, Failed, Reauthenticate }

    private async Task<Outcome> ConnectOnceAsync(string bearer, CancellationToken token)
    {
        string ticket, gateway;
        try
        {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(_origin, "/api/realtime/v1/ticket"));
            request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", bearer);
            using var response = await _http.SendAsync(request, token);
            Diag("ticket", ((int)response.StatusCode).ToString(System.Globalization.CultureInfo.InvariantCulture));
            // Older relays (or the switch off) do not register the route.
            if (response.StatusCode is HttpStatusCode.NotFound or HttpStatusCode.MethodNotAllowed) return Outcome.Unsupported;
            if (!response.IsSuccessStatusCode) return Outcome.Failed;
            using var json = JsonDocument.Parse(await response.Content.ReadAsStringAsync(token));
            var root = json.RootElement;
            if (root.GetProperty("protocol").GetInt32() != 1) return Outcome.Unsupported;
            ticket = root.GetProperty("ticket").GetString() ?? "";
            gateway = root.GetProperty("gateway").GetString() ?? "";
            if (ticket.Length == 0 || !gateway.StartsWith('/')) return Outcome.Failed;
        }
        catch (Exception error) when (error is HttpRequestException or JsonException or InvalidOperationException
                                          or KeyNotFoundException or TaskCanceledException)
        {
            Diag("ticket", error.GetType().Name);
            return Outcome.Failed;
        }

        using var socket = _socketFactory();
        try
        {
            var ws = new UriBuilder(new Uri(_origin, gateway))
            {
                Scheme = _origin.Scheme == "https" ? "wss" : "ws",
                Query = "ticket=" + Uri.EscapeDataString(ticket)
            }.Uri;
            await socket.ConnectAsync(ws, token);
            var hello = await ReceiveAsync(socket, TimeSpan.FromSeconds(10), token);
            if (hello?.Op != "hello") return Outcome.Failed;
            var heartbeat = TimeSpan.FromMilliseconds(Math.Clamp(
                hello.Value.D.GetProperty("heartbeatIntervalMs").GetInt32(), 5000, 60000));
            string? resumeInstance; long resumeAfter;
            lock (_gate) { resumeInstance = _serverInstance; resumeAfter = _lastSeq; }
            if (resumeInstance is not null && resumeAfter >= 0)
                await SendAsync(socket, "resume", new { instance = resumeInstance, afterSeq = resumeAfter }, token);
            else
                await SendAsync(socket, "identify", new { protocol = 1, client = "starbridge-host" }, token);

            while (true)
            {
                var reply = await ReceiveAsync(socket, TimeSpan.FromSeconds(10), token);
                if (reply is null) return Outcome.Failed;
                var (op, d) = reply.Value;
                if (op is "ready" or "resumed")
                {
                    lock (_gate)
                    {
                        token.ThrowIfCancellationRequested();
                        if (op == "ready")
                        {
                            // Missed history cannot be replayed: let every reader re-read once.
                            _serverInstance = d.GetProperty("instance").GetString();
                            _lastSeq = d.GetProperty("latestSeq").GetInt64();
                            _socialVersion++;
                            _communityVersion++;
                        }
                        _state = State.Connected;
                        // A replacement connection must prove DM delivery again.
                        ResetDirectMessageHints();
                        Signal();
                    }
                    Diag("state", "connected");
                    break;
                }
                if (op == "invalidSession")
                {
                    lock (_gate) { token.ThrowIfCancellationRequested(); _serverInstance = null; _lastSeq = -1; }
                    await SendAsync(socket, "identify", new { protocol = 1, client = "starbridge-host" }, token);
                    continue;
                }
                return Outcome.Failed;
            }

            return await SessionAsync(socket, heartbeat, token);
        }
        catch (Exception error) when (error is WebSocketException or JsonException or InvalidOperationException
                                          or KeyNotFoundException or OperationCanceledException)
        {
            if (socket.CloseStatus == (WebSocketCloseStatus)4000) return Outcome.Reauthenticate;
            return Outcome.Failed;
        }
        finally
        {
            lock (_gate) if (!token.IsCancellationRequested && _state == State.Connected) _state = State.Backoff;
        }
    }

    private async Task<Outcome> SessionAsync(ClientWebSocket socket, TimeSpan heartbeat, CancellationToken token)
    {
        using var session = CancellationTokenSource.CreateLinkedTokenSource(token);
        var lastServerMessage = Environment.TickCount64;
        var unanswered = 0;
        var heartbeats = Task.Run(async () =>
        {
            while (!session.IsCancellationRequested)
            {
                var jitter = TimeSpan.FromMilliseconds(heartbeat.TotalMilliseconds * 0.1 * _jitter.NextDouble());
                await Task.Delay(heartbeat + jitter, session.Token);
                if (Interlocked.Increment(ref unanswered) > 2)
                {
                    // Two intervals without a reply: drop and reconnect.
                    session.Cancel();
                    return;
                }
                long ack;
                lock (_gate) ack = _lastSeq;
                await SendAsync(socket, "heartbeat", new { ack }, session.Token);
            }
        }, CancellationToken.None);
        try
        {
            while (!session.IsCancellationRequested)
            {
                var message = await ReceiveAsync(socket, Timeout.InfiniteTimeSpan, session.Token);
                if (message is null)
                    return socket.CloseStatus == (WebSocketCloseStatus)4000 ? Outcome.Reauthenticate : Outcome.Failed;
                Interlocked.Exchange(ref unanswered, 0);
                lastServerMessage = Environment.TickCount64;
                var (op, d) = message.Value;
                if (op == "events") Apply(d.GetProperty("events"), token);
                else if (op == "heartbeatAck")
                {
                    long behind;
                    lock (_gate) behind = d.GetProperty("latestSeq").GetInt64() - _lastSeq;
                    // The server is ahead but sent nothing: reconnect and resume.
                    if (behind > 0) return Outcome.Failed;
                }
                else if (op == "invalidSession") return Outcome.Failed;
            }
            return Outcome.Failed;
        }
        finally
        {
            session.Cancel();
            try { await heartbeats; } catch (Exception) { }
        }
    }

    internal void Apply(JsonElement events, CancellationToken token = default)
    {
        var raised = new List<(string, JsonElement)>();
        lock (_gate)
        {
            token.ThrowIfCancellationRequested();
            var social = false; var community = false;
            foreach (var e in events.EnumerateArray())
            {
                if (e.ValueKind != JsonValueKind.Object ||
                    !e.TryGetProperty("seq", out var sequence) || sequence.ValueKind != JsonValueKind.Number ||
                    !sequence.TryGetInt64(out var seq) || seq < 0) continue;
                if (seq <= _lastSeq) continue; // duplicate after resume
                _lastSeq = seq;
                var type = e.TryGetProperty("type", out var kind) && kind.ValueKind == JsonValueKind.String
                    ? kind.GetString() ?? "" : "";
                if (type.StartsWith("community.", StringComparison.Ordinal)) community = true;
                else if (type != "dm.message.created") social = true;
                raised.Add((type, e.TryGetProperty("data", out var data) ? data.Clone() : default));
            }
            if (social) _genericSocialVersion = ++_socialVersion;
            if (community) _communityVersion++;
            if (social || community) Signal();
            // Serialize hint delivery with Stop/account replacement. Subscribers
            // only invalidate local cursors; content is still read through REST.
            foreach (var (type, data) in raised)
                try { EventReceived?.Invoke(type, data); } catch { /* Observers cannot break the stream. */ }
        }
    }

    private void Signal()
    {
        var previous = _changed;
        _changed = NewSignal();
        previous.TrySetResult();
    }

    private static TaskCompletionSource NewSignal() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    private static Task SendAsync(ClientWebSocket socket, string op, object d, CancellationToken token) =>
        socket.SendAsync(JsonSerializer.SerializeToUtf8Bytes(new { op, d }), WebSocketMessageType.Text, true, token);

    private static async Task<(string Op, JsonElement D)?> ReceiveAsync(ClientWebSocket socket, TimeSpan limit, CancellationToken token)
    {
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token);
        if (limit != Timeout.InfiniteTimeSpan) timeout.CancelAfter(limit);
        var buffer = new byte[64 * 1024];
        var count = 0;
        while (true)
        {
            if (count == buffer.Length) return null;
            var result = await socket.ReceiveAsync(buffer.AsMemory(count), timeout.Token);
            if (result.MessageType == WebSocketMessageType.Close) return null;
            count += result.Count;
            if (result.EndOfMessage) break;
        }
        using var json = JsonDocument.Parse(buffer.AsMemory(0, count));
        var root = json.RootElement;
        return (root.GetProperty("op").GetString() ?? "", root.GetProperty("d").Clone());
    }
}
