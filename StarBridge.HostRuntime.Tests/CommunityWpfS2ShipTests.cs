using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2ShipTests
{
    internal static async Task Verify()
    {
        var member = true;
        var changed = false;
        var duplicate = false;
        var calls = 0;
        const string avatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+aM7sAAAAASUVORK5CYII=";
        using var handler = new Handler(request =>
        {
            calls++;
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization?.Parameter == "fixture", "Authenticated read-only WPF sources");
            if (request.RequestUri!.AbsolutePath == "/api/fleets/membership") return Json(new { fleetCode = member ? "A" : null });
            Check(request.RequestUri.AbsolutePath == "/api/fleets", "No newer ships endpoint or fallback");
            return Json(new[] { new { code = "A", name = "Fixture", totalMembers = 1,
                members = new[] { new { accountId = "private-owner", gameName = "VisibleGame", callsign = "VisibleOwner",
                    online = true, liveStatus = "Online", avatarImageData = avatar } },
                ships = Enumerable.Range(0, 26).Select(i => new { code = "carrack", displayName = "Carrack",
                    instanceId = duplicate ? "same-instance" : "private-instance-" + i,
                    ownerAccountId = i == 25 ? "departed-owner" : "private-owner", ownerGameName = "do-not-use-unredacted",
                    ownerCallsign = "do-not-use-unredacted", catalogSpec = i < 20 ? "大型" : "小型",
                    catalogStatus = "可飞", catalogRole = "探索", roleCategory = "exploration",
                    catalogPriceUsd = changed ? "700" : "600", importedAt = DateTimeOffset.UtcNow,
                    hangarImportedAt = "2026-08-01T00:00:00Z", customImageMediaId = "private-custom-image", privateSecret = "never-export" }) } });
        });
        var clock = new Clock();
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler, clock);
        var mine = await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "private-owner", default);
        var target = mine.Items.Single().TargetRef;
        object Query(string text = "", string filter = "all") => new { text, filter, sort = "spec", descending = true, culture = "zh-CN" };
        JsonElement Body(int offset = 0, string? revision = null, object? query = null) => JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = target, offset, revision, query });
        async Task<JsonElement> Read(JsonElement body, string scope = "scope") => JsonSerializer.SerializeToElement(await client.ReadShipsAsync("fixture", body, scope, () => { }, default));
        var first = await Read(Body());
        Check(first.GetProperty("totalCount").GetInt32() == 25 && first.GetProperty("ships").GetArrayLength() == 20, "Same model instances preserved; departed contribution excluded");
        var version = first.GetProperty("revision").GetString();
        var second = await Read(Body(20, version));
        Check(second.GetProperty("ships").GetArrayLength() == 5 && second.GetProperty("next").ValueKind == JsonValueKind.Null, "Stable continuation despite synthesized share timestamps");
        Check(first.GetProperty("ships").EnumerateArray().Concat(second.GetProperty("ships").EnumerateArray()).Select(s => s.GetProperty("shipRef").GetString()).Distinct().Count() == 25, "Distinct instance references across pages");
        var raw = first.GetRawText();
        Check(!raw.Contains("private-") && !raw.Contains("do-not-use") && !raw.Contains("never-export"), "No raw identities or private fields exported");
        var ship = first.GetProperty("ships")[0];
        Check(ship.GetProperty("ownerAvatarVersion").GetString() ==
            Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(avatar))).ToLowerInvariant(),
            "Ship owner avatar preserves the shared roster and chat version");
        Check(ship.GetProperty("ownerIsSelf").GetBoolean() && ship.GetProperty("ownerOnline").GetBoolean(), "Authoritative owner presence and identity");
        Check(!ship.GetProperty("hasCustomImage").GetBoolean() && ship.GetProperty("sharedAt").ValueKind == JsonValueKind.Null, "No custom images or fabricated share date");
        var filtered = await Read(Body(query: Query(filter: "small")));
        Check(filtered.GetProperty("matchedCount").GetInt32() == 5 && filtered.GetProperty("totalCount").GetInt32() == 25, "Existing size filter and full inventory statistics");
        Check((await Read(Body(query: Query("VisibleOwner")))).GetProperty("matchedCount").GetInt32() == 25, "Visible owner searchable");
        Check((await Read(Body(query: Query("private-owner")))).GetProperty("matchedCount").GetInt32() == 0, "Private account not searchable");
        changed = true;
        await Error(() => Read(Body(20, version)), "communities.shipsChanged");
        var before = calls;
        await Error(() => Read(Body(), "other-scope"), "communities.refreshRequired");
        Check(calls == before, "Cross-account rejected before HTTP");
        for (var i = 0; i < 3; i++)
        {
            clock.Advance(4);
            await Read(Body());
        }
        clock.Advance(2 * 24 * 60);
        before = calls;
        await Read(Body());
        Check(calls > before, "Returning after two idle days reauthorizes without manual directory refresh");
        mine = await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "private-owner", default);
        target = mine.Items.Single().TargetRef;
        await Read(Body());
        member = false;
        await Error(() => Read(Body()), "communities.notAllowed");
        member = true; duplicate = true;
        await Error(() => Read(Body()), "communities.dataInvalid");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Error(Func<Task<JsonElement>> action, string code)
    {
        try { await action(); throw new InvalidOperationException("Expected " + code); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private sealed class Clock : TimeProvider
    {
        private DateTimeOffset _now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => _now;
        internal void Advance(int minutes) => _now = _now.AddMinutes(minutes);
    }
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
