using System.Text.Json;
using StarBridge.HostRuntime.Support;

internal static partial class ContractAchievementTests
{
    internal static async Task MissionRecordsLiveRoles()
    {
        using var live = new ReaderHarness(contracts: false);
        await using var records = new LocalMissionRecords(live.DirectoryRoot);
        live.Game.ConfigureMissionRecords(records);
        live.Select();
        live.Append(string.Join("\n", new[] { LocalMissionRecordsTests.Shared(), LocalMissionRecordsTests.Accepted(),
            LocalMissionRecordsTests.Defined(), LocalMissionRecordsTests.PlayerJoined("12345"),
            LocalMissionRecordsTests.PlayerJoined(), LocalMissionRecordsTests.LiveObjective(), LocalMissionRecordsTests.Ended() }) + "\n");
        await records.FlushAsync();
        var row = (await records.ReadAsync(Owner)).Records.Single();
        var group = LocalMissionRecords.Summarize([row]).Single();
        Require(row is { Joined: true, JoinedFromStart: true, Teammates: 1 } && group.Count == 1 &&
            group.FastestSeconds is null && group.SoloFastestSeconds is null && group.TeamFastestSeconds is null &&
            group.JoinedFullFastestSeconds == 60, "live shared push, objective provenance and own GEID survive the real reader");
        var teamId = Guid.NewGuid().ToString();
        live.Append(string.Join("\n", new[] { LocalMissionRecordsTests.Accepted(teamId), LocalMissionRecordsTests.Defined(teamId),
            LocalMissionRecordsTests.PlayerJoined("12345", mission: teamId), LocalMissionRecordsTests.PlayerJoined(mission: teamId),
            LocalMissionRecordsTests.Ended(teamId, seconds: 90) }) + "\n");
        await records.FlushAsync();
        var rows = (await records.ReadAsync(Owner)).Records;
        Require(rows.Single(r => r.MissionId == teamId) is { Joined: false, Team: true, Teammates: 1 } &&
            LocalMissionRecords.Summarize(rows).Single().TeamFastestSeconds == 90, "live owner team excludes local GEID");
    }

    internal static async Task MissionRecordsLive()
    {
        static string Comparable(StarBridge.HostRuntime.Achievements.ContractAchievementStore store) =>
            JsonSerializer.Serialize(Read(store).Runs.Select(r => r with { ReadingPeriod = Guid.Empty }));
        var states = new[] { "COMPLETED", "FAILED", "ABANDONED", "WITHDRAWN" };
        var ids = states.Select(_ => Guid.NewGuid().ToString()).ToArray();
        var lines = string.Join("\n", states.SelectMany((state, i) => new[] {
            LocalMissionRecordsTests.Accepted(ids[i]), LocalMissionRecordsTests.Defined(ids[i]),
            LocalMissionRecordsTests.Ended(ids[i], state) })) + "\n";
        using var baseline = new ReaderHarness();
        using var enabled = new ReaderHarness();
        await using var records = new LocalMissionRecords(enabled.DirectoryRoot);
        enabled.Game.ConfigureMissionRecords(records);
        baseline.Select(); enabled.Select();
        baseline.Append(lines); enabled.Append(lines);
        await Task.WhenAll(records.FlushAsync(), baseline.History.FlushAsync(), enabled.History.FlushAsync());
        var rows = (await records.ReadAsync(Owner)).Records;
        Require(rows.Length == 1 && rows[0].MissionId == ids[0] && rows[0].Source == "live" &&
            rows[0].AcceptedAt == LocalMissionRecordsTests.At && rows[0].DefinitionId == LocalMissionRecordsTests.Definition,
            "real reader records completed only with same-mission acceptance and definition");
        Require(Comparable(baseline.Store) == Comparable(enabled.Store),
            "achievement state unchanged by mission recording");
        var before = new LocalEventJournalReader(baseline.DirectoryRoot, () => baseline.Time.Now,
            () => baseline.History.DirectoryFor(Owner)).Read().Entries;
        var after = new LocalEventJournalReader(enabled.DirectoryRoot, () => enabled.Time.Now,
            () => enabled.History.DirectoryFor(Owner)).Read().Entries;
        Require(before.SequenceEqual(after), "independent contract history unchanged");
        enabled.Append(lines); await records.FlushAsync();
        Require((await records.ReadAsync(Owner)).Records.Length == 1, "duplicate live completion remains single");

        // Mission records alone, with no achievement tracker: both Observe paths still record
        // the completion, clear the batch and never raise ContractQueued.
        using (var alone = new ReaderHarness(contracts: false))
        {
            await using var aloneRecords = new LocalMissionRecords(alone.DirectoryRoot);
            alone.Game.ConfigureMissionRecords(aloneRecords);
            alone.Select();
            alone.Append(lines); await aloneRecords.FlushAsync();
            Require((await aloneRecords.ReadAsync(Owner)).Records.Length == 1 && alone.Queued == 0,
                "records without a tracker: completed only, no achievement queue");
            alone.Append(lines); alone.ProcessState = "notRunning"; alone.Game.Sample(); await aloneRecords.FlushAsync();
            Require((await aloneRecords.ReadAsync(Owner)).Records.Length == 1 && alone.Queued == 0,
                "records without a tracker survive the session-end path without duplicates");
        }

        using var fault = new ReaderHarness();
        await using var faultRecords = new LocalMissionRecords(fault.DirectoryRoot);
        fault.Game.ConfigureMissionRecords(faultRecords); fault.Select();
        var directory = faultRecords.DirectoryFor(Owner)!;
        Directory.CreateDirectory(directory);
        using (var lease = new FileStream(Path.Combine(directory, LocalMissionRecordsStore.FileName) + ".lock",
            FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            fault.Append(lines); await Task.WhenAll(faultRecords.FlushAsync(), fault.History.FlushAsync());
            Require(faultRecords.WriteFailures > 0 && Comparable(fault.Store) == Comparable(baseline.Store),
                "mission write failure cannot alter achievement state");
            Require(new LocalEventJournalReader(fault.DirectoryRoot, () => fault.Time.Now,
                () => fault.History.DirectoryFor(Owner)).Read().Entries.SequenceEqual(before), "mission write failure cannot suppress history");
        }
        await using var historical = new LocalMissionRecords(fault.DirectoryRoot);
        var parser = new StarBridge.Core.Parsing.RegexLogEventParser();
        historical.Observe(Owner, lines.Split('\n').Select(parser.TryParse).OfType<StarBridge.Core.Events.FleetEvent>()
            .Select(e => (e, false)), () => true);
        await historical.FlushAsync();
        Require((await historical.ReadAsync(Owner)).Records.Length == 0, "historical evidence never writes live completions");
    }
}
