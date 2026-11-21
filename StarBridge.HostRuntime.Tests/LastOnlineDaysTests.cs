using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Friends;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Support;

internal static class LastOnlineDaysTests
{
    private static void Check(bool value, string message)
    { if (!value) throw new Exception(message); }

    internal static async Task Run()
    {
        var now = DateTimeOffset.UtcNow;
        Calendar();
        var hourText = OkHour;
        var hourAt = LastOnlineDays.ParseHour(hourText)!.Value;
        var good = $",\"lastOnlineHour\":\"{hourText}\"";
        foreach (var field in new[] { "", ",\"lastOnlineHour\":null", good,
            ",\"lastOnlineHour\":\"2026-11-13T15:30:00Z\"", ",\"lastOnlineHour\":\"2026-11-13T15:00:00+08:00\"",
            ",\"lastOnlineHour\":\"2026-11-13T15:00:00.000Z\"", ",\"lastOnlineHour\":3", ",\"lastOnlineDays\":3",
            good + ",\"unexpected\":0" })
        {
            var valid = field == "" || field == ",\"lastOnlineHour\":null" || field == good;
            var shared = JsonNode.Parse("{\"presence\":\"Offline\"" + field + "}")!;
            var user = JsonSerializer.SerializeToNode(FriendsReaderTests.User())!;
            user["shared"] = shared;
            try {
                var before = DateTimeOffset.UtcNow;
                var row = FriendsReader.Parse(FriendsReaderTests.Directory(user), sharing: true).Friends.Single();
                Check(valid, "Invalid friend shared accepted");
                Check(field == good ? Within(row.Shared?.LastOnlineDays, hourAt, before) : row.Shared?.LastOnlineDays is null, "Friend calendar days");
                Check(row.Shared?.LastOnlineHour is null && row.Shared?.LastOnlineAt is null, "Neither the relay hour nor the precise time crosses the bridge");
                var bridged = JsonSerializer.SerializeToNode(row.Shared, LocalPrivacyStore.Json)!.AsObject();
                Check(!bridged.ContainsKey("lastOnlineHour"), "Bridge shared omits the hour key");
            } catch (AccountBridgeHostException e) when (!valid) { Check(e.Code == "friends.data_invalid", "Friend stable rejection"); }
        }
        var legacyUser = JsonSerializer.SerializeToNode(FriendsReaderTests.User())!;
        legacyUser["shared"] = new JsonObject { ["presence"] = "Offline", ["lastOnlineAt"] = now.AddDays(-5).ToString("O") };
        var legacyBefore = DateTimeOffset.UtcNow;
        var legacyShared = FriendsReader.Parse(FriendsReaderTests.Directory(legacyUser), sharing: true).Friends.Single().Shared;
        Check(Within(legacyShared?.LastOnlineDays, now.AddDays(-5), legacyBefore) && legacyShared?.LastOnlineAt is null,
            "Older relay precise time falls back to calendar days and stays in the Host");
        // A relay that speaks the hour contract is authoritative even when it says null: no legacy fallback.
        var authoritative = JsonSerializer.SerializeToNode(FriendsReaderTests.User())!;
        authoritative["shared"] = new JsonObject { ["presence"] = "Offline", ["lastOnlineHour"] = null,
            ["lastOnlineAt"] = now.AddDays(-5).ToString("O") };
        Check(FriendsReader.Parse(FriendsReaderTests.Directory(authoritative), sharing: true).Friends.Single().Shared?.LastOnlineDays is null,
            "Null hour masks the legacy time");

        using (var reader = new FriendsReader(new("https://fixture.invalid"), new Handler(request => {
            Header(request, HttpMethod.Get, "/api/friends");
            return Ok(FriendsReaderTests.Directory());
        }))) await reader.ReadAsync("", null, default);

        foreach (var state in new[] { "friend", "accepted", "request_incoming" })
        foreach (var days in new int?[] { null, 0, 3, 30 })
        {
            using var reader = new FriendsReader(new("https://fixture.invalid"), new Handler(request => {
                Header(request, HttpMethod.Get, "/api/friends/chat/conversations");
                return Json(new { conversations = new[] { new {
                    user = new { accountId = "fixture", callsign = "Fixture", gameId = "", shared = new {
                        presence = "Offline", lastOnlineHour = days is { } d ? Hour(now.AddDays(-d)) : null, lastOnlineAt = now.AddHours(-75) } },
                    lastMessagePreview = "", lastMessageAt = now, unreadCount = 0, conversationState = state
                } }, totalUnread = 0, serverTime = now });
            }));
            var before = DateTimeOffset.UtcNow;
            var view = (ConversationsView)await reader.ReadChatAsync("", JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), default, "fixture");
            var actual = view.Conversations.Single().LastOnlineDays;
            // The hour key is always present here, so a null hour never falls back to lastOnlineAt.
            var at = days is { } back ? LastOnlineDays.ParseHour(Hour(now.AddDays(-back))) : null;
            Check(state == "friend" && at is { } seen ? Within(actual, seen, before) : actual is null, "Conversation friend-only hour");
        }
        await Official();
        await Community();
    }

    private static async Task Official()
    {
        const string owner = "fixture-owner";
        foreach (var raw in HourCases())
        {
            var valid = raw is "missing" or "null" or "OK";
            var row = new JsonObject {
                ["ownerBusinessSubjectId"] = owner, ["presence"] = "offline",
                ["server"] = Cell(), ["ship"] = Cell(), ["location"] = Cell(),
                ["arrivalPending"] = false, ["arrivalTargetCode"] = null,
                ["serverRegion"] = null, ["hasServerSession"] = null, ["locationHiddenReason"] = null
            };
            if (raw != "missing") row["lastOnlineHour"] = HourNode(raw);
            using var writer = new PrivacyRelayWriter(new("https://fixture.invalid"), new Handler(request => {
                Header(request, HttpMethod.Post, "/api/official-fleets/realtime/read");
                return Json(new { schemaVersion = 4, sourceRef = "officialFleet:7", coverage = "requestedOwners", requestedOwnerCount = 1,
                    members = new[] { row }, supportedFilters = new[] { "all" }, runtimeCapabilities = new {
                        presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false } });
            }));
            try {
                var rows = await writer.ReadOfficialRuntimeAsync("", "officialFleet:7", [owner], default, () => { });
                Check(valid, "Invalid official days accepted");
                Check(rows[owner].LastOnlineHour == (raw is "missing" or "null" ? null : OkHour), "Official hour read");
            } catch (AccountBridgeHostException) when (!valid) { }
        }
    }

    private static async Task Community()
    {
        foreach (var raw in HourCases())
        {
            var valid = raw is "missing" or "null" or "OK";
            using var client = new CommunityClient(new("https://fixture.invalid"), new Handler(request => {
                if (request.RequestUri!.AbsolutePath == "/api/fleets/directory") return Json(new {
                    schemaVersion = 1, membershipModelVersion = 2, view = "mine", query = "", next = (string?)null,
                    items = new[] { new { code = "A", name = "Fixture", description = "", language = "", activeTime = "",
                        memberCount = 1, relationship = "member", joinMode = "direct", actions = new[] { "leave" }, logoImageData = (string?)null } }
                });
                Header(request, HttpMethod.Get, "/api/fleets/workspace");
                var body = CommunityWorkspaceClientTests.Workspace();
                var member = body["members"]![0]!;
                member["liveStatus"] = "Invisible";
                if (raw != "missing") member["lastOnlineHour"] = HourNode(raw);
                return Json(body);
            }));
            var directory = await client.ReadAsync("", new("mine", "", null, null), "fixture", default);
            var before = DateTimeOffset.UtcNow;
            try {
                var body = await client.ReadWorkspaceAsync("", JsonSerializer.SerializeToElement(new {
                    schemaVersion = 1, targetRef = directory.Items.Single().TargetRef, query = "", offset = 0 }), "fixture", default);
                Check(valid, "Invalid community days accepted");
                var row = JsonSerializer.SerializeToElement(body).GetProperty("members")[0];
                var projected = row.GetProperty("lastOnlineDays");
                Check(raw is "missing" or "null" ? projected.ValueKind == JsonValueKind.Null :
                    Within(projected.GetInt32(), LastOnlineDays.ParseHour(OkHour)!.Value, before), "Offline projection carries calendar days");
                Check(row.GetProperty("lastUpdated").ValueKind == JsonValueKind.Null, "No runtime time fallback");
            } catch (AccountBridgeHostException) when (!valid) { }
        }
    }

    // Local calendar: same local date 0, one local midnight crossed 1, cap 30, a skewed future hour stays 0.
    private static void Calendar()
    {
        var zone = TimeZoneInfo.CreateCustomTimeZone("fixture+8", TimeSpan.FromHours(8), "fixture+8", "fixture+8");
        var now = new DateTimeOffset(2026, 11, 14, 1, 0, 0, TimeSpan.Zero); // 09:00 local
        Check(LastOnlineDays.CalendarDays(now.AddHours(-8), now, zone) == 0, "Same local day is today"); // 01:00 local
        Check(LastOnlineDays.CalendarDays(now.AddHours(-10), now, zone) == 1, "Last night 23:00 local is yesterday");
        Check(LastOnlineDays.CalendarDays(now.AddHours(-34), now, zone) == 2, "Two local midnights");
        Check(LastOnlineDays.CalendarDays(now.AddDays(-99), now, zone) == 30, "Cap at 30");
        Check(LastOnlineDays.CalendarDays(now.AddHours(20), now, zone) == 0, "Clock skew never goes negative");
        Check(LastOnlineDays.Resolve(null, null, now, zone) is null, "Missing stays missing");
        Check(LastOnlineDays.Resolve(now.AddDays(-3), now.AddDays(-9), now, zone) == 3, "Relay hour wins over legacy time");
        Check(LastOnlineDays.ParseHour("2026-11-13T15:00:00Z") is { Hour: 15, Minute: 0 } ok && ok.Offset == TimeSpan.Zero, "Whole UTC hour parses");
        foreach (var bad in new[] { "2026-11-13T15:01:00Z", "2026-11-13T15:00:01Z", "2026-11-13T15:00:00+00:00", "2026-11-13 15:00:00Z", "", "1969-12-31T23:00:00Z" })
            Check(LastOnlineDays.ParseHour(bad) is null, "Rejected hour " + bad);
    }

    private static string Hour(DateTimeOffset at)
    {
        var utc = at.UtcDateTime;
        return new DateTime(utc.Year, utc.Month, utc.Day, utc.Hour, 0, 0, DateTimeKind.Utc)
            .ToString("yyyy-MM-dd'T'HH':00:00Z'", System.Globalization.CultureInfo.InvariantCulture);
    }

    // "OK" is one valid whole UTC hour three days back, fixed for the whole run; the other present values must be rejected.
    private static readonly string OkHour = Hour(DateTimeOffset.UtcNow.AddDays(-3));
    private static string[] HourCases() => ["missing", "null", "OK", "\"2026-11-13T15:30:00Z\"", "\"2026-11-13T15:00:00+08:00\"", "3", "true"];
    private static JsonNode? HourNode(string raw) => raw == "OK" ? JsonValue.Create(OkHour) : JsonNode.Parse(raw);

    // The production read takes its own clock; accept the day count at either end of the call so a local midnight
    // between the two never flakes.
    private static bool Within(int? actual, DateTimeOffset at, DateTimeOffset before) =>
        actual == LastOnlineDays.CalendarDays(at, before, TimeZoneInfo.Local) ||
        actual == LastOnlineDays.CalendarDays(at, DateTimeOffset.UtcNow, TimeZoneInfo.Local);

    private static JsonObject Cell() => new() { ["state"] = "notInGame", ["value"] = null, ["confidence"] = null };
    private static void Header(HttpRequestMessage request, HttpMethod method, string path) =>
        Check(request.Method == method && request.RequestUri!.AbsolutePath == path &&
            request.Headers.GetValues(LastOnlineDays.HeaderName).Single() == "hour-v1", "Read negotiation header");
    private static HttpResponseMessage Json(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    private static HttpResponseMessage Ok(byte[] body) => new(HttpStatusCode.OK) { Content = new ByteArrayContent(body) };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
