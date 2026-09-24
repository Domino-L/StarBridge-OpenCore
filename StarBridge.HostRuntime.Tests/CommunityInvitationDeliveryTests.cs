using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Chat;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityInvitationDeliveryTests
{
    internal static async Task Verify()
    {
        using var handler = new Handler();
        var origin = new Uri("https://community.invalid");
        using var client = new CommunityClient(origin, handler);
        var source = (await client.ReadAsync("bearer", new("mine", "", null, null), "account:1", default)).Items.Single().TargetRef;
        var destination = new InvitationDeliveryTarget("private", "recipient", "account:1", origin);
        var intent = new InvitationDeliveryIntent(Guid.NewGuid().ToString("N"), DateTimeOffset.UtcNow,
            new(ChatAttachmentKinds.FleetInvitation, "邀请", "加入组织", FleetInviteCode: "INVITE-ABC", ExpiresAt: DateTimeOffset.UtcNow.AddDays(7)));
        Task<InvitationDeliveryResult> Send(bool confirm = false, InvitationDeliveryTarget? target = null, Action? current = null) =>
            client.DeliverInvitationCardAsync("bearer", source, target ?? destination, intent, confirm, "account:1", current ?? (() => { }), default);
        foreach (var target in new[] { destination with { Scope = "other" }, destination with { Channel = "unknown" },
            destination with { Origin = new Uri("https://other.invalid") }, destination with { Id = "bad\n" } })
            Check((await Send(target: target)).Status == "rejected" && handler.Bodies.Count == 0, "reject foreign scope/origin or invalid target before sending");
        handler.Version = 0;
        Check((await Send()).Error == "unavailable" && handler.Bodies.Count == 0, "old server receives neither send nor confirm POST");
        Check((await Send(true)).Status == "unknown" && handler.Bodies.Count == 0, "unsupported confirm never becomes a new send");
        handler.Version = 1; handler.Allowed = false;
        Check((await Send()).Error == "notAllowed" && handler.Bodies.Count == 0, "fresh generation permission required for new send");
        handler.Mode = "unknown";
        Check((await Send(true)).Status == "unknown", "confirmation permitted without regeneration permission");
        handler.Allowed = true; handler.Mode = "lost";
        var before = handler.Bodies.Count;
        Check((await Send()).Status == "unknown" && handler.Bodies.Count == before + 1, "lost response is unknown without internal retry");
        handler.Mode = "ok";
        Check((await Send(true)).Status == "sent", "same original delivery can be confirmed");
        using (var first = JsonDocument.Parse(handler.Bodies[^2]))
        using (var confirmation = JsonDocument.Parse(handler.Bodies[^1]))
        {
            foreach (var key in new[] { "targetAccountId", "clientMessageId", "clientRequestedAt", "text", "attachment" })
                Check(first.RootElement.GetProperty(key).GetRawText() == confirmation.RootElement.GetProperty(key).GetRawText(), "confirm preserves original " + key);
            Check(!first.RootElement.GetProperty("confirmOnly").GetBoolean() && confirmation.RootElement.GetProperty("confirmOnly").GetBoolean(), "confirm is explicit");
        }
        foreach (var mode in new[] { "wrong-request", "wrong-message", "zero-sequence", "future", "unknown-with-data", "extra", "duplicate", "bulk", "redirect" })
        {
            handler.Mode = mode;
            Check((await Send()).Status == "unknown", "invalid receipt never claims sent: " + mode);
        }
        handler.Mode = "403";
        Check((await Send()).Status == "rejected" && (await Send(true)).Status == "unknown", "failed check cannot disprove an earlier send");
        handler.Mode = "503";
        Check((await Send()).Status == "unknown", "server failure may follow commit");
        handler.Mode = "ok";
        Check((await Send(target: destination with { Channel = "room", Id = "room-one" })).Status == "sent", "same bounded transport supports current room");
        Check(handler.Paths[^1] == "/api/party-rooms/chat?view=client", "room route is fixed and never supplied by UI");
        handler.OnAccess = client.InvalidateInvitePreviews;
        before = handler.Bodies.Count;
        Check((await Send()).Status == "rejected" && handler.Bodies.Count == before, "epoch change before POST cancels delivery");
        handler.OnAccess = null;
        var active = true;
        handler.OnPost = () => { active = false; client.InvalidateInvitePreviews(); };
        var stale = await Send(current: () => { if (!active) throw new AccountBridgeHostException("communities.identityUnavailable"); });
        Check(stale.Status == "unknown" && stale.MessageId is null, "late old-account receipt is suppressed");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Version = 1;
        internal bool Allowed = true;
        internal string Mode = "ok";
        internal Action? OnAccess, OnPost;
        internal List<string> Bodies = [], Paths = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.Headers.Authorization?.Parameter == "bearer", "bearer preserved");
            if (request.Method == HttpMethod.Get && request.RequestUri!.AbsolutePath == "/api/fleets/directory")
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Organization", description = "", language = "", activeTime = "", memberCount = 1,
                        relationship = "member", joinMode = "direct", actions = Array.Empty<string>() } } });
            if (request.Method == HttpMethod.Get)
            {
                Check(request.RequestUri!.PathAndQuery == "/api/fleets/admissions?code=A&section=access&offset=0", "bounded source support preflight");
                OnAccess?.Invoke();
                return Reply(new { schemaVersion = 1, membershipModelVersion = 2, code = "A", section = "access", inviteDeliveryVersion = Version,
                    access = new { canSendInvitationCard = Allowed } });
            }
            Check(request.RequestUri!.PathAndQuery is "/api/friends/chat/messages?view=client" or "/api/party-rooms/chat?view=client", "no generation or arbitrary POST");
            var body = await request.Content!.ReadAsStringAsync(token);
            Bodies.Add(body); Paths.Add(request.RequestUri.PathAndQuery); OnPost?.Invoke();
            if (Mode == "lost") throw new HttpRequestException("Lost reply");
            if (int.TryParse(Mode, out var status)) return new((HttpStatusCode)status);
            if (Mode == "bulk") return Reply(new { message = new string('x', 5000) });
            if (Mode == "redirect") return new(HttpStatusCode.TemporaryRedirect) { Headers = { Location = new Uri("https://other.invalid") } };
            using var data = JsonDocument.Parse(body);
            var id = data.RootElement.GetProperty("clientMessageId").GetString();
            var unknown = Mode is "unknown" or "unknown-with-data";
            var fields = new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1, ["status"] = unknown ? "unknown" : "sent",
                ["requestId"] = Mode == "wrong-request" ? new string('b', 32) : id,
                ["messageId"] = Mode == "unknown" ? null : Mode == "wrong-message" ? new string('c', 32) : data.RootElement.TryGetProperty("roomId", out _) ? new string('d', 32) : id,
                ["sequence"] = Mode == "unknown" ? null : Mode == "zero-sequence" ? 0 : 9,
                ["createdAt"] = Mode == "unknown" ? null : DateTimeOffset.UtcNow.AddMinutes(Mode == "future" ? 20 : 0)
            };
            if (Mode == "extra") fields["account"] = "secret";
            if (Mode == "duplicate") return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(fields).Replace("\"schemaVersion\":1", "\"schemaVersion\":1,\"schemaVersion\":1")) };
            return Reply(fields);
        }
        private static HttpResponseMessage Reply(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
