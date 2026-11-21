using System.Text;
using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Achievements;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Presence;

internal static partial class ContractAchievementTests
{
    internal static Task TimestampedPhysicalLines()
    {
        using var fixture = JsonDocument.Parse(RestrictedSamples.Read("timestamped-notifications.json"));
        var physical = fixture.RootElement.GetProperty("physicalLines").EnumerateArray().Select(l => l.GetString()!).ToArray();
        Require(physical.Length == 4 && physical.All(l => l.StartsWith("<2026-", StringComparison.Ordinal)), "original four physical timestamps retained");
        using var h = new ReaderHarness();
        var session = new GameLogSessionTracker(); var reader = new GameLogIdentityReader(session);
        var seen = new List<(FleetEvent Event, bool Live)>(); var gaps = 0;
        session.ContractEvidence += (e, live) => seen.Add((e, live)); reader.ContractReadInterrupted += () => gaps++;
        var process = new GameProcessSession("running", h.Log, h.StartedAt, h.Session);
        reader.ReadCurrent(h.Log, process, Ended);
        foreach (var line in physical)
        {
            File.AppendAllText(h.Log, line + "\r\n", new UTF8Encoding(false));
            reader.ReadCurrent(h.Log, process, Ended);
        }
        Require(seen.Count == 2 && seen.All(e => e.Live) && gaps == 0, "timestamped continuation yields two live events without gaps");
        Require(seen[0].Event.Type == FleetEventType.ContractAccepted && seen[0].Event.Timestamp == DateTimeOffset.Parse("2026-10-18T03:29:57.165Z") &&
            seen[1].Event.Type == FleetEventType.ContractObjective && seen[1].Event.Contract?.State == "COMPLETED" &&
            seen[1].Event.Timestamp == DateTimeOffset.Parse("2026-10-18T04:17:34.311Z"), "first physical timestamps and objective body preserved");
        // An unfinished contract must not swallow a different timestamped record.
        File.AppendAllText(h.Log, physical[0] + "\n" + ReaderHarness.Header("2026-10-18T05:00:00Z"), new UTF8Encoding(false));
        Require(reader.ReadCurrent(h.Log, process, Ended).Handle == "Pilot_A" && gaps == 1, "unrelated identity remains a separate record");
        reader.Reset();
        return Task.CompletedTask;
    }

    private static Task HistoricalShareOwnership()
    {
        var share = $"<2026-10-18T03:20:00Z> [Notice] <MissionShared> Received share push message: ownerId[X] - missionId[{Mission}] [Team_GameServices][Missions]\n";
        foreach (var history in new[] { share, "" })
        foreach (var covered in new[] { false, true })
        {
            using var h = new ReaderHarness(history);
            // Missing the process-start portion makes earlier share coverage unknown.
            File.WriteAllText(h.Log, ReaderHarness.Header(covered ? "2026-10-18T03:00:01Z" : "2026-10-18T03:15:00Z") + history, new UTF8Encoding(false));
            h.Select(); h.Append(string.Join("\n", Lines().Select(l => l.Line)) + "\n");
            Require(Pending(h.Store).Owner == (covered && history.Length == 0), "owner requires reliable startup coverage and no historical share");
        }
        var store = new ContractAchievementStore(Root()); var tracker = new ContractRunTracker(store);
        var shared = new RegexLogEventParser().TryParse(share.TrimEnd())!;
        tracker.Observe(Owner, HandleHash, [(shared, false)], () => true);
        tracker.Observe(Owner, HandleHash, Replay(), () => true, ownershipCovered: true);
        Require(!Pending(store).Owner && Read(store).Runs.Single().Shared, "historical share retained as negative evidence");
        return Task.CompletedTask;
    }

    private static Task ContractCodeGrammar()
    {
        var events = Replay();
        var template = new ContractObservation(1, HandleHash, Mission, "unknown", null, "completed", false, false, 0, Ended.AddHours(-2), null, Ended);
        foreach (var code in new[] { "A", "_", "a-b_C9", new string('x', 128) })
            Require((template with { Contract = code }).IsValid, "Java-valid contract: length " + code.Length);
        foreach (var code in new[] { "", "-bad", "a.b", "中文", "a\n", new string('x', 129), new string('x', 160) })
        {
            Require(!(template with { Contract = code }).IsValid, "Java-invalid code rejected: length " + code.Length);
            var store = new ContractAchievementStore(Root());
            new ContractRunTracker(store).Observe(Owner, HandleHash, events.Select(e =>
                (e.Event.Type == FleetEventType.ContractDefined ? e.Event with { Contract = e.Event.Contract! with { Contract = code } } : e.Event, e.Live)).ToArray(), () => true);
            Require(Pending(store).Contract == "unknown" && Pending(store).IsValid && Cloud.Awards(Pending(store)).SetEquals(["contract-first"]), "invalid code still supports first contract");
        }
        return Task.CompletedTask;
    }
}
