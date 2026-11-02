using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Auth;

/// <summary>The achievement read sample shared with Flutter and the server tests.</summary>
internal static class AchievementReadContractTests
{
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential delete");
    }
    private sealed class Handler(string body) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) =>
            Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent(body, Encoding.UTF8, "application/json") });
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    private static string SamplePath()
    {
        for (var directory = new DirectoryInfo(AppContext.BaseDirectory); directory is not null; directory = directory.Parent)
        {
            var path = Path.Combine(directory.FullName, "contracts", "achievements", "read-response.json");
            if (File.Exists(path)) return path;
        }
        throw new FileNotFoundException("contracts/achievements/read-response.json");
    }

    private static async Task<AchievementSnapshot> Read(string body)
    {
        using var handler = new Handler(body);
        var http = new ScmHttpClient(handler);
        var options = new ScmOAuthOptions("fixture-scm", new("http://127.0.0.1:3000/"), new("http://127.0.0.1:18080/"),
            new("http://127.0.0.1:18082/"), "starbridge-desktop", "starbridge-api",
            "profile.read presence.write game_identity.read", "/oauth/callback");
        var session = new ScmOAuthSession("fixture-scm", "synthetic-contract", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write", "game_identity.read"],
            GameIdentityHandle: "Pilot_A", GameIdentityStatus: ScmGameIdentityStatus.Verified);
        var root = Path.Combine(Path.GetTempPath(), "sb-ach-contract-" + Guid.NewGuid().ToString("N"));
        try
        {
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new Vault(), options),
                new ScmProfileCacheStore(root), "fixture", () => null, initialSession: session, initialGeneration: 1);
            var remote = (IAchievementRemote)host;
            return await remote.ReadAchievementsAsync(host.CurrentContext!, 1, default);
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    internal static async Task Run()
    {
        using var sample = JsonDocument.Parse(await File.ReadAllTextAsync(SamplePath()));
        var released = sample.RootElement.GetProperty("releasedClientProgress");
        var releasedKeys = released.GetProperty("keys").EnumerateArray().Select(key => key.GetString()!).ToHashSet();
        var maximum = released.GetProperty("maximumKeys").GetInt32();
        foreach (var name in new[] { "empty", "withoutCities", "withCities" })
        {
            var expected = sample.RootElement.GetProperty(name);
            var snapshot = await Read(expected.GetRawText());
            var earned = expected.GetProperty("earnedAt").EnumerateObject().ToArray();
            Require(snapshot.EarnedAt.Count == earned.Length && earned.All(p =>
                snapshot.EarnedAt.TryGetValue(p.Name, out var at) && at == p.Value.GetDateTimeOffset()),
                $"{name}: every sampled award and its time are decoded");
            var progress = expected.GetProperty("progress").EnumerateObject().ToArray();
            Require(snapshot.Progress is { } read && read.Count == progress.Length &&
                progress.All(p => read.GetValueOrDefault(p.Name, -1) == p.Value.GetInt32()), $"{name}: progress is decoded");
            // A released client must read every account shape that has never reported a city.
            if (name != "withCities")
                Require(progress.Length <= maximum && progress.All(p => releasedKeys.Contains(p.Name)),
                    $"{name}: the sample stays inside the released client's rule");
        }
    }
}
