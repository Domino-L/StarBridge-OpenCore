using StarBridge.HostRuntime;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunCandidateShutdown()
    {
        await Case("normal candidate shutdown preserves credentials only after actual Native and graph exit", CandidateShutdown);
        await Case("a sign-out already owning physical exit cannot be changed into credential preservation", CandidateSignOutWins);
        await Case("normal shutdown never overwrites a newer credential writer", CandidateShutdownNewerCredential);
        await Case("failed physical shutdown keeps its original fault and cannot acknowledge sign-out", CandidateShutdownFailure);
        await Case("failed server withdrawal cannot acknowledge shutdown before actual sampler exit", () => NativeInstallationFailedExit(true));
        await Case("mixed exit intentions can reenter from a cancellation callback without holding its reservation lock", CandidateShutdownReentry);
    }

    private static Task CandidateShutdown() => CandidateShutdownHeld(false, false);
    private static Task CandidateSignOutWins() => CandidateShutdownHeld(true, false);
    private static Task CandidateShutdownNewerCredential() => CandidateShutdownHeld(false, true);

    private static async Task CandidateShutdownHeld(bool signOutFirst, bool replaceCredential)
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original graph is live.");
        var receipt = native.InstallBusiness(install)!;
        var release = Signal(); var cancelled = Signal();
        var read = native.ReadAsync(async (_, token) =>
        {
            using var registration = token.Register(() => cancelled.TrySetResult());
            await release.Task; return true;
        });
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        try
        {
            var first = signOutFirst ? install.RetireAsync() : install.Owner.ShutdownFirstUseOnlineCandidateAsync();
            await Finish(cancelled.Task);
            var shutdown = install.Owner.ShutdownFirstUseOnlineCandidateAsync();
            var retire = install.RetireAsync();
            Check(ReferenceEquals(shutdown, install.Owner.ShutdownFirstUseOnlineCandidateAsync()) &&
                ReferenceEquals(retire, install.RetireAsync()) && ReferenceEquals(first, signOutFirst ? retire : shutdown),
                "Each intention observes the same original physical exit; repeated observations are unique.");
            Check(!first.IsCompleted && !retire.IsCompleted && !shutdown.IsCompleted && !receipt.IsCurrent &&
                native.Generation == -1 && f.Original.Transport.Revokes == 0 &&
                bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
                "Neither exit intention acknowledges cancellation-ignoring Native work or prematurely touches credentials.");
            if (replaceCredential)
            {
                f.Original.Vault.SaveRefreshToken("synthetic-new:other", "synthetic-new-refresh");
                bytes = File.ReadAllBytes(f.Original.VaultPath);
            }
            release.TrySetResult();
            try { await Finish(read); throw new InvalidOperationException("Old callback result escaped shutdown."); }
            catch (OperationCanceledException) { }
            Check(await Finish(shutdown) && await Finish(retire) == signOutFirst && receipt.HasExitedSuccessfully &&
                install.HasCompletedCandidateExit == signOutFirst &&
                install.Owner.HasPreservedFirstUseSessionExit == !signOutFirst &&
                f.Original.Clock.Created.All(timer => timer.Disposed),
                "Actual full exit has one immutable intention and distinct preservation versus sign-out proof.");
            Check(signOutFirst
                ? f.Original.Vault.LoadActiveAccountKey() is null && f.Original.Transport.Revokes == 1
                : bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)) && f.Original.Transport.Revokes == 0,
                "Normal shutdown keeps exact vault bytes, including a newer writer; sign-out clears only its credential.");
            var mode = await Finish(f.Original.Cancel());
            Check(mode.State == (signOutFirst ? "local" : "recoveryRequired") &&
                f.Original.Store.Read().Phase == (signOutFirst ? "local" : "onlinePending"),
                "A preserved session cannot grant local mode or turn unfinished onboarding into durable online.");
            Check(!await native.RestoreLocalCallbacksAsync(prepared, f.Original.Mode.LocalMode().Generation),
                "No recovery slot exists without actual source reconstruction and a successful sign-out receipt.");
            f.Original.Local.RequireLocalStateUnchanged();
        }
        finally
        {
            release.TrySetResult(); try { await Finish(read); } catch (OperationCanceledException) { }
            // An unfinished candidate still requires sign-out. Only mode's
            // durable original installation can select keep-session shutdown.
            try { await Finish(native.DisposeAsync().AsTask()); }
            catch (InvalidOperationException) when (!signOutFirst && install.Owner.HasPreservedFirstUseSessionExit) { }
        }
    }

    private static async Task CandidateShutdownFailure()
    {
        using var f = new Fixture(); f.Original.Clock.AllowTimers = true; await f.Start();
        var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var install = prepared.StageInstallation(callbacks, sources)!;
        Check(install.Configure(_ => { }) && install.TryActivate(), "Original graph is live.");
        // Do not attach Native: this fault test exercises the same candidate
        // exit without total-binding disposal replacing the original fault.
        f.Original.Clock.Created[0].FailDispose = true;
        var bytes = File.ReadAllBytes(f.Original.VaultPath);
        var shutdown = install.Owner.ShutdownFirstUseOnlineCandidateAsync();
        try { await Finish(shutdown); throw new InvalidOperationException("Faulted physical exit was acknowledged."); }
        catch (IOException error) when (error.Message == "Synthetic timer retirement failure.") { }
        Check(shutdown.IsFaulted && ReferenceEquals(shutdown, install.Owner.ShutdownFirstUseOnlineCandidateAsync()) &&
            !install.Owner.HasPreservedFirstUseSessionExit && !install.HasCompletedCandidateExit &&
            f.Original.Clock.Created.All(timer => timer.Disposed) && f.Original.Transport.Revokes == 0 &&
            bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Faulted shutdown drains siblings, retains the original fault and credential, and issues no success proof.");
        try { await Finish(install.RetireAsync()); throw new InvalidOperationException("Fault became sign-out success."); }
        catch (IOException error) when (error.Message == "Synthetic timer retirement failure.") { }
        f.Original.Local.RequireLocalStateUnchanged();
        var disposal = native.DisposeAsync().AsTask();
        try { await Finish(disposal); throw new Exception("Uninstalled candidate fault became successful total Native exit."); }
        catch (InvalidOperationException error) when
            (error.Message == "The installed first-use candidate did not confirm complete exit.") { }
        Check(disposal.IsFaulted && bytes.SequenceEqual(File.ReadAllBytes(f.Original.VaultPath)),
            "Total Native disposal retains uninstalled candidate exit failure and the exact credential.");
    }

    private static async Task CandidateShutdownReentry()
    {
        foreach (var preserveSession in new[] { true, false })
        {
            using var f = new Fixture(); await f.Start();
            var candidate = f.Original.Candidate!;
            var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)typeof(AccountBridgeRuntime)
                .GetField("_requestRetirement", System.Reflection.BindingFlags.NonPublic |
                    System.Reflection.BindingFlags.Instance)!.GetValue(candidate)!;
            using var lease = work.Enter(default)!;
            using var entered = new ManualResetEventSlim(); using var observed = new ManualResetEventSlim();
            var reentered = false;
            var observer = Task.Factory.StartNew(() =>
            {
                Check(entered.Wait(TimeSpan.FromSeconds(3)), "Cancellation callback was entered.");
                var shutdown = candidate.ShutdownFirstUseOnlineCandidateAsync();
                var retire = candidate.RetireFirstUseOnlineCandidateAsync();
                observed.Set(); return (shutdown, retire);
            }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
            using var callback = lease.Token.Register(() =>
            { entered.Set(); reentered = observed.Wait(TimeSpan.FromSeconds(3)); });
            Task<bool>? first = null;
            try
            {
                first = preserveSession ? candidate.ShutdownFirstUseOnlineCandidateAsync() : candidate.RetireFirstUseOnlineCandidateAsync();
                var observations = await Finish(observer);
                Check(reentered && !first.IsCompleted && !observations.shutdown.IsCompleted && !observations.retire.IsCompleted &&
                    ReferenceEquals(first, preserveSession ? observations.shutdown : observations.retire),
                    "Reentrant callers observe reserved tasks without a lock deadlock or false physical completion.");
                lease.Dispose();
                Check(await Finish(observations.shutdown) && await Finish(observations.retire) == !preserveSession,
                    "Cross-thread reentry cannot change the original exit intention.");
            }
            finally
            {
                entered.Set(); lease.Dispose();
                if (first is not null) await Finish(first);
                await Finish(observer);
            }
            f.Original.Local.RequireLocalStateUnchanged();
        }
    }
}
