using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2CreationTests
{
    internal static async Task Verify()
    {
        var posts = 0;
        var created = false;
        var existingMembership = false;
        var mode = "ok";
        var logoPosts = new List<bool>();
        using var handler = new Handler(async request =>
        {
            Check(request.Headers.Authorization?.Parameter == "fixture", "Authenticated legacy contract only");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                if (path == "/api/fleets/membership")
                    return Json(new { fleetCode = created || existingMembership ? "NEWORG" : null });
                if (path == "/api/fleets")
                    return Json(created || existingMembership ? new[] { Fleet(mode == "wrong-owner" ? "other" : "owner-user") } : Array.Empty<object>());
                if (path == "/api/auth/session")
                    return Json(new { accountId = "self", userName = "owner-user" });
                throw new InvalidOperationException("Unexpected legacy GET " + path);
            }

            posts++;
            Check(path == "/api/fleets", "WPF S2 uses the original full snapshot seam");
            Check(!request.RequestUri.Query.Contains("view="), "WPF S2 never selects a new projection");
            var body = await request.Content!.ReadFromJsonAsync<JsonElement>();
            Check(!body.TryGetProperty("requestId", out _), "Bridge intent metadata is not uploaded");
            Check(body.GetProperty("commander").GetString() == "Pilot (Game_Name)", "WPF commander display is preserved");
            Check(body.GetProperty("type").GetString() == "PVP", "WPF tag summary is preserved");
            Check(body.GetProperty("activeSystemIds")[0].GetString() == "stanton", "WPF systems are preserved");
            Check(body.GetProperty("activityWindows")[0].GetProperty("days").GetArrayLength() == 7, "WPF default week is preserved");
            logoPosts.Add(body.GetProperty("logoImageData").ValueKind == JsonValueKind.String);
            if (mode == "lost") throw new HttpRequestException("fixture response lost");
            if (mode == "conflict") return new(HttpStatusCode.Conflict);
            if (mode == "large" && logoPosts[^1]) return new(HttpStatusCode.RequestEntityTooLarge);
            created = true;
            return Json(Fleet(mode == "wrong-owner" ? "other" : "owner-user"));
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var command = Command(new string('1', 32), withLogo: true);
        var result = await client.CreateWpfS2Async("fixture", command, "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "accepted" && result.Organization?.Relationship == "owner", "Authoritative owner read confirms creation");
        Check(posts == 1, "One legacy create is sent");
        await client.CreateWpfS2Async("fixture", command, "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(posts == 1, "Accepted intent is not posted twice");

        existingMembership = true;
        created = false;
        result = await client.CreateWpfS2Async("fixture", Command(new string('2', 32)), "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "rejected" && result.Error == "notAllowed" && posts == 1, "Existing S2 membership closes creation before POST");

        existingMembership = false;
        var staleCalls = 0;
        result = await client.CreateWpfS2Async("fixture", Command(new string('7', 32)), "scope", "self", "Pilot (Game_Name)",
            () =>
            {
                staleCalls++;
                if (staleCalls == 2) throw new AccountBridgeHostException("account.changed");
            }, default);
        Check(result.Status == "rejected" && result.Error == "refreshRequired" && posts == 1,
            "Account generation is rechecked after membership preflight and before POST");

        mode = "lost";
        var uncertain = Command(new string('3', 32));
        result = await client.CreateWpfS2Async("fixture", uncertain, "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "unknown", "Lost legacy response is unknown");
        var before = posts;
        await client.CreateWpfS2Async("fixture", uncertain, "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(posts == before, "Unknown legacy creation is never replayed");

        mode = "conflict";
        result = await client.CreateWpfS2Async("fixture", Command(new string('4', 32)), "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "rejected" && result.Error == "codeUnavailable", "Legacy conflict stays a definite rejection");

        mode = "wrong-owner";
        created = false;
        result = await client.CreateWpfS2Async("fixture", Command(new string('5', 32)), "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "unknown", "A non-owner membership cannot confirm creation");

        mode = "large";
        created = false;
        logoPosts.Clear();
        result = await client.CreateWpfS2Async("fixture", Command(new string('6', 32), withLogo: true), "scope", "self", "Pilot (Game_Name)", () => { }, default);
        Check(result.Status == "accepted" && logoPosts.SequenceEqual([true, false]), "A definite 413 retries once without the optional logo");
    }

    private static object Fleet(string owner) => new
    {
        name = "New Organization",
        code = "NEWORG",
        commander = "Pilot (Game_Name)",
        description = "",
        type = "PVP",
        activeTime = "19:00 - 22:00",
        joinPolicy = "Open",
        logoImageData = (string?)null,
        totalMembers = 1,
        ownerAccount = owner,
        members = new[] { new { accountId = "self" } },
        language = "zh-CN",
        activeSystemIds = new[] { "stanton" }
    };

    private static JsonElement Command(string id, bool withLogo = false) => JsonSerializer.SerializeToElement(new
    {
        schemaVersion = 1,
        requestId = id,
        draft = new
        {
            schemaVersion = 1,
            name = "New Organization",
            code = "NEWORG",
            description = "",
            joinPolicy = "Open",
            tagIds = new[] { "combat_pvp" },
            activeSystemIds = new[] { "stanton" },
            activeFrom = "19:00",
            activeTo = "22:00",
            timeZoneId = "UTC",
            logoImageData = withLogo ? "data:image/png;base64,AQ==" : null
        }
    });

    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }

    private sealed class Handler(Func<HttpRequestMessage, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request);
    }
}
