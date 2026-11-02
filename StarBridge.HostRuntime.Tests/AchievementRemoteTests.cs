using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;
using StarBridge.Core.Identity;
using System.Net;
using System.Net.Http.Json;
using System.Text.Json;

internal static class AchievementRemoteTests
{
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential delete");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Gets, Posts; internal bool Offline;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Require(request.Headers.Authorization?.Parameter == "synthetic-access", "Achievement calls use the authenticated SCM bearer");
            Require(request.RequestUri!.AbsolutePath.StartsWith("/app-api/starbridge/v1/achievements"), "No legacy or unrelated profile endpoint is used");
            if (Offline) return new(HttpStatusCode.ServiceUnavailable) { Content = JsonContent.Create(new { message = "synthetic outage" }) };
            if (request.Method == HttpMethod.Get) { Gets++; return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, earnedAt = new Dictionary<string, string>() }) }; }
            Require(request.Method == HttpMethod.Post, "Only the private observation is written"); Posts++;
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            Require(body.RootElement.EnumerateObject().Count() == 4 && body.RootElement.GetProperty("handleHash").GetString() == FirstEntryObservation.HashHandle("Pilot_A") &&
                body.RootElement.GetProperty("serverState").GetString() == "connected", "Payload contains bounded evidence and no account id, raw Handle, path or log");
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1,
                earnedAt = new Dictionary<string, string> { ["first-entry"] = "2026-09-04T12:00:30Z" }, newlyEarned = true }) };
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    internal static async Task Run()
    {
        using var handler = new Handler(); var http = new ScmHttpClient(handler);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"), new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api", "profile.read presence.write game_identity.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "synthetic-owner", "Synthetic", "synthetic-access", DateTimeOffset.UtcNow.AddHours(1),
            ["profile.read", "presence.write", "game_identity.read"], GameIdentityHandle: "Pilot_A", GameIdentityStatus: ScmGameIdentityStatus.Verified);
        using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new Vault(), options), new ScmProfileCacheStore(Path.GetTempPath()), "fixture", () => null, initialSession: session, initialGeneration: 1);
        var remote = (IAchievementRemote)host; var owner = host.CurrentContext!;
        Require((await remote.ReadAchievementsAsync(owner, 1, default)).EarnedAt.Count == 0, "ISO cloud collection is decoded");
        var receipt = await remote.ObserveFirstEntryAsync(owner, 1, new(1, FirstEntryObservation.HashHandle("Pilot_A"), "LIVE"), default);
        Require(receipt.NewlyEarned && receipt.EarnedAt["first-entry"] == DateTimeOffset.Parse("2026-09-04T12:00:30Z"), "Cloud receipt is decoded without installing another identity");
        var before = handler.Gets + handler.Posts;
        try { await remote.ReadAchievementsAsync(owner with { Subject = "forged-owner" }, 1, default); throw new Exception("Forged account admitted"); } catch (AccountBridgeHostException) { }
        try { await remote.ReadAchievementsAsync(owner, 0, default); throw new Exception("Stale generation admitted"); } catch (AccountBridgeHostException) { }
        Require(handler.Gets + handler.Posts == before, "Forged or stale ownership never reaches HTTP");
        handler.Offline = true;
        try { await remote.ReadAchievementsAsync(owner, 1, default); throw new Exception("Unavailable cloud was returned as empty"); } catch (ScmApiUnavailableException) { }
        Require(host.CurrentContext == owner, "Achievement outage preserves the authenticated account and never falls back to legacy");
    }
}
