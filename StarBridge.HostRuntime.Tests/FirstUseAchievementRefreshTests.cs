using System.Reflection;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Achievements;
using StarBridge.Core.Presence;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunAchievementRefreshRegression()
    {
        await AchievementTriggerRefresh(false);
        await AchievementTriggerRefresh(true);
        await AchievementRefreshReplacedVault();
        await NewLoginCannotRestoreAdmission();
        await InstallationPublicationExit();
        Console.WriteLine("PASS R1 InstallationPublicationExit: all four original publication/retirement scenarios");
    }
    private static async Task NewLoginCannotRestoreAdmission()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Original admission must activate before replacement login.");
        var host = f.Original.Host!; var context = host.GameplayTimeContext!;
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var oauth = (StarBridge.HostRuntime.Auth.OAuthPkceClient)host.GetType().GetField("_oauth", flags)!.GetValue(host)!;
        // Actual synthetic PKCE login installs a new credential/session with the
        // same authoritative identity. It is not an original refresh descendant.
        await oauth.SignInAsync(default);
        if (f.Original.Callback is { } callback) await Finish(callback);
        var replacement = File.ReadAllBytes(f.Original.VaultPath);
        Check(!admission.IsActive, "Same-owner new login must invalidate old admission.");
        try { await host.TriggerScmAchievementsAsync(context, default); }
        catch (Exception error) when (error is HttpRequestException or StarBridge.HostRuntime.Account.AccountBridgeHostException) { }
        Check(!admission.IsActive && admission.Enter(default) is null && host.GameplayTimeContext is null &&
            File.ReadAllBytes(f.Original.VaultPath).SequenceEqual(replacement),
            "R1 NewLoginCannotRestoreAdmission: current same-account session is not original or proven refresh lineage.");
        await Finish(admission.RetireAsync());
        Console.WriteLine("PASS R1 NewLoginCannotRestoreAdmission");
    }
    private sealed class CaptureWindowClock : TimeProvider
    {
        internal Action? BeforeCapture;
        internal int Reads;
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        public override DateTimeOffset GetUtcNow()
        {
            // EnsureActive checks expiry, then RestoreCore checks memory immediately
            // before CaptureResumeCredential. Replace only in that second check.
            if (BeforeCapture is not null && ++Reads == 2)
            { var replace = BeforeCapture; BeforeCapture = null; replace(); }
            return Now;
        }
    }
    private static async Task AchievementRefreshReplacedVault()
    {
        using var f = new Fixture(); var clock = new CaptureWindowClock();
        f.Original.SessionTime = clock; f.Original.Clock.AllowTimers = true;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original installation must pass its initial checks.");
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var unlocks = (ScmAchievementUnlockRuntime)typeof(AccountBridgeRuntime).GetField("_scmAchievementUnlocks", flags)!.GetValue(install.Owner)!;
        await Finish(unlocks.WaitForIdleAsync()); // Initial daily trigger is intentionally unavailable.
        Check(install.IsActive, "Original installed owner remains live after its first trigger.");
        var host = f.Original.Host!; var context = host.GameplayTimeContext!;
        byte[]? replacement = null;
        clock.Now += TimeSpan.FromHours(1);
        clock.Reads = 0; clock.BeforeCapture = () => {
            f.Original.Vault.SaveRefreshToken("synthetic-scm:synthetic-subject", "synthetic-replacement-refresh");
            replacement = File.ReadAllBytes(f.Original.VaultPath);
        };
        f.Original.Transport.TokenLifetimeSeconds = 3600;
        f.Original.Transport.FailAchievementTrigger = false;
        try { await host.TriggerScmAchievementsAsync(context, default); }
        catch (Exception error) when (error is HttpRequestException or StarBridge.HostRuntime.Account.AccountBridgeHostException) { }
        Check(replacement is not null && !install.IsActive,
            "R1 CaptureWindowReplacement: a same-owner replacement before capture cannot inherit the old admission.");
        var oauth = (StarBridge.HostRuntime.Auth.OAuthPkceClient)host.GetType().GetField("_oauth", flags)!.GetValue(host)!;
        var original = (StarBridge.HostRuntime.Auth.ScmOAuthSession)host.GetType().GetField("_session", flags)!.GetValue(host)!;
        var tokenRequests = f.Original.Transport.TokenRequests;
        try { await oauth.TryRestoreSessionAsync(default); }
        catch (HttpRequestException) { }
        Check(oauth.ReadInstalledFirstUseRefreshSuccessor(original) is null && f.Original.Transport.TokenRequests == tokenRequests,
            "A later direct refresh cannot manufacture ancestry from the replacement vault.");
        try { await host.TriggerScmAchievementsAsync(context, default); }
        catch (Exception error) when (error is HttpRequestException or StarBridge.HostRuntime.Account.AccountBridgeHostException) { }
        Check(!install.IsActive && host.GameplayTimeContext is null &&
            File.ReadAllBytes(f.Original.VaultPath).SequenceEqual(replacement!),
            "R1 ReplacementCannotReviveAdmission: subsequent refresh must preserve the new credential and cannot reconnect the old admission.");
        Check(!await Finish(install.RetireAsync()) && !install.IsActive &&
            File.ReadAllBytes(f.Original.VaultPath).SequenceEqual(replacement!),
            "Retirement must drain the old graph and preserve recovery for the replacement credential.");
        Console.WriteLine("PASS R1 CaptureWindowReplacement / ReplacementCannotReviveAdmission");
    }
    private static async Task AchievementTriggerRefresh(bool fail)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        f.Original.SessionTime = new FirstUseOnlineReturnTests.FrozenSessionTime();
        f.Original.Transport.TokenLifetimeSeconds = 2;
        f.Original.Transport.RotateAccessToken = true;
        f.Original.Transport.HoldAchievementTrigger = true;
        f.Original.Transport.FailAchievementTrigger = fail;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        var tokens = f.Original.Transport.TokenRequests;
        f.Original.Transport.TokenLifetimeSeconds = 3600;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Actual first-use installation must activate.");
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var unlocks = (ScmAchievementUnlockRuntime)typeof(AccountBridgeRuntime).GetField("_scmAchievementUnlocks", flags)!.GetValue(install.Owner)!;
        try
        {
            await Finish(f.Original.Transport.AchievementEntered.Task);
            Check(f.Original.Transport.TokenRequests == tokens + 1 && install.IsActive && f.Original.Host!.GameplayTimeContext is not null,
                "R1 FirstInstallationNearExpiry: actual committed refresh must preserve admission even while resource IO is held.");
        }
        finally { f.Original.Transport.ReleaseAchievement.TrySetResult(); }
        if (fail) await Finish(unlocks.WaitForIdleAsync());
        else await unlocks.RetireAsync(); // Success would otherwise wait for delayed catalog reads.
        Check(install.IsActive && f.Original.Transport.AchievementTriggers == 1,
            "Success/failure must preserve the original installed owner without retriggering.");
        f.Original.Transport.AllowPresenceWrite = true;
        var mode = await f.Original.Host!.SetPresenceVisibilityAuthorityAsync(f.Original.Host.GameplayTimeContext!,
            f.Original.Host.Generation, PlayerPresenceVisibilityMode.Online, default);
        Check(mode == PlayerPresenceVisibilityMode.Online && install.IsActive && f.Original.Transport.TokenRequests == tokens + 1,
            "Existing presence owner must continue the committed refresh after trigger success/failure.");
        Check(await Finish(install.RetireAsync()), "Original installation must physically retire.");
        Console.WriteLine("PASS R1 FirstInstallationNearExpiry: " + (fail ? "failed trigger" : "successful trigger"));
    }

    internal static async Task RunAchievementConcurrencyRegression()
    {
        var failed = 0;
        foreach (var test in new Func<Task>[] { OwnershipReadDuringIdentityRefresh, SamplerSealsDuringAchievementExit, ResourceFailureRecovery, PresenceSupersededReceipt, DirectSnapshotGenerationFence, GovernanceLockTimeoutIsNotSent })
        {
            try { await test(); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL ACHFU " + test.Method.Name + ": " + error.Message); }
        }
        Check(failed == 0, "ACHFU concurrency regressions failed: " + failed);
    }

    private sealed class OwnershipReadClock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.UtcNow;
        internal Action? Read;
        public override DateTimeOffset GetUtcNow() { Read?.Invoke(); return Now; }
    }

    private static async Task OwnershipReadDuringIdentityRefresh()
    {
        using var f = new Fixture();
        var clock = new OwnershipReadClock();
        f.Original.SessionTime = clock;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Original admission must activate before the concurrent ownership read.");
        var host = f.Original.Host!;
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var hostSession = host.GetType().GetField("_session", flags)!;
        var oauth = (OAuthPkceClient)host.GetType().GetField("_oauth", flags)!.GetValue(host)!;
        var oauthSession = typeof(OAuthPkceClient).GetField("_currentSession", flags)!;
        var original = (ScmOAuthSession)hostSession.GetValue(host)!;
        var observed = false;
        var changed = false;
        clock.Now += TimeSpan.FromHours(2);
        clock.Read = () => {
            if (oauthSession.GetValue(oauth) is not ScmOAuthSession current ||
                current.CredentialVersion == original.CredentialVersion) return;
            // The real resource refresh has committed in OAuth, but the identity
            // operation still owns Host's mutation lane and its old snapshot.
            // Reproduce an achievement worker consulting GameplayTimeContext here.
            clock.Read = null;
            observed = true;
            var before = hostSession.GetValue(host);
            Check(host.GameplayTimeContext == host.CurrentContext && admission.IsActive,
                "A proven refresh must keep the installed admission live during ownership reads.");
            changed = !ReferenceEquals(before, hostSession.GetValue(host));
        };
        var result = await host.ReadFirstUseIdentityAsync(default);
        Check(observed && !changed && result.State == "observed" && admission.IsActive,
            "Concurrent achievement ownership reads must not replace the identity lane's Host snapshot: " + result.State);
        // Also cover a completed resource refresh whose Host caller has not yet
        // adopted it. A getter stays read-only; the next identity operation must
        // reconnect only that proven descendant under its mutation ownership.
        clock.Now += TimeSpan.FromHours(2);
        await oauth.TryRestoreSessionAsync(default);
        var beforeReview = hostSession.GetValue(host);
        Check(host.GameplayTimeContext == host.CurrentContext && admission.IsActive &&
            ReferenceEquals(beforeReview, hostSession.GetValue(host)),
            "Completed OAuth refresh must keep admission live without read-side adoption.");
        Check((await host.ReadFirstUseIdentityAsync(default)).State == "observed" && admission.IsActive &&
            !ReferenceEquals(beforeReview, hostSession.GetValue(host)),
            "The installed identity mutation must adopt its exact committed refresh successor.");
        await Finish(admission.RetireAsync());
        Console.WriteLine("PASS ACHFU ownership read during committed identity refresh preserves the mutation owner");
    }

    private static async Task SamplerSealsDuringAchievementExit()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        f.Original.Transport.HoldAchievementTrigger = true;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original graph must activate before held achievement IO.");
        await Finish(f.Original.Transport.AchievementEntered.Task);
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var sampler = typeof(AccountBridgeRuntime).GetField("_gameLog", flags)!.GetValue(install.Owner)!;
        var sampling = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)sampler.GetType().GetField("_samplingWork", flags)!.GetValue(sampler)!;
        using var lease = sampling.Enter(default)!;
        Task<bool>? exit = null;
        try
        {
            exit = install.RetireAsync();
            Check(!exit.IsCompleted && sampling.IsClosed && lease.Token.IsCancellationRequested &&
                f.Original.Vault.LoadActiveAccountKey() is not null,
                "Held achievement IO must not postpone sampler sealing or clear the original credential.");
            f.Original.Transport.ReleaseAchievement.TrySetResult();
            var unlocks = (StarBridge.HostRuntime.Achievements.ScmAchievementUnlockRuntime)typeof(AccountBridgeRuntime)
                .GetField("_scmAchievementUnlocks", flags)!.GetValue(install.Owner)!;
            await Finish(unlocks.WaitForIdleAsync());
            Check(!exit.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null,
                "Achievement exit alone cannot clear credentials while the original sampler lease remains held.");
        }
        finally
        {
            lease.Dispose(); f.Original.Transport.ReleaseAchievement.TrySetResult();
            if (exit is not null) Check(await Finish(exit), "The original complete graph must physically exit.");
        }
        Check(f.Original.Vault.LoadActiveAccountKey() is null, "Fresh candidate credentials clear only after both physical exits.");
        Console.WriteLine("PASS ACHFU held achievement and sampler IO seal together and drain before credential removal");
    }
}
