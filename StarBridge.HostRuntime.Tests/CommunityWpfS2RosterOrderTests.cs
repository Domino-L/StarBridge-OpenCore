using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2RosterOrderTests
{
    internal static async Task Verify()
    {
        var members = new[]
        {
            Member("offline", "Offline", false), Member("owner", "Offline", false),
            Member("online", "AppOnline", true), Member("officer", "Away", true),
            Member("game", "InGame", true), Member("hidden-game", "InGame", false),
            Member("away", "Away", true), Member("named-role-only", "AppOnline", true),
            Member("manual", "ManualOffline", true), Member("invisible", " iNvIsIbLe ", true),
            Member("paused", "pAuSeD", true),
        }.Concat(Enumerable.Range(0, 20).Select(i => Member("tail-" + i, "Offline", false)))
            .Concat(new[] { Member("unknown", "Unknown", true), Member("future", "future-state", true) }).ToArray();
        var fleet = new
        {
            code = "A", name = "Fixture", ownerAccount = "owner", totalMembers = members.Length,
            members, memberPermissions = new[]
            {
                new { accountId = "officer", permissionEnabled = true, roleGroupKey = "custom" },
                new { accountId = "named-role-only", permissionEnabled = false, roleGroupKey = "custom" },
            },
        };
        using var handler = new Handler(request => request.RequestUri!.AbsolutePath switch
        {
            "/api/fleets/membership" => Json(new { fleetCode = "A" }),
            "/api/fleets" => Json(new[] { fleet }),
            _ => new(HttpStatusCode.NotFound),
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        var directory = await client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "owner", default);
        var reference = directory.Items.Single().TargetRef;
        async Task<JsonElement[]> ReadRows(int offset, string query = "")
        {
            var page = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("fixture",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, query, offset }), "scope", default));
            return page.GetProperty("members").EnumerateArray().ToArray();
        }
        async Task<string[]> Read(int offset, string query = "") => (await ReadRows(offset, query))
            .Select(row => row.GetProperty("callsign").GetString()!).ToArray();
        var rows = (await ReadRows(0)).Concat(await ReadRows(20)).ToArray();
        var all = rows.Select(row => row.GetProperty("callsign").GetString()!).ToArray();
        var expected = new[] { "game", "officer", "online", "away", "named-role-only", "owner", "offline", "hidden-game" }
            .Concat(new[] { "manual", "invisible", "paused" })
            .Concat(Enumerable.Range(0, 20).Select(i => "tail-" + i)).Concat(new[] { "unknown", "future" });
        if (!all.SequenceEqual(expected))
            throw new InvalidOperationException("WPF member order differs: " + string.Join(",", all.Take(8)));
        if (!(await Read(20)).SequenceEqual(Enumerable.Range(9, 11).Select(i => "tail-" + i)
                .Concat(new[] { "unknown", "future" })))
            throw new InvalidOperationException("Unknown presence must stay in ordinary offline source order across the 20-row page boundary.");
        if (rows.Count(row => row.GetProperty("online").GetBoolean()) != 5 ||
            rows.Count(row => row.GetProperty("liveStatus").GetString() == "InGame") != 1)
            throw new InvalidOperationException("Unknown presence cannot inflate public online/game counts.");
        if (!(await Read(0, "game")).SequenceEqual(new[] { "game", "hidden-game" }))
            throw new InvalidOperationException("Search must retain the same privacy-projected order.");
        foreach (var row in rows.Where(row => new[] { "offline", "hidden-game", "manual", "invisible", "paused", "unknown", "future" }
                     .Contains(row.GetProperty("callsign").GetString())))
        {
            if (row.GetProperty("online").GetBoolean() || row.GetProperty("liveStatus").GetString() != "Offline")
                throw new InvalidOperationException("Organization offline presence must not reveal a private sharing choice.");
            foreach (var key in new[] { "serverRegion", "serverShard", "hasServerSession", "ship", "location", "locationConfidence", "locationHiddenReason", "arrivalTargetCode", "lastUpdated" })
                if (row.TryGetProperty(key, out var value) && value.ValueKind != JsonValueKind.Null)
                    throw new InvalidOperationException("Organization offline runtime leaked: " + key);
            if (row.GetProperty("arrivalPendingConfirmation").GetBoolean())
                throw new InvalidOperationException("Organization offline arrival state leaked.");
        }
    }

    private static object Member(string id, string status, bool online) => new
    {
        accountId = id, gameName = id, callsign = id, roleTitle = "Custom title", online, liveStatus = status,
        ship = "Private ship", location = "Private location", serverRegion = "USA", serverShard = "Private shard",
        hasServerSession = true, locationConfidence = "Confirmed", arrivalPendingConfirmation = true,
        arrivalTargetCode = "Private destination", lastUpdated = DateTimeOffset.UtcNow,
    };
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> read) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(read(request));
    }
}
