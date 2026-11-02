using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunRetainedOnline()
    {
        await Case("retained resume requires new identity review and installs a unique online graph", RetainedOnlineInstallation);
        await Case("retained candidate dispatch cannot invoke browser login or logout", RetainedClosedDispatcher);
        await Case("cancelled retained candidate preserves credentials and local sources", RetainedCancel);
        await Case("cancel waits for an actual retained refresh that ignores cancellation", RetainedHeldRefresh);
        await Case("total close drains held retained refresh without clearing credentials", RetainedCloseRefresh);
        await Case("failed retained online commit reconstructs offline without revocation", RetainedCommitFailure);
        await Case("cancelling an installed retained candidate restores real local and Native sources", RetainedInstalledCancel);
        await Case("observer cancellation cannot abandon retained installed recovery", () => RetainedInstalledHeldCancel(false));
        await Case("total close waits for retained installed cancellation", () => RetainedInstalledHeldCancel(true));
        await Case("fresh installed cancellation still signs out and restores actual local sources", FreshInstalledCancel);
        await Case("replaced credentials cannot fabricate readiness after retained installed cancellation", RetainedInstalledChangedVault);
        await Case("retained pre-slot cancellation consumes original drained callbacks", () => PreSlotCancel(true));
        await Case("fresh pre-slot cancellation consumes original drained callbacks", () => PreSlotCancel(false));
        await Case("retained configuration failure owns a preserved physical exit", RetainedConfigurationFailure);
        await Case("retained partial activation fault drains every actual timer", RetainedActivationFailure);
        await Case("reserved cancellation immediately rejects late Native installation", RetainedLateInstallation);
        await Case("cold retained pending mode never restores credentials implicitly", RetainedCold);
        await Case("ordinary-root installed resume cancellation preserves the next explicit resume", () => OrdinaryRetainedRecovery(false));
        await Case("ordinary-root failed resume commit preserves the next explicit resume", () => OrdinaryRetainedRecovery(true));
        await Case("installed mode bridge keeps the transport generation after offline restoration", InstalledModeBridge);
        await RunRetainedReviewBridge();
        await RunRetainedAccountFirst();
    }

    internal static async Task RunRetainedAccountFirst()
    {
        await Case("retained account restores before unconfirmed local game identity", () => RetainedBeforeLocalIdentity(false));
        await Case("cold SCM authority does not manufacture local recording consent", () => RetainedBeforeLocalIdentity(true));
        await Case("retained account restores independently of a mismatching local profile", () => RetainedBeforeLocalIdentity(false, true));
        await Case("completed cold setup revalidates live identity without another ceremony", () => RetainedBeforeLocalIdentity(true, false, true));
        await Case("installed identity review refreshes an expired original session", () => RetainedBeforeLocalIdentity(false, expire: true));
        await Case("confirmed identity survives installed resource token renewal", () => RetainedBeforeLocalIdentity(false, boundExpire: true));
    }

    private static async Task RetainedBeforeLocalIdentity(bool cold, bool mismatching = false, bool completedCold = false, bool expire = false, bool boundExpire = false)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        await f.Original.PrepareOrdinary();
        var local = new LocalFirstUseStore(f.Original.Local.Root);
        var saved = local.Read();
        local.SelectSource(saved.Revision, Id(), Path.Combine(f.Original.Local.Root, "other", "LIVE", "Game.log"), "LIVE", () => true);
        if (mismatching)
        {
            var selected = local.Read();
            local.ConfirmIdentity(selected.Revision, Id(), new(selected.SelectedSourceKey!, Id(), "Other-Pilot",
                DateTimeOffset.UtcNow, "history", true, false), () => true);
        }
        var before = local.Read();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var mode = f.Original.Mode;
        Check((await Finish(mode.ApplyRootOfflineAsync(0, Id(), native.Generation, native))).State == "offline", "Original online owner must actually exit.");
        mode.RequestResume(mode.Current.Revision, Id());
        var revision = mode.Current.Revision;
        if (expire || boundExpire) { f.Original.Transport.TokenLifetimeSeconds = 10; f.Original.Transport.RotateAccessToken = true; }
        Check(await Finish(mode.ResumeOnlineCandidateAsync(revision)) == "observed", "Retained session must be freshly authenticated.");
        var review = await mode.ReadOnlineIdentityAsync(revision);
        Check(review.State == "accountReviewRequired" && review.ConfirmationKey is not null && review.LocalHandle is null,
            "Account restoration must not wait for the first local Handle confirmation.");
        Check((await mode.ConfirmOnlineIdentityAsync(revision, review.ConfirmationKey!)).State == "accountConfirmedForHandoff", "Re-read the same authenticated account before handoff.");
        using var composition = new CompositionFixture(f, native);
        Check((await Finish(native.InstallConfirmedOnlineAsync(revision, composition.Composition.Configure))).State == "online",
            "Install the actual account and Native consumer composition before game identity setup.");
        Check(!mode.HasInstalledOnlineForCompletion &&
            f.Original.Host!.ReadCurrentGameIdentityPolicy(f.Original.Host.CurrentContext!).SensitiveWritesAllowed,
            "Verified SCM authority remains usable without completing local recording identity setup.");
        var statistics = new InstalledSetupStatisticsChoice(f.Original.Local.Root, mode);
        Check(statistics.Read(() => true, default).State == "inactive", "Unbound identity cannot issue local statistics consent.");
        if (cold)
        {
            await native.DisposeAsync();
            f.Original.Candidate!.Dispose();
            using var transport = new FirstUseOnlineReturnTests.Transport();
            var uri = new Uri("https://synthetic.example.invalid/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), f.Original.Vault,
                new("synthetic-scm", uri, uri, uri, "synthetic-client", "synthetic-resource",
                    "openid profile.read offline_access", "/callback"));
            using var host = new ScmAccountBridgeHost(oauth,
                new ScmProfileCacheStore(Path.Combine(f.Original.Local.Root, "cold-profile")), "synthetic", () => "Pilot-Example");
            using var runtime = AccountBridgeRuntime.CreateAccountBusinessRuntime(host, f.Original.Local.Root, null, false, null);
            await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root, _ => Task.FromResult(runtime));
            await runtime.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Id(), runtime.Generation, new { schemaVersion = 1 }));
            var coldMode = runtime.FirstUseMode!;
            Check(coldMode.HasInstalledOnlineAccount && !coldMode.HasInstalledOnlineForCompletion &&
                host.ReadCurrentGameIdentityPolicy(host.CurrentContext!).SensitiveWritesAllowed,
                "Cold verified SCM authority is independent of local recording confirmation.");
            var snapshot = local.Read();
            local.ConfirmIdentity(snapshot.Revision, Id(), new(snapshot.SelectedSourceKey!, Id(), "Pilot-Example",
                DateTimeOffset.UtcNow, "history", true, false), () => true);
            if (completedCold)
            {
                var completedLocal = local.Read();
                new FirstUseCompletionStore(f.Original.Local.Root).Save(null, Id(), "online",
                    completedLocal.ActiveProfileId!, completedLocal.SelectedSourceKey!, () => true);
                Check(coldMode.HasInstalledOnlineForCompletion && coldMode.CurrentOnlineIdentity(coldMode.Current.Revision).State == "boundOnlineIdentity",
                    "Completed source/profile still needs current authenticated verified identity, but no duplicate confirmation ceremony.");
                f.Original.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
                Check(!coldMode.HasInstalledOnlineForCompletion, "Historical completion cannot authorize a replacement credential.");
                return;
            }
            var coldReview = await coldMode.ReadOnlineIdentityAsync(coldMode.Current.Revision);
            Check(coldReview.State == "installedReviewRequired", "Cold online account must expose actual identity review, not a dead end.");
            Check((await coldMode.ConfirmOnlineIdentityAsync(coldMode.Current.Revision, coldReview.ConfirmationKey!)).State == "boundOnlineIdentity" &&
                coldMode.HasInstalledOnlineForCompletion, "Explicit cold identity confirmation restores completion readiness.");
            return;
        }
        Check(local.Read().Revision == before.Revision && local.Read().ActiveProfileId == before.ActiveProfileId && f.Original.BrowserOpens == 0,
            "Restoration must not confirm, merge or replace a local profile, or reopen login.");
        var currentLocal = local.Read();
        local.ConfirmIdentity(currentLocal.Revision, Id(), new(currentLocal.SelectedSourceKey!, Id(), "Pilot-Example",
            DateTimeOffset.UtcNow, "history", true, false), () => true);
        Check(mode.HasInstalledOnlineAccount && mode.AllowsLocalIdentitySetup && !mode.HasInstalledOnlineForCompletion,
            "Confirming a local Handle keeps the account live but does not silently bind it.");
        var requests = f.Original.Transport.TokenRequests;
        if (expire) { await Task.Delay(10200); f.Original.Transport.TokenLifetimeSeconds = 3600; }
        var identity = await mode.ReadOnlineIdentityAsync(mode.Current.Revision);
        if (expire) Check(f.Original.Transport.TokenRequests > requests, "Installed expired session must refresh its original credential.");
        Check(identity.State == "installedReviewRequired" && identity.ConfirmationKey is not null, "Installed account must support fresh game identity review: " + identity.State);
        Check((await mode.ConfirmOnlineIdentityAsync(mode.Current.Revision, identity.ConfirmationKey!)).State == "boundOnlineIdentity" &&
            mode.HasInstalledOnlineForCompletion, "Only actual readback and explicit confirmation admits bound completion.");
        Check((await mode.ReadOnlineIdentityAsync(mode.Current.Revision)).State == "boundOnlineIdentity", "Rechecking bound identity must remain bound.");
        var listening = local.Read();
        local.SetListening(listening.Revision, Id(), listening.SelectedSourceKey!, true, () => true);
        Check(mode.HasInstalledOnlineForCompletion, "Listening preference is not a change of game identity.");
        if (boundExpire)
        {
            var tokenRequests = f.Original.Transport.TokenRequests;
            await Task.Delay(10200);
            f.Original.Transport.TokenLifetimeSeconds = 3600;
            f.Original.Transport.AllowProfileRead = true;
            await f.Original.Host!.GetProfileAsync(f.Original.Host.CurrentContext!, default);
            Check(f.Original.Transport.TokenRequests > tokenRequests && mode.HasInstalledOnlineForCompletion,
                "Actual resource renewal must retain the already confirmed same-account game identity.");
        }
        var boundSource = local.Read().Sources.Single(s => s.SourceKey == local.Read().SelectedSourceKey);
        Directory.CreateDirectory(Path.GetDirectoryName(boundSource.LogPath)!);
        for (var launch = 0; launch < 2; launch++)
        {
            var started = DateTimeOffset.UtcNow.AddSeconds(-1);
            File.WriteAllText(boundSource.LogPath, $"<{DateTimeOffset.UtcNow:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> nickname=\"Pilot-Example\" playerGEID=100\n");
            var evidence = new LocalLogEvidenceOwner(local,
                () => new("running", boundSource.LogPath, started, "synthetic-session-" + launch));
            Check(evidence.Refresh(boundSource.SourceKey).State == "candidate" && mode.HasInstalledOnlineForCompletion,
                "A game-log rewrite and same-Handle relaunch must not revoke the confirmed binding.");
        }
        var choice = statistics.Read(() => true, default);
        Check(choice.ChoiceKey is not null && !choice.Recording, "Installed setup issues consent without a second sampler.");
        var accepted = statistics.Confirm(choice.ChoiceKey!, true, () => true, default);
        Check(accepted.State == "saved" && accepted.Consent == "allowed" && !accepted.Recording &&
            accepted.SavedSeconds == choice.SavedSeconds, "Consent preserves totals and cannot start local recording inside online ownership.");
        currentLocal = local.Read();
        local.SelectSource(currentLocal.Revision, Id(), Path.Combine(f.Original.Local.Root, "changed", "LIVE", "Game.log"), "LIVE", () => true);
        Check(mode.HasInstalledOnlineAccount && !mode.HasInstalledOnlineForCompletion &&
            f.Original.Host!.ReadCurrentGameIdentityPolicy(f.Original.Host.CurrentContext!).SensitiveWritesAllowed,
            "Changing local setup revokes local recording consent, not verified SCM authority without a log conflict.");
        try { statistics.Confirm(accepted.ChoiceKey!, false, () => true, default); throw new Exception("Expected stale consent rejection."); }
        catch (LocalFirstUseException) { }
        Check((await Finish(mode.ApplyOfflineAsync(mode.Current.Revision, Id(), native.Generation))).State == "offline",
            "Changed local identity must not prevent the restored online account from exiting safely.");
    }

    private static async Task InstalledModeBridge()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var mode = f.Original.Mode;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        Check((await Finish(mode.CommitOnlineAsync(3, Id(), installed))).State == "online", "Actual online installation required.");
        var generation = native.Generation;
        using var bridge = native.CreateModeDispatcher()!;
        var batch = await bridge.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.OfflineRequest,
            Id(), generation, new { schemaVersion = 1, revision = 4 })).AsTask().WaitAsync(TimeSpan.FromSeconds(5));
        Check(batch.Response.Status == "ok" && batch.Response.Payload.GetProperty("state").GetString() == "offline",
            "Actual installed offline success must be returned to the original transport, not context_changed.");
        Check(mode.ControlGeneration >= generation && native.Generation == mode.ControlGeneration,
            "Restoring device ownership must not rewind the transport generation.");
        var read = await bridge.DispatchAsync(BridgeEnvelope.Request(FirstUseModeBridgeDispatcher.ReadRequest,
            Id(), generation, new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && read.Response.Payload.GetProperty("state").GetString() == "offline",
            "The same client must be able to observe the real restored mode.");
        foreach (var deviceEvent in new[] { native.DeviceNotificationActivation(generation, new { schemaVersion = 1 }),
            native.DeviceUpdateProgress(generation, new { schemaVersion = 1 }),
            native.DeviceMenuHotkeyIntent(f.Original.Local.Runtime.CurrentOverlaySourceScope.Generation, new { schemaVersion = 1 }) })
            Check(deviceEvent.SessionGeneration == generation && deviceEvent.AccountContext is null,
                "Explicit device events retain the current transport, never the retired account identity.");
        try { native.SocialNotification(generation, new { schemaVersion = 1 }); throw new Exception("Expected old account fence."); }
        catch (OperationCanceledException) { }
        mode.RequestResume(6, Id());
        Check(mode.ControlGeneration == generation && native.Generation == generation,
            "Beginning a new resume cannot erase the current transport high-water.");
        await f.Original.Cancel();
    }

    private static async Task OrdinaryRetainedRecovery(bool failedCommit)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true;
        await f.Original.PrepareOrdinary();
        var mode = f.Original.Mode;
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        Check((await Finish(mode.ApplyRootOfflineAsync(0, Id(), native.Generation, native))).State == "offline", "Actual ordinary root exit required.");
        mode.RequestResume(2, Id()); await ConfirmRetained(f);
        var installation = await CommitInstallation(f, native);
        if (failedCommit)
        {
            var release = Signal(); var cancelled = Signal();
            var read = native.ReadAsync(async (_, token) =>
            { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
            using var writer = new FileStream(Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock"),
                FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            var commit = mode.CommitOnlineAsync(3, Id(), installation);
            try
            {
                await Finish(cancelled.Task);
                Check(!commit.IsCompleted && !read.IsCompleted, "Actual writer failure owns physical Native recovery.");
                writer.Dispose();
            }
            finally
            {
                release.TrySetResult();
                try { await Finish(read); } catch (OperationCanceledException) { }
            }
            Check((await Finish(commit)).State == "offline", "Failed ordinary-root retained commit must return offline.");
        }
        else Check((await f.Original.Cancel()).State == "offline", "Installed retained cancellation returns offline.");
        var revision = f.Original.Store.Read().Revision;
        Check(mode.RequestResume(revision, Id()).State == "signInRequired" && mode.LocalMode().Active,
            "A recovered ordinary-root graph must retain readiness after clearing the prior commit.");
        await ConfirmRetained(f);
        Check((await f.Original.Cancel()).State == "offline" && f.Original.BrowserOpens == 0 &&
            f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Second explicit resume refreshes and cancels without browser login, logout or merge.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task EnterOffline(Fixture f, NativeAccountRuntimeBinding native)
    {
        var first = await CommitInstallation(f, native);
        await Finish(f.Original.Mode.CommitOnlineAsync(3, Id(), first));
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(4, Id(), native.Generation))).State == "offline", "Actual offline exit required.");
    }

    private static async Task ConfirmRetained(Fixture f)
    {
        var rev = f.Original.Store.Read().Revision;
        Check(await Finish(f.Original.Mode.ResumeOnlineCandidateAsync(rev)) == "observed", "Actual retained refresh required.");
        var review = await f.Original.Mode.ReadOnlineIdentityAsync(rev);
        Check(review.State == "reviewRequired" && review.ConfirmationKey is not null, "Resume is not identity confirmation.");
        Check((await f.Original.Mode.ConfirmOnlineIdentityAsync(rev, review.ConfirmationKey!)).State == "confirmedForHandoff", "Explicit authoritative readback required.");
    }

    private static async Task RetainedOnlineInstallation()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        await EnterOffline(f, native);
        var first = f.Original.Candidate!; var generation = first.Generation;
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        Check(f.Original.Candidate!.Generation > generation && f.Original.Transport.LastGrant!.Contains("grant_type=refresh_token") &&
            f.Original.BrowserOpens == 1 && f.Original.Host!.BusinessStartupDeferred && f.Original.Mode.LocalMode().Active,
            "Retained refresh gets a higher generation, no new browser and no implicit business activation.");
        var next = await CommitInstallation(f, native);
        Check((await Finish(f.Original.Mode.CommitOnlineAsync(7, Id(), next))).State == "online" &&
            native.Generation == next.Owner.Generation && f.Original.Mode.ControlGeneration == native.Generation,
            "Only unique installed Native graph can commit online.");
        Check((await Finish(f.Original.Mode.ApplyOfflineAsync(8, Id(), native.Generation))).State == "offline" &&
            f.Original.Transport.Revokes == 0 && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Second offline transition consumes the new original installation and still preserves login.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task RetainedClosedDispatcher()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); var next = await f.Original.Stage();
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var requests = f.Original.Transport.Requests;
        foreach (var name in new[] { "account.login", "account.logout", "account.cancelLogin", "presence.read" })
        {
            var result = await next.DispatchAsync(BridgeEnvelope.Request(name, Id(), next.Generation, new { schemaVersion = 1 }));
            Check(result.Response.Error is not null, "Retained candidate must expose no ordinary auth or business mutation.");
        }
        Check(f.Original.Transport.Requests == requests && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Blocked dispatch has no network or credential effect.");
        Check((await f.Original.Cancel()).State == "offline", "Unstarted authentication can safely cancel to offline.");
    }

    private static async Task RetainedCancel()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var candidate = f.Original.Candidate!;
        Check((await f.Original.Cancel()).State == "offline" && candidate.HasPreservedFirstUseSessionExit &&
            f.Original.Mode.LocalMode().Active && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) &&
            f.Original.Transport.Revokes == 0, "Cancel uses keep-session physical exit, not fresh credential deletion.");
        f.Original.Mode.RequestResume(f.Original.Store.Read().Revision, Id()); await ConfirmRetained(f);
        Check(f.Original.Candidate!.Generation > candidate.Generation && f.Original.BrowserOpens == 1,
            "A subsequent explicit resume creates a new owner and reuses retained login.");
        Check((await f.Original.Cancel()).State == "offline", "Second explicit resume also has an owned exit.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task WaitRefresh(Fixture f)
    {
        using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(3));
        while (f.Original.Transport.TokenRequests < 2) await Task.Delay(10, deadline.Token);
    }

    private static async Task RetainedHeldRefresh()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); f.Original.Transport.HoldToken = true;
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var resume = f.Original.Mode.ResumeOnlineCandidateAsync(7);
        await WaitRefresh(f); var cancel = f.Original.Cancel();
        Check(!cancel.IsCompleted && !resume.IsCompleted, "Mode cancellation must own the actual held transport exit.");
        f.Original.Transport.ReleaseToken.TrySetResult();
        Check(await Finish(resume) == "contextChanged" && (await Finish(cancel)).State == "offline" &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "Late cancelled refresh cannot rotate, publish or clear retained credentials.");
    }

    private static async Task RetainedCloseRefresh()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); f.Original.Transport.HoldToken = true;
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var resume = f.Original.Mode.ResumeOnlineCandidateAsync(7);
        await WaitRefresh(f); var close = native.DisposeAsync().AsTask();
        Check(!close.IsCompleted, "Total Native close must await retained auth physical exit.");
        f.Original.Transport.ReleaseToken.TrySetResult(); await Finish(close);
        Check(await Finish(resume) == "contextChanged" && f.Original.Candidate!.HasPreservedFirstUseSessionExit &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "Closing pending retained auth cannot choose strict fresh sign-out.");
    }

    private static async Task RetainedCommitFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var installed = await CommitInstallation(f, native); var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var lockPath = Path.Combine(f.Original.Local.Root, "first-use-mode-v1", "state.bin.lock");
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        using (var lease = new FileStream(lockPath, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
        {
            // Hold an actual Native callback until failure has started physical
            // retirement, then release the writer before reconstruction can run.
            var work = f.Original.Mode.CommitOnlineAsync(7, Id(), installed);
            try
            {
                await Finish(cancelled.Task);
                Check(!work.IsCompleted && !read.IsCompleted, "Write failure owns the held original callback.");
                lease.Dispose();
            }
            finally
            {
                release.TrySetResult();
                try { await Finish(read); } catch (OperationCanceledException) { }
            }
            Check((await Finish(work)).State == "offline", "Failed retained commit must restore offline, not clear login.");
        }
        Check(f.Original.Mode.LocalMode().Active && native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0 && !installed.HasCompletedCandidateExit,
            "Exact preserved candidate/Native exits authorize local reconstruction without sign-out proof.");
        f.Original.Mode.RequestResume(f.Original.Store.Read().Revision, Id());
        await ConfirmRetained(f);
        Check((await f.Original.Cancel()).State == "offline", "Recovered offline supports another explicit resume and cancellation.");
    }

    private static async Task RetainedInstalledCancel()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var installed = await CommitInstallation(f, native); var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check((await f.Original.Cancel()).State == "offline" && f.Original.Mode.LocalMode().Active &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation) &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            installed.Owner.HasPreservedFirstUseSessionExit && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Installed cancellation cannot acknowledge offline until actual local sources and Native callbacks are restored.");
    }

    private static async Task RetainedCold()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var bytes = File.ReadAllBytes(f.Original.VaultPath); var requests = f.Original.Transport.Requests;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Original.Local.Root,
            _ => throw new Exception("Cold pending resume restored account implicitly."));
        Check(cold.FirstUseMode!.LocalMode().Active && cold.FirstUseMode.CurrentOnlineIdentity(7).State == "recoveryRequired" &&
            f.Original.Transport.Requests == requests && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Cold pending restore exposes recovery without traffic or credential adoption.");
        Check((await f.Original.Cancel()).State == "offline", "Only the live original owner can cancel its started candidate.");
    }

    private static async Task RetainedInstalledHeldCancel(bool close)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var installed = await CommitInstallation(f, native); var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        { using var registration = token.Register(() => cancelled.TrySetResult()); await release.Task; return true; });
        using var observer = new CancellationTokenSource();
        var op = Id(); var physical = f.Original.Mode.CancelOnlineAsync(7, op);
        var wait = f.Original.Mode.CancelOnlineAsync(7, op, observer.Token);
        Task? shutdown = null;
        try
        {
            await Finish(cancelled.Task);
            Check(!physical.IsCompleted && !read.IsCompleted && !f.Original.Mode.LocalMode().Active,
                "Cancellation may not advertise local readiness while original callback is held.");
            observer.Cancel();
            try { await wait; throw new Exception("Observer cancellation was ignored."); }
            catch (OperationCanceledException) { }
            Check(!physical.IsCompleted, "Leaving the observer cannot abandon actual reconstruction.");
            if (close)
            {
                shutdown = native.DisposeAsync().AsTask();
                Check(!shutdown.IsCompleted, "Close must await original cancellation and Native callback.");
            }
        }
        finally
        {
            release.TrySetResult();
            try { await Finish(read); } catch (OperationCanceledException) { }
        }
        var result = await Finish(physical);
        if (shutdown is not null)
        {
            await Finish(shutdown);
            Check(result.State == "recoveryRequired" && !f.Original.Mode.LocalMode().Active,
                "Close-first cannot resurrect local readiness.");
        }
        else Check(result.State == "offline" &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation),
            "Original physical recovery restores both actual local owners after the observer leaves.");
        Check(installed.Owner.HasPreservedFirstUseSessionExit && f.Original.Transport.Revokes == 0 &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)), "Neither close nor UI cancellation clears login.");
    }

    private static async Task FreshInstalledCancel()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var installed = await CommitInstallation(f, native);
        Check((await f.Original.Cancel()).State == "local" && installed.HasCompletedCandidateExit &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation) &&
            f.Original.Vault.LoadActiveAccountKey() is null, "Fresh original exit still requires real sign-out, not preserved-session proof.");
        f.Original.Mode.RequestOnline(f.Original.Store.Read().Revision, Id());
        Check(await Finish(f.Original.Mode.AuthenticateOnlineCandidateAsync(f.Original.Store.Read().Revision, default)) &&
            f.Original.BrowserOpens == 2, "Fresh retry stays browser-authenticated after the original restoration.");
        Check((await f.Original.Cancel()).State == "local", "Fresh retry owns its original strict exit.");
    }

    private static async Task RetainedInstalledChangedVault()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var installed = await CommitInstallation(f, native);
        f.Original.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var result = await f.Original.Cancel();
        Check(bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
            "Retirement cannot clear or adopt the newer selected credential.");
        Check(result.State == "offline" ? native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation) :
            result.State == "recoveryRequired" && !f.Original.Mode.LocalMode().Active,
            "Revoked live business authority cannot fall into auth-only cancellation and fabricate local readiness.");
    }

    private static async Task PreSlotCancel(bool retained)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        if (retained) { await EnterOffline(f, native); f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f); }
        var installation = await CommitInstallation(f, native, attach: false);
        Check((await f.Original.Cancel()).State == (retained ? "offline" : "local") &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false) &&
            f.Original.Local.Runtime.HasCurrentFirstUseLocalSources(f.Original.Mode.LocalMode().Generation) &&
            (retained ? installation.Owner.HasPreservedFirstUseSessionExit : installation.HasCompletedCandidateExit),
            "Pre-slot cancellation must restore actual root sources and its drained original callbacks.");
    }

    private static async Task RetainedConfigurationFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!; var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check(!await install.Owner.RetireFirstUseOnlineCandidateAsync(), "Wrong exit kind cannot claim sign-out.");
        try { install.Configure(_ => throw new IOException("Synthetic retained configuration failure.")); throw new Exception("Expected failure."); }
        catch (IOException) { }
        Check(await Finish(install.RetireAsync()) && install.Owner.HasPreservedFirstUseSessionExit &&
            !install.Configure(_ => { }) && !install.TryActivate() && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) &&
            f.Original.Transport.Revokes == 0, "Wrong retirement must not poison actual preserved configuration exit.");
        Check((await f.Original.Cancel()).State == "offline" &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false), "Failed configuration still owns actual local restoration.");
    }

    private static async Task RetainedActivationFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        f.Original.Clock.FailAt = f.Original.Clock.Timers + 3;
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!; var bytes = File.ReadAllBytes(f.Original.VaultPath);
        Check(install.Configure(_ => { }), "Dormant retained graph must configure.");
        try { install.TryActivate(); throw new Exception("Expected partial startup fault."); } catch (IOException) { }
        try { await Finish(install.RetireAsync()); throw new Exception("Expected physical exit fault."); } catch (IOException) { }
        Check(!install.IsActive && f.Original.Clock.Created.All(timer => timer.Disposed) &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0 &&
            (await f.Original.Cancel()).State == "recoveryRequired" && !f.Original.Mode.LocalMode().Active,
            "Actual partial fault drains siblings but retains credentials and refuses offline readiness.");
        try { await Finish(native.DisposeAsync().AsTask()); } catch (IOException) { }
    }

    private static async Task RetainedLateInstallation()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        await using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime); await EnterOffline(f, native);
        f.Original.Mode.RequestResume(6, Id()); await ConfirmRetained(f);
        var install = await CommitInstallation(f, native, attach: false);
        var queue = new CommitQueue(); var original = SynchronizationContext.Current;
        Task<FirstUseModeObservation> cancellation;
        SynchronizationContext.SetSynchronizationContext(queue);
        try { cancellation = f.Original.Mode.CancelOnlineAsync(7, Id()); }
        finally { SynchronizationContext.SetSynchronizationContext(original); }
        Check(!cancellation.IsCompleted && native.InstallBusiness(install) is null,
            "A queued physical exit does not leave late Native installation authority open.");
        await Finish(queue.Start());
        Check((await Finish(cancellation)).State == "offline" &&
            native.Read(owner => ReferenceEquals(owner, f.Original.Local.Runtime), false), "Original pre-slot cancellation still restores offline.");
    }
}
