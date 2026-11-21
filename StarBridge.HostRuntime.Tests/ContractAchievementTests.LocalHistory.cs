using StarBridge.Core.Events;
using StarBridge.HostRuntime.Support;

internal static partial class ContractAchievementTests
{
    internal static async Task LocalHistoryRuntimeGates()
    {
        var full = string.Join("\n", Lines().Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n";
        LocalEventJournalSnapshot Read(ReaderHarness f) {
            f.History.FlushAsync().GetAwaiter().GetResult();
            return new LocalEventJournalReader(f.DirectoryRoot,
            () => f.Time.Now, () => f.History.DirectoryFor(Owner)).Read();
        }
        using (var live = new ReaderHarness())
        {
            live.Select();
            var directory = live.History.DirectoryFor(Owner)!;
            Directory.CreateDirectory(directory);
            using (var lease = new FileStream(Path.Combine(directory, LocalEventJournalReader.ContractFileName) + ".lock",
                FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            {
                await Task.Run(() => live.Append(full)).WaitAsync(TimeSpan.FromSeconds(2));
                await Task.Run(live.Game.Sample).WaitAsync(TimeSpan.FromSeconds(2));
                Require(live.Game.DetectedHandle == "Pilot_A", "reader and next sample complete while writer lease remains blocked");
            }
            var rows = Read(live).Entries;
            Require(rows.Count > 2 && rows.Any(e => e.Title == "合约完成：需要战术打击群"), "live self reader emits contract history");
            Require(rows.All(e => e.Category == "contract"), "contract history remains separate");
        }
        using (var historical = new ReaderHarness(full))
        {
            historical.Select(); historical.Append(full);
            var rows = Read(historical).Entries;
            Require(rows.Count > 0 && rows.All(e => e.EventType != nameof(FleetEventType.ContractAccepted)) &&
                rows.All(e => !e.Detail.Contains("接单到完成")), "historical acceptance never backfills; subsequent live evidence is admitted without duration");
        }
        using (var wrong = new ReaderHarness())
        {
            wrong.Expected = "Other_Pilot"; wrong.Select(); wrong.Append(full);
            Require(Read(wrong).Entries.Count == 0, "verified identity mismatch cannot record contract history");
        }
        using (var disconnected = new ReaderHarness(connected: false))
        {
            disconnected.Select(); disconnected.Append(full);
            Require(Read(disconnected).Entries.Count == 0, "disconnected source cannot record contract history");
        }
        using (var foreign = new ReaderHarness())
        {
            foreign.Select();
            var head = Lines().Where(l => !l.Line.Contains("<MissionEnded>") && !l.Line.Contains("<EndMission>"));
            foreign.Append(string.Join("\n", head.Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n" +
                Lines().Single(l => l.Line.Contains("<EndMission>")).Line.Replace("Player[Pilot_A]", "Player[Other_Pilot]") + "\n");
            Require(Read(foreign).Entries.All(e => e.EventType != nameof(FleetEventType.ContractEnded)),
                "another player's whole ending cannot appear in self history");
        }
        return;
    }
    internal static async Task LocalHistoryReadClearCommit()
    {
        using var f = new ReaderHarness();
        f.Select();
        var session = (StarBridge.HostRuntime.Presence.GameLogSessionTracker)typeof(StarBridge.HostRuntime.Presence.GameLogRuntime)
            .GetField("_session", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(f.Game)!;
        var cleared = false;
        session.ContractEvidence += (_, live) =>
        {
            if (!live || cleared) return;
            // The real reader has already added evidence to _contractEvents, still under its sampling lock.
            cleared = true;
            Require(f.History.ClearAsync(Owner, () => true, default).GetAwaiter().GetResult() == LocalJournalClearResult.Cleared,
                "clear succeeds between evidence read and tracker submission");
        };
        f.Append(string.Join("\n", Lines().Select(l => l.Line.Replace(" ⏎ ", "\n"))) + "\n");
        await f.History.FlushAsync();
        var reader = new LocalEventJournalReader(f.DirectoryRoot, () => f.Time.Now, () => f.History.DirectoryFor(Owner));
        Require(cleared && reader.Read().Entries.Count == 0, "original reader batch cannot resurrect after confirmed clear");
        Require(Pending(f.Store).CompleteRun, "diagnostic clear barrier does not alter achievement eligibility");
        // A fresh read after the clear is allowed to append.
        var fresh = Lines().First(l => l.Line.Contains("<MissionEnded>")).Line.Replace(Mission, Guid.NewGuid().ToString());
        f.Append(fresh + "\n"); await f.History.FlushAsync();
        Require(reader.Read().Entries.Count == 1, "next read uses the new clear revision");
    }}
