using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2DiscoveryTests
{
    internal static async Task Verify()
    {
        var calls = new List<string>();
        var status = HttpStatusCode.OK;
        var largeMedia = false;
        var multiMembership = false;
        using var handler = new Handler(request =>
        {
            calls.Add(request.RequestUri!.AbsolutePath);
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "test-token", "S2 authenticated reads only");
            if (status != HttpStatusCode.OK) return new(status);
            return request.RequestUri.AbsolutePath switch
            {
                "/api/fleets/membership" => multiMembership
                    ? Json(new { fleetCode = "MEMBER", fleetCodes = new[] { "MEMBER" } })
                    : Json(new { fleetCode = "MEMBER" }),
                "/api/fleets/applications/mine" => Json(new[] { new { fleetCode = "ORG-02" } }),
                "/api/fleets" => Json(Enumerable.Range(0, 25).Select(i => Fleet("ORG-" + i.ToString("D2"), i, largeMedia)).Append(Fleet("MEMBER", 26, largeMedia)).ToArray()),
                _ => new(HttpStatusCode.NotFound)
            };
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid"), handler);
        async Task<CommunityPage> Read(string query = "", string? filters = null, string? after = null, string scope = "A") =>
            await client.ReadWpfS2Async("test-token", new("discover", query, after, null, filters), scope, "self", default);
        var page = await Read(filters: "{\"sort\":\"name\"}");
        Check(page.Items.Length == 20 && page.TotalCount == 24 && page.Next is not null, "Visible directory returns bounded pages and accurate count");
        Check(!calls.Contains("/api/fleets/directory"), "No new directory route is required");
        var last = await Read(filters: "{\"sort\":\"name\"}", after: page.Next);
        Check(last.Items.Length == 4 && last.Next is null, "Final discovery page");
        Check(page.Items.Concat(last.Items).Select(x => x.Name).Distinct().Count() == 24, "No duplicate rows across pages");
        var pending = await Read(filters: "{\"status\":[\"pending\"]}");
        Check(pending.Items.Single().Name == "ORG-02" && pending.Items[0].Relationship == "pending", "WPF pending application status");
        Check(pending.Items[0].Actions.SequenceEqual(new[] { "withdraw" }), "Existing pending application can be withdrawn");
        Check((await Read(query: "ORG-05")).Items.Single().Actions.Length == 0,
            "Old single-membership servers retain the conservative admission guard");
        multiMembership = true;
        Check((await Read(query: "ORG-05")).Items.Single().Actions.SequenceEqual(new[] { "join" }),
            "Multi-membership server enables direct join while already in another organization");
        Check((await Read(query: "ORG-06")).Items.Single().Actions.SequenceEqual(new[] { "apply" }),
            "Multi-membership server enables applications while already in another organization");
        Check((await Read(query: "MEMBER")).Items.Single().Actions.Length == 0,
            "Existing membership never offers duplicate join");
        var hidden = await Read(query: "secret-search-key");
        Check(hidden.TotalCount == 0, "Hidden fields cannot be searched");
        var filtered = await Read(filters: "{\"join\":[\"application\"],\"systems\":[\"Pyro\"],\"tags\":[\"探索\"]}");
        Check(filtered.Items.Length > 0 && filtered.Items.All(x => x.JoinMode == "application" && x.Systems.Contains("Pyro")), "Existing filter groups are composed");
        var activity = await Read(filters: "{\"days\":[\"Mon\"],\"period\":[\"evening\"],\"sameZone\":true,\"offset\":0,\"ships\":[\"small\"],\"roles\":[\"exploration\"],\"language\":\"中文\"}");
        Check(activity.TotalCount == 23, "Activity timezone/day/period and ship role/scale filters reuse existing implementation");
        Check((await Read(filters: "{\"roles\":[\"combat\"]}")).TotalCount == 0, "Unmatched role filter produces a real empty result");
        var privateRow = (await Read(query: "ORG-03")).Items.Single();
        Check((await Read(query: "ORG-02")).Items.Single().RecruitingNote == "Weekend crews welcome", "Recruitment note reaches the directory without extra profile reads");
        var approximate = (await Read(query: "ORG-04")).Items.Single();
        Check(approximate.MemberCount is null && approximate.MemberScale == "small", "Approximate scale must not expose an exact count");
        Check(!approximate.Recruiting && approximate.RecruitingNote == "", "Inactive recruitment must not expose stale recruiting copy");
        Check(privateRow.Description == "" && privateRow.ActiveTime == "" && privateRow.Tags == "" && privateRow.Systems.Length == 0 && privateRow.MemberCount is null && privateRow.MemberScale == "", "Public flags and hidden member scale survive projection");
        var before = calls.Count;
        await Error(async () => await Read(filters: "{\"sort\":\"name\"}", after: page.Next, scope: "B"), "communities.refreshRequired");
        await Error(async () => await Read(query: "changed", filters: "{\"sort\":\"name\"}", after: page.Next), "communities.refreshRequired");
        Check(calls.Count == before, "Cross-account and changed-query cursors rejected before HTTP");
        await Error(async () => await Read(filters: "{\"unexpected\":true}"), "communities.dataInvalid");
        largeMedia = true;
        var images = await Read();
        Check(images.Items.Length == 20 && images.Items.All(x => x.LogoImageData is null) && images.Next is not null &&
            JsonSerializer.SerializeToUtf8Bytes(images).Length < 100 * 1024, "Original logos must not shrink the directory page");
        var logoTarget = images.Items[0].TargetRef;
        var mediaBody = JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = logoTarget, kind = "logo", offset = 0 });
        before = calls.Count;
        var media = JsonSerializer.SerializeToElement(await client.ReadMediaAsync("test-token", mediaBody, "A", default));
        Check(media.GetProperty("data").GetString() == LargeLogo.Split(',')[1], "Directory logo preserves original bytes through existing media channel");
        Check(calls.Count == before, "Directory media reads the bounded authenticated snapshot, not repeated bulk downloads");
        await Error(() => client.ReadMediaAsync("test-token", mediaBody, "B", default), "communities.refreshRequired");
        status = HttpStatusCode.Forbidden;
        before = calls.Count;
        await Error(async () => await Read(), "communities.notAllowed");
        Check(calls.Count == before + 1, "Permission failure never falls back or probes alternate routes");
    }
    internal static async Task AdmissionCommands()
    {
        var memberships = new List<string> { "MEMBER" };
        var pending = new List<string>();
        var writes = new List<string>();
        var confirming = false;
        using var handler = new Handler(request =>
        {
            var path = request.RequestUri!.AbsolutePath;
            Check(request.Headers.Authorization?.Parameter == "test-token", "Admission remains authenticated");
            if (request.Method == HttpMethod.Post)
            {
                confirming = true;
                writes.Add(path);
                Check(path == "/api/fleets/apply", "Joining never leaves or moves another membership");
                var data = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
                using (data)
                {
                    var code = data.RootElement.GetProperty("fleetCode").GetString()!;
                    if (code == "DIRECT") memberships.Add(code); else pending.Add(code);
                }
                return Json(new { });
            }
            Check(!confirming || path != "/api/fleets", "Admission readback must not download the full discovery catalog again");
            return path switch
            {
                "/api/fleets/membership" => Json(new { fleetCode = "MEMBER", fleetCodes = memberships.ToArray() }),
                "/api/fleets/applications/mine" => Json(pending.Select(code => new { fleetCode = code }).ToArray()),
                "/api/fleets" => Json(new[] { Fleet("MEMBER", 9, false), Fleet("DIRECT", 5, false), Fleet("APPLY", 6, false) }),
                _ => new(HttpStatusCode.NotFound)
            };
        });
        using var client = new CommunityClient(new Uri("https://relay.invalid"), handler);
        foreach (var (code, action) in new[] { ("DIRECT", "join"), ("APPLY", "apply") })
        {
            confirming = false;
            var page = await client.ReadWpfS2Async("test-token", new("discover", code, null, null), "A", "self", default);
            var body = JsonSerializer.SerializeToElement(new { schemaVersion = 1, action, targetRef = page.Items.Single().TargetRef });
            var result = await client.ExecuteAsync("test-token", body, "A", () => { }, default);
            Check(result.Status == "accepted", "Admission is confirmed by current membership/application readback");
        }
        Check(writes.Count == 2 && memberships.SequenceEqual(new[] { "MEMBER", "DIRECT" }) && pending.SequenceEqual(new[] { "APPLY" }),
            "Direct join and application preserve the original organization independently");
    }

    private static object Fleet(string code, int index, bool largeMedia) => new
    {
        code, name = code, description = index == 3 ? "secret-search-key" : "Public description", type = "探索",
        language = "中文", activeTime = "20:00–23:00", totalMembers = 8, onlineMembers = 2,
        lastUpdated = "2026-09-10T00:00:00Z", joinPolicy = index % 2 == 0 ? "Application" : "Open",
        publicListingEnabled = index != 0, publicProfileEnabled = index != 1,
        publicShowDescription = index != 3, publicShowTags = index != 3, publicShowActivityTime = index != 3,
        publicShowActiveSystems = index != 3, publicMemberScaleMode = index == 3 ? "Hidden" : index == 4 ? "Approx" : "Exact",
        activeSystemIds = new[] { "Pyro" }, recruitingEnabled = index != 4, recruitingTarget = "新手友好", recruitingNote = "Weekend crews welcome", members = Array.Empty<object>(),
        timeZoneId = "UTC", publicShipCount = 4, publicShipScaleMode = "TypeSummary", publicShipTypeSummary = "exploration=4",
        activityWindows = new[] { new { days = new[] { "Mon" }, startTime = "20:00", endTime = "23:00", endsNextDay = false } },
        logoImageData = largeMedia ? LargeLogo : null
    };
    private static readonly string LargeLogo = BuildLogo();
    private static string BuildLogo()
    {
        var bytes = new byte[90_000];
        Convert.FromBase64String("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=").CopyTo(bytes, 0);
        return "data:image/png;base64," + Convert.ToBase64String(bytes);
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<object>> read, string code)
    {
        try { await read(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
