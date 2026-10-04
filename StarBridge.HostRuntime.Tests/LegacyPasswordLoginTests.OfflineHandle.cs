using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static partial class LegacyPasswordLoginTests
{
    internal static async Task OfflineHandleChange()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-offline-handle-" + Guid.NewGuid().ToString("N"));
        var path = Path.Combine(root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, "<2026-09-04T12:00:10Z> nickname=\"Pilot-New\" playerGEID=12345\n" +
            "<2026-09-04T12:00:20Z> SystemQuit CSystem::Quit\n");
        try {
            using var http = new HandleTransport();
            using var client = new LegacyPasswordLoginClient(new Uri("https://example.invalid/"), new Store(), http, new Store());
            GameLogRuntime? log = null;
            using var host = new ScmAccountBridgeHost(
                new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "development", () => log?.DetectedHandle,
                legacyPasswordLogin: client, recentGameIdentity: () => log?.RecentDetectedHandle);
            using var runtime = new AccountBridgeRuntime(host);
            await host.LoginLegacyAsync(BridgePayload.From(new { schemaVersion = 1, email = "old@example.invalid", password = "synthetic" }), 0, default);
            using var gameLog = new GameLogRuntime(new GameLogSettingsStore(root),
                () => (host.CurrentContext, host.Generation), () => host.HangarIdentity?.Identity.Handle,
                () => new("notRunning"), startTimer: false);
            log = gameLog;
            BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), host.Generation, body, host.CurrentContext);
            void ReadLog() => Check(gameLog.Dispatch(Request("gameLog.select", new { schemaVersion = 1, path })).Response.Status == "ok", "read existing selected log");
            ReadLog();
            Check(gameLog.DetectedHandle is null && gameLog.RecentDetectedHandle == "Pilot-New", "recent identity is not a running game");
            var policy = host.ReadCurrentGameIdentityPolicy(host.CurrentContext!);
            Check(policy.State == "mismatch" && policy.DetectedHandle == "Pilot-New" && http.Writes == 0,
                "offline mismatch exposes the correction without changing the account");
            var ready = await runtime.DispatchAsync(Request("gameIdentity.prepareHandleChange", new { schemaVersion = 1 }));
            Check(ready.Response.Payload.GetProperty("state").GetString() == "ready", "existing log unlocks explicit correction");
            var id = ready.Response.Payload.GetProperty("confirmationId").GetString();
            await runtime.DispatchAsync(Request("gameIdentity.cancelHandleChange", new { schemaVersion = 1, confirmationId = id }));
            Check(http.Writes == 0 && host.ReadCurrentGameIdentityPolicy(host.CurrentContext!).State == "mismatch", "cancel retains account and mismatch");
            ready = await runtime.DispatchAsync(Request("gameIdentity.prepareHandleChange", new { schemaVersion = 1 }));
            id = ready.Response.Payload.GetProperty("confirmationId").GetString();
            var result = await runtime.DispatchAsync(Request("gameIdentity.confirmHandleChange", new { schemaVersion = 1, confirmationId = id }));
            Check(result.Response.Status == "ok" && http.Writes == 1 && host.HangarIdentity?.Identity.Handle == "Pilot-New", "one explicitly confirmed update reads back");
            ReadLog();
            Check(host.ReadCurrentGameIdentityPolicy(host.CurrentContext!).State == "match" &&
                gameLog.CurrentSession == GameLogSessionSnapshot.Empty && gameLog.ConfirmedVersion is null,
                "resolved identity must not publish historical gameplay presence");
            var restored = await client.RestoreAsync(default);
            Check(restored.Identity?.Handle == "Pilot-New", "synthetic restart reads server-confirmed new Handle");
            using var scm = new ScmAccountBridgeHost(
                new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "development", () => null,
                initialSession: new ScmOAuthSession("scm", "subject", "Synthetic", "token", DateTimeOffset.UtcNow.AddHours(1), [],
                    GameIdentityVerified: true, GameIdentityHandle: "Scm-Pilot"),
                recentGameIdentity: () => "Pilot-New");
            Check(scm.ReadCurrentGameIdentityPolicy(scm.CurrentContext!).DetectedHandle is null,
                "compatibility change does not extend historical identity to SCM sessions");
        } finally { Directory.Delete(root, true); }
    }
}
