using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class LocalGameProcessJournalTests
{
    private sealed class Clock : TimeProvider
    {
        internal DateTimeOffset Now = DateTimeOffset.Parse("2026-09-10T12:00:00Z");
        public override DateTimeOffset GetUtcNow() => Now;
        internal void Advance(int seconds) => Now = Now.AddSeconds(seconds);
    }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-process-journal-" + Guid.NewGuid().ToString("N"));
        internal readonly Clock Time = new();
        internal readonly LocalGameEventJournal Journal;
        internal bool? Running = false;
        internal Fixture()
        {
            Directory.CreateDirectory(Root);
            Journal = new(Path.Combine(Root, "local-event-log.json"), () => Time.Now);
            Journal.Load();
        }
        internal LocalGamePresenceReader Reader(Func<bool?>? probe = null) =>
            new(probe ?? (() => Running), Time, journal: Journal);
        internal int Starts => Journal.Entries.Count(e => e.EventType == "GameStarted");
        internal int Stops => Journal.Entries.Count(e => e.EventType == "GameStopped");
        public void Dispose()
        {
            Journal.FlushAsync().GetAwaiter().GetResult(); Journal.Dispose();
            if (!Root.StartsWith(Path.Combine(Path.GetTempPath(), "starbridge-process-journal-"), StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected test root");
            Directory.Delete(Root, true);
        }
    }
    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException(message); }

    internal static async Task ConfirmedLifecyclePersists()
    {
        using var f = new Fixture(); using var r = f.Reader();
        Check(r.Read().State == "notRunning" && f.Journal.Entries.Length == 0, "Initial absence is not an exit");
        f.Running = true; r.Read(); r.Read();
        Check(f.Starts == 1, "One detection, no repeated polling entries");
        f.Running = false; r.Read(); f.Time.Advance(9); r.Read();
        Check(f.Stops == 0, "Single missed poll / nine seconds cannot confirm exit");
        f.Time.Advance(1); r.Read(); r.Read();
        Check(f.Stops == 1, "Ten seconds confirms exactly one exit");
        Check(f.Journal.Entries.All(e => e.Category == "session" && e.Detail == "来源：本机进程监控"),
            "WPF classification and wording reused; no identity or path");
        f.Running = true; f.Time.Advance(3); r.Read();
        Check(f.Starts == 2, "A later real launch is not permanently deduplicated");
        await f.Journal.FlushAsync();
        Check(new LocalEventJournalReader(f.Root, () => f.Time.Now).Read().Entries.Count == 3,
            "Same actual journal persisted");
    }

    internal static Task UnknownRestartsExitConfirmation()
    {
        using var f = new Fixture(); using var r = f.Reader();
        f.Running = true; r.Read();
        f.Running = false; r.Read(); f.Time.Advance(9); r.Read();
        f.Running = null; Check(r.Read().State == "unknown", "Unknown remains unknown in UI");
        f.Time.Advance(60); f.Running = false; r.Read();
        Check(f.Stops == 0, "Unknown interval cannot complete earlier exit timer");
        f.Time.Advance(9); r.Read(); Check(f.Stops == 0, "Fresh ten-second window required");
        f.Time.Advance(1); r.Read(); Check(f.Stops == 1 && f.Starts == 1, "Only confirmed exit emitted");
        return Task.CompletedTask;
    }

    internal static Task UnknownRecoveryDoesNotInventStart()
    {
        using var f = new Fixture(); using var r = f.Reader();
        f.Running = true; r.Read();
        f.Running = null; r.Read(); f.Time.Advance(30); r.Read();
        f.Running = true; r.Read();
        Check(f.Starts == 1 && f.Stops == 0, "Recovering positive evidence is not another start");
        return Task.CompletedTask;
    }

    internal static Task FailedProbeIsNotExit()
    {
        using var f = new Fixture(); bool fail = false;
        using var r = f.Reader(() => fail ? throw new IOException("synthetic probe failure") : f.Running);
        f.Running = true; r.Read();
        fail = true; Check(r.Read().State == "unknown", "Probe failure returns unknown");
        fail = false; f.Running = false; f.Time.Advance(40); r.Read();
        Check(f.Stops == 0, "First negative after failure cannot imply exit");
        f.Running = true; r.Read(); Check(f.Starts == 1, "Recovery does not duplicate start");
        return Task.CompletedTask;
    }

    internal static async Task ConcurrentReadsAreSerialized()
    {
        using var f = new Fixture(); f.Running = true; int concurrent = 0, max = 0, calls = 0;
        using var r = f.Reader(() =>
        {
            var active = Interlocked.Increment(ref concurrent);
            Interlocked.Exchange(ref max, Math.Max(max, active));
            Interlocked.Increment(ref calls);
            Thread.SpinWait(50000);
            Interlocked.Decrement(ref concurrent);
            return true;
        });
        await Task.WhenAll(Enumerable.Range(0, 30).Select(_ => Task.Run(r.Read)));
        Check(calls == 30 && max == 1 && f.Starts == 1, "No concurrent mutation or duplicate start");
    }

    internal static async Task ClearDuringProbeDoesNotResurrect()
    {
        using var f = new Fixture(); bool clear = false;
        using var r = f.Reader(() =>
        {
            if (clear)
            {
                clear = false;
                Check(f.Journal.ClearAsync().GetAwaiter().GetResult() == LocalJournalClearResult.Cleared,
                    "Synthetic concurrent clear");
            }
            return f.Running;
        });
        r.Read(); f.Running = true; clear = true; r.Read();
        Check(f.Journal.Entries.Length == 0, "Pre-clear observation cannot write back afterward");
        r.Read(); Check(f.Journal.Entries.Length == 0, "No retry of cleared detection");
        f.Running = false; r.Read(); f.Time.Advance(10); r.Read();
        Check(f.Stops == 1, "Later actual transition still recorded");
        await f.Journal.FlushAsync();
        Check(new LocalEventJournalReader(f.Root, () => f.Time.Now).Read().Entries.Count == 1, "Disk has new event only");
    }

    internal static async Task AccountAndVersionDoNotDriveLifecycle()
    {
        using var f = new Fixture(); long generation = 1; int probes = 0; string? version = "LIVE";
        using var r = new LocalGamePresenceReader(() =>
        {
            probes++; return new LocalGameProcessObservation(f.Running == true, "LIVE");
        }, f.Time, () => version, f.Journal);
        using var host = new HostBridgeDispatcher("synthetic-process-host", () => generation,
            ["host.lifecycle", "host.gamePresence"], r);
        async Task<BridgeDispatchBatch> Read(long gen) => await host.DispatchAsync(
            BridgeEnvelope.Request("host.getGamePresence", Guid.NewGuid().ToString("N"), gen));
        f.Running = true; var response = await Read(1);
        Check(response.Response.Status == "ok" && response.Events.Count == 0 && f.Starts == 1,
            "Accountless device observation records locally without public event");
        generation = 2; version = null;
        await Read(2); generation = 3; version = "EPTU"; await Read(3);
        Check(f.Starts == 1 && f.Stops == 0, "Logout, switch and version labels are not process transitions");
        var previous = probes; var stale = await Read(2);
        Check(stale.Response.Status != "ok" && probes == previous, "Stale request never starts observation");
    }

    internal static Task DisposalDoesNotEmitExitOrOwnJournal()
    {
        using var f = new Fixture(); f.Running = true;
        var r = f.Reader();
        using (var host = new HostBridgeDispatcher("dispose-test", gamePresence: r))
        { r.Read(); }
        f.Running = false; f.Time.Advance(100);
        Check(r.Read().State == "unknown" && f.Stops == 0, "Closing Host is not game exit; late reads inert");
        f.Journal.Append("other", "still-owned", "shared owner remains usable");
        Check(f.Journal.IsWritable && f.Journal.Entries.Length == 2, "Reader never disposes borrowed journal");
        return Task.CompletedTask;
    }

    internal static Task StorageAndVersionFailuresDoNotBreakObservation()
    {
        using var f = new Fixture();
        using var unavailable = new LocalGameEventJournal(Path.Combine(f.Root, "local-event-log.json"));
        using var r = new LocalGamePresenceReader(() => true, f.Time,
            () => throw new InvalidOperationException("synthetic version failure"), unavailable);
        var observed = r.Read();
        Check(observed.State == "running" && observed.Version is null, "Version or journal failure does not imply process failure");
        Check(unavailable.LastWriteError is not null && f.Journal.Entries.Length == 0,
            "Unloaded journal cannot replace original data");
        return Task.CompletedTask;
    }

    internal static Task BackwardClockAndSharedGameLogJournal()
    {
        using var f = new Fixture(); using var r = f.Reader();
        var log = Path.Combine(f.Root, "StarCitizen", "LIVE", "Game.log");
        Directory.CreateDirectory(Path.GetDirectoryName(log)!);
        File.WriteAllText(log, "<2026-09-10T11:59:00Z> nickname=\"Pilot_A\" playerGEID=12345\n");
        var owner = new BridgeAccountContext("test", "legacy", "synthetic-shared-source");
        using var gameLog = new GameLogRuntime(new(f.Root), () => (owner, 1), () => "Pilot_A",
            () => new("running", log, f.Time.Now.AddMinutes(-5), "synthetic-session"),
            f.Time, false, new(() => [Path.Combine(f.Root, "StarCitizen")]), f.Journal);
        gameLog.Sample();
        f.Running = true; r.Read();
        File.AppendAllText(log, "<2026-09-10T11:59:30Z> SetDriver: Local client node accepted 'ANVL_Arrow_333'\n");
        gameLog.Sample();
        Check(f.Starts == 1 && f.Journal.Entries.Any(e => e.EventType == "PlayerControllingShip"),
            "Both sources borrow exactly one shared journal");
        f.Running = false; r.Read(); f.Time.Advance(9); r.Read();
        f.Time.Advance(-30); r.Read(); f.Time.Advance(9); r.Read();
        Check(f.Stops == 0, "Clock rollback starts a new exit confirmation window");
        f.Time.Advance(1); r.Read(); Check(f.Stops == 1, "Stable absence after rollback still ends session");
        return Task.CompletedTask;
    }
}
