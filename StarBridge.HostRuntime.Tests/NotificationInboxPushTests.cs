using System.Net;
using System.Net.WebSockets;
using System.Text.Json;
using System.Threading.Channels;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;

internal static class NotificationInboxPushTests
{
    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }

    internal static async Task Run()
    {
        await Socket();
        await NoProfileSubscription();
        ReadPolicy();
    }

    private static void ReadPolicy()
    {
        Check(!AccountSafetyRequest.InboxRead(JsonSerializer.SerializeToElement(new { schemaVersion = 1 })), "Manual and old callers always read fresh SCM");
        Check(AccountSafetyRequest.InboxRead(JsonSerializer.SerializeToElement(new { schemaVersion = 1, allowScmCache = true })), "Only explicit passive callers permit cache reuse");
        foreach (var json in new[] { "null", "{}", "{\"schemaVersion\":1,\"allowScmCache\":null}", "{\"schemaVersion\":1,\"extra\":true}", "{\"schemaVersion\":1,\"schemaVersion\":1}" })
        {
            try { AccountSafetyRequest.InboxRead(JsonDocument.Parse(json).RootElement); throw new Exception("Invalid inbox cache policy accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "accountSafety.invalid_request") { }
        }
        Console.WriteLine("PASS CX-L06 inbox cache policy preserves manual and legacy refresh semantics");
    }

    private static async Task Socket()
    {
        using var http = new DenyHttp();
        var uri = new Uri("https://fixture.invalid/");
        var options = new ScmOAuthOptions("fixture", uri, uri, uri, "fixture", "fixture", "", "/callback");
        var oauth = new OAuthPkceClient(new ScmHttpClient(http), new Vault(), options);
        var session = new ScmOAuthSession("fixture", "fixture", "Fixture", "synthetic-only",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        var transports = Channel.CreateUnbounded<Transport>();
        var signals = Channel.CreateUnbounded<string>();
        var sockets = new List<Transport>();
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(12));
        await using var client = new ScmRealtimeClient(oauth, options, "fixture-device", (_, _) => { },
            (_, _) => signals.Writer.TryWrite("heartbeat"), (_, _) => { }, (_, _, _, _) => { },
            issueTicket: _ => Task.FromResult(new ScmWebSocketTicketResult(new("fixture-ticket", DateTimeOffset.UtcNow.AddMinutes(1)), session)),
            disconnected: _ => signals.Writer.TryWrite("disconnected"),
            tradeNotice: (_, _) => signals.Writer.TryWrite("message"),
            transportFactory: () => {
                var socket = new Transport(); sockets.Add(socket); transports.Writer.TryWrite(socket); return socket;
            },
            inboxInvalidated: _ => signals.Writer.TryWrite("inbox"));
        client.Start(session);
        var first = await transports.Reader.ReadAsync(timeout.Token);
        Check(await signals.Reader.ReadAsync(timeout.Token) == "heartbeat", "Heartbeat alone is not a subscription acknowledgement");
        foreach (var content in new object?[] { null, "{bad", 1, new { }, new { total = -1 }, new { total = "1" } })
            first.Frame("unread-count-update", content);
        first.Frame("unknown-message", new { total = 1 });
        first.Frame("new-message", null);
        first.Frame("unread-count-update", new { total = 0 });
        Check(await signals.Reader.ReadAsync(timeout.Token) == "inbox", "Only valid unread counts acknowledge and invalidate inbox");
        first.Frame("unread-count-update", "{\"total\":2}");
        Check(await signals.Reader.ReadAsync(timeout.Token) == "inbox", "Java string-content unread counts reconcile page one too");
        first.Frame("new-message", new { id = 71, type = 0 });
        first.Frame("new-message", "{\"id\":72,\"type\":1,\"subType\":4}");
        Check(await signals.Reader.ReadAsync(timeout.Token) == "message" &&
            await signals.Reader.ReadAsync(timeout.Token) == "message", "Both message content shapes use the existing trade callback");
        Check(sockets.Count == 1 && first.SubscriptionCount == 0, "Malformed or unknown frames neither disconnect nor cause a subscription");
        first.Incoming.Writer.TryWrite(null);
        Check(await signals.Reader.ReadAsync(timeout.Token) == "disconnected", "A closed connection immediately invalidates health");
        var second = await transports.Reader.ReadAsync(timeout.Token);
        Check(await signals.Reader.ReadAsync(timeout.Token) == "heartbeat", "Reconnect does not assume subscription health");
        second.Frame("unread-count-update", new { total = 3 });
        Check(await signals.Reader.ReadAsync(timeout.Token) == "inbox" && second.SubscriptionCount == 0,
            "Reconnects never subscribe on the relay socket; a stray unread count still only requests reconciliation");
        client.Stop(); await client.StopCompletion;
        Check(http.Requests == 0 && sockets.All(s => s.Disposed), "All socket tests use fake transports without HTTP");
        Console.WriteLine("PASS CX-L06 socket acknowledgements, malformed frames and reconnect subscription");
    }

    private static async Task NoProfileSubscription()
    {
        using var http = new DenyHttp();
        var uri = new Uri("https://fixture.invalid/");
        var options = new ScmOAuthOptions("fixture", uri, uri, uri, "fixture", "fixture", "", "/callback");
        foreach (var capabilities in new[] { Array.Empty<string>(), new[] { "presence.write" } })
        {
            var oauth = new OAuthPkceClient(new ScmHttpClient(http), new Vault(), options);
            var session = new ScmOAuthSession("fixture", "fixture", "Fixture", "synthetic-only",
                DateTimeOffset.UtcNow.AddHours(1), capabilities);
            var socket = new Transport();
            var heartbeat = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var invalidations = 0;
            await using var client = new ScmRealtimeClient(oauth, options, "fixture-device", (_, _) => { },
                (_, _) => heartbeat.TrySetResult(), (_, _) => { }, (_, _, _, _) => { },
                issueTicket: _ => Task.FromResult(new ScmWebSocketTicketResult(new("fixture-ticket", DateTimeOffset.UtcNow.AddMinutes(1)), session)),
                transportFactory: () => socket, inboxInvalidated: _ => invalidations++);
            socket.Frame("unread-count-update", new { total = 1 });
            client.Start(session);
            await heartbeat.Task.WaitAsync(TimeSpan.FromSeconds(2));
            Check(socket.SubscriptionCount == 0 && invalidations == 0, "Sessions without authenticated profile.read neither subscribe nor accept unread acknowledgements");
            client.Stop(); await client.StopCompletion;
        }
        Check(http.Requests == 0, "Capability gates never touch an endpoint");
        Console.WriteLine("PASS CX-L06 profileless sessions never subscribe or establish inbox health");
    }

    private sealed class Transport : IScmChatTransport
    {
        internal readonly Channel<string?> Incoming = Channel.CreateUnbounded<string?>();
        internal readonly TaskCompletionSource Subscribed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int SubscriptionCount;
        internal bool Disposed;
        internal void Frame(string type, object? content) => Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type, content }));
        public Task ConnectAsync(Uri endpoint, CancellationToken token) => Task.CompletedTask;
        public Task SendAsync(string text, CancellationToken token)
        {
            using var doc = JsonDocument.Parse(text);
            switch (doc.RootElement.GetProperty("type").GetString())
            {
                case "message-subscribe":
                    // Hotfix 10-29: the relay closes on this message, which kept presence from registering.
                    SubscriptionCount++; Check(false, "message-subscribe is never sent on the relay socket"); break;
                case "member-online-heartbeat": Frame("member-status-update", new { signInStatus = 1 }); break;
                default:
                    Check(doc.RootElement.GetProperty("type").GetString() is "member-online-heartbeat" or "fleet-broadcast-subscribe"
                        or "fleet-broadcast-unsubscribe" or "ping", "The relay socket only receives message types the relay accepts");
                    break;
            }
            return Task.CompletedTask;
        }
        public async Task<string?> ReceiveAsync(CancellationToken token) => await Incoming.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }
    private sealed class DenyHttp : HttpMessageHandler
    {
        internal int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Requests++; throw new InvalidOperationException("Network forbidden in CX-L06 socket fixture"); }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential writes");
        public void DeleteRefreshToken(string key) => throw new InvalidOperationException("No credential writes");
    }
}
