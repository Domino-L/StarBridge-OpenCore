using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2AdmissionTests
{
    internal static async Task Verify()
    {
        string? membership = null;
        var pending = false;
        var mode = "ok";
        var policy = "Open";
        var posts = 0;
        var requests = 0;
        var stale = false;
        using var handler = new Handler(request =>
        {
            requests++;
            Check(request.Headers.Authorization?.Parameter == "fixture", "Authenticated original protocol");
            var path = request.RequestUri!.AbsolutePath;
            Check(!path.Contains("directory"), "No new directory endpoint required");
            if (request.Method == HttpMethod.Get)
            {
                if (path == "/api/fleets/membership") return Json(new { fleetCode = membership });
                if (path == "/api/fleets/applications/mine") return Json(pending ? new[] { new { fleetCode = "A" } } : Array.Empty<object>());
                Check(path == "/api/fleets", "No unrelated reads");
                return Json(new[] { new { code = "A", name = "Fixture", totalMembers = 1, joinPolicy = policy,
                    publicListingEnabled = true, publicProfileEnabled = true } });
            }
            Check(request.Method == HttpMethod.Post, "Original post only");
            posts++;
            using var body = JsonDocument.Parse(request.Content!.ReadAsStringAsync().GetAwaiter().GetResult());
            Check(body.RootElement.GetProperty("fleetCode").GetString() == "A", "Only selected organization");
            if (mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (mode == "lost") throw new HttpRequestException("Fixture lost reply");
            if (mode == "unchanged") return Json(new { });
            if (path == "/api/fleets/apply")
            {
                Check(body.RootElement.GetProperty("message").GetString() == "", "Same empty application message as WPF");
                if (policy == "Open") membership = "A";
                else pending = true;
            }
            else
            {
                Check(path == "/api/fleets/applications/withdraw", "No implicit leave, player sync or sharing write");
                pending = false;
            }
            if (mode == "switch") stale = true;
            return Json(new { privateExtra = "not-exported" });
        });
        using var client = new CommunityClient(new Uri("https://fixture.invalid"), handler);
        async Task<CommunityView> Card() => (await client.ReadWpfS2Async("fixture", new("discover", "", null, null), "scope", "viewer", default)).Items.Single();
        async Task<CommunityCommand> Run(CommunityView card, string action, string scope = "scope") => await client.ExecuteAsync("fixture",
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, targetRef = card.TargetRef, action }), scope,
            () => { if (stale) throw new StarBridge.NativeBridge.BridgeStaleGenerationException(1, 2); }, default);
        var card = await Card();
        Check(card.Actions.SequenceEqual(new[] { "join" }), "Open fleet offers join to unjoined account");
        var detail = await client.ReadAsync("fixture", new("discover", "", null, card.TargetRef), "scope", default);
        Check(detail.Items.Length == 1, "Single-card refresh reuses S2 snapshot");
        Status(await Run(card, "join"), "accepted");
        var count = posts;
        Status(await Run(card, "join"), "rejected"); Check(posts == count, "Consumed target cannot repost");
        Check((await Card()).Actions.Length == 0, "Members receive no unimplemented management actions");
        membership = "B"; Check((await Card()).Actions.Length == 0, "Never simulate multiple membership by switching");
        membership = null; policy = "Application"; card = await Card();
        Check(card.Actions.SequenceEqual(new[] { "apply" }), "Application policy preserved");
        Status(await Run(card, "apply"), "accepted");
        card = await Card(); Check(card.Actions.SequenceEqual(new[] { "withdraw" }), "Pending application offers withdrawal");
        Status(await Run(card, "withdraw"), "accepted");
        policy = "InviteOnly"; Check((await Card()).Actions.Length == 0, "Invite-only cannot use direct admission");
        policy = "Open"; card = await Card(); policy = "InviteOnly"; count = posts;
        Status(await Run(card, "join"), "rejected"); Check(posts == count, "Changed policy checked before POST");
        policy = "Open"; card = await Card(); count = requests;
        Status(await Run(card, "join", "other-scope"), "rejected"); Check(requests == count, "Cross-account request rejected before transport");
        foreach (var failure in new[] { "lost", "unchanged", "forbidden", "switch" })
        {
            mode = failure; membership = null; stale = false; card = await Card();
            Status(await Run(card, "join"), failure == "forbidden" ? "rejected" : "unknown");
            count = posts; stale = false;
            Status(await Run(card, "join"), "rejected"); Check(posts == count, "Failed or uncertain POST never replayed");
        }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static void Status(CommunityCommand result, string status) => Check(result.Status == status, "Expected " + status + ": " + result);
    private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => Task.FromResult(send(request));
    }
}
