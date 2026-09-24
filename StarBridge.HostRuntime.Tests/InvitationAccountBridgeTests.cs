using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Friends;
using StarBridge.NativeBridge;

internal static class InvitationAccountBridgeTests
{
    internal static async Task Verify()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-invitation-bridge-").FullName;
        using var handler = new Handler();
        var id = Guid.NewGuid().ToString("N");
        using (var first = new Fixture(root, handler, "owner", 7))
        {
            var scope = JsonSerializer.Serialize(first.Context) + ":7";
            var organization = (await first.Communities.ReadAsync("bearer", new("mine", "", null, null), scope, default)).Items.Single().TargetRef;
            var chats = (ConversationsView)await first.Friends.ReadChatAsync("bearer", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default, scope);
            var target = chats.Conversations.Single().TargetRef;
            var send = new { schemaVersion = 1, operationId = id, organizationRef = organization, channel = "private", destinationRef = target, maxUses = 1, action = "advance" };
            handler.RecipientIsMember = true;
            var sameOrganization = await first.Send("communities.sendInvite", send);
            Check(sameOrganization.Response.Payload.GetProperty("status").GetString() == "rejected" && handler.Generations == 0 && handler.Sends == 0,
                "WPF member exclusion uses existing roster before generating or replacing an invitation");
            handler.RecipientIsMember = false;
            var badAccount = await first.Runtime.DispatchAsync(BridgeEnvelope.Request("communities.sendInvite", "bad-context", 7, send,
                first.Context with { Subject = "other" }));
            Check(badAccount.Response.Status == BridgeResponseStatuses.Error && handler.Sends == 0, "dispatcher rejects foreign account before invitation work");
            var response = await first.Send("communities.sendInvite", send);
            Check(response.Response.Status == BridgeResponseStatuses.Ok && response.Response.Payload.GetProperty("status").GetString() == "unknown",
                "real account owner returns uncertain send instead of success");
            var page = await first.Send("communities.invitationOutbox", new { schemaVersion = 1 });
            var item = page.Response.Payload.GetProperty("items").EnumerateArray().Single();
            Check(item.EnumerateObject().Count() == 7 && item.GetProperty("phase").GetString() == "sending"
                && item.GetProperty("sourceName").GetString() == "Synthetic organization"
                && item.GetProperty("destinationName").GetString() == "Synthetic recipient", "outbox projects display labels and phase");
            var raw = page.Response.Payload.GetRawText();
            Check(!raw.Contains("INVITE-SECRET") && !raw.Contains("recipient-id") && !raw.Contains("https://")
                && !raw.Contains("bearer") && !raw.Contains("deliveryId"), "no code, raw target, origin, token or internal delivery ID crosses Bridge");
            var invalid = await first.Send("communities.resumeInvite", new { schemaVersion = 1, operationId = id, action = "sendNew" });
            Check(invalid.Response.Status == BridgeResponseStatuses.Error, "unsupported resume action rejected");
        }
        using (var next = new Fixture(root, handler, "owner", 8))
        {
            var result = await next.Send("communities.resumeInvite", new { schemaVersion = 1, operationId = id, action = "check" });
            Check(result.Response.Status == BridgeResponseStatuses.Ok && result.Response.Payload.GetProperty("status").GetString() == "sent"
                && handler.Generations == 1 && handler.Sends == 1 && handler.Confirms == 1, "new account runtime rebinds and confirms without duplicate generation/send");
        }
        using (var other = new Fixture(root, handler, "other", 9))
        {
            var page = await other.Send("communities.invitationOutbox", new { schemaVersion = 1 });
            Check(page.Response.Payload.GetProperty("items").GetArrayLength() == 0, "different signed-in account cannot list owner's journal");
            var result = await other.Send("communities.resumeInvite", new { schemaVersion = 1, operationId = id, action = "check" });
            Check(result.Response.Payload.GetProperty("status").GetString() == "unknown" && handler.Confirms == 1, "foreign operation ID never causes a delivery request");
        }
        await File.WriteAllBytesAsync(Directory.GetFiles(Path.Combine(root, "outbox"), "*.dat").Single(), [1, 2, 3]);
        using (var damaged = new Fixture(root, handler, "owner", 10))
        {
            var result = await damaged.Send("communities.invitationOutbox", new { schemaVersion = 1 });
            Check(result.Response.Error?.Code == "communities.localRecoveryUnavailable", "damaged local recovery returns stable error without private filesystem detail");
        }
        Check(AccountBridgeRuntime.AdvertisedCapabilities.Contains("communities.sendInvite"), "capability advertised with all actual routes");
    }

    private sealed class Fixture : IDisposable
    {
        internal CommunityClient Communities { get; }
        internal FriendsReader Friends { get; }
        internal AccountBridgeRuntime Runtime { get; }
        internal BridgeAccountContext Context { get; }
        private readonly string _previousRoot;
        internal Fixture(string root, Handler handler, string owner, long generation)
        {
            _previousRoot = HostDataRoot.CurrentRoot;
            HostDataRoot.UsePreparedRoot(root);
            var origin = new Uri("https://invitation.invalid");
            Communities = new(origin, handler, invitationJournal: new(Path.Combine(root, "outbox")));
            Friends = new(origin, handler);
            var options = new ScmOAuthOptions("synthetic", origin, origin, origin, "synthetic", "synthetic", "openid profile.read", "/callback");
            var session = new ScmOAuthSession("synthetic", owner, "Synthetic pilot", "bearer", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            Context = new("integration", "synthetic", owner);
            Runtime = new(new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
                new ScmProfileCacheStore(Path.Combine(root, "cache")), "integration", () => null, session, generation,
                friends: Friends, communities: Communities));
        }
        internal ValueTask<BridgeDispatchBatch> Send(string name, object body) =>
            Runtime.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), Runtime.Generation, body, Context));
        public void Dispose() { Runtime.Dispose(); HostDataRoot.UsePreparedRoot(_previousRoot); }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string accountKey) => null;
        public void SaveRefreshToken(string accountKey, string refreshToken) { }
        public void DeleteRefreshToken(string accountKey) { }
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Generations, Sends, Confirms;
        internal bool RecipientIsMember;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                if (path == "/api/fleets/workspace") return Reply(new { schemaVersion = 1, membershipModelVersion = 2,
                    code = "A", query = "", offset = 0, totalCount = 1, matchedCount = 1, next = (int?)null,
                    members = new[] { new { memberId = RecipientIsMember ? "account:recipient-id" : "account:owner" } } });
                if (path == "/api/fleets/directory") return Reply(new { schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Synthetic organization", description = "", language = "", activeTime = "", memberCount = 1,
                        relationship = "member", joinMode = "direct", actions = Array.Empty<string>() } } });
                if (path == "/api/fleets/admissions") return Reply(new { schemaVersion = 1, membershipModelVersion = 2, code = "A", section = "access",
                    inviteGenerationVersion = 1, inviteDeliveryVersion = 1, access = new { canSendInvitationCard = true } });
                if (path == "/api/friends/chat/conversations") return Reply(new { totalUnread = 0, serverTime = DateTimeOffset.UtcNow,
                    conversations = new[] { new { user = new { accountId = "recipient-id", callsign = "Synthetic recipient", gameId = "Visible handle" },
                        unreadCount = 0, lastMessagePreview = "", lastMessageAt = DateTimeOffset.UtcNow, conversationState = "friend" } } });
                if (path == "/api/friends/chat/messages") return Reply(new { targetAccountId = "recipient-id", canSend = true });
                throw new InvalidOperationException("Unexpected read route.");
            }
            using var data = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            if (path == "/api/fleets/invites")
            {
                Generations++;
                return Reply(new { schemaVersion = 1, status = "accepted", requestId = data.RootElement.GetProperty("clientRequestId").GetString(),
                    inviteId = new string('a', 32), code = "INVITE-SECRET", expiresAt = DateTimeOffset.UtcNow.AddDays(7) });
            }
            Check(path == "/api/friends/chat/messages", "account owner posts only intended invitation operation");
            if (!data.RootElement.GetProperty("confirmOnly").GetBoolean()) { Sends++; throw new HttpRequestException("Lost acknowledgement"); }
            Confirms++;
            var id = data.RootElement.GetProperty("clientMessageId").GetString();
            return Reply(new { schemaVersion = 1, status = "sent", requestId = id, messageId = id, sequence = 9, createdAt = DateTimeOffset.UtcNow });
        }
        protected override void Dispose(bool disposing) { }
        private static HttpResponseMessage Reply(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
}
