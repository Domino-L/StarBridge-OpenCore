using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    private static async Task<(AccountBridgeRuntime.PreparedFirstUseBusinessOwner Prepared,
        NativeAccountRuntimeBinding.PreparedNativeCallbacks Callbacks, Task Sources)> AdmissionPreparation(
        Fixture f, NativeAccountRuntimeBinding native)
    {
        var prepared = (await f.Prepare())!;
        var callbacks = (await native.PrepareHandoffAsync(prepared))!;
        var sources = f.Original.Local.Runtime.RetireFirstUseLocalSourcesAsync();
        await Finish(sources);
        return (prepared, callbacks, sources);
    }

    private static async Task BusinessAdmissionReceipts()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var prepared = (await f.Prepare())!;
        var callbacks = (await native.PrepareHandoffAsync(prepared))!;
        Check(prepared.StageBusinessAdmission(callbacks, Task.CompletedTask) is null,
            "A copied successful task is not the original local sampler exit receipt.");
        var sourceExit = f.Original.Local.Runtime.RetireFirstUseLocalSourcesAsync(); await Finish(sourceExit);
        var admission = prepared.StageBusinessAdmission(callbacks, sourceExit)!;
        Check(admission is { IsActive: false } && ReferenceEquals(admission, prepared.StageBusinessAdmission(callbacks, sourceExit)) &&
            f.Original.Host!.BusinessStartupDeferred && f.Original.Host.GameplayTimeContext is null,
            "Staging must be unique and dormant.");
        Check(admission.TryActivate() && admission.IsActive && !f.Original.Host!.BusinessStartupDeferred &&
            f.Original.Host.GameplayTimeContext == f.Original.Host.CurrentContext,
            "The consumed live admission enables the same SCM business identity.");
        Check(f.Original.Candidate!.FirstUseAuthenticationSealed &&
            (await f.Original.Login()).Response.Status != BridgeResponseStatuses.Ok && f.Original.Clock.Timers == 0,
            "SCM admission must never reopen the sealed auth dispatcher or start Host timers.");
        Check(native.Read(owner => owner.Generation, -1L) == -1L && f.Original.Store.Read().Phase == "onlinePending",
            "SCM admission alone neither replaces the drained Native slot nor commits online mode.");
        var exit = admission.RetireAsync(); await Finish(exit);
        Check(ReferenceEquals(exit, admission.RetireAsync()) && admission.HasExited && !admission.TryActivate() &&
            admission.Enter(default) is null && f.Original.Host!.GameplayTimeContext is null,
            "The original installed admission exits once and cannot be reopened.");
        Check((await f.Original.Cancel()).State == "local", "Retired staging must still support actual candidate cancellation.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task BusinessAdmissionLifetime()
    {
        using var f = new Fixture();
        var time = new ModeClock(); await f.Start(modeTime: time);
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Activate from real current original receipts.");
        var refreshed = await f.Original.Host!.ReadFirstUseIdentityAsync(default);
        Check(refreshed.State == "observed" && admission.IsActive,
            "A real same-subject OAuth identity refresh retains the consumed business lifetime.");
        time.Now = time.Now.AddMinutes(10);
        Check(!prepared.IsCurrent && admission.IsActive && f.Original.Host!.GameplayTimeContext is not null,
            "Pending-review freshness must not govern an already consumed installed account lifetime.");
        using (var work = admission.Enter(default)) Check(work is { IsCurrent: true }, "Live installation admits independent work.");
        await f.Original.Host!.LogoutAsync(f.Original.Host.CurrentContext!, default);
        Check(!admission.IsActive && admission.Enter(default) is null && f.Original.Host.BusinessStartupDeferred,
            "A session generation change cannot relabel the old installation.");
        await Finish(admission.RetireAsync());
    }

    private static async Task BusinessAdmissionExit()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual admission activation required.");
        using var work = admission.Enter(default)!;
        using var observer = new CancellationTokenSource();
        var cancel = f.Original.Cancel(observer.Token);
        Check(!cancel.IsCompleted && work.Token.IsCancellationRequested && !admission.IsActive &&
            f.Original.Vault.LoadActiveAccountKey() is not null && f.Original.Store.Read().Phase == "onlinePending",
            "Requested cancellation is not business exit or credential removal.");
        observer.Cancel();
        try { await cancel; throw new InvalidOperationException("Observer cancellation was ignored."); }
        catch (OperationCanceledException) { }
        var retry = f.Original.Cancel();
        Check(!retry.IsCompleted && f.Original.Vault.LoadActiveAccountKey() is not null, "Retry must await the same original admission exit.");
        work.Dispose();
        Check((await Finish(retry)).State == "local" && admission.HasExited && f.Original.Vault.LoadActiveAccountKey() is null,
            "Only actual business lease exit permits candidate credential clear and local return.");
        f.Original.Local.RequireLocalStateUnchanged();
    }

    private static async Task BusinessAdmissionReadExit()
    {
        using var f = new Fixture();
        var clock = new AdmissionOwnershipClock(); f.Original.DataOwnerTime = clock; await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual admission activation required.");
        f.Coordinator.Hold = true;
        clock.Timestamp += TimeSpan.FromMinutes(2).Ticks;
        var read = f.Original.Host!.GetCurrentAsync(default);
        Check(!read.IsCompleted, "Original installed ownership read must be held.");
        var exit = admission.RetireAsync();
        Check(!exit.IsCompleted && f.Coordinator.Token.IsCancellationRequested && f.Original.Vault.LoadActiveAccountKey() is not null,
            "Installed get-current ownership IO must retain physical work even when transport ignores cancellation.");
        f.Coordinator.Release.TrySetResult();
        try { await Finish(read); throw new InvalidOperationException("Retired ownership reply was accepted."); }
        catch (OperationCanceledException) { }
        await Finish(exit);
        Check(admission.HasExited && (await f.Original.Cancel()).State == "local", "Actual IO exit permits cleanup.");
    }
    private sealed class AdmissionOwnershipClock : TimeProvider
    {
        internal long Timestamp;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Timestamp;
    }
    private static async Task BusinessAdmissionTokenRefresh()
    {
        using var f = new Fixture();
        var time = new FirstUseOnlineReturnTests.FrozenSessionTime(); f.Original.SessionTime = time;
        f.Original.Transport.TokenLifetimeSeconds = 2;
        await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "A still-current actual token permits activation.");
        var host = f.Original.Host!; var generation = host.Generation; var context = host.CurrentContext!;
        var tokenReads = f.Original.Transport.TokenRequests;
        // Actual OAuth/session clock, not merely the temporary review clock.
        time.Now += TimeSpan.FromMilliseconds(2200);
        Check(admission.IsActive && !host.BusinessStartupDeferred && host.GameplayTimeContext == context,
            "Access-token expiry must not cut off the installed owner's refresh path.");
        f.Original.Transport.TokenLifetimeSeconds = 3600; f.Original.Transport.AllowProfileRead = true;
        using (var work = admission.Enter(default))
        {
            Check(work is not null, "Valid original refresh credentials still admit business work.");
            await host.GetProfileAsync(context, work!.Token);
        }
        Check(f.Original.Transport.TokenRequests == tokenReads + 1 && admission.IsActive &&
            host.Generation == generation && host.GameplayTimeContext == context && f.Original.Clock.Timers == 0,
            "Actual resource refresh preserves the same installed account and original generation.");
        await Finish(admission.RetireAsync());
        Check((await f.Original.Cancel()).State == "local", "Refreshed original credentials still retire safely.");
    }
    private static async Task BusinessAdmissionInvalidStage()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        using var other = new Fixture(); await other.Start();
        var foreign = (await other.Prepare())!;
        var foreignExit = other.Original.Local.Runtime.RetireFirstUseLocalSourcesAsync(); await Finish(foreignExit);
        Check(foreign.StageBusinessAdmission(callbacks, foreignExit) is null &&
            prepared.StageBusinessAdmission(callbacks, foreignExit) is null,
            "Another owner or another real source exit cannot reuse this Native preparation.");
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check((await f.Original.Cancel()).State == "local" && admission.HasExited && !admission.TryActivate() &&
            f.Original.Clock.Timers == 0 && f.Original.Vault.LoadActiveAccountKey() is null,
            "A staged installation is retired without activation on actual mode cancellation.");
        Check((await other.Original.Cancel()).State == "local", "Foreign candidate retains independent cleanup.");
    }
    private static async Task BusinessAdmissionChangedVault()
    {
        using var f = new Fixture(); await f.Start();
        using var native = new NativeAccountRuntimeBinding(f.Original.Local.Runtime);
        var (prepared, callbacks, sources) = await AdmissionPreparation(f, native);
        var admission = prepared.StageBusinessAdmission(callbacks, sources)!;
        Check(admission.TryActivate(), "Actual business admission activation required.");
        f.Original.Vault.SaveRefreshToken("synthetic-replacement:other", "synthetic-new-refresh");
        var newer = File.ReadAllBytes(f.Original.VaultPath);
        Check(!admission.IsActive && admission.Enter(default) is null && f.Original.Host!.GameplayTimeContext is null,
            "A replaced credential version cannot retain original installed business admission.");
        await Finish(admission.RetireAsync());
        Check((await f.Original.Cancel()).State == "recoveryRequired" &&
            File.ReadAllBytes(f.Original.VaultPath).SequenceEqual(newer),
            "Recovery must preserve the exact newer credential rather than declaring local success.");
    }
}
