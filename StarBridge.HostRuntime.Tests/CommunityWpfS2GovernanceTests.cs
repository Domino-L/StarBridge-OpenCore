using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2GovernanceTests
{
    private static readonly JsonSerializerOptions Web = new(JsonSerializerDefaults.Web);
    internal static async Task Verify()
    {
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            fixture.Clock.Advance(6);
            var requests = fixture.Requests;
            try
            {
                await fixture.Client.ReadWpfS2GovernanceAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef }),
                    "another-scope", "roles", () => { }, default);
                throw new InvalidOperationException("cross-account root read unexpectedly accepted");
            }
            catch (AccountBridgeHostException e) when (e.Code == "communities.refreshRequired") { }
            Check(fixture.Requests == requests, "retained address cannot cross account scope or reach HTTP");
            fixture.Clock.Advance(1440);
            await fixture.Read("roles");
            Check(fixture.Requests > requests && fixture.Posts.Count == 0,
                "idle address requires fresh server authorization without restoring any write lease");
            fixture.HasMembership = false;
            try { await fixture.Read("roles"); throw new InvalidOperationException("revoked idle address unexpectedly accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.notAllowed") { }
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            fixture.Clock.Advance(6);
            await fixture.Client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "owner-secret", default);
            var roles = await fixture.Read("roles");
            Check(roles.GetProperty("roles").GetArrayLength() > 0, "idle management page revalidates without returning to directory");
            fixture.Clock.Advance(6);
            var logs = E(await fixture.Client.ReadWpfS2LogsAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef, type = "All", query = "", offset = 0 }), "scope", () => { }, default));
            Check(logs.GetProperty("items").GetArrayLength() == 1, "idle logs page revalidates");
            fixture.Clock.Advance(6);
            await fixture.Client.ReadAdmissionsAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef, section = "applications", offset = 0 }), "scope", () => { }, default, wpfS2: true);
            fixture.Clock.Advance(6);
            await fixture.Client.ReadAnnouncementsAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef, offset = 0 }), "scope", () => { }, default);
            Check(fixture.Posts.Count == 0, "refreshing a stale page never retries a write");
            fixture.Clock.Advance(16);
            var expired = await fixture.Write("roles", roles, new() { ["roles"] = roles.GetProperty("roles").EnumerateArray().Select(Draft).ToArray() });
            Check(Status(expired) == "rejected" && fixture.Posts.Count == 0, "stale write confirmation cannot be renewed by root read recovery");
            fixture.HasMembership = false;
            try { await fixture.Read("roles"); throw new InvalidOperationException("revoked member unexpectedly read roles"); }
            catch (AccountBridgeHostException e) when (e.Code == "communities.notAllowed") { }
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("roles");
            Check(!edit.GetRawText().Contains("owner-secret") && !edit.GetRawText().Contains("member-secret"), "role projection omits account IDs");
            var roles = edit.GetProperty("roles").EnumerateArray().Select(row => Draft(row)).ToArray();
            roles[1]["displayName"] = "副负责人调整";
            var result = await fixture.Write("roles", edit, new() { ["roles"] = roles });
            Check(Status(result) == "accepted", "S2 role definitions save");
            Check(fixture.Posts.Single() == "/api/fleets/info", "roles use original unprojected info route");
            Check(fixture.LastBody!["bannerImageData"]!.GetValue<string>() == "preserved-banner" &&
                fixture.LastBody["websiteUrl"]!.GetValue<string>() == "https://fixture.invalid/about" &&
                fixture.LastBody["updatedSections"]![0]!.GetValue<string>() == "role-groups", "roles preserve unrelated profile data and section intent");
            Check(result.GetProperty("profileRevision").GetInt64() == 2, "new revision reaches existing editor");
            var reread = E(await fixture.Client.ReadWpfS2GovernanceAsync("fixture", E(new { schemaVersion = 1, editRef = edit.GetProperty("editRef").GetString() }),
                "scope", "roles", () => { }, default));
            Check(reread.GetProperty("profileRevision").GetInt64() == 2, "existing role editor can reread its consumed write handle");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("roles");
            fixture.Fleet["profileRevision"] = 9;
            var result = await fixture.Write("roles", edit, new() { ["roles"] = edit.GetProperty("roles").EnumerateArray().Select(Draft).ToArray() });
            Check(Status(result) == "rejected" && fixture.Posts.Count == 0, "stale profile version cannot overwrite a concurrent change");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("role");
            Check(edit.GetProperty("canAssign").GetBoolean(), "owner may assign another member");
            var result = await fixture.Write("role", edit, new() { ["roleKey"] = "fleet_deputy_commander" });
            Check(Status(result) == "accepted" && fixture.Posts.Single() == "/api/fleets/permissions", "original role assignment accepted");
            var permission = fixture.LastBody!["permission"]!;
            Check(permission["gameName"]!.GetValue<string>() == "Pilot" && permission["canManageFleetInfo"]!.GetValue<bool>() &&
                permission["canRemoveMembers"]!.GetValue<bool>() && !permission["canPublishTasks"]!.GetValue<bool>(), "WPF role flags and actual target name preserved");
            var reread = E(await fixture.Client.ReadWpfS2GovernanceAsync("fixture", E(new { schemaVersion = 1, editRef = edit.GetProperty("editRef").GetString() }),
                "scope", "role", () => { }, default));
            Check(reread.GetProperty("roleKey").GetString() == "fleet_deputy_commander", "member editor confirms saved role through original edit reference");
        }
        foreach (var kind in new[] { "role", "remove", "transfer", "exit" })
        {
            using var fixture = new Fixture();
            await fixture.Open();
            var self = await fixture.Read(kind, self: true);
            Check(!self.GetProperty(kind == "role" ? "canAssign" : kind == "remove" ? "canRemove" : "canTransfer").GetBoolean(), "self/owner is protected: " + kind);
            var denied = await fixture.Write(kind, self, kind == "role" ? new() { ["roleKey"] = "" } : null);
            Check(Status(denied) == "rejected" && fixture.Posts.Count == 0, "protected target never reaches transport");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            fixture.Fleet["ownerAccount"] = "another-login";
            fixture.Fleet["commander"] = "Another";
            fixture.Fleet["memberPermissions"]![0]!["roleGroupKey"] = "fleet_deputy_commander";
            var remove = await fixture.Read("remove");
            Check(remove.GetProperty("canRemove").GetBoolean(), "manager may remove an ordinary member");
            foreach (var kind in new[] { "role", "transfer", "exit" })
            {
                var edit = await fixture.Read(kind);
                Check(!edit.GetProperty(kind == "role" ? "canAssign" : "canTransfer").GetBoolean(), "manager cannot exercise owner-only action");
            }
            fixture.Fleet["memberPermissions"]!.AsArray().Add(JsonSerializer.SerializeToNode(new
                { gameName = "Pilot", accountId = "member-secret", permissionEnabled = true, roleGroupKey = "fleet_deputy_commander" }, Web));
            var protectedMember = await fixture.Read("remove");
            Check(!protectedMember.GetProperty("canRemove").GetBoolean(), "manager cannot remove another privileged member");
        }
        foreach (var kind in new[] { "remove", "transfer", "exit" })
        {
            using var fixture = new Fixture();
            await fixture.Open();
            var edit = await fixture.Read(kind);
            var result = await fixture.Write(kind, edit);
            Check(Status(result) == "accepted", "S2 membership mutation completes: " + kind);
            Check(fixture.Posts.Single() == (kind == "remove" ? "/api/fleets/members/remove" : kind == "exit" ? "/api/fleets/leave" : "/api/fleets/transfer-commander"), "original membership route");
            if (kind == "exit") Check(fixture.LastBody!["transferCommanderTo"]!.GetValue<string>() == "Pilot", "owner exit is one atomic request with named successor");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("remove");
            fixture.Fleet["ownerAccount"] = "someone-else";
            var result = await fixture.Write("remove", edit);
            Check(Status(result) == "rejected" && fixture.Posts.Count == 0, "authority loss blocks captured confirmation");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("remove");
            fixture.DropReply = true;
            var requestId = Guid.NewGuid().ToString("N");
            var result = await fixture.Write("remove", edit, new() { ["requestId"] = requestId });
            var replay = await fixture.Write("remove", edit, new() { ["requestId"] = requestId });
            Check(Status(result) == "unknown" && Status(replay) == "unknown" && fixture.Posts.Count == 1, "lost reply is retained and never automatically replayed");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("remove");
            fixture.Client.InvalidateWpfS2Governance();
            var result = await fixture.Write("remove", edit);
            Check(Status(result) == "rejected" && fixture.Posts.Count == 0, "account generation invalidates pending confirmation");
            await Error(() => fixture.Client.ReadWpfS2GovernanceAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef }), "other", "roles", () => { }, default));
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var logs = E(await fixture.Client.ReadWpfS2LogsAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef, type = "All", query = "加入", offset = 0 }), "scope", () => { }, default));
            Check(logs.GetProperty("matchedCount").GetInt32() == 1 && !logs.GetRawText().Contains("log-private"), "legacy logs support bounded local filter and private refs");
            var row = logs.GetProperty("items")[0];
            Check(row.GetProperty("timestamp").GetString() == row.GetProperty("endTimestamp").GetString(), "old default log end time is normalized");
            var result = E(await fixture.Client.WriteWpfS2GovernanceAsync("fixture", E(new { schemaVersion = 1, targetRef = fixture.TargetRef, logRef = row.GetProperty("logRef").GetString() }), "scope", "log", () => { }, default));
            Check(Status(result) == "accepted" && fixture.Posts.Single() == "/api/fleets/logs/delete", "log deletion verifies disappearance in returned snapshot");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("disband");
            const string password = " exact password ";
            var command = E(new { schemaVersion = 1, targetRef = fixture.TargetRef, confirmationRef = edit.GetProperty("confirmationRef").GetString(), password });
            var result = E(await fixture.Client.WriteWpfS2GovernanceAsync("fixture", command, "scope", "disband", () => { }, default));
            Check(Status(result) == "accepted" && fixture.LastBody!["password"]!.GetValue<string>() == password &&
                !result.GetRawText().Contains(password), "disband preserves original credential exactly and never returns it");
            await fixture.Client.WriteWpfS2GovernanceAsync("fixture", command, "scope", "disband", () => { }, default);
            Check(fixture.Posts.Count == 1, "disband confirmation is single-use");
        }
        using (var fixture = new Fixture())
        {
            await fixture.Open();
            var edit = await fixture.Read("remove");
            fixture.WrongReceipt = true;
            var result = await fixture.Write("remove", edit);
            Check(Status(result) == "unknown", "HTTP 200 alone is not a valid mutation receipt");
        }
    }

    private static Dictionary<string, object?> Draft(JsonElement row) => row.EnumerateObject()
        .Where(p => new[] { "key", "displayName", "description", "color", "sortOrder", "isEnabled", "permissions" }.Contains(p.Name))
        .ToDictionary(p => p.Name, p => (object?)p.Value.Clone());
    private static JsonElement E(object value) => JsonSerializer.SerializeToElement(value, Web);
    private static string? Status(JsonElement value) => value.GetProperty("status").GetString();
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> action)
    {
        try { await action(); throw new InvalidOperationException("Expected scoped-reference rejection"); }
        catch (AccountBridgeHostException) { }
    }

    private sealed class TargetClock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(int minutes) => _now = _now.AddMinutes(minutes);
    }

    private sealed class Fixture : HttpMessageHandler
    {
        internal readonly TargetClock Clock = new();
        internal readonly CommunityClient Client;
        internal readonly JsonObject Fleet;
        internal readonly List<string> Posts = [];
        internal int Requests;
        internal JsonNode? LastBody;
        internal bool DropReply, WrongReceipt;
        internal bool HasMembership = true;
        internal string TargetRef = "", MemberRef = "", SelfRef = "";
        private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-11T00:00:00Z");
        internal Fixture()
        {
            Client = new(new Uri("https://fixture.invalid"), this, Clock);
            Fleet = JsonSerializer.SerializeToNode(new
            {
                code = "A", name = "测试舰队", commander = "Owner", ownerAccount = "owner-login", profileRevision = 1,
                totalMembers = 2, description = "保留", type = "自由", language = "any", activeTime = "19:00", joinPolicy = "Open",
                bannerImageData = "preserved-banner", logoImageData = (string?)null, websiteUrl = "https://fixture.invalid/about",
                roleGroups = new[] { Role("fleet_commander", "负责人", 0, ["members.remove", "audit.delete"]),
                    Role("fleet_deputy_commander", "副负责人", 1, ["members.remove", "fleet.profile.edit", "audit.view"]) },
                members = new[] { Member("Owner", "owner-secret", "负责人"), Member("Pilot", "member-secret", "成员") },
                memberPermissions = new[] { Permission("Owner", "owner-secret", "fleet_commander") },
                eventLog = new[] { new { id = "log-private", timestamp = Now, endTimestamp = DateTimeOffset.MinValue, type = "成员", title = "加入组织", detail = "成员已加入", occurrenceCount = 1 } },
                applications = Array.Empty<object>(), invites = Array.Empty<object>()
            }, Web)!.AsObject();
        }
        internal async Task Open()
        {
            var mine = await Client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "owner-secret", default);
            TargetRef = mine.Items.Single().TargetRef;
            var workspace = E(await Client.ReadWorkspaceAsync("fixture", E(new { schemaVersion = 1, targetRef = TargetRef, query = "", offset = 0 }), "scope", default));
            var members = workspace.GetProperty("members").EnumerateArray().ToArray();
            SelfRef = members.Single(row => row.GetProperty("gameName").GetString() == "Owner").GetProperty("memberRef").GetString()!;
            MemberRef = members.Single(row => row.GetProperty("gameName").GetString() == "Pilot").GetProperty("memberRef").GetString()!;
        }
        internal async Task<JsonElement> Read(string kind, bool self = false)
        {
            object payload = kind is "roles" or "disband" ? new { schemaVersion = 1, targetRef = TargetRef } :
                new { schemaVersion = 1, targetRef = TargetRef, memberRef = self ? SelfRef : MemberRef };
            return E(await Client.ReadWpfS2GovernanceAsync("fixture", E(payload), "scope", kind, () => { }, default));
        }
        internal async Task<JsonElement> Write(string kind, JsonElement edit, Dictionary<string, object?>? extra = null)
        {
            var fields = new Dictionary<string, object?> { ["schemaVersion"] = 1, ["requestId"] = Guid.NewGuid().ToString("N"), ["editRef"] = edit.GetProperty("editRef").GetString() };
            if (extra is not null) foreach (var pair in extra) fields[pair.Key] = pair.Value;
            return E(await Client.WriteWpfS2GovernanceAsync("fixture", E(fields), "scope", kind, () => { }, default));
        }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            Check(request.Headers.Authorization?.Parameter == "fixture", "fixture current bearer only");
            var path = request.RequestUri!.AbsolutePath;
            Check(request.RequestUri.Query.Length == 0 || path == "/api/fleets/announcements" && request.RequestUri.Query == "?fleetCode=A", "S2 governance never calls newer projected endpoints");
            if (request.Method == HttpMethod.Get) return path switch
            {
                "/api/fleets/membership" => Json(new { fleetCode = HasMembership ? "A" : null }), "/api/fleets" => Json(new[] { Fleet }),
                "/api/fleets/announcements" => HasMembership ? Json(new { fleetCode = "A", revision = 1, canManage = true, current = (object?)null, history = Array.Empty<object>(), refreshedAt = Now }) : new(HttpStatusCode.Forbidden),
                "/api/auth/session" => Json(new { accountId = "owner-secret", userName = "owner-login", gameName = "Owner", callsign = "Owner" }),
                _ => new(HttpStatusCode.NotFound)
            };
            Posts.Add(path);
            LastBody = JsonNode.Parse(await request.Content!.ReadAsStringAsync(token))!;
            Check(LastBody["fleetCode"]!.GetValue<string>() == "A", "writes stay scoped to captured fleet");
            if (WrongReceipt) return Json(new { wrong = "receipt" });
            switch (path)
            {
                case "/api/fleets/info":
                    Fleet["roleGroups"] = LastBody["roleGroups"]!.DeepClone();
                    foreach (var role in Fleet["roleGroups"]!.AsArray()) role!["memberCount"] = 1;
                    Fleet["profileRevision"] = 2;
                    break;
                case "/api/fleets/permissions":
                    var permission = LastBody["permission"]!.DeepClone();
                    permission["accountId"] = "member-secret";
                    Fleet["memberPermissions"]!.AsArray().Add(permission);
                    break;
                case "/api/fleets/members/remove": Fleet["members"]!.AsArray().RemoveAt(1); break;
                case "/api/fleets/transfer-commander": case "/api/fleets/leave":
                    Fleet["ownerAccount"] = "pilot-login";
                    Fleet["commander"] = "Pilot";
                    Fleet["memberPermissions"] = JsonSerializer.SerializeToNode(new[] { Permission("Pilot", "member-secret", "fleet_commander") }, Web);
                    if (path == "/api/fleets/leave") Fleet["members"]!.AsArray().RemoveAt(0);
                    break;
                case "/api/fleets/logs/delete": Fleet["eventLog"] = new JsonArray(); break;
                case "/api/fleets/disband": return Json(new { disbanded = true, fleet = "A" });
                default: throw new InvalidOperationException("Unexpected route: " + path);
            }
            if (DropReply) throw new HttpRequestException("fixture lost response after apply");
            return Json(Fleet);
        }
        private static object Role(string key, string name, int order, string[] permissions) => new
        { key, displayName = name, description = "", color = "#AABBCC", sortOrder = order, isSystem = true, isEnabled = true, memberCount = 1, permissions, createdAt = Now, updatedAt = Now };
        private static object Member(string gameName, string accountId, string roleTitle) => new
        { gameName, accountId, callsign = gameName, roleTitle, online = false, lastUpdated = Now, joinedAt = Now };
        private static object Permission(string gameName, string accountId, string roleGroupKey) => new
        { gameName, accountId, callsign = gameName, roleGroupKey, permissionEnabled = true, canManageFleetInfo = true, canRemoveMembers = true, updatedAt = Now };
        private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value, options: Web) };
    }
}
