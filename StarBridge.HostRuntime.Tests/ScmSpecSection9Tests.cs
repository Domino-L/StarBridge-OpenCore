using System.Collections.Concurrent;
using System.Net;
using System.Reflection;
using System.Text.Json;
using System.Threading.Channels;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// Offline client contract tests. Server fan-out is an explicit fixture input, not server acceptance.
internal static class ScmSpecSection9Tests
{
    private const string TokenMarker = "SPEC9-SYNTHETIC-TOKEN-MARKER";
    private const string MsgMarker = "SPEC9-SERVER-MSG-MARKER";
    private const string IdMarker = "SPEC9-CLIENT-ID-MARKER";
    private static readonly Uri Endpoint = new("https://fixture.invalid/");
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("SPEC9: " + message);
    }
    private static async Task Until(Func<bool> ready)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(10));
        while (!ready()) await Task.Delay(10, timeout.Token);
    }
    private static string Frame(string type, object body) =>
        JsonSerializer.Serialize(new { type, content = JsonSerializer.Serialize(body) });
    private static JsonElement Body(string frame)
    {
        using var doc = JsonDocument.Parse(frame);
        using var body = JsonDocument.Parse(doc.RootElement.GetProperty("content").GetString()!);
        return body.RootElement.Clone();
    }
    private static string Type(string frame)
    {
        using var doc = JsonDocument.Parse(frame);
        return doc.RootElement.GetProperty("type").GetString()!;
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }
    private sealed class Handler(long self) : HttpMessageHandler
    {
        internal int Tickets;
        internal int? ErrorCode;
        internal readonly ConcurrentQueue<string> Paths = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid", "unexpected fixture host");
            var path = request.RequestUri.AbsolutePath;
            Paths.Enqueue(path);
            object data = path switch
            {
                "/app-api/member/user/get" => new { id = self },
                "/app-api/member/chat/ws-ticket" => "synthetic-ticket-" + Interlocked.Increment(ref Tickets),
                _ when ErrorCode is not null => new { },
                _ => throw new Exception("Unexpected fake route: " + path),
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(JsonSerializer.Serialize(new {
                    code = ErrorCode ?? 0, data, msg = MsgMarker,
                    access_token = TokenMarker, clientMessageId = IdMarker })) });
        }
    }
    private sealed class Socket : IScmChatTransport
    {
        private readonly Channel<string?> _inbox = Channel.CreateUnbounded<string?>();
        internal readonly ConcurrentQueue<string> Sent = new();
        internal readonly ConcurrentQueue<string> Delivered = new();
        internal Uri? Connected;
        internal bool Disposed;
        public Task ConnectAsync(Uri endpoint, CancellationToken token)
        {
            Check(endpoint.Host == "fixture.invalid", "unexpected socket host");
            Connected = endpoint;
            return Task.CompletedTask;
        }
        public Task SendAsync(string text, CancellationToken token) { Sent.Enqueue(text); return Task.CompletedTask; }
        internal void Push(string type, object body)
        {
            var frame = Frame(type, body);
            Delivered.Enqueue(frame);
            _inbox.Writer.TryWrite(frame);
        }
        internal void Close() => _inbox.Writer.TryWrite(null);
        public async Task<string?> ReceiveAsync(CancellationToken token) => await _inbox.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }
    private sealed class Peer : IAsyncDisposable
    {
        internal readonly Handler Http;
        internal readonly OAuthPkceClient Client;
        internal readonly ScmOAuthSession Session;
        internal readonly ConcurrentQueue<Socket> Sockets = new();
        internal readonly ConcurrentQueue<JsonElement> Pushes = new();
        internal readonly ScmChatConnection Connection;
        internal Peer(long self)
        {
            Http = new Handler(self);
            Client = Create(Http);
            Session = new("fixture", "synthetic-owner-" + self, "Fixture", TokenMarker,
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "trade.read", "trade.write"]);
            Client.ChatTransport = () => { var socket = new Socket(); Sockets.Enqueue(socket); return socket; };
            Connection = Client.StartChat(OAuthPkceClient.ChatOwner(Session),
                async t => (await Client.IssueChatTicketAsync(Session, t)).Ticket,
                payload => Pushes.Enqueue(BridgePayload.From(payload)));
        }
        internal Socket Live => Sockets.Last();
        internal int Count(string kind) => Pushes.Count(p => p.GetProperty("kind").GetString() == kind);
        internal async Task Ready() => await Until(() => Count("resync") > 0);
        // FIFO barrier: once the unread sentinel is projected, all previous frames were dispatched.
        internal async Task Drain()
        {
            var count = Count("unread");
            Live.Push("chat-unread-count", 17);
            await Until(() => Count("unread") == count + 1);
        }
        internal async Task<JsonElement> Send(string id)
        {
            var reference = Client.ChatPeerReference(OAuthPkceClient.ChatOwner(Session), 909);
            var result = await Client.MarketplaceChatAsync(Session, BridgePayload.From(new {
                schemaVersion = 1, operation = "send", @ref = reference, content = "fixture message", clientMessageId = id
            }), () => true, () => Connection, default);
            return BridgePayload.From(result.Data);
        }
        public async ValueTask DisposeAsync() => await Client.StopChatAsync();
    }
    private static OAuthPkceClient Create(Handler handler) => new(new ScmHttpClient(handler), new Vault(),
        new("fixture", Endpoint, Endpoint, Endpoint, "fixture", "starbridge-api", "", "/callback"));
    private static object Message() => new { id = 700, fromUserId = 4242, toUserId = 909,
        fromUserNickname = "Synthetic sender", content = "fixture message", isRead = 0, createTime = 1760000000000 };
    private static void Reply(Socket socket, string id, bool success = true) => socket.Push("chat-send-result",
        new { success, clientMessageId = id, message = Message(), error = MsgMarker });

    private static async Task MultiEndAndDuplicates()
    {
        await using var a = new Peer(4242);
        await using var b = new Peer(4242);
        await using var receiver = new Peer(909);
        await Task.WhenAll(a.Ready(), b.Ready(), receiver.Ready());
        var first = a.Send(IdMarker);
        var retryPending = a.Send(IdMarker);
        await Until(() => a.Live.Sent.Any(f => Type(f) == "chat-send"));
        // The fixture models SCM routing: only A gets the receipt; B and receiver get new-chat-message.
        b.Live.Push("new-chat-message", Message());
        receiver.Live.Push("new-chat-message", Message());
        await Task.WhenAll(b.Drain(), receiver.Drain());
        Check(!first.IsCompleted && !retryPending.IsCompleted, "other-end sync completed origin pending");
        var own = b.Pushes.Single(p => p.GetProperty("kind").GetString() == "message");
        Check(own.GetProperty("message").GetProperty("mine").GetBoolean() && !own.TryGetProperty("name", out _),
            "own message direction/name");
        var incoming = receiver.Pushes.Single(p => p.GetProperty("kind").GetString() == "message");
        Check(!incoming.GetProperty("message").GetProperty("mine").GetBoolean() &&
            incoming.GetProperty("name").GetString() == "Synthetic sender", "receiver direction/name");
        Check(b.Count("unread") == 1 && receiver.Count("unread") == 1, "message synthesized unread push");
        Reply(a.Live, IdMarker);
        var results = await Task.WhenAll(first, retryPending).WaitAsync(TimeSpan.FromSeconds(10));
        Check(results.All(r => r.GetProperty("status").GetString() == "sent"), "origin receipt result");
        Check(a.Live.Sent.Count(f => Type(f) == "chat-send") == 1, "pending retries sent more than one frame");
        Check(Body(a.Live.Sent.Single(f => Type(f) == "chat-send")).GetProperty("clientMessageId").GetString() == IdMarker,
            "bridge changed stable id");
        Check(a.Live.Delivered.Count(f => Type(f) == "chat-send-result") == 1 &&
            !a.Live.Delivered.Any(f => Type(f) == "new-chat-message") &&
            !b.Live.Delivered.Any(f => Type(f) == "chat-send-result"), "fixture routing contract");
        // SPEC-GAP: Host forwards duplicate server ids; Flutter owns message-id deduplication.
        b.Live.Push("new-chat-message", Message());
        await b.Drain();
        var duplicates = b.Pushes.Where(p => p.GetProperty("kind").GetString() == "message").ToArray();
        Check(duplicates.Length == 2 && duplicates[0].GetRawText() == duplicates[1].GetRawText(), "Host duplicate forwarding changed");
        Check(b.Count("unread") == 2, "own duplicate synthesized unread beyond barrier sentinels");
        Reply(b.Live, IdMarker, false);
        var disconnected = b.Live;
        disconnected.Close();
        await Until(() => disconnected.Disposed);
        Reply(a.Live, IdMarker, false);
        await a.Drain();
        Check(results.All(r => r.GetProperty("status").GetString() == "sent") &&
            (await first).GetRawText() == results[0].GetRawText(), "late failure changed confirmed result");
        // SPEC-GAP: only pending calls coalesce; after completion a retry emits another frame with the SAME id.
        // This preserves section 6.3 server idempotency, but is not lifetime one-frame-per-id suppression.
        var retryCompleted = a.Send(IdMarker);
        await Until(() => a.Live.Sent.Count(f => Type(f) == "chat-send") == 2);
        Check(a.Live.Sent.Where(f => Type(f) == "chat-send").All(f => Body(f).GetProperty("clientMessageId").GetString() == IdMarker),
            "completed retry changed id");
        Reply(a.Live, IdMarker);
        Check((await retryCompleted.WaitAsync(TimeSpan.FromSeconds(10))).GetProperty("status").GetString() == "sent", "retry receipt");
    }
    private static async Task Reconnect()
    {
        await using var peer = new Peer(4242);
        await peer.Ready();
        await peer.Connection.FocusAsync(909, default);
        for (var i = 1; i <= 2; i++)
        {
            peer.Live.Close();
            var expected = i + 1;
            await Until(() => peer.Count("resync") == expected);
            Check(peer.Http.Tickets == expected && peer.Sockets.Count == expected, "reconnect did not fetch new ticket");
            var subscribe = peer.Live.Sent.First();
            Check(Type(subscribe) == "chat-subscribe" && Body(subscribe).GetProperty("otherUserId").GetInt64() == 909,
                "reconnect lost subscription/focus");
        }
        var queries = peer.Sockets.Select(s => s.Connected!.Query).ToArray();
        Check(queries.Distinct().Count() == 3 && queries.SequenceEqual(new[] {
            "?ticket=synthetic-ticket-1", "?ticket=synthetic-ticket-2", "?ticket=synthetic-ticket-3" }), "ticket reused");
        Check(peer.Http.Paths.Count(p => p == "/app-api/member/chat/ws-ticket") == 3, "ticket HTTP count");
        // Host signals resync. Fetching/merging history, conversations and unread is Flutter's responsibility.
    }
    private static async Task BusinessCodes()
    {
        foreach (var code in new[] { 401, 403, 500 })
        {
            var handler = new Handler(4242) { ErrorCode = code };
            var client = Create(handler);
            var session = new ScmOAuthSession("fixture", "synthetic-owner", "Fixture", TokenMarker,
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            Exception? error = null;
            try { await client.GetDesktopDeviceStatusAsync(session, "synthetic-device", default); }
            catch (Exception ex) { error = ex; }
            Check(code switch { 401 => error is ScmApiAuthenticationException, 403 => error is ScmApiForbiddenException,
                _ => error is ScmApiUnavailableException }, "HTTP 200 business code mapping: " + code);
            Check(handler.Paths.Count == 1, "business error was not exercised through fake HTTP");
        }
    }
    private static async Task Diagnostics()
    {
        foreach (var methodName in new[] { "ExchangeCodeAsync", "RefreshTokenAsync" })
        {
            var client = Create(new Handler(4242) { ErrorCode = 500 });
            var method = typeof(OAuthPkceClient).GetMethod(methodName, BindingFlags.Instance | BindingFlags.NonPublic)!;
            object?[] args = methodName == "ExchangeCodeAsync"
                ? ["fixture", TokenMarker, Endpoint, TokenMarker, CancellationToken.None, true]
                : ["fixture", TokenMarker, CancellationToken.None];
            Exception? error = null;
            try { await (Task)method.Invoke(client, args)!; }
            catch (InvalidOperationException ex) { error = ex; }
            Check(error is not null, "fake token failure accepted");
        }
        var path = Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log");
        Check(File.Exists(path), "diagnostic log absent");
        var log = await File.ReadAllTextAsync(path);
        Check(log.Contains("code=500") && log.Contains("reconnecting"), "diagnostic positive controls absent");
        foreach (var marker in new[] { TokenMarker, MsgMarker, IdMarker })
            Check(!log.Contains(marker, StringComparison.Ordinal), "synthetic marker leaked into diagnostics");
    }
    internal static async Task Run()
    {
        var previousRoot = HostDataRoot.CurrentRoot;
        var previousTimeout = ScmChatConnection.ReplyTimeout;
        var root = Path.Combine(Environment.GetEnvironmentVariable("STARBRIDGE_TEST_WORKSPACE_ROOT") ?? Environment.CurrentDirectory,
            ".cxt03-patch", "test-data", Guid.NewGuid().ToString("N"));
        HostDataRoot.UsePreparedRoot(root);
        ScmChatConnection.ReplyTimeout = TimeSpan.FromSeconds(10);
        try
        {
            await MultiEndAndDuplicates(); Console.WriteLine("PASS SPEC9 multi-end receipts, failures, duplicates and stable retries");
            await Reconnect(); Console.WriteLine("PASS SPEC9 fresh tickets, focus subscription and resync");
            await BusinessCodes(); Console.WriteLine("PASS SPEC9 HTTP 200 business codes: 3 passed");
            await Diagnostics(); Console.WriteLine("PASS SPEC9 diagnostic marker exclusion");
            Console.WriteLine("PASS SPEC9 4 groups, 0 failures (offline Host contracts only)");
        }
        finally { ScmChatConnection.ReplyTimeout = previousTimeout; HostDataRoot.UsePreparedRoot(previousRoot); }
    }
}
