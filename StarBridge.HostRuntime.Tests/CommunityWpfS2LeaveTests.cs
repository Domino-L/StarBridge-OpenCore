using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Communities;

internal static class CommunityWpfS2LeaveTests
{
    internal static async Task Verify()
    {
        using (var f = new Fixture())
        {
            var first = await f.Card(); var second = await f.Card();
            Check(first.Actions.SequenceEqual(new[] { "leave" }), "Only ordinary leave is offered");
            var calls = f.Calls;
            Check((await f.Leave(first, "other")).Status == "rejected" && f.Calls == calls, "Cross-account reference rejected before HTTP");
            Check((await f.Leave(first)).Status == "accepted" && f.Posts == 1 && f.Member is null, "Original exit followed by membership confirmation");
            calls = f.Calls;
            Check((await f.Leave(second)).Status == "rejected" && f.Calls == calls, "All old organization references invalidated");
            try
            {
                await f.Client.ReadWorkspaceAsync("fixture", JsonSerializer.SerializeToElement(new { schemaVersion = 1,
                    targetRef = second.TargetRef, query = "", offset = 0 }), "scope", default);
                throw new InvalidOperationException("Old workspace remained usable");
            }
            catch (AccountBridgeHostException e) when (e.Code == "communities.refreshRequired") { }
            Check((await f.Client.ReadWpfS2Async("fixture", new("mine", "", null, null), "scope", "self-id", default)).Items.Length == 0,
                "Joined directory confirms removal, no synthetic SCM session");
        }
        foreach (var owner in new string?[] { "self-id", "SELF-USER", null, "" })
        {
            using var f = new Fixture { Owner = owner };
            var card = await f.Card();
            Check(card.Actions.Length == 0, "Owner or unknown ownership has no ordinary exit action");
            Check((await f.Leave(card)).Status == "rejected" && f.Posts == 0, "Owner cannot force ordinary exit by payload");
        }
        foreach (var mode in new[] { "wrong-session", "no-username", "missing-self", "duplicate-self", "auth-unavailable" })
        {
            using var f = new Fixture { Mode = mode };
            var card = await f.Card();
            Check(card.Actions.Length == 0 && (await f.Leave(card)).Status == "rejected" && f.Posts == 0,
                "Unverifiable identity never grants exit: " + mode);
        }
        using (var f = new Fixture())
        {
            var card = await f.Card(); f.Owner = "self-user";
            Check((await f.Leave(card)).Status == "rejected" && f.Posts == 0, "Promotion after rendering is rechecked");
        }
        using (var f = new Fixture())
        {
            var card = await f.Card(); f.Member = "B";
            Check((await f.Leave(card)).Status == "accepted" && f.Posts == 0 && f.Member == "B", "Absent old membership never leaves the new organization");
        }
        foreach (var mode in new[] { "lost", "lost-left", "unchanged", "readback-fails", "forbidden", "server-error", "switched" })
        {
            using var f = new Fixture(); var card = await f.Card(); f.Mode = mode;
            var result = await f.Leave(card);
            Check(result.Status == (mode == "forbidden" ? "rejected" : "unknown"), "Truthful outcome: " + mode);
            Check(f.Posts == 1, "Single original POST: " + mode);
            f.Stale = false;
            await f.Leave(card);
            Check(f.Posts == 1, "Same reference never replays: " + mode);
            if (mode is "lost" or "unchanged" or "server-error")
            {
                f.Mode = "ok";
                var fresh = await f.Card();
                Check((await f.Leave(fresh)).Status == "unknown" && f.Posts == 1, "New target cannot replay uncertain exit");
                f.Member = null;
                Check((await f.Leave(fresh)).Status == "accepted" && f.Posts == 1, "Read-only reconciliation resolves absence");
            }
        }
        using (var f = new Fixture())
        {
            var card = await f.Card(); f.Clock.Now += TimeSpan.FromMinutes(6); var calls = f.Calls;
            Check((await f.Leave(card)).Status == "rejected" && f.Calls == calls, "Expired target rejected without network");
        }
        using (var f = new Fixture())
        {
            var card = await f.Card(); using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
            try { await f.Leave(card, token: cancellation.Token); } catch (OperationCanceledException) { }
            Check(f.Posts == 0, "Cancellation before send does not write");
        }
    }
    private static void Check(bool ok, string message) { if (!ok) throw new InvalidOperationException(message); }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow() => Now;
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly Clock Clock = new();
        internal readonly CommunityClient Client;
        internal string? Owner = "other-user", Member = "A";
        internal string Mode = "ok";
        internal bool Stale;
        internal int Calls, Posts;
        internal Fixture() => Client = new(new Uri("https://fixture.invalid"), new Handler(this), Clock);
        internal async Task<CommunityView> Card() => (await Client.ReadWpfS2Async("fixture", new("mine", "", null, null),
            "scope", "self-id", default)).Items.Single();
        internal Task<CommunityCommand> Leave(CommunityView card, string scope = "scope", CancellationToken token = default) =>
            Client.ExecuteAsync("fixture", JsonSerializer.SerializeToElement(new { schemaVersion = 1, action = "leave", targetRef = card.TargetRef }),
                scope, () => { if (Stale) throw new StarBridge.NativeBridge.BridgeStaleGenerationException(1, 2); }, token);
        public void Dispose() => Client.Dispose();
        internal async Task<HttpResponseMessage> Send(HttpRequestMessage request)
        {
            Calls++;
            Check(request.Headers.Authorization?.Parameter == "fixture", "Authenticated S2 request");
            var path = request.RequestUri!.AbsolutePath;
            if (request.Method == HttpMethod.Get)
            {
                if (path == "/api/fleets/membership")
                {
                    if (Mode == "readback-fails" && Posts > 0) throw new HttpRequestException("fixture");
                    return Json(new { fleetCode = Member });
                }
                if (path == "/api/auth/session")
                    return Mode == "auth-unavailable" ? new(HttpStatusCode.ServiceUnavailable) : Json(new {
                        accountId = Mode == "wrong-session" ? "another-id" : "self-id",
                        userName = Mode == "no-username" ? null : "self-user" });
                Check(path == "/api/fleets", "No modern or unrelated read endpoint");
                return Json(new[] { new { code = Member, name = "Fixture", totalMembers = 2, ownerAccount = Owner,
                    publicListingEnabled = false, publicProfileEnabled = false,
                    members = Enumerable.Repeat(new { accountId = "self-id", roleTitle = "Misleading owner title" },
                        Mode == "missing-self" ? 0 : Mode == "duplicate-self" ? 2 : 1).ToArray() } });
            }
            Check(path == "/api/fleets/leave" && request.Method == HttpMethod.Post && request.RequestUri.Query == "", "WPF ordinary leave only");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync());
            Check(body.RootElement.EnumerateObject().Count() == 1 && body.RootElement.GetProperty("fleetCode").GetString() == "A",
                "Never send a successor, disband consent, player snapshot or another organization's code");
            Posts++;
            if (Mode == "forbidden") return new(HttpStatusCode.Forbidden);
            if (Mode == "server-error") return new(HttpStatusCode.InternalServerError);
            if (Mode is not ("lost" or "unchanged")) Member = null;
            if (Mode is "lost" or "lost-left") throw new HttpRequestException("fixture");
            if (Mode == "switched") Stale = true;
            return Json(new { privateSnapshot = "not-a-receipt" });
        }
        private static HttpResponseMessage Json(object body) => new(HttpStatusCode.OK) { Content = JsonContent.Create(body) };
    }
    private sealed class Handler(Fixture fixture) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => fixture.Send(request);
    }
}
