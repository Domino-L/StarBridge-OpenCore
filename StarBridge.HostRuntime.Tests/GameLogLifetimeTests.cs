using System.Security.Cryptography;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class GameLogLifetimeTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-log-lifetime");
    private static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Id() => Guid.NewGuid().ToString("N");
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Finish(Task task) => await task.WaitAsync(TimeSpan.FromSeconds(8));
    private static BridgeEnvelope Request(string name, string? path = null) =>
        BridgeEnvelope.Request(name, Id(), 1,
            path is null ? new { schemaVersion = 1 } : (object)new { schemaVersion = 1, path }, Owner);

    internal static async Task Run()
    {
        await Case("account IO must actually exit before whole-owner retirement", AccountExit);
        await Case("a direct account command keeps its original admission until actual exit", AccountCommandExit);
        await Case("local IO and direct local commands cannot outlive the old sampler", LocalExit);
        await Case("a direct local listening command cannot acknowledge success after retirement", LocalCommandExit);
        await Case("a cancelled waiter cannot acknowledge or reopen the original timer", TimerExit);
        await Case("timer disposal failure remains a failure after admitted IO exits", TimerFailure);
        await Case("account-to-local handoff still uses one timer until whole-owner retirement", AccountThenLocal);
        await Case("the real System timer waits for its cancellation-ignoring callback", SystemTimerExit);
        await Case("deferred sampler starts its original timer once and retirement waits for that timer", DeferredSampler);
    }
    private static async Task Case(string name, Func<Task> test)
    { await test(); Console.WriteLine("PASS first-use log lifetime: " + name); }

    private static async Task DeferredSampler()
    {
        using var fixture = new Fixture(); using var sampler = fixture.Create(startTimer: false);
        Check(fixture.Clock.Timers.Count == 0, "Deferred sampler allocates no physical timer.");
        Check(sampler.StartDeferredSampling() && sampler.StartDeferredSampling() && fixture.Clock.Timers.Count == 1,
            "Activation owns the same single sampler and is idempotent.");
        var original = fixture.Clock.Timers.Single(); original.HoldExit = true;
        var exit = sampler.RetireAsync();
        try
        {
            await Finish(original.DisposeStarted.Task);
            Check(!exit.IsCompleted && !sampler.StartDeferredSampling(), "Original timer must exit; sampler cannot reopen.");
            var probes = fixture.Probes; original.DeliverQueued();
            Check(fixture.Probes == probes, "No old callback can probe after retirement.");
        }
        finally { original.ReleaseExit.TrySetResult(); await Finish(exit); }
        Check(original.DisposeCalls == 1 && fixture.Clock.Timers.Count == 1, "Sole original timer is disposed once.");
    }

    private sealed class Held
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal void Wait()
        {
            Started.TrySetResult();
            if (!Release.Task.Wait(TimeSpan.FromSeconds(8))) throw new TimeoutException("Synthetic probe was not released.");
        }
    }
    private sealed class Clock : TimeProvider
    {
        internal readonly List<Timer> Timers = [];
        public override DateTimeOffset GetUtcNow() => Start;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { var timer = new Timer(callback, state); Timers.Add(timer); return timer; }
        internal sealed class Timer(TimerCallback callback, object? state) : ITimer
        {
            internal bool Disposed, HoldExit, FailExit;
            internal int DisposeCalls;
            internal readonly TaskCompletionSource DisposeStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
            internal readonly TaskCompletionSource ReleaseExit = new(TaskCreationOptions.RunContinuationsAsynchronously);
            internal void Fire() { if (!Disposed) callback(state); }
            // Model a callback already queued before stop, not a new timer tick.
            internal void DeliverQueued() => callback(state);
            public bool Change(TimeSpan dueTime, TimeSpan period) => !Disposed;
            public void Dispose() => Disposed = true;
            public async ValueTask DisposeAsync()
            {
                DisposeCalls++; Disposed = true; DisposeStarted.TrySetResult();
                if (HoldExit) await ReleaseExit.Task;
                if (FailExit) throw new IOException("Synthetic timer retirement failure.");
            }
        }
    }
    private sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-log-lifetime", Id());
        internal string Log => Path.Combine(Root, "StarCitizen", "LIVE", "Game.log");
        internal readonly Clock Clock = new();
        internal readonly Held Probe = new();
        internal bool Block;
        internal int Probes, AccountReads;
        internal GameProcessSession Process;
        internal Fixture()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            File.WriteAllText(Log, Line("nickname=\"Pilot-Example\" playerGEID=100"));
            Process = new("running", Log, Start, "synthetic-session");
        }
        private static string Line(string body) => $"<{Start:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> {body}\n";
        internal GameProcessSession ReadProcess()
        { Interlocked.Increment(ref Probes); if (Block) Probe.Wait(); return Process; }
        internal GameLogRuntime Create(TimeProvider? clock = null, bool startTimer = true) => new(new(Root),
            () => { Interlocked.Increment(ref AccountReads); return (Owner, 1); }, () => "Pilot-Example",
            ReadProcess, clock ?? Clock, startTimer: startTimer);
        internal void Select(GameLogRuntime sampler) =>
            Check(sampler.Dispatch(Request("gameLog.select", Log)).Response.Status == "ok", "Synthetic account selection succeeds.");
        internal byte[] AccountHash() => SHA256.HashData(File.ReadAllBytes(
            Directory.GetFiles(Path.Combine(Root, "game-log-local-v1"), "*.json").Single()));
        internal LocalGameLogRuntime CreateLocal(Func<(bool Active, long Generation)> mode)
        {
            Process = new("notRunning");
            var store = new LocalFirstUseStore(Path.Combine(Root, "device"), Clock);
            var evidence = new LocalLogEvidenceOwner(store, ReadProcess, Clock);
            var candidate = evidence.Select(store.Read().Revision, Log, "LIVE");
            evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
            Process = new("running", Log, Start, "synthetic-session");
            var local = new LocalGameLogRuntime(store, mode, ReadProcess, Clock);
            local.ApplyListening(store.Read().SelectedSourceKey!, true);
            Check(local.Current.State == "ready", "Confirmed local Handle and explicitly enabled log are ready.");
            return local;
        }
        public void Dispose()
        {
            Probe.Release.TrySetResult();
            foreach (var timer in Clock.Timers) timer.ReleaseExit.TrySetResult();
            var full = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-log-lifetime"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _))
                throw new InvalidOperationException("Unsafe synthetic fixture path.");
            for (var directory = new DirectoryInfo(full); directory is not null; directory = directory.Parent)
                if (directory.Exists && directory.Attributes.HasFlag(FileAttributes.ReparsePoint))
                    throw new InvalidOperationException("Unsafe synthetic fixture ancestor.");
            Directory.Delete(full, recursive: true);
        }
    }

    private static async Task AccountExit()
    {
        using var f = new Fixture(); using var sampler = f.Create(); f.Select(sampler);
        var original = f.AccountHash(); f.Block = true;
        var sample = Task.Run(f.Clock.Timers.Single().Fire);
        Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted && sampler.DetectedHandle is null &&
                sampler.Dispatch(Request("gameLog.read")).Response.Error?.Code == "gameLog.localMode",
                "Retirement closes account evidence and commands while original IO is still running.");
            Check(ReferenceEquals(stop, sampler.RetireAsync()), "Every waiter observes the same original completion.");
            f.Probe.Release.TrySetResult(); await Finish(sample); await Finish(stop);
            Check(original.SequenceEqual(f.AccountHash()) && sampler.CurrentSession == GameLogSessionSnapshot.Empty,
                "A late account probe cannot rewrite choices or retain live evidence.");
            var probes = f.Probes; var reads = f.AccountReads;
            f.Clock.Timers.Single().DeliverQueued(); sampler.Sample();
            Check(f.Probes == probes && f.AccountReads == reads && f.Clock.Timers.Single().DisposeCalls == 1,
                "Queued ticks and repeated retirement do not restart IO or dispose the original timer twice.");
            using var file = new GameLogSettingsStore(f.Root).Open(Owner);
            Check(file.Read().Enabled, "The actual retired account lease is released without clearing saved listening.");
        }
        finally { f.Probe.Release.TrySetResult(); await Finish(sample); if (stop is not null) await Finish(stop); }
    }

    private static async Task LocalExit()
    {
        using var f = new Fixture(); var mode = (Active: true, Generation: 3L);
        var local = f.CreateLocal(() => mode); using var sampler = f.Create(); sampler.AttachLocalSlot(local);
        f.Block = true; var sample = Task.Run(local.Sample); Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted && local.Current.State == "unavailable",
                "Direct local IO belongs to the attached owner, not merely to timer callbacks.");
            f.Probe.Release.TrySetResult(); await Finish(sample); await Finish(stop);
            mode = (true, 99); var probes = f.Probes; var reads = f.AccountReads;
            local.Sample(); sampler.Sample(); f.Clock.Timers.Single().DeliverQueued();
            Check(local.Current.Handle is null && local.Current.State == "unavailable" && f.Probes == probes && f.AccountReads == reads,
                "A later local mode or generation cannot resurrect either old slot.");
            try { local.ApplyListening(Id(), false); throw new InvalidOperationException("A retired local command was accepted."); }
            catch (LocalFirstUseException error) { Check(error.Code == "firstUse.context_changed", "Retired local command is fenced."); }
            try { sampler.AttachLocalSlot(local); throw new InvalidOperationException("A retired sampler accepted a slot."); }
            catch (InvalidOperationException error) when (error.Message == "The game log sampling slot is already owned.") { }
        }
        finally { f.Probe.Release.TrySetResult(); await Finish(sample); if (stop is not null) await Finish(stop); }
    }

    private static async Task AccountCommandExit()
    {
        using var f = new Fixture(); using var sampler = f.Create(); f.Select(sampler);
        f.Block = true;
        var command = Task.Run(() => sampler.Dispatch(Request("gameLog.retry"))); Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); var original = f.AccountHash(); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted, "An admitted direct command is not replaced by the timer drain.");
            f.Probe.Release.TrySetResult(); await Finish(command); await Finish(stop);
            Check(command.Result.Response.Status == BridgeResponseStatuses.Error && original.SequenceEqual(f.AccountHash()) &&
                sampler.DetectedHandle is null, "A late direct retry cannot return success or retain account evidence.");
        }
        finally { f.Probe.Release.TrySetResult(); await Finish(command); if (stop is not null) await Finish(stop); }
    }

    private static async Task LocalCommandExit()
    {
        using var f = new Fixture(); var local = f.CreateLocal(() => (true, 3));
        using var sampler = f.Create(); sampler.AttachLocalSlot(local);
        var source = local.Current.SourceKey!; f.Block = true;
        var command = Task.Run(() => local.ApplyListening(source, true)); Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted && local.Current.State == "unavailable",
                "Listening commands own their admitted local read through the result check.");
            f.Probe.Release.TrySetResult();
            try { await Finish(command); throw new InvalidOperationException("Retired local command returned success."); }
            catch (LocalFirstUseException error) { Check(error.Code == "firstUse.context_changed", "Late local success is revoked."); }
            await Finish(stop);
            var probes = f.Probes; local.Sample();
            Check(f.Probes == probes && local.Current.State == "unavailable", "Late local commands cannot reactivate sampling.");
        }
        finally
        {
            f.Probe.Release.TrySetResult();
            try { await Finish(command); } catch (LocalFirstUseException) { }
            if (stop is not null) await Finish(stop);
        }
    }

    private static async Task TimerExit()
    {
        using var f = new Fixture(); using var sampler = f.Create(); f.Select(sampler);
        var timer = f.Clock.Timers.Single(); timer.HoldExit = true;
        var stop = sampler.RetireAsync(); await Finish(timer.DisposeStarted.Task);
        try
        {
            using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
            try { await stop.WaitAsync(cancellation.Token); throw new InvalidOperationException("Cancelled wait was accepted."); }
            catch (OperationCanceledException) { }
            sampler.Dispose();
            Check(!stop.IsCompleted && !sampler.DisposeAsync().IsCompleted && timer.DisposeCalls == 1,
                "Neither cancelled waiting nor synchronous Dispose proves timer exit.");
            var reads = f.AccountReads; timer.DeliverQueued();
            Check(reads == f.AccountReads && f.Clock.Timers.Count == 1, "No new timer or account reader is installed by retirement.");
        }
        finally { timer.ReleaseExit.TrySetResult(); await Finish(stop); }
    }

    private static async Task TimerFailure()
    {
        using var f = new Fixture(); using var sampler = f.Create(); f.Select(sampler);
        var timer = f.Clock.Timers.Single(); timer.FailExit = true;
        f.Block = true; var sample = Task.Run(timer.Fire); Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted, "A timer error cannot release a still-admitted account read.");
            f.Probe.Release.TrySetResult(); await Finish(sample);
            try { await Finish(stop); throw new InvalidOperationException("Timer failure was acknowledged as a successful drain."); }
            catch (IOException) { }
            Check(stop.IsFaulted && ReferenceEquals(stop, sampler.RetireAsync()), "Original failure is retained, never repaired by a synthetic new receipt.");
            var probes = f.Probes; timer.DeliverQueued(); sampler.Sample();
            Check(probes == f.Probes, "Failed retirement is still permanently closed.");
            using var file = new GameLogSettingsStore(f.Root).Open(Owner);
            Check(file.Read().Enabled, "Actual read exit releases its store even when timer disposal failed.");
        }
        finally
        {
            f.Probe.Release.TrySetResult(); await Finish(sample);
            if (stop is not null) { try { await Finish(stop); } catch (IOException) { } }
        }
    }

    private static async Task AccountThenLocal()
    {
        using var f = new Fixture(); var mode = (Active: true, Generation: 2L);
        var local = f.CreateLocal(() => mode); using var sampler = f.Create(); sampler.AttachLocalSlot(local);
        await sampler.RetireAccountAsync(); f.Clock.Timers.Single().Fire();
        Check(local.Current.State == "ready" && !f.Clock.Timers.Single().Disposed && f.Clock.Timers.Count == 1,
            "Account-only retirement preserves the existing independent local reader and timer.");
        await Finish(sampler.RetireAsync());
        Check(local.Current.State == "unavailable" && f.Clock.Timers.Single().Disposed && f.Clock.Timers.Count == 1,
            "Only whole-owner retirement shuts down that same local slot and timer.");
    }

    private sealed class SystemClock : TimeProvider
    {
        internal ITimer? Timer;
        public override DateTimeOffset GetUtcNow() => Start;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period) =>
            Timer = TimeProvider.System.CreateTimer(callback, state, dueTime, period);
    }
    private static async Task SystemTimerExit()
    {
        using var f = new Fixture(); var clock = new SystemClock(); using var sampler = f.Create(clock); f.Select(sampler);
        f.Block = true; Task? stop = null;
        try
        {
            await Finish(f.Probe.Started.Task); stop = sampler.RetireAsync();
            Check(!stop.IsCompleted, "The real original timer callback still owns its synchronous probe.");
            f.Probe.Release.TrySetResult(); await Finish(stop);
            var probes = f.Probes; sampler.Sample();
            Check(f.Probes == probes && sampler.DetectedHandle is null, "Actual System timer retirement cannot resume old sampling.");
        }
        finally { f.Probe.Release.TrySetResult(); if (stop is not null) await Finish(stop); }
    }
}
