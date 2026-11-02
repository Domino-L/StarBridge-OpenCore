using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

internal static class OverlayFleetReaderTests
{
    private static JsonElement Json(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static Task Run() => Run(false, false);
    internal static Task RunCommunicationWake(string kind) => Run(true, true, activityChange: kind);
    internal static Task RunAuthors() => Run(true, true);
    internal static Task RunNeutralAuthors() => Run(true, false);
    internal static Task RunAuthorTransition(string state) => Run(true, true, state);

    private static async Task Run(bool chat, bool authors, string? transition = null, string? activityChange = null)
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-fleet-reader-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            using var handler = new Handler { Chat = chat, Authors = authors };
            var options = new ScmOAuthOptions("fixture", new("https://fixture.invalid/"), new("https://fixture.invalid/"),
                new("https://fixture.invalid/"), "fixture", "fixture", "profile.read organizations.read", "/callback");
            using var communication = new CommunityClient(new("https://fixture.invalid/"), handler);
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
                new ScmProfileCacheStore(root), "fixture", () => null,
                initialSession: new ScmOAuthSession("fixture", "fixture-owner", "Pilot", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "organizations.read"]),
                initialGeneration: 1, communities: communication);
            using var writer = new PrivacyRelayWriter(new("https://fixture.invalid/"), handler);
            host.ConfigurePrivacyWriter(writer);
            // This in-memory fixture has no configuration files, real account or
            // network transport. Product feature switches are never changed.
            host.ConfigureOfficialRealtime(true);
            var owner = host.CurrentContext!;
            var reader = (IOverlayFleetReader)host;
            var target = await reader.ReadFleetTargetAsync(owner, default) ?? throw new Exception("Fixture fleet missing.");
            var page = Json(await host.GetOfficialFleetRuntimeMembersAsync(owner, Json(new
                { schemaVersion = 2, sourceRef = target.Reference, search = "", filter = "all", pageNumber = 1, pageSize = 100 }), default));
            InformationOverlayCommunityContent? progressive = null;
            var content = await reader.ReadFleetContentAsync(owner, target, roster => progressive = roster, true, default);
            var expected = page.GetProperty("members").EnumerateArray().Select(row => ScmAccountBridgeHost.ProjectOverlayFleetMember(row,
                OverlaySceneChoiceStore.Hash(owner) + "\n" + target.Reference)).ToArray();
            Check(content.SharedFieldsOnly && content.Members.SequenceEqual(expected) && progressive?.Members.SequenceEqual(expected) == true,
                "Overlay exactly equals the real getRuntimeMembers projection; progressive and final roster share it.");
            Check(content.Members.Count == 3 && content.Members[1] is { Callsign: "—", Ship: "", Location: "" } &&
                content.Members[0] is { Location: "", LocationHiddenReason: "lowConfidence", Ship: "Fixture ship" } &&
                !Json(content).GetRawText().Contains("PRIVATE NAME"), "Restricted identity and location stay hidden; no other read fills fields.");
            if (chat)
            {
                Check(content.Messages.Count == 3 && content.LatestChatSequence == 3, "The official chat page is projected.");
                Check(content.Messages[0].SenderCallsign == (authors ? "Projected chat author" : "") &&
                    content.Messages.Skip(1).All(message => message.SenderCallsign == "") &&
                    content.Messages.All(message => message.SenderGameId == ""),
                    "Only the page's visible author is named; hidden/unavailable authors stay anonymous, without roster or raw-name fallback.");
                Check(handler.AuthorReads == (authors ? 1 : 0) && handler.LegacyChatReads == (authors ? 0 : 1),
                    "The reader opts into the authorized page projection only when the context supports it.");
                var fields = new[] { "Sequence", "SenderCallsign", "SenderGameId", "Text", "CreatedAt", "IsSystem", "IsSelf", "AttachmentKind" };
                Check(content.Messages.All(message => Json(message).EnumerateObject().Select(field => field.Name).ToHashSet().SetEquals(fields)),
                    "The HUD message contract adds no author IDs, refs, avatars, roles or other fields.");
                Check(content.Messages.All(message => message.AttachmentKind == "attachment") && !Json(content.Messages).GetRawText().Contains("RAW PRIVATE"),
                    "Only attachment metadata and projected names cross into the HUD.");
            }
            Check(content.AnnouncementText == "" && (chat || content.Messages.Count == 0) && handler.Paths.All(path =>
                !path.Contains("rally", StringComparison.OrdinalIgnoreCase) && !path.Contains("attachment", StringComparison.OrdinalIgnoreCase)), "No rally or attachment reads occur.");
            if (transition is not null) await AuthorTransition(host, owner, handler, root, transition);
            if (activityChange is not null)
            {
                await CommunicationWake(host, owner, handler, root, activityChange);
                return;
            }
            var cursor = await reader.WaitFleetChangesAsync(owner, 1, new(), default);
            Check(cursor.PresenceEvents && cursor.Version > 0 && handler.ActivityReads == 1, "Reader uses the actual official runtime held activity path.");
            handler.NoFleet = true;
            Check(await reader.ReadFleetTargetAsync(owner, default) is null, "Actual bootstrap absence produces notMember.");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task CommunicationWake(ScmAccountBridgeHost host, BridgeAccountContext owner, Handler handler, string root, string kind)
    {
        handler.HoldRuntime = true;
        using var source = new OverlayCommunitySource(() => (owner, 1), host, true, choiceStore: new(root));
        await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, Guid.NewGuid().ToString(), 1,
            new { schemaVersion = 1, revision = 0L, mode = "fleet", code = (string?)null }, owner), default);
        source.ReadForDisplay();
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        async Task Until(Func<bool> predicate)
        {
            try { while (!predicate()) await Task.Delay(10, deadline.Token); }
            catch (OperationCanceledException) { throw new Exception("Communication-only activity must refresh before the 15s reconcile: " + kind); }
        }
        try
        {
            await Until(() => source.Read()?.LatestChatSequence == 3 && handler.CommunicationWaiting.Task.IsCompleted);
            var cancelledBefore = handler.RuntimeCancelled;
            // Both member data and its held runtime wait remain unchanged.
            if (kind == "chat") handler.ChatSequence = 4;
            else handler.Notice = "Updated announcement";
            handler.CommunicationChanged.TrySetResult();
            await Until(() => kind == "chat" ? source.Read()?.Messages.Any(m => m.Sequence == 4) == true
                : source.Read()?.AnnouncementText == "Updated announcement");
            Check(handler.RuntimeCancelled > cancelledBefore, "The losing member runtime wait must be cancelled for this communication change.");
            Check(handler.CommunicationReads <= 4, "Communication waits use revisions, not a short poll.");
        }
        finally { await source.RetireAsync(); }
    }

    private static async Task AuthorTransition(ScmAccountBridgeHost host, BridgeAccountContext owner, Handler handler, string root, string state)
    {
        var now = DateTimeOffset.UtcNow;
        using var source = new OverlayCommunitySource(() => (owner, 1), host, false, now: () => now, choiceStore: new(root));
        var selected = await source.DispatchAsync(BridgeEnvelope.Request(OverlayCommunitySource.SelectRequest, Guid.NewGuid().ToString(), 1,
            new { schemaVersion = 1, revision = 0L, mode = "fleet", code = (string?)null }, owner), default);
        Check(selected.Response.Error is null, "Fixture selects the main fleet.");
        await source.RefreshAsync(); // Establish the existing sequence baseline; old messages never enter the HUD.
        handler.ChatSequence = 4;
        await source.RefreshAsync();
        var cached = source.Read()!;
        Check(cached.Messages.Count == 1 && cached.Messages[0] is { Sequence: 4, SenderCallsign: "Projected chat author" },
            "A new message initially has a visible author.");
        var receipt = source.ReadFleetSource(owner, 1)!;
        var frame = InformationOverlayModuleFrame.Capture(new(new(OverlaySourceMode.Fleet)), source.CaptureResolutionContext(owner, 1, null)!,
            _ => source.ReadFleetSource(owner, 1), () => true, snapshot => source.IsFleetSourceCurrent(owner, 1, snapshot));
        if (state == "expired")
        {
            now = handler.AuthorUntil; // Exactly the author expiry, while the communication lease is still valid.
            Check(receipt.At(now).Community!.Messages.Single().SenderCallsign == "",
                "A retained HUD receipt anonymizes at author expiry without a network read.");
        }
        else
        {
            handler.AuthorState = state;
            await source.RefreshAsync(); // Same sequence: a later anonymous projection must replace the old author.
        }
        var expected = state == "visible" ? "Projected chat author" : "";
        var current = source.Read()!;
        Check(current.Messages.Count == 1 && current.Messages[0].SenderCallsign == expected && current.Messages[0].SenderGameId == "",
            "Cached content must reflect the current author projection: " + state);
        Check(source.ReadForDisplay()!.Messages.Single().SenderCallsign == expected &&
            frame.ReadModules(now)[OverlaySourceModule.Chat].Snapshot!.Community!.Messages.Single().SenderCallsign == expected,
            "HUD display must reflect the current author projection: " + state);
        Check(current.Messages[0].Text == cached.Messages[0].Text && current.Messages[0].AttachmentKind == "attachment",
            "Anonymization preserves the message and attachment metadata.");
    }

    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string account, string value) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string account) => throw new Exception("Unexpected credential read");
        public string? LoadActiveAccountKey() => throw new Exception("Unexpected account read");
        public void DeleteRefreshToken(string account) => throw new Exception("Unexpected credential delete");
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal bool NoFleet;
        internal bool Chat, Authors;
        internal int ChatSequence = 3;
        internal string AuthorState = "visible";
        internal DateTimeOffset AuthorUntil;
        internal int ActivityReads, AuthorReads, LegacyChatReads;
        internal bool HoldRuntime;
        internal int RuntimeCancelled, CommunicationReads;
        internal string Notice = "";
        internal readonly TaskCompletionSource CommunicationWaiting = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource CommunicationChanged = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly List<string> Paths = [];
        private static string Subject(int id) => "scm-v1:" + new string((char)('a' + id - 1), 64);
        private object AnnouncementPage()
        {
            var person = new { accountId = "fixture-author", callsign = "Fixture author", gameId = "", roleTitle = "", roleColor = "#FFFFFF", avatarImageData = (string?)null };
            return new { schemaVersion = 1, membershipModelVersion = 2, fleetCode = "OFFICIALFLEET:7", revision = Notice == "" ? 0L : 1L,
                canManage = false, refreshedAt = DateTimeOffset.UtcNow, offset = 0, next = (int?)null, totalHistoryCount = 0,
                current = Notice == "" ? null : new { authorHasAvatar = false, lastEditorHasAvatar = false, announcement = new
                {
                    id = "fixture-notice", fleetCode = "OFFICIALFLEET:7", title = "Notice", content = Notice, state = "published", revision = 1,
                    publishedAt = DateTimeOffset.UtcNow, updatedAt = DateTimeOffset.UtcNow, archivedAt = (string?)null, withdrawnAt = (string?)null,
                    author = person, lastEditor = person
                } }, history = Array.Empty<object>() };
        }
        private object ChatPage()
        {
            var channel = FleetChatIdentity.FleetChannelId("OFFICIALFLEET:7");
            return new { schemaVersion = 1, channelId = channel, latestSequence = (long)ChatSequence, oldestSequence = 1L, hasOlder = false,
                canSend = false, serverTime = DateTimeOffset.UtcNow, messages = Enumerable.Range(1, ChatSequence).Select(id => new
                {
                    sequence = (long)id, messageId = "fixture-message-" + id, senderAccountId = Subject(id == 4 ? 1 : id),
                    senderCallsign = "RAW PRIVATE NAME", senderGameId = "RAW PRIVATE GAME ID", senderRoleTitle = "RAW PRIVATE ROLE",
                    senderRoleColor = "#123456", text = "Fixture chat " + id, createdAt = DateTimeOffset.UtcNow,
                    isSelf = false, hasAvatar = false, avatarVersion = (string?)null, hasAttachment = true
                }).ToArray() };
        }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath; Paths.Add(path);
            object value;
            if (path == "/app-api/starbridge/v1/bootstrap")
            {
                var fleet = new ScmBootstrapFleet(7, "FIXTURE", "Fixture fleet", null, true, "Member", 1, []);
                value = new ScmBootstrapSnapshot(new("fixture-owner", "Pilot", null, false), new(false, null),
                    NoFleet ? [] : [fleet], NoFleet ? null : fleet, 0, 1, new() { ["fleets"] = 1 }, DateTimeOffset.UtcNow, ["profile.read", "organizations.read"]);
            }
            else if (path == "/app-api/member/organization/member/page")
                value = new { code = 0, data = new { total = 3, list = Enumerable.Range(1, 3).Select(id => new
                    { userId = id, nickname = id == 2 ? "PRIVATE NAME" : "Public name", organizationRank = "Member" }).ToArray() } };
            else if (path == "/app-api/starbridge/v1/official-fleet/member-identities")
            {
                using var document = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                var now = DateTimeOffset.UtcNow;
                value = new { schemaVersion = 2, sourceRef = "officialFleet:7", members = document.RootElement.GetProperty("memberIds").EnumerateArray().Select(raw =>
                {
                    var id = raw.GetInt64();
                    return new { memberId = id, state = id == 1 ? "visible" : id == 2 ? "restricted" : "unlinked",
                        businessSubjectId = id == 1 ? "scm-v1:" + new string('a', 64) : null, callsign = id == 1 ? "Visible pilot" : null,
                        identityObservedAtUtc = now.ToString("O"), identityValidUntilUtc = now.AddSeconds(5).ToString("O") };
                }).ToArray() };
            }
            else if (path == "/api/official-fleets/realtime/read")
                value = new { schemaVersion = 4, sourceRef = "officialFleet:7", coverage = "requestedOwners", requestedOwnerCount = 1,
                    supportedFilters = new[] { "all" }, runtimeCapabilities = new { presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false },
                    members = new[] { new OfficialRealtimeMemberWire("scm-v1:" + new string('a', 64), "inGame", new("notShared", null, null),
                        new("value", "Fixture ship", null), new("unknown", null, null), false, null, null, null, "lowConfidence") } };
            else if (path == "/api/official-fleets/realtime/activity")
            {
                Interlocked.Increment(ref ActivityReads);
                if (HoldRuntime)
                {
                    try { await Task.Delay(Timeout.Infinite, token); }
                    catch (OperationCanceledException) { Interlocked.Increment(ref RuntimeCancelled); throw; }
                }
                value = new { schemaVersion = 4, sourceRef = "officialFleet:7", changed = true };
            }
            else if (path == "/api/official-fleets/activity")
            {
                Interlocked.Increment(ref CommunicationReads);
                var query = request.RequestUri!.Query;
                var version = query.Contains("after=1&", StringComparison.Ordinal) ? 1 : 0;
                if (query.Contains("after=-1&", StringComparison.Ordinal)) { }
                else if (version == 0)
                {
                    CommunicationWaiting.TrySetResult();
                    await CommunicationChanged.Task.WaitAsync(token);
                    version = 1;
                }
                else await Task.Delay(Timeout.Infinite, token);
                value = new { sourceRef = "officialFleet:7", instanceId = "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa", version, serverTime = DateTimeOffset.UtcNow };
            }
            else if (path == "/api/official-fleets/announcements")
                value = AnnouncementPage();
            else if (path == "/api/official-fleets/context")
                value = new { schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = "OFFICIALFLEET:7", name = "Fixture fleet",
                    announcementsAvailable = HoldRuntime, chatAvailable = Chat, canManageAnnouncements = false, canSend = false,
                    readReceiptsAvailable = false, authorIdentitySchemaVersion = Authors ? 1 : 0 };
            else if (Chat && path == "/api/official-fleets/chat/channels")
                value = new { totalUnread = 0, channels = new[] { new { type = "fleet", channelId = FleetChatIdentity.FleetChannelId("OFFICIALFLEET:7"),
                    unreadCount = 0, canSend = false } } };
            else if (Chat && path == "/api/official-fleets/chat/messages")
            { LegacyChatReads++; value = ChatPage(); }
            else if (Chat && Authors && path == "/api/official-fleets/chat/messages/read")
            {
                AuthorReads++;
                using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                var payload = body.RootElement;
                Check(request.Method == HttpMethod.Post && payload.EnumerateObject().Select(field => field.Name).ToHashSet().SetEquals(
                    ["schemaVersion", "sourceRef", "fleetCode", "mode", "after", "before", "limit", "observedMessages"]) &&
                    payload.GetProperty("schemaVersion").GetInt32() == 2 && payload.GetProperty("sourceRef").GetString() == "officialFleet:7" &&
                    payload.GetProperty("fleetCode").GetString() == "OFFICIALFLEET:7" && payload.GetProperty("mode").GetString() == "page" &&
                    payload.GetProperty("after").GetInt64() == 0 && payload.GetProperty("before").GetInt64() == 0 &&
                    payload.GetProperty("limit").GetInt32() == 50 && payload.GetProperty("observedMessages").GetArrayLength() == 0,
                    "The HUD uses exactly the existing page author read, with no direct identity lookup or extra request fields.");
                var now = DateTimeOffset.UtcNow;
                AuthorUntil = now.AddSeconds(5);
                var version = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes("StarBridge.OfficialFleet.CommunicationAuthor.v1\n" +
                    JsonSerializer.Serialize(new string?[] { "Projected chat author", null })))).ToLowerInvariant();
                value = new { schemaVersion = 2, sourceRef = "officialFleet:7", page = ChatPage(), observedMessages = Array.Empty<object>(),
                    identities = new object[] {
                        AuthorState == "visible" ? (object)new { businessSubjectId = Subject(1), state = "visible", callsign = "Projected chat author", hasAvatar = false,
                            identityVersion = version, identityObservedAtUtc = now.ToString("O"), identityValidUntilUtc = AuthorUntil.ToString("O") }
                            : new { businessSubjectId = Subject(1), state = AuthorState },
                        new { businessSubjectId = Subject(2), state = "hidden" }, new { businessSubjectId = Subject(3), state = "unavailable" }
                    }, authorRefreshRequired = false };
            }
            else throw new Exception("Unexpected synthetic HTTP path: " + path);
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(value, options: new(JsonSerializerDefaults.Web)) };
        }
    }
}
