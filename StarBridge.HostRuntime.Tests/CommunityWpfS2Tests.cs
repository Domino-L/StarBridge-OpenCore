using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2Tests
{
    internal static async Task Verify()
    {
        await CommunityWpfS2RosterOrderTests.Verify();
        var calls = new List<string>();
        var membership = "A";
        var duplicates = false;
        StarBridge.HostRuntime.Notifications.PlayerActivitySourceSnapshot? activity = null;
        using var handler = new Handler(request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            calls.Add(path);
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "test-token", "Only authenticated GETs");
            if (path == "/api/fleets/membership") return Json(new { fleetCode = membership });
            if (path == "/api/fleets/hangar-sharing") return Json(new { schemaVersion = 1, version = new string('a', 64),
                usesExplicitTargets = false, selectedCodes = Array.Empty<string>() });
            if (path == "/api/fleets") return Json(duplicates ? new[] { Fleet("A"), Fleet("A") } : new[] { Fleet("B"), Fleet("A") });
            if (path == "/api/fleets/chat/channels") return Json(new { totalUnread = 0,
                channels = new[] { new { channelId = "fleet:A", type = "fleet", unreadCount = 0, canSend = true } } });
            if (path == "/api/fleets/chat/messages") return Json(new { channelId = "fleet:A", latestSequence = 1,
                oldestSequence = 1, hasOlder = false, canSend = true, serverTime = "2026-09-10T00:00:00Z",
                messages = new[] { new { sequence = 1, messageId = "fixture-message", channelId = "fleet:A",
                    senderAccountId = "self-id", senderCallsign = "Member 0", senderGameId = "",
                    senderRoleTitle = "成员", senderRoleColor = "#9DAAB3", text = "Fixture",
                    createdAt = "2026-09-10T00:00:00Z", senderAvatarImageData = Pixel, attachment = (object?)null } } });
            if (path == "/api/players") return Json(Enumerable.Range(0, 21).Select(i => new {
                accountId = i == 0 ? "self-id" : "account-" + i, online = true, liveStatus = "InGame",
                sharedEventTypes = i == 1 ? 0 : 1, lastUpdated = "2026-09-10T00:00:00Z"
            }).ToArray());
            return new(HttpStatusCode.NotFound);
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid/"), handler);
        var mine = await client.ReadWpfS2Async("test-token", new("mine", "", null, null), "owner-scope", "self-id", default);
        Check(mine.Items.Length == 1 && mine.Items[0].Name == "Organization A", "Existing WPF membership appears, not every public organization");
        Check(mine.Items[0].Actions.Length == 0, "Read compatibility does not enable multi-organization writes");
        Check(calls.SequenceEqual(new[] { "/api/fleets/membership", "/api/fleets" }), "Explicit S2 path never probes new directory");
        var sharingStart = calls.Count;
        var sharing = JsonSerializer.SerializeToElement(await client.ReadHangarSharingAsync("test-token",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1 }), "owner-scope", () => { }, default, legacyViewerId: "self-id"));
        Check(sharing.GetProperty("options").GetArrayLength() == 1 && !calls.Skip(sharingStart).Contains("/api/fleets/directory"),
            "legacy sharing editor uses the verified WPF membership path, never the unavailable modern directory");
        var reference = mine.Items[0].TargetRef;
        var before = calls.Count;
        await Error(() => client.ReadWorkspaceAsync("test-token", Query(reference), "other-scope", default), "communities.refreshRequired");
        Check(calls.Count == before, "Cross-account target rejected before HTTP");
        var page = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-token", Query(reference), "owner-scope", default));
        Check(page.GetProperty("members").GetArrayLength() == 20 && page.GetProperty("next").GetInt32() == 20, "WPF roster has bounded member pages");
        Check(page.GetProperty("totalCount").GetInt32() == 21 && page.GetProperty("description").GetString() == "Existing description", "Existing organization data survives projection");
        Check(!page.GetRawText().Contains("self-id") && !page.GetRawText().Contains("private-only"), "Raw account IDs and unrelated fields do not cross Bridge");
        Check(page.GetProperty("members")[0].GetProperty("avatarVersion").GetString() ==
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(Pixel))).ToLowerInvariant(),
            "Roster avatar has the same content-version convention as chat");
        var avatar = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-token", JsonSerializer.SerializeToElement(new
        {
            schemaVersion = 1, targetRef = reference, kind = "avatar", memberRef = page.GetProperty("members")[0].GetProperty("memberRef").GetString(), offset = 0
        }), "owner-scope", default));
        Check(avatar.GetProperty("data").GetString() == Pixel.Split(',')[1], "Existing avatar bytes preserved");
        var chat = JsonSerializer.SerializeToElement(await client.ReadChatAsync("test-token",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, after = 0, before = 0 }),
            "owner-scope", () => { }, default));
        var sender = chat.GetProperty("messages")[0];
        Check(sender.GetProperty("senderRef").GetString() == page.GetProperty("members")[0].GetProperty("memberRef").GetString()
            && sender.GetProperty("avatarVersion").GetString() == page.GetProperty("members")[0].GetProperty("avatarVersion").GetString(),
            "Actual S2 roster and chat expose identical authorized avatar cache identity and version");
        var logo = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-token", JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, targetRef = reference, kind = "logo", offset = 0 }), "owner-scope", default));
        Check(logo.GetProperty("data").GetString() == Pixel.Split(',')[1], "Organization logo uses old snapshot, no new endpoint");
        await Error(() => client.ReadMediaAsync("test-token", JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, targetRef = reference, kind = "logo", offset = 0, version = new string('a', 64) }), "owner-scope", default), "communities.mediaChanged");
        var filtered = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-token", JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, targetRef = reference, query = "Member 20", offset = 0 }), "owner-scope", default));
        Check(filtered.GetProperty("matchedCount").GetInt32() == 1, "Member search uses visible fields only");
        before = calls.Count;
        var mutation = await client.ExecuteAsync("test-token", JsonSerializer.SerializeToElement(new
        { schemaVersion = 1, targetRef = reference, action = "leave" }), "owner-scope", () => { }, default);
        Check(mutation.Status == "rejected" && calls.Count == before + 2, "Unknown ownership is rechecked without granting exit or entering modern paths");
        var last = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-token", Query(reference, 20), "owner-scope", default));
        Check(last.GetProperty("members").GetArrayLength() == 1 && last.GetProperty("next").ValueKind == JsonValueKind.Null, "Final page preserved");
        var observedPage = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("test-token", Query(reference, 20),
            "owner-scope", default, snapshot => activity = snapshot));
        Check(observedPage.GetProperty("members").GetArrayLength() == 1 && activity?.Members.Length == 21 && activity.IsComplete,
            "activity observes the full authorized roster, never just the last page");
        Check(activity!.Members.Single(row => row.AccountId == "account-20").Presence == "inGame" &&
            !activity.Members.Single(row => row.AccountId == "account-1").AllowsPresenceEvents,
            "actual projected presence and event-sharing eligibility are preserved");
        Check(!observedPage.GetRawText().Contains("account-20"), "internal observation IDs never enter the workspace wire payload");
        membership = "B";
        await Error(() => client.ReadWorkspaceAsync("test-token", Query(reference), "owner-scope", default), "communities.notAllowed");
        membership = "A";
        duplicates = true;
        await Error(async () => await client.ReadWpfS2Async("test-token", new("mine", "", null, null), "owner-scope", "self-id", default), "communities.dataInvalid");
    }
    private static object Fleet(string code) => new
    {
        code, name = "Organization " + code, description = "Existing description", type = "探索", language = "中文",
        activeTime = "20:00–23:00", totalMembers = 21, lastUpdated = "2026-09-10T00:00:00Z", privateField = "private-only", logoImageData = Pixel,
        members = Enumerable.Range(0, 21).Select(i => new
        {
            accountId = i == 0 ? "self-id" : "account-" + i, gameName = "", callsign = "Member " + i,
            roleTitle = "成员", online = i == 0, liveStatus = i == 0 ? "AppOnline" : "Offline",
            ship = (string?)null, location = (string?)null, lastUpdated = "2026-09-10T00:00:00Z", avatarImageData = Pixel
        }).ToArray()
    };
    private const string Pixel = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
    private static JsonElement Query(string reference, int offset = 0) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, query = "", offset });
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string reason) { if (!condition) throw new InvalidOperationException(reason); }
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException ex) when (ex.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
