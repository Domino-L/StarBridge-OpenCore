using System.Net;
using System.Net.Http.Json;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Communities;

internal static class CommunityMemberReferenceAuthorTests
{
    private const string Code = "OFFICIALFLEET:7", Scope = "cx-l13b";
    private static readonly string Subject = "scm-v1:" + new string('a', 64);
    private static readonly string IdentityVersion = Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(
        "StarBridge.OfficialFleet.CommunicationAuthor.v1\n" + JsonSerializer.Serialize(new string?[] { "Fixture", null })))).ToLowerInvariant();

    internal static async Task InvisibleAnnouncementAuthors()
    {
        using var f = new Fixture();
        var initial = await f.Announcements();
        var announcement = initial.GetProperty("current");
        var reference = announcement.GetProperty("announcementRef").GetString()!;
        var member = announcement.GetProperty("author").GetProperty("memberRef").GetString()!;
        Check(announcement.GetProperty("author").GetProperty("identityState").GetString() == "visible", "Fixture projects a real visible identity");
        var visible = await f.Announcements(reference);
        void CheckVisiblePage(JsonElement page)
        {
            Check(page.GetProperty("history").GetArrayLength() == 1, "Fixture includes a history announcement");
            foreach (var entry in new[] { page.GetProperty("current"), page.GetProperty("history")[0] })
                foreach (var role in new[] { "author", "editor" })
                    Check(entry.GetProperty(role).GetProperty("identityState").GetString() == "visible" &&
                        entry.GetProperty(role).GetProperty("memberRef").GetString() == member && member.Length == 32,
                        "Visible current/history people preserve the mapped address");
        }
        CheckVisiblePage(initial);
        CheckVisiblePage(visible);
        Check(visible.GetProperty("authorUpdates")[0].GetProperty("author").GetProperty("memberRef").GetString() == member,
            "Visible author updates preserve the mapped address");
        Check((await f.Detail(reference)).GetProperty("author").GetProperty("memberRef").GetString() == member,
            "Visible author detail preserves the mapped address");
        var failures = new List<string>();
        void CheckPeople(JsonElement value, string scenario)
        {
            foreach (var role in new[] { "author", "editor" })
                if (value.GetProperty(role).GetProperty("memberRef").ValueKind != JsonValueKind.Null)
                    failures.Add(scenario + "/" + role + " retained memberRef");
        }
        void CheckPage(JsonElement page, string scenario)
        {
            CheckPeople(page.GetProperty("current"), scenario + " current");
            CheckPeople(page.GetProperty("history")[0], scenario + " history");
            CheckPeople(page.GetProperty("authorUpdates")[0], scenario + " update");
        }
        foreach (var state in new[] { "hidden", "unavailable" })
        {
            f.Handler.State = "visible";
            CheckVisiblePage(await f.Announcements(reference));
            f.Handler.State = state;
            CheckPage(await f.Announcements(reference), state);
            CheckPeople(await f.Detail(reference), state + " detail");
        }
        f.Handler.State = "visible";
        var pendingPage = await f.AnnouncementResponse(reference);
        var pendingDetail = await f.DetailResponse(reference);
        f.Clock.Now += TimeSpan.FromSeconds(6);
        CheckPage(Freeze(pendingPage), "expired at publication");
        CheckPeople(Freeze(pendingDetail), "expired at publication detail");
        f.Handler.NotRetained = true;
        var missing = (await f.Announcements(reference)).GetProperty("authorUpdates")[0];
        Check(missing.GetProperty("recordState").GetString() == "notRetained", "Fixture exercises the notRetained projection");
        CheckPeople(missing, "notRetained update");
        Check(failures.Count == 0, string.Join("; ", failures));
    }

    internal static async Task LapsedAnnouncementAuthors(double observedOffset)
    {
        using var f = new Fixture();
        var first = await f.Announcements();
        var reference = first.GetProperty("current").GetProperty("announcementRef").GetString()!;
        f.Handler.ObservedOffset = observedOffset;
        var page = await f.Announcements(reference);
        foreach (var entry in new[] { page.GetProperty("current"), page.GetProperty("history")[0], page.GetProperty("authorUpdates")[0], await f.Detail(reference) })
        foreach (var role in new[] { "author", "editor" })
        {
            var person = entry.GetProperty(role);
            Check(person.GetProperty("identityState").GetString() == "unavailable" && person.GetProperty("callsign").GetString() == "" &&
                person.GetProperty("memberRef").ValueKind == JsonValueKind.Null, "Announcement lapsed proof remains unavailable with no member reference");
        }
    }

    internal static async Task ChatReferencesAgree()
    {
        var failures = new List<string>();
        foreach (var removal in new[] { "expired", "evicted", "replaced by another read" })
        {
            using var f = new Fixture();
            var first = (await f.Chat()).GetProperty("messages")[0];
            var message = first.GetProperty("messageRef").GetString()!;
            var original = first.GetProperty("senderRef").GetString()!;
            if (removal != "evicted") f.RetentionNow += TimeSpan.FromHours(24);
            else for (var i = 0; i < 10000; i++)
                CommunityMemberReferenceTests.Retained(f.Client, "account:filler-" + i, Code, Scope, true);
            Check(CommunityMemberReferenceTests.Retained(f.Client, "account:" + Subject, Code, Scope, false) is null,
                "Fixture removes the sender mapping: " + removal);
            if (removal == "replaced by another read") await f.Announcements();
            var response = await f.Chat(message);
            var current = response.GetProperty("messages")[0];
            var update = response.GetProperty("authorUpdates")[0];
            Check(current.GetProperty("messageRef").GetString() == message && update.GetProperty("messageRef").GetString() == message,
                "The response describes the same observed message");
            var sender = current.GetProperty("senderRef").GetString()!;
            if (update.GetProperty("senderRef").GetString() != sender) failures.Add(removal + ": messages and authorUpdates senderRef differ");
            await f.Media(sender);
            try { await f.Media(update.GetProperty("senderRef").GetString()!); }
            catch (StarBridge.HostRuntime.Account.AccountBridgeHostException error) { failures.Add(removal + ": authorUpdates avatar " + error.Code); }
            // Hidden author updates still carry the message address, while presentation is redacted.
            f.Handler.State = "hidden";
            var hidden = (await f.Chat(message)).GetProperty("authorUpdates")[0];
            Check(hidden.GetProperty("senderRef").GetString() == sender && hidden.GetProperty("senderCallsign").GetString() == "" &&
                hidden.GetProperty("authorIdentityState").GetString() == "hidden", "Hidden chat updates keep address matching without display identity");
            Check(original.Length == 32, "Original address is opaque");
        }
        Check(failures.Count == 0, string.Join("; ", failures));
    }

    private static JsonElement Freeze(object response) => JsonSerializer.SerializeToElement(response);
    private static JsonElement Body(object value) => JsonSerializer.SerializeToElement(value);
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }

    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly Clock Clock = new();
        internal readonly Handler Handler;
        internal readonly CommunityClient Client;
        internal DateTimeOffset RetentionNow = DateTimeOffset.UtcNow;
        private readonly string _target;
        internal Fixture()
        {
            Handler = new(Clock);
            Client = new(new Uri("https://community.invalid"), Handler, Clock);
            Client.MemberReferenceUtcNow = () => RetentionNow;
            _target = Freeze(Client.OpenOfficialFleetAsync("fixture", "officialFleet:7", Scope, () => { }, default).GetAwaiter().GetResult())
                .GetProperty("targetRef").GetString()!;
        }
        internal Task<object> AnnouncementResponse(params string[] observed) => Client.ReadAnnouncementsAsync("fixture", Body(new
            { schemaVersion = 1, targetRef = _target, offset = 0, authorIdentitySchemaVersion = 1, observeAnnouncementRefs = observed }), Scope, () => { }, default);
        internal async Task<JsonElement> Announcements(params string[] observed) => Freeze(await AnnouncementResponse(observed));
        internal Task<object> DetailResponse(string reference) => Client.ReadAnnouncementDetailAsync("fixture", Body(new
        {
            schemaVersion = 1, targetRef = _target, announcementRef = reference, offset = 0, authorIdentitySchemaVersion = 1,
            expectedAuthorIdentityVersion = IdentityVersion, expectedEditorIdentityVersion = IdentityVersion
        }), Scope, () => { }, default);
        internal async Task<JsonElement> Detail(string reference) => Freeze(await DetailResponse(reference));
        internal async Task<JsonElement> Chat(params string[] observed) => Freeze(await Client.ReadChatAsync("fixture", Body(new
            { schemaVersion = 1, targetRef = _target, after = 0, before = 0, authorIdentitySchemaVersion = 1, observeMessageRefs = observed }), Scope, () => { }, default));
        internal Task<object> Media(string reference) => Client.ReadMediaAsync("fixture", Body(new
            { schemaVersion = 1, targetRef = _target, kind = "avatar", memberRef = reference, offset = 0 }), Scope, default);
        public void Dispose() => Client.Dispose();
    }

    // Every route is served in memory; unknown routes fail instead of reaching a socket.
    private sealed class Handler(Clock clock) : HttpMessageHandler
    {
        internal string State = "visible";
        internal double ObservedOffset;
        internal bool NotRetained;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            object response;
            if (path == "/api/official-fleets/context") response = new
            {
                schemaVersion = 1, sourceRef = "officialFleet:7", fleetCode = Code, name = "Fixture", announcementsAvailable = true,
                chatAvailable = true, canSend = false, readReceiptsAvailable = false, canManageAnnouncements = false, authorIdentitySchemaVersion = 1
            };
            else if (path == "/api/official-fleets/chat/channels") response = new
                { totalUnread = 0, channels = new[] { new { channelId = "fleet:" + Code, type = "fleet", unreadCount = 0, latestSequence = 1, canSend = false } } };
            else if (path == "/api/fleets/media") response = new
            {
                schemaVersion = 1, kind = "avatar", memberId = "account:" + Subject, version = new string('a', 64),
                mimeType = "image/png", totalBytes = 1, offset = 0, next = (int?)null, data = "AQ=="
            };
            else
            {
                using var document = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                var body = document.RootElement;
                var detail = body.GetProperty("mode").GetString() == "detail";
                var identities = NotRetained ? Array.Empty<object>() : new[] { Identity() };
                if (path == "/api/official-fleets/announcements/read")
                {
                    var page = new JsonObject
                    {
                        ["schemaVersion"] = 1, ["membershipModelVersion"] = 2, ["fleetCode"] = Code, ["revision"] = 2L, ["canManage"] = false
                    };
                    if (detail) page["entry"] = JsonSerializer.SerializeToNode(Announcement());
                    else
                    {
                        page["refreshedAt"] = clock.Now.ToString("O"); page["totalHistoryCount"] = NotRetained ? 0 : 1; page["offset"] = 0; page["next"] = null;
                        page["current"] = NotRetained ? null : JsonSerializer.SerializeToNode(Announcement());
                        page["history"] = NotRetained ? new JsonArray() : new JsonArray(JsonSerializer.SerializeToNode(Announcement(history: true)));
                    }
                    var observed = body.GetProperty("observedAnnouncements").EnumerateArray().Select(row => NotRetained
                        ? (object)new { announcementId = row.GetProperty("announcementId").GetString(), revision = 2, recordState = "notRetained" }
                        : new { announcementId = row.GetProperty("announcementId").GetString(), revision = 2, recordState = "found", authorAccountId = Subject, editorAccountId = Subject }).ToArray();
                    response = new { schemaVersion = 2, sourceRef = "officialFleet:7", page, observedAnnouncements = observed, identities, authorRefreshRequired = false };
                }
                else if (path == "/api/official-fleets/chat/messages/read")
                {
                    Check(!detail, "Only page chat reads expected");
                    var page = new
                    {
                        schemaVersion = 1, channelId = "fleet:" + Code, latestSequence = 1, oldestSequence = 1, hasOlder = false,
                        canSend = false, serverTime = clock.Now.ToString("O"), messages = new[] { new
                        {
                            sequence = 1, messageId = "fixture", senderAccountId = Subject, senderCallsign = "", senderGameId = "", senderRoleTitle = "",
                            senderRoleColor = "#9DAAB3", text = "fixture", createdAt = "2026-10-30T00:00:00Z", isSelf = false, hasAvatar = false, hasAttachment = false
                        } }
                    };
                    response = new
                    {
                        schemaVersion = 2, sourceRef = "officialFleet:7", page, identities, authorRefreshRequired = false,
                        observedMessages = body.GetProperty("observedMessages").EnumerateArray().Select(row => new
                            { messageId = row.GetProperty("messageId").GetString(), sequence = 1, recordState = "found", senderAccountId = Subject }).ToArray()
                    };
                }
                else throw new InvalidOperationException("Unexpected fixture route");
            }
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(response) };
        }
        private object Identity() => State != "visible" ? new { businessSubjectId = Subject, state = State } : new
        {
            businessSubjectId = Subject, state = "visible", callsign = "Fixture", hasAvatar = false, identityVersion = IdentityVersion,
            identityObservedAtUtc = clock.Now.AddSeconds(ObservedOffset), identityValidUntilUtc = clock.Now.AddSeconds(ObservedOffset + 5)
        };
        private static object Announcement(bool history = false)
        {
            var person = new { accountId = Subject, callsign = "", gameId = "", roleTitle = "", roleColor = "#9DAAB3", avatarImageData = (string?)null };
            return new { authorHasAvatar = false, lastEditorHasAvatar = false, announcement = new
            {
                id = history ? "fixture-history" : "fixture", fleetCode = Code, title = "Fixture", content = "", revision = 2, state = history ? "Archived" : "Published",
                publishedAt = "2026-10-30T00:00:00Z", updatedAt = "2026-10-30T00:00:00Z",
                archivedAt = history ? "2026-10-30T00:00:00Z" : null, withdrawnAt = (string?)null,
                author = person, lastEditor = person
            } };
        }
    }
}
