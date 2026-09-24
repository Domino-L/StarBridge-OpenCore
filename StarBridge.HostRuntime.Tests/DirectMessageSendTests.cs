using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Friends;

internal static class DirectMessageSendTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private const string Id = "00000000000000000000000000000011";
    private static JsonElement Payload(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    private static HttpResponseMessage Ok(object value) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(value)) };
    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request); }
    private sealed class Fixture : IDisposable
    {
        internal readonly FriendsReader Reader;
        internal int Posts, Checks;
        internal string Fault = "";
        internal bool Allowed = true;
        internal string Reference = "";
        internal Fixture() {
            Reader = new FriendsReader(new Uri("https://relay.example.test"), new Handler(async request => {
                Check(request.Headers.Authorization?.Parameter == "token", "Scoped bearer");
                if (request.RequestUri!.AbsolutePath.EndsWith("conversations")) return Ok(new {
                    conversations = new[] { new { user = new { accountId = "target", callsign = "示例", gameId = "Example" },
                        lastMessagePreview = "", lastMessageAt = Now, unreadCount = 0, conversationState = "friend" } }, totalUnread = 0, serverTime = Now });
                if (request.Method == HttpMethod.Get) {
                    Checks++;
                    Check(request.RequestUri.Query.Contains("targetAccountId=target") && request.RequestUri.Query.Contains("limit=1"), "Bounded preflight");
                    return Ok(new { targetAccountId = "target", canSend = Allowed, conversationState = Allowed ? "friend" : "request_outgoing" });
                }
                Posts++;
                Check(request.Method == HttpMethod.Post && request.RequestUri.AbsolutePath == "/api/friends/chat/messages", "Only send endpoint");
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
                var root = body.RootElement;
                Check(root.GetProperty("targetAccountId").GetString() == "target" && root.GetProperty("clientMessageId").GetString() == Id &&
                    root.GetProperty("text").GetString() == "消息\n正文" && root.GetProperty("origin").GetString() == "friend_center" &&
                    !root.TryGetProperty("attachment", out _), "Immutable plain text intent");
                if (Fault == "timeout") throw new TaskCanceledException();
                if (int.TryParse(Fault, out var code)) return new((HttpStatusCode)code) { Content = new StringContent("private detail") };
                if (Fault == "empty") return Ok(new { status = "sent", message = (object?)null });
                return Ok(new { status = Fault == "request" ? "request_sent" : "sent", message = new {
                    sequence = 9, messageId = Fault == "id" ? "wrong" : Id, senderAccountId = "viewer",
                    recipientAccountId = Fault == "target" ? "other" : "target", text = "消息\n正文", createdAt = Now,
                    attachment = Fault == "attachment" ? new { kind = "overlay_preset" } : null } });
            }));
        }
        internal async Task Init() => Reference = ((ConversationsView)await Reader.ReadChatAsync("token", Payload(new { schemaVersion = 1 }), default, "a:1")).Conversations[0].TargetRef;
        internal Task<DirectSendView> Send(string scope = "a:1", string text = "消息\n正文", Action? current = null) =>
            Reader.SendChatAsync("token", Payload(new { schemaVersion = 1, targetRef = Reference, clientMessageId = Id, text }), default, scope, current);
        public void Dispose() => Reader.Dispose();
    }
    internal static async Task Confirmation()
    {
        foreach (var fault in new[] { "", "request" }) {
            using var f = new Fixture { Fault = fault }; await f.Init();
            var result = await f.Send();
            Check(result.Status == (fault == "request" ? "request_sent" : "sent") && result.Message?.MessageId == Id && !result.Message.Incoming, "Authoritative acknowledgement");
            Check(f.Posts == 1 && f.Checks == 1, "One preflight and write");
            await f.Send(); Check(f.Posts == 1, "Confirmed intent cannot duplicate");
            Check((await f.Send(text: "changed")).Status == "rejected", "ID cannot carry different text");
            await f.Init(); await f.Send(); Check(f.Posts == 1, "Ref refresh does not replay intent");
        }
    }
    internal static async Task Failures()
    {
        foreach (var fault in new[] { "timeout", "500", "302", "empty", "id", "target", "attachment" }) {
            using var f = new Fixture { Fault = fault }; await f.Init();
            Check((await f.Send()).Status == "unknown", "Uncertain write: " + fault);
            Check((await f.Send()).Status == "unknown" && f.Posts == 1, "Uncertain writes never replay");
        }
        foreach (var fault in new[] { "401", "403", "404", "409", "429", "400" }) {
            using var f = new Fixture { Fault = fault }; await f.Init();
            var result = await f.Send();
            Check(result.Status == "rejected" && !JsonSerializer.Serialize(result).Contains("private detail"), "Stable rejection");
            f.Fault = ""; Check((await f.Send()).Status == "sent" && f.Posts == 2, "Explicit retry after rejection");
        }
    }
    internal static async Task Guards()
    {
        using var f = new Fixture(); await f.Init();
        Check((await f.Send("b:1")).Status == "rejected" && f.Checks == 0 && f.Posts == 0, "Cross-owner no IO");
        f.Allowed = false; Check((await f.Send()).Error == "request_pending" && f.Posts == 0, "Fresh permission revocation");
        f.Allowed = true;
        try { await f.Send(current: () => throw new InvalidOperationException("changed")); throw new Exception("Expected context failure"); }
        catch (InvalidOperationException) { Check(f.Posts == 0, "Context checked immediately before POST"); }
        foreach (var body in new object[] {
            new { schemaVersion = 1, targetRef = f.Reference, clientMessageId = Id, text = " " },
            new { schemaVersion = 1, targetRef = f.Reference, clientMessageId = Id, text = new string('x', 1001) },
            new { schemaVersion = 1, targetRef = f.Reference, clientMessageId = Id, text = "valid", targetAccountId = "injected" },
            new { schemaVersion = 1, targetRef = f.Reference, clientMessageId = "invalid", text = "valid" } }) {
            try { FriendsReader.ParseChatSend(Payload(body)); throw new Exception("Invalid payload accepted"); }
            catch (AccountBridgeHostException e) { Check(e.Code == "directMessages.invalid_request", "Strict input"); }
        }
    }
}
