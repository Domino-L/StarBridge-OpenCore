using StarBridge.Core.Events;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class GameLogJournalSourceTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.Parse("2026-09-10T12:05:00Z");
    private sealed class Clock : TimeProvider { public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-journal-source-" + Guid.NewGuid().ToString("N"));
        internal string Log => Path.Combine(Root, "StarCitizen", "LIVE", "Game.log");
        internal (BridgeAccountContext? Context, long Generation) Owner =
            (new BridgeAccountContext("test", "legacy", "synthetic-source-owner"), 1);
        internal string Expected = "Pilot_A";
        internal GameProcessSession Process;
        internal readonly LocalGameEventJournal Journal;
        internal readonly GameLogRuntime Runtime;
        internal Fixture()
        {
            Directory.CreateDirectory(Path.GetDirectoryName(Log)!);
            File.WriteAllText(Log, Line("nickname=\"Pilot_A\" playerGEID=12345"));
            Journal = new(Path.Combine(Root, "local-event-log.json"), () => Now);
            Journal.Load();
            Process = new("running", Log, Now.AddMinutes(-5), "synthetic-source-session");
            Runtime = new(new GameLogSettingsStore(Root), () => Owner, () => Expected,
                () => Process, new Clock(), false, new GameLogLocator(() => [Path.Combine(Root, "StarCitizen")]), Journal);
        }
        internal BridgeEnvelope Call(string operation = "read") => Runtime.Dispatch(BridgeEnvelope.Request(
            "gameLog." + operation, Guid.NewGuid().ToString("N"), Owner.Generation,
            new { schemaVersion = 1 }, Owner.Context)).Response;
        internal void Add(string body) => File.AppendAllText(Log, Line(body));
        public void Dispose()
        {
            Runtime.Dispose(); Journal.FlushAsync().GetAwaiter().GetResult(); Journal.Dispose();
            // Only this fixture's freshly created temp directory is removed.
            if (!Root.StartsWith(Path.Combine(Path.GetTempPath(), "starbridge-journal-source-"), StringComparison.Ordinal))
                throw new InvalidOperationException("Unexpected test root.");
            Directory.Delete(Root, true);
        }
    }
    private static string Line(string body) => $"<2026-09-10T12:04:00Z> {body}\n";
    private static void Check(bool yes, string message) { if (!yes) throw new Exception(message); }

    internal static Task WarmupThenRealEvents()
    {
        using var f = new Fixture();
        using var events = new StarBridge.HostRuntime.Privacy.SharedActivityEventSource(f.Journal, new Clock());
        var lease = new StarBridge.HostRuntime.Privacy.EventSourceLease(f.Owner.Context!, f.Owner.Generation, 1,
            SharedActivityEventTypes.All);
        events.Activate(lease);
        f.Add("PLAYER_ENTER_SHIP player=Pilot_A ship=ANVL_Arrow");
        Check(f.Call().Status == "ok" && f.Journal.Entries.Length == 0, "Initial read cannot replay journal");
        Check(events.Take(lease).Length == 0, "Initial parser baseline cannot become shared events");
        f.Add("SetDriver: Local client node accepted 'ANVL_Arrow_45678'");
        f.Call();
        var e = f.Journal.Entries.Single();
        Check(e.EventType == "PlayerControllingShip" && e.Title.Contains("箭矢"), "Existing parser and catalog used");
        Check(!e.Detail.Contains("45678") && !e.Title.Contains("12345"), "No instance or GEID leakage");
        Check(events.Take(lease) is [{ Type: "PlayerControllingShip" }], "Confirmed live parser event reaches independent source");
        f.Call(); f.Runtime.Sample();
        Check(f.Journal.Entries.Length == 1, "Repeated refresh/timer does not replay consumed bytes");
        f.Add("SetDriver: Local client node accepted 'ANVL_Arrow_45678'");
        f.Call();
        Check(f.Journal.Entries.Length == 1, "Original journal dedup reused");
        Check(events.Take(lease).Length == 0, "Repeated reads and duplicate log evidence cannot resend shared events");
        return Task.CompletedTask;
    }

    internal static Task LifeEvidenceUsesSameParser()
    {
        using var f = new Fixture(); f.Call();
        f.Add("<SHUDEvent_OnNotification> Added notification \"local medical responders are on the way\"");
        f.Add("<UpdateNotificationItem> Notification \"local medical responders are on the way\", Action: Remove");
        f.Add("<AttachmentReceived> Player[Pilot_A] Attachment[synthetic] Port[weapon_attach_hand_right]");
        f.Call();
        Check(f.Journal.Entries.Any(e => e.EventType == "PlayerRevived"), "Attachment evidence was not discarded by snapshot-only filter");
        Check(f.Journal.Entries.Any(e => e.EventType == "PlayerDowned" && e.Title.Contains("安全区")), "Safe zone meaning preserved");
        f.Add("<SHUDEvent_OnNotification> Added notification \"incapacitated\"");
        f.Add("<UpdateNotificationItem> Notification \"incapacitated\", Action: RemoveIgnore");
        f.Call();
        Check(f.Journal.Entries.Any(e => e.EventType == "PlayerDied"), "Death confirmation evidence retained");
        return Task.CompletedTask;
    }

    internal static Task InvalidIdentityAndAccountDoNotCommit()
    {
        using var f = new Fixture(); f.Call();
        f.Add("PLAYER_ENTER_SHIP player=Pilot_A ship=ANVL_Arrow");
        f.Add("nickname=\"Pilot_B\" playerGEID=78900");
        f.Call();
        Check(f.Journal.Entries.Length == 0, "Later conflicting identity discards entire batch");
        File.WriteAllText(f.Log, Line("nickname=\"Pilot_A\" playerGEID=12345"));
        f.Call();
        f.Add("PLAYER_ENTER_SHIP player=Pilot_A ship=ANVL_Arrow");
        f.Owner = (new BridgeAccountContext("test", "legacy", "synthetic-next-owner"), 2);
        f.Call();
        Check(f.Journal.Entries.Length == 0, "Switching owner never replays the prior owner's pending bytes");
        f.Add("PLAYER_ENTER_SHIP player=Pilot_A ship=AEGS_Sabre");
        f.Expected = "Pilot_B";
        f.Call();
        Check(f.Journal.Entries.Length == 0, "Mismatch cannot commit");
        f.Owner = (null, 3); f.Runtime.Sample();
        Check(f.Journal.Entries.Length == 0, "Logout cannot record");
        return Task.CompletedTask;
    }

    internal static Task PauseResetAndPartialLines()
    {
        using var f = new Fixture(); f.Call();
        f.Call("stop");
        f.Add("PLAYER_ENTER_SHIP player=Pilot_A ship=ANVL_Arrow");
        f.Call("resume");
        Check(f.Journal.Entries.Length == 0, "Resume establishes baseline without replay");
        File.AppendAllText(f.Log, Line("SetDriver: Local client node accepted 'ANVL_Arrow_333'").TrimEnd('\n'));
        f.Call();
        Check(f.Journal.Entries.Length == 0, "Half line never emitted");
        File.AppendAllText(f.Log, "\n"); f.Call();
        Check(f.Journal.Entries.Length == 1, "Completed live line emitted once");
        File.WriteAllText(f.Log, Line("nickname=\"Pilot_A\" playerGEID=12345") +
            Line("PLAYER_ENTER_SHIP player=Pilot_A ship=AEGS_Sabre"));
        f.Call();
        Check(f.Journal.Entries.Length == 1, "Rotation/truncation baseline never replayed");
        f.Add("PLAYER_EXIT_SHIP player=Pilot_A ship=AEGS_Sabre"); f.Call();
        Check(f.Journal.Entries.Length == 2, "New lines after reset still work");
        return Task.CompletedTask;
    }

    internal static Task ServerNavigationAndPrivateProjection()
    {
        using var f = new Fixture(); f.Call();
        f.Add("<Join PU> connected shard[pub_sc_alpha_apse1_123]");
        f.Add("<Join PU> connected shard[pub_sc_alpha_apse1_123]");
        f.Add("<RequestLocationInventory> Player[Pilot_A] requested inventory for Location[Stanton1_Lorville]");
        f.Add("<Player Selected Quantum Target - Local> | AUTH | ANVL_Arrow_101[1]| Player has selected point Area04 as their destination");
        f.Add("<Quantum Drive Arrived - Arrived at Final Destination> CSCItemNavigation::OnQuantumDriveArrived");
        f.Call();
        Check(f.Journal.Entries.Count(e => e.EventType == "ServerJoined") == 1, "Join transition not repeated state");
        Check(f.Journal.Entries.Any(e => e.Title.Contains("罗威尔")), "Existing location catalog used");
        Check(f.Journal.Entries.Any(e => e.Title.Contains("已抵达导航目标")), "Arrival uses preceding navigation evidence");
        var count = f.Journal.Entries.Length;
        f.Add("<RequestLocationInventory> Player[Other_Pilot] requested inventory for Location[Stanton1_Lorville]");
        f.Add("NETWORK_STATE player=Pilot_A state=Online");
        f.Call();
        Check(count == f.Journal.Entries.Length, "Other-player and suppressed network events not logged");
        f.Add("<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"");
        f.Add("<Channel Disconnection> gamerules=\"SC_Default\" reason=\"Player requested disconnect\"");
        f.Call();
        Check(f.Journal.Entries.Count(e => e.EventType == "ServerLeft") == 1, "Only real server transition recorded");
        return Task.CompletedTask;
    }

    internal static async Task ClearAndAccountRace()
    {
        using var f = new Fixture();
        var batch = new GameLogJournalBatch(f.Journal);
        batch.BeginRead(); batch.Complete(() => true);
        batch.BeginRead(); batch.Add(new("ship", "old-pending", "old pending", ""));
        Check(await f.Journal.ClearAsync() == LocalJournalClearResult.Cleared, "Clear completed");
        batch.Complete(() => true);
        Check(f.Journal.Entries.Length == 0, "Preclear pending batch cannot resurrect cleared events");
        batch.BeginRead(); batch.Add(new("ship", "new", "new event", ""));
        batch.Complete(() => true);
        Check(f.Journal.Entries.Length == 1, "Events read after clear still record");
        batch.BeginRead(); batch.Add(new("ship", "stale", "stale owner", ""));
        int checks = 0;
        batch.Complete(() => ++checks < 3);
        Check(f.Journal.Entries.Length == 1, "Account guard is rechecked inside append lock");
        await f.Journal.FlushAsync();
        Check(new LocalEventJournalReader(f.Root, () => Now).Read().Entries.Count == 1, "Actual persisted journal matches");
    }

    internal static Task RecoveryAndBoundedQueue()
    {
        using var f = new Fixture();
        var batch = new GameLogJournalBatch(f.Journal);
        batch.BeginRead(); batch.Complete(() => true);
        batch.BeginRead(); batch.Add(new("life", "stale", "partial", ""));
        batch.Complete(() => false);
        batch.BeginRead(); batch.Add(new("life", "warmup", "baseline", "")); batch.Complete(() => true);
        Check(f.Journal.Entries.Length == 0, "Invalid read requires a fresh baseline");
        batch.BeginRead();
        for (int i = 0; i < 4000; i++) batch.Add(new("other", "sample", "row " + i, ""));
        // Rejecting an oversized observation must still retain nothing.
        batch.Complete(() => false);
        Check(f.Journal.Entries.Length == 0, "Unaccepted bounded batch has no side effects");
        return Task.CompletedTask;
    }

internal static Task MultiReadBatchPreservesEvents()
    {
        using var f = new Fixture(); f.Call();
        f.Add("SetDriver: Local client node accepted 'ANVL_Arrow_444'");
        f.Add(new string('x', 17 * 1024 * 1024));
        f.Add("ClearDriver: Local client node accepted 'ANVL_Arrow_444'");
        Check(f.Call().Payload.GetProperty("state").GetString() == "reading", "Read budget enforced");
        Check(f.Journal.Entries.Length == 0, "Partial batch never commits before final identity validation");
        f.Call();
        Check(f.Journal.Entries.Any(e => e.EventType == "PlayerControllingShip") &&
            f.Journal.Entries.Any(e => e.EventType == "PlayerStoppedDrivingShip"),
            "Events on both sides of a bounded read survive catch-up");
        return Task.CompletedTask;
    }

    internal static Task WpfPresentationParity()
    {
        static string Name(string? s) => string.IsNullOrWhiteSpace(s) || s == "None" ? "未知" : s;
        var e = new FleetEvent(FleetEventType.PlayerDied, "Pilot_A", SourceLine: "never export",
            PlayerId: "never-export-geid", ShipInstanceId: "never-export-instance");
        Check(LocalGameEventPresentation.Title(e, Name, Name) == "Pilot_A 已死亡，等待重生", "WPF death copy");
        Check(LocalGameEventPresentation.Detail(e) == "玩家：Pilot_A", "WPF detail excludes raw line and IDs");
        Check(LocalGameEventPresentation.Title(e with { Type = FleetEventType.PlayerShipControlSignal }, Name, Name) == "", "Weak signal not log noise");
        var nav = e with { Type = FleetEventType.PlayerNavigationTargetChanged, Location = "A", NavigationTarget = "B" };
        Check(LocalGameEventPresentation.Title(nav, Name, Name) == "Pilot_A 设置导航：A → B", "WPF route wording");
        return Task.CompletedTask;
    }
}
