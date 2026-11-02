using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;

internal static class CityAchievementRemoteTests
{
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("No credential persistence in this fixture");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("No credential deletion in this fixture");
    }
    // Every request terminates here, in memory. No socket, DNS, or partner endpoint is used.
    private sealed class Handler : HttpMessageHandler
    {
        internal int Posts;
        internal bool InvalidReceipt;
        internal string ExpectedEvidence = "explicit", ExpectedCity = "orison";
        private readonly JsonDocument _sample = JsonDocument.Parse(File.ReadAllText(SamplePath()));
        private static string SamplePath()
        {
            for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
            {
                var path = Path.Combine(directory.FullName, "contracts", "achievements", "city-observation.json");
                if (File.Exists(path)) return path;
            }
            throw new FileNotFoundException("contracts/achievements/city-observation.json");
        }
        protected override void Dispose(bool disposing) { if (disposing) _sample.Dispose(); base.Dispose(disposing); }
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Get)
                return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1, earnedAt = new Dictionary<string, string>() }) };
            Require(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath ==
                "/app-api/starbridge/v1/achievements/observations/city", "city route");
            Require(request.Headers.Authorization?.Parameter == "synthetic-access", "existing authenticated transport");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            var value = body.RootElement;
            var sample = _sample.RootElement;
            var keys = sample.GetProperty("request").EnumerateObject().Select(p => p.Name).ToHashSet();
            Require(keys.Count == 4 && value.EnumerateObject().Count() == keys.Count &&
                keys.SetEquals(value.EnumerateObject().Select(p => p.Name)), "shared request key set");
            Require(sample.GetProperty("cities").EnumerateArray().Any(c => c.GetString() == ExpectedCity) &&
                sample.GetProperty("evidence").EnumerateArray().Any(e => e.GetString() == ExpectedEvidence), "shared finite values");
            Require(value.GetProperty("schemaVersion").GetInt32() == sample.GetProperty("request").GetProperty("schemaVersion").GetInt32() &&
                value.GetProperty("handleHash").GetString() == FirstEntryObservation.HashHandle("Pilot_A") &&
                value.GetProperty("city").GetString() == ExpectedCity &&
                value.GetProperty("evidence").GetString() == ExpectedEvidence, "wire evidence uses inventory/explicit, never local parser names");
            Posts++;
            return new(HttpStatusCode.OK) { Content = JsonContent.Create(new { schemaVersion = 1,
                earnedAt = new Dictionary<string, string> { ["journey-" + ExpectedCity] = "2026-10-28T12:00:30Z", ["journey-stanton"] = "2026-10-28T12:00:30Z" },
                newlyEarned = new[] { "journey-" + ExpectedCity, InvalidReceipt ? "unknown" : "journey-stanton" },
                progress = new Dictionary<string, int> { ["journey-stanton"] = 4 } }) };
        }
    }
    internal static async Task Run()
    {
        using var handler = new Handler(); var http = new ScmHttpClient(handler);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api",
            "profile.read presence.write game_identity.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "synthetic-city", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write", "game_identity.read"],
            GameIdentityHandle: "Pilot_A", GameIdentityStatus: ScmGameIdentityStatus.Verified);
        var root = Path.Combine(Path.GetTempPath(), "sb-city-http-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new Vault(), options),
                new ScmProfileCacheStore(root), "fixture", () => null, initialSession: session, initialGeneration: 1);
            var remote = (IAchievementRemote)host;
            var observation = new CityObservation(1, FirstEntryObservation.HashHandle("Pilot_A"), "orison", "PLAYER_LOCATION");
            var owner = host.CurrentContext!;
            var receipt = await remote.ObserveCityAsync(owner, 1, observation, default);
            Require(receipt.NewlyEarned.SequenceEqual(new[] { "journey-orison", "journey-stanton" }), "decode new-grant list");
            foreach (var city in new[] { "lorville", "area18", "orison", "new-babbage" })
            {
                handler.ExpectedCity = city; handler.ExpectedEvidence = "inventory";
                await remote.ObserveCityAsync(owner, 1, observation with { City = city, Evidence = "RequestLocationInventory" }, default);
            }
            handler.ExpectedCity = "orison"; handler.ExpectedEvidence = "explicit";
            try { await remote.ObserveCityAsync(owner with { Subject = "other" }, 1, observation, default); throw new Exception("owner admitted"); }
            catch (AccountBridgeHostException) { }
            try { await remote.ObserveCityAsync(owner, 0, observation, default); throw new Exception("generation admitted"); }
            catch (AccountBridgeHostException) { }
            try { await remote.ObserveCityAsync(owner, 1, observation with { City = "stanton" }, default); throw new Exception("aggregate observation admitted"); }
            catch (ArgumentException) { }
            foreach (var evidence in new[] { "inventory", "explicit", "unknown" })
            {
                try { await remote.ObserveCityAsync(owner, 1, observation with { Evidence = evidence }, default); throw new Exception("unknown local evidence admitted"); }
                catch (ArgumentException) { }
            }
            Require(handler.Posts == 5, "invalid ownership and input rejected before HTTP handler");
            // A pre-fix persisted parser name must drain through the actual HTTP mapping after restart.
            var queueRoot = Path.Combine(root, "legacy-outbox");
            var store = new CityAchievementOutbox(queueRoot);
            using (var lease = store.Open(owner))
                lease.Save(new([observation with { City = "new-babbage", Evidence = "RequestLocationInventory" }], []), () => true);
            handler.ExpectedCity = "new-babbage"; handler.ExpectedEvidence = "inventory";
            using (var runtime = new AchievementRuntime(new(queueRoot), remote, () => (owner, 1), () => null,
                _ => { }, startTimer: false, cityStore: store))
                await runtime.TickAsync(true);
            using (var lease = store.Open(owner))
                Require(lease.Read().Pending.Length == 0 && lease.Read().Confirmed.Contains("new-babbage"), "old inventory outbox drains");
            handler.ExpectedCity = "orison"; handler.ExpectedEvidence = "explicit";
            handler.InvalidReceipt = true;
            try { await remote.ObserveCityAsync(owner, 1, observation, default); throw new Exception("invalid receipt admitted"); }
            catch (InvalidDataException) { }
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }
}
