using System.Text.RegularExpressions;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

internal static partial class ContractAchievementTests
{

    internal static async Task<int> OwnerGate073Contracts()
    {
        var tests = new (string, Func<Task>)[] {
            ("ContractTimeoutIsolation", OwnerGate073ContractTimeout),
            ("ContractStorageRecoveryAndHistoryIndependence", OwnerGate073ContractStorage),
            ("ContractHistoryFailureDoesNotBreakAchievements", OwnerGate073HistoryFault),
            ("ContractRecordFaultNeverBlocksAchievements", OwnerGate073RecordFault),
            ("RecognitionRecoversAfterDelayedOwner", OwnerGate073RecognitionOwnerRecovery),
            ("HistoryFaultsPreserveAuthority", LocalContractHistoryTests.HistoryFaultsPreserveAuthority),
            ("ShipChannelSurvivesContractFault", OwnerGate073ShipAfterFault),
        };
        var failed = 0;
        var skipped = 0;
        foreach (var (name, run) in tests)
        {
            try { await run(); Console.WriteLine("PASS CX073 " + name); }
            catch (RestrictedSampleAbsentException e) { skipped++; e.Report(name); }
            catch (Exception e) { failed++; Console.WriteLine("FAIL CX073 " + name + " " + e.Message); }
        }
        Console.WriteLine($"CX073 contract: {tests.Length - failed - skipped} passed, {failed} failed, {skipped} skipped");
        return failed;
    }

    private static async Task OwnerGate073RecordFault()
    {
        using var f = new ReaderHarness();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        f.Select();
        f.Records.Capture(Owner, Mission, "Synthetic contract", null, () => true);
        var path = Directory.GetFiles(Path.Combine(f.DirectoryRoot, "achievements-contract-records-v1"), "*.json").Single();
        var saved = File.ReadAllBytes(path);
        File.WriteAllText(path, "{}");
        f.Append(FullGateReplay());
        await f.History.FlushAsync();
        // Records are display-only (achievement-line review P2-1): a persistently corrupt
        // records file must not interrupt achievement judgement or identity.
        Require(f.Game.DetectedHandle == "Pilot_A" &&
            Read(f.Store).Runs.Single(r => r.MissionId == Mission).Pending?.CompleteRun == true,
            "A display-only record fault must neither invalidate identity nor block a complete run.");
        var history = new StarBridge.HostRuntime.Support.LocalEventJournalReader(f.DirectoryRoot,
            () => f.Time.Now, () => f.History.DirectoryFor(Owner));
        Require(history.Read().Entries.Count > 0, "Contract record fault must preserve independent history.");
        File.WriteAllBytes(path, saved);
        var other = Guid.NewGuid().ToString("D");
        f.Append(FullGateReplay().Replace(Mission, other, StringComparison.Ordinal));
        Require(Read(f.Store).Runs.Single(r => r.MissionId == other).Pending?.CompleteRun == true,
            "A later healthy mission is accounted normally.");
    }


    private static Task OwnerGate073RecognitionOwnerRecovery()
    {
        using var f = new ReaderHarness();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        f.Select(); f.Game.Dispose(); // Saved selection exists, as on an ordinary restart.
        var ready = false;
        var settings = new GameLogSettingsStore(f.DirectoryRoot) {
            ResolveOwner = owner => ready ? owner : throw new StarBridge.HostRuntime.Privacy.LocalPrivacyOwnerUnavailableException() };
        using var game = new GameLogRuntime(settings, () => f.Current, () => f.Expected,
            () => new(f.ProcessState, f.Log, f.StartedAt, f.Session), f.Time, startTimer: false);
        game.Sample();
        Require(game.DetectedHandle is null, "Startup owner gate must initially suppress recognition.");
        ready = true; f.Time.Now += TimeSpan.FromSeconds(1);
        game.Sample();
        Require(game.DetectedHandle == f.Expected && game.CurrentSession.Server.State == "connected",
            "A healthy sample after delayed ownership must clear the old storage error without manual retry.");
        return Task.CompletedTask;
    }

    private static string FullGateReplay() => string.Join("\n", Lines().Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n";
    private static async Task OwnerGate073ContractStorage()
    {
        using var f = new ReaderHarness();
        var diagnostics = new List<(string Stage, string Code)>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((s, c) => diagnostics.Add((s, c)));
        f.Select();
        var groups = Lines().GroupBy(l => l.Source).ToArray();
        f.Append(string.Join("\n", groups[0].Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n");
        await f.History.FlushAsync();
        var history = new StarBridge.HostRuntime.Support.LocalEventJournalReader(f.DirectoryRoot,
            () => f.Time.Now, () => f.History.DirectoryFor(Owner));
        var before = history.Read().Entries.Count;
        var path = Directory.GetFiles(Path.Combine(f.DirectoryRoot, "achievements-contract-v1"), "*.json").Single();
        var saved = File.ReadAllBytes(path);
        File.WriteAllText(path, "{}");
        f.Append(string.Join("\n", groups.Skip(1).SelectMany(g => g).Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n");
        await f.History.FlushAsync();
        Require(f.Game.DetectedHandle == "Pilot_A" && f.Game.CurrentSession.Server.State == "connected" &&
            history.Read().Entries.Count > before, "Achievement journal fault must preserve identity and independent display history.");
        Require(diagnostics.Any(d => d.Stage == "gamelog-contract" && d.Code.Contains("code=contract")), "Storage failure has an injected reason-code diagnostic.");
        File.WriteAllBytes(path, saved);
        f.Append(FullGateReplay());
        Require(Pending(f.Store).CompleteRun == false, "Recovered old mission must carry a reading gap.");
        var other = Guid.NewGuid().ToString("D");
        f.Append(FullGateReplay().Replace(Mission, other, StringComparison.Ordinal));
        Require(Read(f.Store).Runs.Single(r => r.MissionId == other).Pending?.CompleteRun == true, "Distinct healthy mission is accounted after storage recovers.");
        var queued = f.Queued;
        f.Append(FullGateReplay().Replace(Mission, other, StringComparison.Ordinal));
        Require(queued == f.Queued, "Recovered terminal outbox remains idempotent.");
    }
    private static async Task OwnerGate073HistoryFault()
    {
        using var f = new ReaderHarness();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        f.Select();
        var faults = 0;
        f.History.BeforeObserve = () => { faults++; throw new TimeoutException(); };
        f.Append(FullGateReplay());
        Require(faults == 1 && Pending(f.Store).CompleteRun && f.Game.DetectedHandle == "Pilot_A",
            "Unexpected display-history fault stops only that history batch without breaking complete-run achievements.");
        f.History.BeforeObserve = null;
        f.Append(FullGateReplay().Replace(Mission, Guid.NewGuid().ToString("D"), StringComparison.Ordinal));
        await f.History.FlushAsync();
        var history = new StarBridge.HostRuntime.Support.LocalEventJournalReader(f.DirectoryRoot,
            () => f.Time.Now, () => f.History.DirectoryFor(Owner));
        Require(history.Read().Entries.Count > 0, "Display history recovers on the next healthy batch.");
    }

    internal static Task OwnerGate073ContractTimeout()
    {
        using var f = new ReaderHarness();
        var diagnostics = new List<string>();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((stage, code) => diagnostics.Add(stage + " " + code));
        var selected = f.Game.Dispatch(BridgeEnvelope.Request("gameLog.select", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1, path = f.Log }, Owner)).Response;
        f.Game.Sample();
        Require(f.Game.DetectedHandle == f.Expected, "Synthetic selection: " + selected.Error?.Code + " state=" + selected.Payload.GetProperty("state").GetString() + " process=" + f.ProcessState + " " + string.Join("; ", diagnostics));
        using var gameplay = new GameplayTimeRuntime(new GameplayTimeStore(f.DirectoryRoot),
            () => f.Current, () => new(1, f.Game.DetectedHandle is null ? "unknown" : "running"),
            f.Time, startTimer: false, verifiedHandle: () => f.Expected);
        gameplay.Dispatch(BridgeEnvelope.Request("gameplayTime.setConsent", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1, allowed = true }, Owner));
        gameplay.Sample();
        var parser = new RegexLogEventParser();
        var faults = 0;
        var callsAfterFault = 0;
        var faulted = false;
        f.Game.EventParser = line => {
            if (faulted && (line.Contains("<EndMission>", StringComparison.Ordinal) ||
                line.Contains("<Mission", StringComparison.Ordinal))) callsAfterFault++;
            if (line.Contains("<MissionEnded>", StringComparison.Ordinal) && faults++ == 0)
            { faulted = true; throw new RegexMatchTimeoutException(); }
            return parser.TryParse(line);
        };
        var full = string.Join("\n", Lines().Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n";
        f.Append(full);
        Require(f.Game.DetectedHandle == "Pilot_A" && f.Game.RecentDetectedHandle == "Pilot_A" &&
            f.Game.CurrentSession.Server.State == "connected", "Contract regex timeout must preserve identified presence and identity publication.");
        var retry = f.Game.Dispatch(BridgeEnvelope.Request("gameLog.retry", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1 }, Owner)).Response;
        Require(retry.Error is null && retry.Payload.GetProperty("state").GetString() == "identified" &&
            retry.Payload.GetProperty("observedAtUtc").ValueKind == System.Text.Json.JsonValueKind.String,
            "Retry after a contract timeout must finish observation and update the check timestamp.");
        Require(faults == 1 && callsAfterFault == 0, "Faulting line is consumed and the remaining contract batch is skipped until the next read.");
        f.Time.Now += TimeSpan.FromSeconds(5);
        f.Game.Sample(); gameplay.Sample();
        var time = gameplay.Dispatch(BridgeEnvelope.Request("gameplayTime.read", Guid.NewGuid().ToString("N"), 1,
            new { schemaVersion = 1 }, Owner)).Response;
        Require(time.Payload.GetProperty("seconds").GetInt64() >= 5, "Contract timeout must not stop gameplay recording.");
        // Repeating the interrupted mission must not manufacture a complete new run.
        f.Append(full);
        Require(Read(f.Store).Runs.All(r => r.Pending?.CompleteRun != true),
            "Interrupted batch remains uncertain even when its acceptance is repeated.");
        var other = Guid.NewGuid().ToString("D");
        f.Append(full.Replace(Mission, other, StringComparison.Ordinal));
        Require(Read(f.Store).Runs.Single(r => r.MissionId == other).Pending is not null,
            "A later healthy batch can still account a distinct mission.");
        var queued = f.Queued;
        f.Append(full.Replace(Mission, other, StringComparison.Ordinal));
        Require(f.Queued == queued, "Terminal outcome must remain idempotent after recovery.");
        return Task.CompletedTask;
    }

    // Achievement-line review P2-2: after a contract fault, only mission lines are skipped;
    // the ship channel HUD notification in the same batch still drives the current ship.
    private static Task OwnerGate073ShipAfterFault()
    {
        using var f = new ReaderHarness();
        using var capture = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
        f.Select();
        f.Game.Sample();
        var parser = new RegexLogEventParser();
        var faults = 0;
        f.Game.EventParser = line => {
            if (line.Contains("<MissionEnded>", StringComparison.Ordinal) && faults++ == 0) throw new RegexMatchTimeoutException();
            return parser.TryParse(line);
        };
        var last = Lines().Last().Line; var stamp = last.Substring(0, last.IndexOf('>') + 1);
        f.Append(FullGateReplay() + stamp +
            " [Notice] <SHUDEvent_OnNotification> Added notification \"You joined channel 'Anvil F8C Lightning : Pilot_A'\"\n");
        Require(faults == 1, "the synthetic fault fired");
        Require(f.Game.DetectedHandle == "Pilot_A" && f.Game.CurrentSession.Ship.Key is not null,
            "a ship channel notification after a contract fault must still set the current ship");
        return Task.CompletedTask;
    }
}
