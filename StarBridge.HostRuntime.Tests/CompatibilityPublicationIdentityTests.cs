using System.Reflection;
using StarBridge.Core.Identity;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Privacy;

internal static class CompatibilityPublicationIdentityTests
{
    internal static void Verify()
    {
        foreach (var useRecent in new[] { false, true })
        foreach (var (status, check, detected, expected) in new[] {
            (ScmGameIdentityStatus.Verified, LocalIdentityCheckState.NotObserved, (string?)null, true),
            (ScmGameIdentityStatus.Verified, LocalIdentityCheckState.Match, "FixturePilot", true),
            // Persisted prior-log comparison is not current conflicting evidence.
            (ScmGameIdentityStatus.Verified, LocalIdentityCheckState.Mismatch, (string?)null, true),
            (ScmGameIdentityStatus.Verified, LocalIdentityCheckState.NotObserved, "DifferentPilot", false),
            (ScmGameIdentityStatus.Revoked, LocalIdentityCheckState.Match, "FixturePilot", false),
            (ScmGameIdentityStatus.Unverified, LocalIdentityCheckState.Match, "FixturePilot", false)
        })
        {
            var http = new ScmHttpClient();
            var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
                DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot", GameIdentityStatus: status);
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(http, new Vault(), ScmOAuthOptions.CreateDefault()),
                new ScmProfileCacheStore(), "fixture", () => useRecent ? null : detected, initialSession: session,
                lastGameIdentityCheck: () => check, recentGameIdentity: () => useRecent ? detected : null);
            // SCM's verified identity is authoritative even while local setup
            // has not confirmed a Game.log identity. A real mismatch still blocks.
            host.RequireColdFirstUseGameIdentity(() => false);
            using var runtime = new AccountBridgeRuntime(host);
            var account = host.ReadCurrentGameIdentityPolicy(host.CurrentContext!);
            // Inspect the exact input consumed by realtime/friend/event publishers;
            // do not call a network writer or manufacture a confirmed input.
            var input = (PrivacyPublicationInput?)typeof(AccountBridgeRuntime)
                .GetMethod("PublicationInput", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(runtime, null);
            if (account.SensitiveWritesAllowed != expected || (input?.IdentityConfirmed ?? false) != expected)
                throw new InvalidOperationException($"Account and publication must agree: status={status}, local={check}, expected={expected}, publication={input?.IdentityConfirmed}");
        }
        VerifyLogReadOwnerBeforeLocalConfirmation();
    }

    private static void VerifyLogReadOwnerBeforeLocalConfirmation()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-log-owner-" + Guid.NewGuid().ToString("N"));
        var session = new ScmOAuthSession("fixture-scm", "fixture-subject", "Fixture", "synthetic-token",
            DateTimeOffset.UtcNow.AddMinutes(5), [], GameIdentityHandle: "FixturePilot",
            GameIdentityStatus: ScmGameIdentityStatus.Verified);
        using var host = new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(), new Vault(), ScmOAuthOptions.CreateDefault()),
            new ScmProfileCacheStore(), "fixture", () => null, initialSession: session);
        using var runtime = new AccountBridgeRuntime(host,
            gameLog: new StarBridge.HostRuntime.Presence.GameLogSettingsStore(root));
        typeof(AccountBridgeRuntime).GetMethod("RequireColdFirstUseGameIdentity",
            BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(runtime, [new Func<bool>(() => false)]);
        var log = typeof(AccountBridgeRuntime).GetField("_gameLog",
            BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(runtime)!;
        var owner = (Func<(StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation)>)log.GetType()
            .GetField("_current", BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(log)!;
        if (owner().Context != host.CurrentContext || owner().Generation != host.Generation)
            throw new InvalidOperationException("Verified SCM log review must retain the current owner before local confirmation.");
        var recording = ((StarBridge.NativeBridge.BridgeAccountContext? Context, long Generation))typeof(AccountBridgeRuntime)
            .GetMethod("GameplayRecordingOwner", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(runtime, null)!;
        if (recording.Context is not null)
            throw new InvalidOperationException("Log review must not bypass independent game recording admission.");
        var journalAllowed = (Func<bool>)log.GetType().GetField("_recordingAllowed",
            BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(log)!;
        if (journalAllowed())
            throw new InvalidOperationException("Log review must not bypass journal recording admission.");
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected credential write");
        public string? LoadRefreshToken(string a) => throw new Exception("Unexpected credential read");
        public string? LoadActiveAccountKey() => throw new Exception("Unexpected credential read");
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected credential delete");
    }
}
