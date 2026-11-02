using System.Security.Cryptography;
using System.Text;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static partial class FirstUseModeTests
{
    internal static async Task Run()
    {
        await Case("missing mode and local UI progress preserve existing startup without writes", ExistingStartup);
        await Case("actual account retirement commits local intent and cold startup bypasses account construction", LocalAndColdStart);
        await Case("cancellation after intent cannot restore credentials on a cold restart", Interrupted);
        await Case("failed logout retains pending mode until the original lifecycle finishes", FailedLogoutRetry);
        await Case("cancelled final session drain resumes our signed-out generation without restoring credentials", InterruptedAfterLogout);
        await Case("pending mode retry cannot adopt an unrelated account generation", InterruptedOwnerChanged);
        await Case("storage failure before intent does not sign out or retire the current account", FailedIntent);
        await Case("final receipt storage failure preserves pending intent after real sign-out", FailedReceipt);
        await Case("unchecked sessions remain blocked, not acknowledged or restored", Unchecked);
        await Case("stale requests and temporary transport errors cannot switch modes", StaleAndNetwork);
        await Case("corrupt and strict mode documents block automatic account startup and remain intact", InvalidDocuments);
        await Case("mode CAS, commit guards and busy writers preserve prior intent", StoreGuards);
        await Case("online return suppresses both credential authorities until explicit fresh login", FreshSignInPolicy);
        await Case("external intent changes and disposed runtimes invalidate old local sources", SourceInvalidation);
        await Case("a choice changed during account construction cannot authorize startup", StartupChoiceChanged);
        await Case("device source retirement waits for every actual owner without committing a mode", DeviceSourcesExit);
        await Case("device source cancellation can reenter retirement and fail without skipping other owners", DeviceSourcesReentry);
        await Case("local recovery rebuilds one drained source graph without changing saved choices", DeviceSourcesRecovery);
        await Case("retirement racing replacement timer construction drains the new graph", DeviceSourcesRecoveryRace);
        await Case("failed replacement timer retains its failure and cannot authorize another recovery", DeviceSourcesRecoveryTimerFailure);
        await Case("root closure during replacement cannot acknowledge local recovery", () => DeviceSourcesRecoveryInvalidated(true));
        await Case("mode change during replacement preserves the newer intent", () => DeviceSourcesRecoveryInvalidated(false));
        await Case("replacement timer drives only the new local reader through the retained source", DeviceSourcesRecoverySampling);
        await RunRootOffline();
    }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use mode: " + name); }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string ModePath(string root) => Path.Combine(root, "first-use-mode-v1", "state.bin");
    private static BridgeEnvelope Request(LocalAccountStopTests.Fixture f, string name = "profile.getSelf") =>
        BridgeEnvelope.Request(name, Op(), f.Host.Generation, new { schemaVersion = 1 }, f.Host.CurrentContext);
    private static void Require(bool value, string label) { if (!value) throw new InvalidOperationException(label); }
    private static void Expect(string code, Action run)
    {
        try { run(); } catch (LocalFirstUseException error) when (error.Code == code) { return; }
        throw new InvalidOperationException("Expected " + code);
    }
    private static async Task Cancelled(Task work)
    {
        try { await work.WaitAsync(TimeSpan.FromSeconds(3)); } catch (OperationCanceledException) { return; }
        throw new InvalidOperationException("Expected cancellation");
    }
    private static Task<AccountBridgeRuntime> NoOnline(CancellationToken _) =>
        throw new InvalidOperationException("Offline bootstrap cannot invoke account configuration, OAuth, vault, or network construction.");

    private static async Task DeviceSourcesExit()
    {
        // Each owner must independently be able to keep the joint exit pending.
        for (var last = 0; last < 4; last++) await DeviceSourcesExit(last);
    }

    private static async Task DeviceSourcesReentry() => await DeviceSourcesExit(0, reenter: true);

    private static async Task DeviceSourcesRecovery()
    {
        var clock = new RecoveryClock();
        using var f = new LocalAccountStopTests.Fixture(sampling: true, backgroundTime: clock);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var generation = mode.LocalMode().Generation;
        var modeBytes = File.ReadAllBytes(ModePath(f.Root));
        var bridge = f.Runtime.FirstUseStatisticsDispatcher!;
        var overlay = f.Runtime.FirstUseOverlaySource!;
        var oldGame = f.Runtime.FirstUseGame!;
        var oldStats = f.Runtime.FirstUseStatistics!;
        object Field(object owner, string name) => owner.GetType().GetField(name,
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(owner)!;
        var oldSampler = Field(f.Runtime, "_gameLog");
        var work = (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)Field(oldSampler, "_samplingWork");
        using var held = work.Enter(default)!;
        var exited = f.Runtime.RetireFirstUseLocalSourcesAsync();
        Require(!exited.IsCompleted && !await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation),
            "retirement must actually finish before a replacement can be constructed");
        held.Dispose(); await exited.WaitAsync(TimeSpan.FromSeconds(5));
        Require(clock.Live == 0, "all former timers exited before reconstruction");
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(Task.CompletedTask, generation) &&
            !await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation + 1),
            "another completed task or stale mode cannot authorize reconstruction");
        Require(await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation) && clock.Live == 1,
            "actual current exit restores exactly one local sampler");
        var replacement = Field(f.Runtime, "_gameLog");
        Require(!ReferenceEquals(oldSampler, replacement) && !ReferenceEquals(oldGame, f.Runtime.FirstUseGame) &&
            !ReferenceEquals(oldStats, f.Runtime.FirstUseStatistics) &&
            ReferenceEquals(bridge, f.Runtime.FirstUseStatisticsDispatcher) && ReferenceEquals(overlay, f.Runtime.FirstUseOverlaySource),
            "new consumers retain the same Native routes, not retired readers");
        Require(((StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)Field(replacement, "_accountWork")).IsClosed &&
            !((StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)Field(replacement, "_samplingWork")).IsClosed && work.IsClosed,
            "only the replacement sampler admits work, its account slot stays closed");
        var read = await bridge.DispatchAsync(BridgeEnvelope.Request(LocalStatisticsChoiceBridgeDispatcher.ReadRequest,
            Op(), f.Host.Generation, new { schemaVersion = 1 }));
        Require(read.Response.Status == "ok" && read.Response.Payload.GetProperty("consent").GetString() == "unknown" &&
            !read.Response.Payload.GetProperty("recording").GetBoolean() && overlay.Capture() is not null,
            "actual retained routes work without granting recording or account fallback");
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation) &&
            ReferenceEquals(replacement, Field(f.Runtime, "_gameLog")), "old receipt cannot replace a live sampler twice");
        Require(modeBytes.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))), "recovery does not commit a new mode");
        f.RequireLocalStateUnchanged();
        var secondExit = f.Runtime.RetireFirstUseLocalSourcesAsync();
        Require(!ReferenceEquals(exited, secondExit), "replacement has its own retirement receipt");
        await secondExit.WaitAsync(TimeSpan.FromSeconds(5));
        Require(clock.Live == 0, "replacement timer also physically exits");
        f.Runtime.Dispose();
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(secondExit, generation), "closed root cannot reconstruct readers");
    }

    private static async Task DeviceSourcesRecoveryRace()
    {
        var clock = new RecoveryClock();
        using var f = new LocalAccountStopTests.Fixture(sampling: true, backgroundTime: clock);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var bytes = File.ReadAllBytes(ModePath(f.Root));
        var exited = f.Runtime.RetireFirstUseLocalSourcesAsync(); await exited;
        Task? racedExit = null;
        clock.Creating = () => racedExit = f.Runtime.RetireFirstUseLocalSourcesAsync();
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, mode.LocalMode().Generation),
            "retirement requested during timer construction prevents successful recovery acknowledgement");
        clock.Creating = null;
        Require(racedExit is not null && !ReferenceEquals(racedExit, exited), "new graph owns the raced exit");
        await racedExit!.WaitAsync(TimeSpan.FromSeconds(5));
        Require(clock.Live == 0 && bytes.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))),
            "new timer drained and no mode intent changed");
        f.RequireLocalStateUnchanged();
        Require(await f.Runtime.RestoreFirstUseLocalSourcesAsync(racedExit, mode.LocalMode().Generation) && clock.Live == 1,
            "only a later explicit recovery with the current exit can restart one sampler");
        await f.Runtime.RetireFirstUseLocalSourcesAsync();
        Require(clock.Live == 0, "final synthetic timer cleanup");
    }

    private static async Task DeviceSourcesRecoveryTimerFailure()
    {
        var clock = new RecoveryClock();
        using var f = new LocalAccountStopTests.Fixture(sampling: true, backgroundTime: clock);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var generation = mode.LocalMode().Generation;
        var bytes = File.ReadAllBytes(ModePath(f.Root));
        var exited = f.Runtime.RetireFirstUseLocalSourcesAsync(); await exited;
        var failure = new InvalidOperationException("Synthetic timer construction failure");
        clock.Creating = () => throw failure;
        async Task Faulted(Task work)
        {
            try { await work.WaitAsync(TimeSpan.FromSeconds(5)); }
            catch (InvalidOperationException error) when (ReferenceEquals(error, failure)) { return; }
            throw new InvalidOperationException("Original timer failure must remain observable");
        }
        await Faulted(f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation));
        clock.Creating = null;
        var failedExit = f.Runtime.RetireFirstUseLocalSourcesAsync();
        await Faulted(failedExit);
        Require(!ReferenceEquals(exited, failedExit) && failedExit.IsFaulted && clock.Live == 0,
            "failed graph owns a faulted receipt and leaves no physical timer");
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation),
            "previous graph receipt cannot retry the failed replacement");
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(failedExit, generation),
            "a faulted drain must never authorize reconstruction");
        Require(clock.Live == 0 && bytes.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))),
            "retry does not commit mode or leave sampling behind");
        f.RequireLocalStateUnchanged();
    }

    private static async Task DeviceSourcesRecoveryInvalidated(bool closeRoot)
    {
        var clock = new RecoveryClock();
        using var f = new LocalAccountStopTests.Fixture(sampling: true, backgroundTime: clock);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var generation = mode.LocalMode().Generation;
        var expected = File.ReadAllBytes(ModePath(f.Root));
        var exited = f.Runtime.RetireFirstUseLocalSourcesAsync(); await exited;
        clock.Creating = () =>
        {
            if (closeRoot) f.Runtime.Dispose();
            else
            {
                new FirstUseModeStore(f.Root).Save(2, Op(), "onlinePending", () => true);
                expected = File.ReadAllBytes(ModePath(f.Root));
            }
        };
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, generation),
            "invalidated mode or root cannot acknowledge recovery");
        clock.Creating = null;
        var cleanup = f.Runtime.RetireFirstUseLocalSourcesAsync();
        await cleanup.WaitAsync(TimeSpan.FromSeconds(5));
        Require(clock.Live == 0 && expected.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))),
            "late timer is disposed without overwriting the current durable intent");
        Require(!await f.Runtime.RestoreFirstUseLocalSourcesAsync(cleanup, generation),
            "invalidated generation cannot restart sampling with a newer receipt");
        f.RequireLocalStateUnchanged();
    }

    private static async Task DeviceSourcesRecoverySampling()
    {
        var clock = new RecoveryClock();
        using var f = new LocalAccountStopTests.Fixture(sampling: true, backgroundTime: clock);
        var probes = 0;
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime),
            localGameProbe: () => { probes++; return new("notRunning"); });
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var store = new LocalFirstUseStore(f.Root);
        var selected = store.Read();
        store.SetListening(selected.Revision, Op(), selected.SelectedSourceKey!, true, () => true);
        var identityBytes = File.ReadAllBytes(Path.Combine(f.Root, "local-first-use-v1", "state.bin"));
        var modeBytes = File.ReadAllBytes(ModePath(f.Root));
        var original = f.Runtime.FirstUseGame!;
        var retainedOverlay = f.Runtime.FirstUseOverlaySource!;
        clock.FireAll();
        Require(probes == 1 && original.Current is { State: "notRunning", ObservedAt: not null },
            "original physical timer reads the chosen local source");
        var retiredFrame = retainedOverlay.Capture()!;
        var exited = f.Runtime.RetireFirstUseLocalSourcesAsync(); await exited;
        clock.FireAll();
        Require(probes == 1 && original.Current.State == "unavailable", "queued old timer callbacks cannot probe again");
        Require(await f.Runtime.RestoreFirstUseLocalSourcesAsync(exited, mode.LocalMode().Generation),
            "replacement uses the original local process dependency");
        var replacement = f.Runtime.FirstUseGame!;
        Require(replacement.Current.State == "waiting", "replacement observation starts without old reader state");
        clock.FireAll();
        Require(probes == 2 && replacement.Current is { State: "notRunning", ObservedAt: not null } &&
            original.Current.State == "unavailable" && retiredFrame.Read().State == "unavailable" &&
            retainedOverlay.Capture()!.Read().State != "unavailable",
            "only new timer reads and retained Native source resolves the new reader");
        Require(identityBytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Root, "local-first-use-v1", "state.bin"))) &&
            modeBytes.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))),
            "sampling does not alter saved identity, listening choice or mode");
        await f.Runtime.RetireFirstUseLocalSourcesAsync();
        clock.FireAll();
        Require(probes == 2 && clock.Live == 0, "no new local probes after final physical retirement");
    }

    private sealed class RecoveryClock : TimeProvider
    {
        private readonly List<RecoveryTimer> _timers = [];
        internal int Live => _timers.Count(timer => !timer.Disposed);
        internal Action? Creating;
        // Deliver even queued callbacks from disposed timers; the real owning
        // timer admission, rather than the test clock, must reject stale work.
        internal void FireAll() { foreach (var timer in _timers.ToArray()) timer.Fire(); }
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        {
            Creating?.Invoke();
            var timer = new RecoveryTimer(callback, state); _timers.Add(timer); return timer;
        }
        private sealed class RecoveryTimer(TimerCallback callback, object? state) : ITimer
        {
            internal bool Disposed;
            internal void Fire() => callback(state);
            public bool Change(TimeSpan dueTime, TimeSpan period) => !Disposed;
            public void Dispose() => Disposed = true;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }

    private static async Task DeviceSourcesExit(int last, bool reenter = false)
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var before = File.ReadAllBytes(ModePath(f.Root));
        object Field(object owner, string name) => owner.GetType().GetField(name,
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(owner)!;
        var owners = new[] {
            (Owner: Field(f.Runtime, "_gameLog"), Work: "_samplingWork"),
            (Owner: (object)f.Runtime.FirstUseGame!, Work: "_work"),
            (Owner: (object)f.Runtime.FirstUseStatistics!, Work: "_work"),
            (Owner: Field(f.Runtime, "_firstUseOverlay"), Work: "_work"),
        };
        var admissions = owners.Select(value => (StarBridge.HostRuntime.Lifecycle.AsyncWorkRetirement)
            Field(value.Owner, value.Work)).ToArray();
        var leases = admissions.Select(value => value.Enter(default)!).ToArray();
        Task? observedExit = null;
        Task<Task>? observer = null;
        using var callbackEntered = new ManualResetEventSlim();
        using var observerReturned = new ManualResetEventSlim();
        var callbackFinished = false;
        if (reenter)
        {
            // A separate ready thread must be able to observe the reserved exit
            // while a real source's synchronous cancellation callback is running.
            observer = Task.Factory.StartNew(() =>
            {
                if (!callbackEntered.Wait(TimeSpan.FromSeconds(3)))
                    throw new InvalidOperationException("Source cancellation callback did not run.");
                var pending = f.Runtime.RetireFirstUseLocalSourcesAsync();
                observerReturned.Set();
                return pending;
            }, CancellationToken.None, TaskCreationOptions.LongRunning, TaskScheduler.Default);
        }
        using var callback = reenter ? leases[3].Token.Register(() =>
        {
            callbackEntered.Set();
            callbackFinished = observerReturned.Wait(TimeSpan.FromSeconds(3));
            // A failing consumer callback must not prevent subsequent sources
            // from closing or falsely acknowledge outstanding leases.
            throw new InvalidOperationException("Synthetic cancellation callback failure.");
        }) : default;
        Task? stop = null;
        try
        {
            stop = f.Runtime.RetireFirstUseLocalSourcesAsync();
            if (observer is not null)
            {
                observedExit = await observer.WaitAsync(TimeSpan.FromSeconds(3));
                Require(callbackFinished && ReferenceEquals(stop, observedExit),
                    "Cancellation can reenter from another thread and receives the same reserved exit.");
            }
            Require(ReferenceEquals(stop, f.Runtime.RetireFirstUseLocalSourcesAsync()) &&
                !stop.IsCompleted && admissions.All(value => value.IsClosed),
                "One reserved exit closes every actual source admission before waiting.");
            using var cancellation = new CancellationTokenSource();
            cancellation.Cancel(); await Cancelled(stop.WaitAsync(cancellation.Token));
            foreach (var index in Enumerable.Range(0, leases.Length).Where(index => index != last).Append(last))
            {
                Require(!stop.IsCompleted, "An outstanding original source lease must prevent completion.");
                leases[index].Dispose();
            }
            await stop.WaitAsync(TimeSpan.FromSeconds(3));
            Require(f.Runtime.FirstUseGame!.Current.State == "unavailable" &&
                f.Runtime.FirstUseStatistics!.Current.State == "inactive" &&
                f.Runtime.FirstUseOverlaySource!.Capture()!.Read().State == "unavailable" &&
                admissions.All(value => value.Enter(default) is null),
                "No retired reader can publish or admit work after the original exit.");
            Require(before.SequenceEqual(File.ReadAllBytes(ModePath(f.Root))) && mode.LocalMode().Active,
                "Source exit alone neither commits online nor closes the independent mode owner.");
            f.RequireLocalStateUnchanged();
        }
        finally
        {
            callbackEntered.Set();
            foreach (var lease in leases) lease.Dispose();
            if (stop is not null) await stop.WaitAsync(TimeSpan.FromSeconds(3));
            if (observer is not null) await observer.WaitAsync(TimeSpan.FromSeconds(3));
        }
    }

    private static async Task ExistingStartup()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        var profiles = new LocalFirstUseStore(f.Root);
        var before = profiles.Read();
        profiles.SaveProgress(before.Revision, Op(), new("mode", "local", null, null, null), () => true);
        var calls = 0;
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => { calls++; return Task.FromResult(f.Runtime); });
        Require(calls == 1 && f.Runtime.FirstUseMode!.Current.ActiveMode == "online" &&
            f.Runtime.FirstUseOverlaySource!.Capture() is null && !File.Exists(ModePath(f.Root)),
            "page progress is not device mode and creates no new choice or automatic onboarding");
    }

    private static async Task LocalAndColdStart()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        var switched = await mode.ApplyLocalAsync(0, Op(), f.Host.Generation).WaitAsync(TimeSpan.FromSeconds(3));
        Require(switched is { State: "local", ActiveMode: "local", PublicationSuspended: true, Revision: 2 } &&
            mode.LocalMode().Active && f.Vault.Deleted && f.Host.CurrentContext is null &&
            new FirstUseModeStore(f.Root).Read().Phase == "local", "only actual logout and drain commit local readiness");
        Expect("firstUse.invalid_request", () => mode.ApplyLocalAsync(2, "not-an-operation", f.Host.Generation).GetAwaiter().GetResult());
        Expect("firstUse.revision_conflict", () => mode.ApplyLocalAsync(2,
            new FirstUseModeStore(f.Root).Read().OperationId!, f.Host.Generation).GetAwaiter().GetResult());
        f.RequireLocalStateUnchanged();
        using var actualDefault = await AccountBridgeRuntime.CreateDefaultAsync();
        Require(actualDefault.FirstUseMode!.Current.State == "local" && actualDefault.FirstUseOverlaySource!.Capture() is not null,
            "public product factory uses the same startup policy before SCM configuration");
        var blocked = await f.Runtime.DispatchAsync(Request(f, "account.login"));
        Require(blocked.Response.Error?.Code == "account.local_mode", "old account admission cannot be reopened");
        var traffic = f.Transport.AllRequests; var loads = f.Vault.Loads;
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current is { State: "local", PublicationSuspended: true } &&
            cold.FirstUseGame is not null && cold.FirstUseStatistics is not null &&
            cold.FirstUseOverlaySource!.Capture() is not null &&
            f.Transport.AllRequests == traffic && f.Vault.Loads == loads, "cold local sources use no account owner or restored session");
        Require((await cold.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Op(), 0,
            new { schemaVersion = 1 }))).Response.Error?.Code == "account.local_mode", "cold startup cannot restore on read");
        f.RequireLocalStateUnchanged();
    }

    private static async Task Interrupted()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        f.Transport.HoldProfile = true;
        var reading = f.Runtime.DispatchAsync(Request(f)).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        using var cancellation = new CancellationTokenSource();
        var switching = f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation, cancellation.Token);
        Require(!switching.IsCompleted && new FirstUseModeStore(f.Root).Read().Phase == "localPending" &&
            !f.Runtime.FirstUseMode.LocalMode().Active && !f.Vault.Deleted, "intent precedes actual foreground exit and logout");
        cancellation.Cancel(); await Cancelled(switching);
        using (var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline))
        {
            Require(cold.FirstUseMode!.Current.State == "recoveryRequired" && !cold.FirstUseMode.LocalMode().Active &&
                cold.FirstUseOverlaySource!.Capture()!.Read().State == "unavailable", "pending cold mode is not a fabricated completion");
            Expect("firstUse.mode_receipt_required", () => cold.FirstUseMode.RequestOnline(1, Op()));
        }
        var rejected = await f.Runtime.DispatchAsync(Request(f, "account.getCurrent"));
        Require(rejected.Response.Error?.Code == "account.local_mode", "late implicit restore is denied after interrupted intent");
        f.Transport.ProfileRelease.TrySetResult();
        Require((await reading.WaitAsync(TimeSpan.FromSeconds(3))).Response.Status == BridgeResponseStatuses.Cancelled,
            "late profile result cannot regain authority");
        var retry = await f.Runtime.FirstUseMode.ApplyLocalAsync(1, Op(), f.Host.Generation);
        Require(retry.State == "local" && f.Vault.Deletions == 1, "explicit retry resumes retirement, not login");
        f.RequireLocalStateUnchanged();
    }

    private static async Task FailedIntent()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        Directory.CreateDirectory(Path.GetDirectoryName(ModePath(f.Root))!);
        using (var lease = new FileStream(ModePath(f.Root) + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            try { await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation); }
            catch (LocalFirstUseException error) when (error.Code == "firstUse.mode_write_failed") { }
            Require(!f.Vault.Deleted && f.Host.CurrentContext is not null &&
                f.Runtime.FirstUseMode!.LocalMode() is { Active: false, Generation: >= 0 } && !File.Exists(ModePath(f.Root)),
                "failed durable intent cannot start irreversible account retirement");
        }
        Require((await f.Runtime.DispatchAsync(Request(f, "account.getCurrent"))).Response.Error?.Code != "account.local_mode",
            "account admission survives intent storage failure");
        f.RequireLocalStateUnchanged();
    }

    private static async Task FailedLogoutRetry()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var mode = f.Runtime.FirstUseMode!;
        var store = new FirstUseModeStore(f.Root);
        f.Vault.FailDeletion = true;
        var failed = await mode.ApplyLocalAsync(0, Op(), f.Host.Generation);
        Require(failed is { State: "unavailable", Revision: 1, ActiveMode: null } && store.Read().Phase == "localPending" &&
            store.ReadRetirement() is null && !mode.LocalMode().Active && !f.Vault.Deleted &&
            f.Runtime.FirstUseOverlaySource!.Capture()!.Read().State == "unavailable",
            "failed actual logout grants neither a mode nor local sources or a durable complete receipt");
        using (var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline))
            Require((await cold.FirstUseMode!.RecoverLocalAsync(1, Op())).State == "recoveryRequired" &&
                !cold.FirstUseMode.LocalMode().Active, "a second runtime cannot acknowledge the partial original retirement");
        f.Vault.FailDeletion = false;
        var retry = await mode.ApplyLocalAsync(1, Op(), f.Host.Generation);
        Require(retry is { State: "local", Revision: 2, PublicationSuspended: true } && f.Vault.Deletions == 1 &&
            store.ReadRetirement() is { RequestsDrained: true, PublicationStopped: true, SessionLoopsStopped: true,
                BusinessBackgroundStopped: true } && mode.LocalMode().Active,
            "only the original real retirement and persisted complete receipt can activate the retry");
        f.RequireLocalStateUnchanged();
    }

    private static async Task InterruptedAfterLogout()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        using var cancellation = new CancellationTokenSource();
        f.Host.AccountChanged += _ => { if (f.Host.CurrentContext is null) cancellation.Cancel(); };
        await Cancelled(f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation, cancellation.Token));
        var store = new FirstUseModeStore(f.Root);
        Require(store.Read().Phase == "localPending" && store.ReadRetirement() is null &&
            f.Vault.Deletions == 1 && !f.Runtime.FirstUseMode.LocalMode().Active &&
            !f.Runtime.IsLocalAccountStopped(f.Host.Generation), "cancelled loop drain cannot produce a complete retirement receipt");
        var traffic = f.Transport.AllRequests; var loads = f.Vault.Loads;
        Require((await f.Runtime.FirstUseMode.ApplyLocalAsync(1, Op(), f.Host.Generation)).State == "local" &&
            f.Vault.Deletions == 1 && f.Transport.AllRequests == traffic && f.Vault.Loads == loads &&
            store.ReadRetirement()!.SignedOutGeneration == f.Host.Generation,
            "explicit original-owner retry drains loops and persists without a second login or logout");
        f.RequireLocalStateUnchanged();
    }

    private static async Task InterruptedOwnerChanged()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        f.Transport.HoldProfile = true;
        var reading = f.Runtime.DispatchAsync(Request(f)).AsTask();
        await f.Transport.ProfileStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var switching = f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        await f.Host.LogoutAsync(f.Host.CurrentContext!, default);
        f.Transport.ProfileRelease.TrySetResult();
        await reading.WaitAsync(TimeSpan.FromSeconds(3));
        Require((await switching).State == "contextChanged", "separate lifecycle changes invalidate the original transition");
        var store = new FirstUseModeStore(f.Root); var pending = store.Read();
        var traffic = f.Transport.AllRequests; var loads = f.Vault.Loads;
        Require((await f.Runtime.FirstUseMode.ApplyLocalAsync(1, Op(), f.Host.Generation)).State == "contextChanged" &&
            store.Read() == pending && store.ReadRetirement() is null && !f.Runtime.FirstUseMode.LocalMode().Active &&
            f.Transport.AllRequests == traffic && f.Vault.Loads == loads && f.Vault.Deletions == 1,
            "fresh UI generation does not let pending intent adopt an unrelated sign-out, fabricate withdrawal, or inspect credentials");
        f.RequireLocalStateUnchanged();
    }

    private static async Task Unchecked()
    {
        using var f = new LocalAccountStopTests.Fixture(initialSession: false);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        var result = await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        Require(result.State == "sessionUnchecked" && !f.Runtime.FirstUseMode.LocalMode().Active &&
            f.Vault.Loads == 0 && !f.Vault.Deleted && f.Transport.AllRequests == 0,
            "no unknown session or stored credential is inspected or declared removed");
        Require((await f.Runtime.DispatchAsync(Request(f, "account.getCurrent"))).Response.Error?.Code == "account.local_mode",
            "unchecked pending mode also seals automatic account restore");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current.State == "recoveryRequired", "an interrupted or unchecked handoff needs real recovery");
        f.RequireLocalStateUnchanged();
    }

    private static async Task FailedReceipt()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        FileStream? writer = null;
        f.Transport.RevokeReply = () => writer = new FileStream(ModePath(f.Root) + ".lock",
            FileMode.Open, FileAccess.ReadWrite, FileShare.None);
        try
        {
            try { await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation); }
            catch (LocalFirstUseException error) when (error.Code == "firstUse.mode_write_failed") { }
            Require(writer is not null && f.Vault.Deleted && f.Host.CurrentContext is null &&
                new FirstUseModeStore(f.Root).Read().Phase == "localPending" &&
                f.Runtime.FirstUseMode!.Current.State == "recoveryRequired" && !f.Runtime.FirstUseMode.LocalMode().Active,
                "failed final receipt cannot fabricate readiness or restore the logged-out account");
        }
        finally { writer?.Dispose(); f.Transport.RevokeReply = null; }
        Require((await f.Runtime.FirstUseMode!.ApplyLocalAsync(1, Op(), f.Host.Generation)).State == "local" && f.Vault.Deletions == 1,
            "explicit retry can persist the actual stop receipt without repeating sign-out");
        f.RequireLocalStateUnchanged();
    }

    private static async Task StaleAndNetwork()
    {
        using var f = new LocalAccountStopTests.Fixture();
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        try { await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation + 1); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.context_changed") { }
        Require(!File.Exists(ModePath(f.Root)) && !f.Vault.Deleted, "stale authority creates no intent or logout");
        await f.Runtime.DispatchAsync(Request(f)); // Real SCM host and synthetic 503 transport.
        Require(f.Runtime.FirstUseMode!.LocalMode() is { Active: false, Generation: >= 0 } &&
            !File.Exists(ModePath(f.Root)) && !f.Vault.Deleted, "temporary transport failure is not user mode selection");
        f.RequireLocalStateUnchanged();
    }

    private static async Task InvalidDocuments()
    {
        using var f = new LocalAccountStopTests.Fixture();
        Directory.CreateDirectory(Path.GetDirectoryName(ModePath(f.Root))!);
        var documents = new[] {
            "not-dpapi", "{}", "{\"schemaVersion\":1,\"schemaVersion\":1,\"value\":{}}",
            "{\"schemaVersion\":2,\"value\":{}}", "{\"schemaVersion\":1,\"value\":{\"revision\":1}}",
            "{\"schemaVersion\":1,\"value\":{\"revision\":1,\"operationId\":\"" + Op() +
                "\",\"savedAt\":\"2026-01-01T00:00:00Z\",\"phase\":\"local\",\"extra\":true}}"
        };
        foreach (var document in documents)
        {
            var bytes = document == "not-dpapi" ? Encoding.UTF8.GetBytes(document) : ProtectedData.Protect(
                Encoding.UTF8.GetBytes(document), Encoding.UTF8.GetBytes("StarBridge.first-use-mode.v1"), DataProtectionScope.CurrentUser);
            File.WriteAllBytes(ModePath(f.Root), bytes);
            Expect("firstUse.mode_read_failed", () => new FirstUseModeStore(f.Root).Read());
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
            Require(cold.FirstUseMode!.Current.State == "unavailable" && !cold.FirstUseMode.LocalMode().Active &&
                File.ReadAllBytes(ModePath(f.Root)).SequenceEqual(bytes), "invalid mode cannot be interpreted as a fresh install or cleared");
        }
        f.RequireLocalStateUnchanged();
    }

    private static Task StoreGuards()
    {
        using var f = new LocalAccountStopTests.Fixture();
        var store = new FirstUseModeStore(f.Root);
        Expect("firstUse.mode_receipt_required", () => store.Save(0, Op(), "local", () => true));
        Expect("firstUse.context_changed", () => store.Save(0, Op(), "localPending", () => false));
        var first = store.Save(0, Op(), "localPending", () => true);
        var bytes = File.ReadAllBytes(ModePath(f.Root));
        Expect("firstUse.revision_conflict", () => store.Save(0, Op(), "local", () => true));
        Expect("firstUse.revision_conflict", () => store.Save(1, first.OperationId!, "local", () => true));
        var checks = 0;
        Expect("firstUse.context_changed", () => store.Save(1, Op(), "local", () => ++checks < 2));
        using (var lease = new FileStream(ModePath(f.Root) + ".lock", FileMode.Open, FileAccess.ReadWrite, FileShare.None))
            Expect("firstUse.mode_write_failed", () => store.Save(1, Op(), "local", () => true));
        Require(File.ReadAllBytes(ModePath(f.Root)).SequenceEqual(bytes) && store.Read() == first &&
            Directory.GetFiles(Path.GetDirectoryName(ModePath(f.Root))!, "*.tmp").Length == 0,
            "failed commits and busy writers preserve bytes and remove only their own temporary output");
        f.RequireLocalStateUnchanged();
        return Task.CompletedTask;
    }

    private static async Task FreshSignInPolicy()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var online = f.Runtime.FirstUseMode.RequestOnline(2, Op());
        Require(online.State == "signInRequired" && new FirstUseModeStore(f.Root).Read().Phase == "onlinePending" &&
            f.Runtime.FirstUseMode.LocalMode().Active && online.ActiveMode == "local",
            "online return preserves established local sources without restoring credentials or completing online mode");
        using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
        Require(cold.FirstUseMode!.Current is { State: "signInRequired", ActiveMode: "local" },
            "verified local origin survives pending restart without restoring credentials");
        var oldLoads = f.Vault.Loads; var oldTraffic = f.Transport.AllRequests;
        var legacy = new CountingLegacyStore();
        using var host = new ScmAccountBridgeHost(f.OAuth, new ScmProfileCacheStore(Path.Combine(f.Root, "fresh-profile")),
            "synthetic-environment", () => null, legacyPasswordLogin: new LegacyPasswordLoginClient(f.Options.MeEndpoint,
                legacy, f.Transport), requireFreshSignIn: true);
        Require((await host.GetCurrentAsync(default)).State == "signedOut" &&
            (await host.GetCurrentAsync(default)).State == "signedOut" && host.CurrentContext is null &&
            f.Vault.Loads == oldLoads && legacy.Loads == 0 && f.Transport.AllRequests == oldTraffic &&
            !host.IsKnownSignedOutForLocalMode, "signed-out projection is not proof that ignored credentials were removed");
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Cancelled(host.LoginAsync(cancelled.Token));
        Require(host.CurrentContext is null && f.Vault.Loads == oldLoads, "cancelled explicit login cannot revive authorization");
        using var ordinary = new ScmAccountBridgeHost(f.OAuth, new ScmProfileCacheStore(Path.Combine(f.Root, "ordinary-profile")),
            "synthetic-environment", () => null);
        Require((await ordinary.GetCurrentAsync(default)).State == "signedOut" && f.Vault.Loads > oldLoads &&
            ordinary.IsKnownSignedOutForLocalMode, "ordinary startup retains the original actual credential restore check");
        f.RequireLocalStateUnchanged();
    }

    private static async Task SourceInvalidation()
    {
        using var f = new LocalAccountStopTests.Fixture(sampling: true);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, _ => Task.FromResult(f.Runtime));
        await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Host.Generation);
        var frame = f.Runtime.FirstUseOverlaySource!.Capture()!;
        var store = new FirstUseModeStore(f.Root);
        store.Save(2, Op(), "onlinePending", () => true);
        Require(f.Runtime.FirstUseMode.LocalMode().Generation < 0 && frame.Read().State == "unavailable",
            "external choice changes cannot reactivate a retained local frame");
        f.Runtime.Dispose();
        Require(f.Runtime.FirstUseMode.LocalMode().Generation < 0 &&
            f.Runtime.FirstUseOverlaySource.Capture()!.Read().State == "unavailable", "disposed mode cannot publish a local source");
        f.RequireLocalStateUnchanged();
    }

    private sealed class CountingLegacyStore : ILegacyMigrationCredentialStore
    {
        internal int Loads;
        public LegacyMigrationCredential? Load() { Loads++; return null; }
        public void Save(LegacyMigrationCredential _) => throw new InvalidOperationException("No legacy credential write");
        public void Delete() => throw new InvalidOperationException("No implicit legacy credential deletion");
    }

    private static async Task StartupChoiceChanged()
    {
        using var f = new LocalAccountStopTests.Fixture();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var booting = AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, async _ =>
        { entered.TrySetResult(); await release.Task; return f.Runtime; });
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        new FirstUseModeStore(f.Root).Save(0, Op(), "localPending", () => true);
        release.TrySetResult();
        try { await booting.WaitAsync(TimeSpan.FromSeconds(3)); }
        catch (LocalFirstUseException error) when (error.Code == "firstUse.context_changed")
        {
            Require(f.Vault.Loads == 0 && f.Transport.AllRequests == 0 && !f.Vault.Deleted,
                "late factory cannot restore credentials, declare local readiness or sign out an unchecked owner");
            using var cold = await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Root, NoOnline);
            Require(cold.FirstUseMode!.Current.State == "recoveryRequired", "new cold startup observes the durable pending choice");
            return;
        }
        throw new InvalidOperationException("Expected startup choice guard");
    }
}
