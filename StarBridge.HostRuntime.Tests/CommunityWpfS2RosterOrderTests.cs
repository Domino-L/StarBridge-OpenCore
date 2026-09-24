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
        }.Concat(Enumerable.Range(0, 20).Select(i => Member("tail-" + i, "Offline", false))).ToArray();
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
        async Task<string[]> Read(int offset, string query = "")
        {
            var page = JsonSerializer.SerializeToElement(await client.ReadWorkspaceAsync("fixture",
                JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = reference, query, offset }), "scope", default));
            return page.GetProperty("members").EnumerateArray().Select(row => row.GetProperty("callsign").GetString()!).ToArray();
        }
        var all = (await Read(0)).Concat(await Read(20)).ToArray();
        var expected = new[] { "game", "officer", "online", "away", "named-role-only", "owner", "offline", "hidden-game" }
            .Concat(Enumerable.Range(0, 20).Select(i => "tail-" + i));
        if (!all.SequenceEqual(expected))
            throw new InvalidOperationException("WPF member order differs: " + string.Join(",", all.Take(8)));
        if (!(await Read(0, "game")).SequenceEqual(new[] { "game", "hidden-game" }))
            throw new InvalidOperationException("Search must retain the same privacy-projected order.");
    }

    private static object Member(string id, string status, bool online) => new
    {
        accountId = id, gameName = id, callsign = id, roleTitle = "Custom title", online, liveStatus = status,
    };
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> read) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(read(request));
    }
}
