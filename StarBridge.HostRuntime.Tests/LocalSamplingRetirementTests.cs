using System.Security.Cryptography;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static class LocalSamplingRetirementTests
{
    private static readonly BridgeAccountContext Owner = new("test", "scm", "synthetic-sampling-stop");
    private static readonly DateTimeOffset Start = new(2026, 1, 1, 12, 0, 0, TimeSpan.Zero);
    private static string Id() => Guid.NewGuid().ToString("N");
    private static BridgeEnvelope Request(string name) => BridgeEnvelope.Request(name, Id(), 1, new { schemaVersion = 1 }, Owner);
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Finish(Task task) => await task.WaitAsync(TimeSpan.FromSeconds(5));

    internal static async Task Run()
    {
        await Case("blocked account sample drains without a late save", Sampling);
        await Case("publication read cannot become a new write after retirement", () => Publication(false));
        await Case("already submitted publication waits for actual exit without replay", () => Publication(true));
        await Case("reset observer cannot apply a late account-wide reset", ResetObserver);
        await Case("submitted reset retains its uncertain journal and original total", ResetWrite);
        await Case("import recovery cannot finish a journal after retirement", ImportRecovery);
        await Case("submitted history import retains its journal without a follow-up read", ImportWrite);
        await Case("history eligibility cannot consume the opportunity after retirement", HistoryEligibility);
        await Case("reset preview retains its lease through actual response", ResetPreview);
        await Case("one log timer hands over only after the account sample exits", GameLogHandoff);
    }
    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use sampling retirement: " + name); }

    private sealed class Temp : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-sampling", Id());
        internal Temp() => Directory.CreateDirectory(Root);
        internal string Json(string directory = "gameplay-time-local-v1") => Directory.GetFiles(Path.Combine(Root, directory), "*.json").Single();
        internal byte[] Hash(string directory = "gameplay-time-local-v1") => SHA256.HashData(File.ReadAllBytes(Json(directory)));
        public void Dispose()
        {
            var full = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-sampling"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup");
            Directory.Delete(full, recursive: true);
        }
    }
    private sealed class Held : IDisposable
    {
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal CancellationToken Token;
        internal async Task Wait(CancellationToken token)
        { Token = token; Started.TrySetResult(); await Release.Task; } // Deliberately ignores cancellation.
        public void Dispose() => Release.TrySetResult();
    }
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = Start;
        internal readonly List<Timer> Timers = [];
        public override DateTimeOffset GetUtcNow() => Now;
        public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
        { var timer = new Timer(callback, state); Timers.Add(timer); return timer; }
        internal sealed class Timer(TimerCallback callback, object? state) : ITimer
        {
            internal bool Disposed;
            internal void Fire() { if (!Disposed) callback(state); }
            public bool Change(TimeSpan dueTime, TimeSpan period) => !Disposed;
            public void Dispose() => Disposed = true;
            public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
        }
    }
    private sealed class Remote(Held held, string stage) : IGameplayHistoryRemote
    {
        internal int Reads, Publications, Resets;
        internal GameplayTimeResetState State = new(1, 0, null, null, 0, 0, null, IsPublic: true);
        public async Task<GameplayTimeResetState> ReadAsync(BridgeAccountContext owner, CancellationToken token)
        { Reads++; if (stage == "read") await held.Wait(token); return State; }
        public async Task<bool> PublishGameplayStatisticsAsync(BridgeAccountContext owner,
            PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token)
        { Publications++; if (stage == "publish") await held.Wait(token); return true; }
        public async Task<GameplayTimeResetResult> ResetAsync(BridgeAccountContext owner, GameplayTimeResetRequest request, CancellationToken token)
        {
            Resets++; if (stage == "reset") await held.Wait(token);
            return new("completed", new(1, request.ExpectedRevision + 1, request.OperationId, request.ExpectedRevision, 0, 0, null));
        }
    }
    private static void Seed(Temp temp, bool pendingImport = false, bool historyCutoff = false)
    {
        using var file = new GameplayTimeStore(temp.Root).Open(Owner);
        var saved = file.Read();
        saved = file.Save(saved, saved with { Consent = GameplayRecordingConsent.Allowed, Seconds = 37, ShowOnProfile = false,
            FirstRecordedAt = historyCutoff ? Start : null }, () => true);
        if (pendingImport)
            file.BeginImport(saved, new(new(false, 97, 0, 0, 60, HistoryImportedAt: Start,
                ExpectedGameplayRevision: 0, HistoryImportOperationId: Id(), ExpiresAt: Start.AddMinutes(2))), () => true);
    }
    private static GameplayTimeRuntime Runtime(Temp temp, Clock clock, Remote? remote = null,
        Func<LocalGamePresenceSnapshot>? presence = null,
        Func<BridgeAccountContext, CancellationToken, Task<GameplayHistoryEligibility>>? eligibility = null) =>
        new(new(temp.Root), () => (Owner, 1), presence ?? (() => new(1, "notRunning")), clock,
            verifiedHandle: () => "Pilot-Example", historyEligibility: eligibility, resetRemote: remote, historyRemote: remote,
            boundLiveLog: () => Path.Combine(temp.Root, "LIVE", "Game.log"));

    private static async Task Sampling()
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        var block = false; var probes = 0;
        using var module = Runtime(temp, clock, presence: () => {
            probes++; if (block) { held.Started.TrySetResult(); held.Release.Task.Wait(TimeSpan.FromSeconds(5)); }
            return new(1, "running");
        });
        module.Sample(); var original = temp.Hash(); block = true; clock.Now = Start.AddSeconds(5);
        var sampling = Task.Run(module.Sample);
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && clock.Timers.All(t => t.Disposed), "admission is closed before waiting for the blocked probe");
            Check(module.Dispatch(Request("gameplayTime.read")).Response.Error?.Code == "gameplay.account_changed",
                "new commands cannot queue behind the blocked state lock");
            held.Release.TrySetResult(); await Finish(sampling); await Finish(stop);
            module.Sample(); foreach (var timer in clock.Timers) timer.Fire();
            Check(probes == 2 && original.SequenceEqual(temp.Hash()), "late sample cannot persist elapsed time or re-open sampling");
            using var file = new GameplayTimeStore(temp.Root).Open(Owner);
            Check(file.Read() is { Seconds: 37, Consent: GameplayRecordingConsent.Allowed, ShowOnProfile: false },
                "retirement releases the writer while retaining the user's original settings and total");
        }
        finally { held.Release.TrySetResult(); await Finish(sampling); }
    }
    private static async Task Publication(bool write)
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        var remote = new Remote(held, write ? "publish" : "read"); using var module = Runtime(temp, clock, remote);
        var original = temp.Hash(); var publishing = module.PublishCurrentGameplayAsync();
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "transport cancellation is not a drain receipt");
            held.Release.TrySetResult(); await Finish(publishing); await Finish(stop);
            await module.PublishCurrentGameplayAsync(); await module.RecoverResetAsync(remote);
            foreach (var timer in clock.Timers) timer.Fire();
            Check(remote.Reads == 1 && remote.Publications == (write ? 1 : 0) && remote.Resets == 0 && original.SequenceEqual(temp.Hash()),
                "no next-stage publication, replay, timer recovery or file update after retirement");
        }
        finally { held.Release.TrySetResult(); await Finish(publishing); }
    }
    private static async Task ResetObserver()
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        var remote = new Remote(held, "read") { State = new(1, 1, Id(), 0, 0, 0, null) };
        using var module = Runtime(temp, clock, remote); var original = temp.Hash();
        var recovering = module.RecoverResetAsync(remote);
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "reset observer owns its actual read");
            held.Release.TrySetResult(); await Finish(recovering); await Finish(stop);
            Check(remote.Reads == 1 && remote.Publications == 0 && original.SequenceEqual(temp.Hash()), "late reset cannot clear local time or continue publication");
        }
        finally { held.Release.TrySetResult(); await Finish(recovering); }
    }
    private static async Task ResetWrite()
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        var remote = new Remote(held, "reset"); using var module = Runtime(temp, clock, remote);
        var resetting = module.ResetAsync(Owner, 1, 0, remote);
        try
        {
            await Finish(held.Started.Task); var journaled = temp.Hash(); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "submitted destructive write must actually exit");
            held.Release.TrySetResult(); Check(await resetting == "accountChanged", "late accepted response cannot finish local reset");
            await Finish(stop); Check(journaled.SequenceEqual(temp.Hash()) && remote.Resets == 1 && remote.Reads == 0,
                "pending reset is neither cleared nor replayed during retirement");
            using var file = new GameplayTimeStore(temp.Root).Open(Owner);
            Check(file.Read() is { Seconds: 37, PendingReset: not null, Consent: GameplayRecordingConsent.Allowed, ShowOnProfile: false },
                "uncertain remote outcome and existing total survive for later online reconciliation");
        }
        finally { held.Release.TrySetResult(); await Finish(resetting); }
    }
    private static async Task ImportRecovery()
    {
        using var temp = new Temp(); Seed(temp, true); using var held = new Held(); var clock = new Clock();
        GameplayPendingImport pending;
        using (var file = new GameplayTimeStore(temp.Root).Open(Owner)) pending = file.Read().PendingImport!;
        var remote = new Remote(held, "read") { State = new(1, 1, null, null, 97, 60, Start, pending.Update.HistoryImportOperationId) };
        using var module = Runtime(temp, clock, remote); var original = temp.Hash(); var recovery = module.RecoverHistoryImportAsync();
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "pending import read needs actual exit");
            held.Release.TrySetResult(); await Finish(recovery); await Finish(stop); await module.RecoverHistoryImportAsync();
            using var file = new GameplayTimeStore(temp.Root).Open(Owner);
            Check(file.Read() is { Seconds: 37, PendingImport: not null, HistoryConsumed: not true } && original.SequenceEqual(temp.Hash()) &&
                remote.Reads == 1 && remote.Publications == 0, "late import receipt cannot consume, add time or replay a write");
        }
        finally { held.Release.TrySetResult(); await Finish(recovery); }
    }
    private static async Task HistoryEligibility()
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        using var module = Runtime(temp, clock, eligibility: async (_, token) => {
            await held.Wait(token); return new("imported", Start);
        });
        var original = temp.Hash(); var request = module.DispatchHistoryAsync(Request("gameplayTime.historyStatus"));
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "history command owns its eligibility read");
            held.Release.TrySetResult(); var reply = await request; await Finish(stop);
            Check(reply.Response.Payload.GetProperty("state").GetString() == "accountChanged" && original.SequenceEqual(temp.Hash()),
                "a late imported marker cannot modify the independent recording file");
        }
        finally { held.Release.TrySetResult(); await Finish(request); }
    }
    private static async Task ImportWrite()
    {
        using var temp = new Temp(); Seed(temp, historyCutoff: true); using var held = new Held(); var clock = new Clock();
        var remote = new Remote(held, "publish"); using var module = Runtime(temp, clock, remote, eligibility: (_, _) => Task.FromResult(new GameplayHistoryEligibility("available")));
        var log = Path.Combine(temp.Root, "LIVE", "Game.log");
        var backups = Path.Combine(temp.Root, "LIVE", "logbackups"); Directory.CreateDirectory(backups); File.WriteAllText(log, "");
        File.WriteAllText(Path.Combine(backups, "session.log"), "<2020-01-01T00:00:00Z> boot\n" +
            "<2020-01-01T00:00:01Z> nickname=\"Pilot-Example\" playerGEID=100\n" +
            "<2020-01-01T00:01:00Z> <SystemQuit> CSystem::Quit\n");
        var preview = await module.DispatchHistoryAsync(Request("gameplayTime.historyPreview"));
        Check(preview.Response.Payload.GetProperty("state").GetString() == "preview", "real scanner supplies an import ticket");
        var confirmation = module.DispatchHistoryAsync(Request("gameplayTime.historyConfirm") with {
            Payload = BridgePayload.From(new { schemaVersion = 1, previewId = preview.Response.Payload.GetProperty("previewId").GetString() }) });
        try
        {
            await Finish(held.Started.Task); var journaled = temp.Hash(); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "the actual history POST still owns its admitted command");
            held.Release.TrySetResult(); var reply = await confirmation; await Finish(stop);
            using var file = new GameplayTimeStore(temp.Root).Open(Owner);
            Check(reply.Response.Payload.GetProperty("state").GetString() == "accountChanged" &&
                file.Read() is { Seconds: 37, PendingImport: not null, HistoryConsumed: not true } &&
                journaled.SequenceEqual(temp.Hash()) && remote.Reads == 1 && remote.Publications == 1,
                "retirement cannot reconcile, count history, discard the unknown outcome or resend it");
        }
        finally { held.Release.TrySetResult(); await Finish(confirmation); }
    }
    private static async Task ResetPreview()
    {
        using var temp = new Temp(); Seed(temp); using var held = new Held(); var clock = new Clock();
        var remote = new Remote(held, "read"); using var module = Runtime(temp, clock, remote);
        var original = temp.Hash(); var request = module.DispatchResetAsync(Request("gameplayTime.resetPreview"), remote);
        try
        {
            await Finish(held.Started.Task); var stop = module.RetireAsync();
            Check(!stop.IsCompleted && held.Token.IsCancellationRequested, "preview's external read is counted too");
            held.Release.TrySetResult(); var reply = await request; await Finish(stop);
            Check(reply.Response.Payload.GetProperty("state").GetString() == "accountChanged" && original.SequenceEqual(temp.Hash()) && remote.Resets == 0,
                "late preview cannot issue a reset confirmation ticket");
        }
        finally { held.Release.TrySetResult(); await Finish(request); }
    }
    private static async Task GameLogHandoff()
    {
        using var temp = new Temp(); using var held = new Held(); var clock = new Clock();
        var log = Path.Combine(temp.Root, "install", "LIVE", "Game.log"); Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        string Line(string body, DateTimeOffset at) => $"<{at:yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'}> {body}\n";
        File.WriteAllText(log, Line("nickname=\"Pilot-Example\" playerGEID=100", Start.AddMinutes(-1)));
        var store = new LocalFirstUseStore(Path.Combine(temp.Root, "device"), clock);
        var process = new GameProcessSession("notRunning");
        var evidence = new LocalLogEvidenceOwner(store, () => process, clock);
        var candidate = evidence.Select(store.Read().Revision, log, "LIVE"); evidence.Confirm(candidate.SourceKey!, candidate.EvidenceKey!);
        var mode = (Active: false, Generation: 1L);
        var local = new LocalGameLogRuntime(store, () => mode, () => process, clock);
        process = new("running", log, Start, "synthetic-session");
        File.WriteAllText(log, Line("nickname=\"Pilot-Example\" playerGEID=100", Start) + Line("<Join PU> connected to shard[pub_sc_alpha_apse1_123]", Start));
        var block = false; var accountReads = 0;
        using var sampler = new GameLogRuntime(new(temp.Root), () => { accountReads++; return (Owner, 1); }, () => "Pilot-Example",
            () => { if (block) { held.Started.TrySetResult(); held.Release.Task.Wait(TimeSpan.FromSeconds(5)); } return process; }, clock);
        sampler.AttachLocalSlot(local);
        var selected = sampler.Dispatch(Request("gameLog.select") with { Payload = BridgePayload.From(new { schemaVersion = 1, path = log }) });
        Check(selected.Response.Status == "ok" && sampler.DetectedHandle == "Pilot-Example", "the real account reader is initially active");
        var original = temp.Hash("game-log-local-v1"); block = true; var sampling = Task.Run(sampler.Sample);
        try
        {
            await Finish(held.Started.Task); var stop = sampler.RetireAccountAsync();
            Check(!stop.IsCompleted && sampler.DetectedHandle is null && sampler.CurrentSession == GameLogSessionSnapshot.Empty &&
                sampler.Dispatch(Request("gameLog.read")).Response.Error?.Code == "gameLog.localMode", "blocked account IO is revoked before actual exit");
            held.Release.TrySetResult(); await Finish(sampling); await Finish(stop);
            Check(clock.Timers.Count == 1 && !clock.Timers[0].Disposed && original.SequenceEqual(temp.Hash("game-log-local-v1")),
                "retirement releases the account lease but retains exactly the existing timer and original selection");
            var reads = accountReads; clock.Timers[0].Fire(); Check(reads == accountReads, "timer cannot re-open the retired account before handoff");
            mode = (true, 2); local.ApplyListening(store.Read().SelectedSourceKey!, true); clock.Timers[0].Fire();
            Check(local.Current.State == "ready" && local.Current.LocalSession.Server.State == "connected" && reads == accountReads &&
                sampler.DetectedHandle is null && sampler.CaptureFirstEntry() is null, "same timer samples the confirmed local profile without account authority");
            mode = (false, 3); clock.Timers[0].Fire(); Check(reads == accountReads && local.Current.State == "inactive",
                "later mode changes cannot resurrect the old account slot");
            using var file = new GameLogSettingsStore(temp.Root).Open(Owner);
            Check(file.Read() is { Enabled: true, Selection: "manual" } && original.SequenceEqual(temp.Hash("game-log-local-v1")),
                "the account's saved listening choice is retained, not rewritten as local mode");
        }
        finally { held.Release.TrySetResult(); await Finish(sampling); }
    }
}
