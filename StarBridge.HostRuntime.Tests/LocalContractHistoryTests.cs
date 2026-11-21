using System.Text.Json;
using StarBridge.Core.Events;
using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class LocalContractHistoryTests
{
    private static readonly BridgeAccountContext Owner = ContractAchievementTests.Owner;
    private static readonly DateTimeOffset Now = ContractAchievementTests.Ended.AddMinutes(1);
    private const string M = ContractAchievementTests.Mission;
    private const string O = "a61907c8-f55b-a942-8123-abf36f3af484";
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web);
    private sealed class Fixture : IDisposable
    {
        internal readonly string Root = Directory.CreateTempSubdirectory("sb-contract-history-").FullName;
        internal readonly LocalContractHistory History;
        internal readonly LocalEventJournalReader Reader;
        internal readonly ContractRunTracker Tracker;
        internal Fixture()
        {
            History = new(Root, () => Now);
            Reader = new(Root, () => Now, () => History.DirectoryFor(Owner));
            Tracker = new(new ContractAchievementStore(Root), history: History);
        }
        internal string ContractPath => Path.Combine(History.DirectoryFor(Owner)!, LocalEventJournalReader.ContractFileName);
        internal string LegacyPath => Path.Combine(Root, "local-event-log.json");
        internal void Observe(IEnumerable<string> lines, bool live = true, bool flush = true, bool continuationOnly = false)
        {
            var parser = new RegexLogEventParser();
            Tracker.Observe(Owner, ContractAchievementTests.HandleHash,
                lines.Select(parser.TryParse).OfType<FleetEvent>().Select(e => (e, live)).ToArray(), () => true, ownershipCovered: true, continuationOnly: continuationOnly);
            if (flush) History.FlushAsync().GetAwaiter().GetResult();
        }
        public void Dispose() { History.Dispose(); Directory.Delete(Root, true); }
    }
    internal static Task RealTimeline()
    {
        using var f = new Fixture();
        // Same sanitized section-1 physical log shapes already used by the achievement replay.
        var lines = ContractAchievementTests.Lines().Select(l => l.Line.Replace(" ⏎ ", " ")).ToArray();
        f.Observe(lines);
        var rows = f.Reader.Read().Entries;
        var accepted = rows.Single(e => e.EventType == nameof(FleetEventType.ContractAccepted));
        Check(accepted.Title == "接受合约：需要战术打击群", "game HUD contract name");
        Check(accepted.Detail == "互安防务 - 战术打击群", "HUD issuer");
        var stages = rows.Where(e => e.EventType == nameof(FleetEventType.ContractObjective)).ToArray();
        Check(stages.Length > 0 && stages.Select(e => e.Title).Distinct().Count() == stages.Length, "same-name stage dedup");
        Check(stages.Single(e => e.Title == "阶段目标完成：前往 QV 采矿站").Detail ==
            "需要战术打击群 · 已到达作战地点", "first arrival annotates the swift timer start");
        var ended = rows.Single(e => e.EventType == nameof(FleetEventType.ContractEnded));
        Check(ended.Title == "合约完成：需要战术打击群" && ended.Detail ==
            "互安防务 - 战术打击群 · 接单到完成 2 小时 35 分", "completion and live acceptance duration");
        Check(accepted.OccurredAt < stages.Min(e => e.OccurredAt) && stages.Max(e => e.OccurredAt) <= ended.OccurredAt,
            "acceptance, completed stages, ending use game timestamps");
        var json = File.ReadAllText(f.ContractPath);
        Check(!json.Contains(M) && !json.Contains("Pilot_A") && !json.Contains("position") &&
            !json.Contains("sourceLine") && !File.Exists(f.LegacyPath), "private fields and raw log excluded; legacy file untouched");
        f.Observe(lines);
        Check(f.Reader.Read().Entries.Count == rows.Count, "duplicate acceptance, stages and two whole endings remain first-only");
        return Task.CompletedTask;
    }

    internal static Task StageTextAndOutcomes()
    {
        using var f = new Fixture();
        f.Observe([
            Hud("已接受合约：[发布方]示例合约", 0),
            Hud("新的任务：目标甲", 1, O),
            Upsert(2, O, "COMPLETED"), // Completion may carry only an ID; prior text is already parsed.
            Hud("任务完成：目标甲", 3, Guid.NewGuid().ToString()),
            Upsert(4, Guid.NewGuid().ToString(), "COMPLETED"),
            Hud("新的任务：尚未完成", 5, Guid.NewGuid().ToString()),
            Upsert(6, O, "WITHDRAWN"),
            End(7, "FAILED")]);
        var rows = f.Reader.Read().Entries;
        Check(rows.Count == 3 && rows.Count(e => e.Title == "阶段目标完成：目标甲") == 1,
            "same-name goals dedup across IDs; unnamed, in-progress and withdrawn objectives omitted");
        Check(rows.Any(e => e.Title == "合约失败：示例合约"), "whole-mission failure only");
        foreach (var state in new[] { "ABANDONED", "WITHDRAWN", "COMPLETED", "UNKNOWN" })
        {
            using var unknown = new Fixture();
            unknown.Observe([End(8, state)]);
            var endings = unknown.Reader.Read().Entries;
            Check(state == "UNKNOWN" ? endings.Count == 0 : endings.Single().Title ==
                (state == "COMPLETED" ? "合约完成：未知合约" : "放弃合约：未知合约"), "unknown-name whole ending: " + state);
            if (state == "COMPLETED") Check(endings.Single().Detail == "", "no fabricated duration without live acceptance");
        }
        using var abandon = new Fixture();
        abandon.Observe([Hud("Contract Accepted: Other Contract", 0),
            Stamp(9) + $"<EndMission> Ending mission for player. MissionId[{M}] Player[Pilot_A] PlayerId[X] CompletionType[Abandon] Reason[Mission Ended]"]);
        Check(abandon.Reader.Read().Entries.Any(e => e.Title == "放弃合约：Other Contract"), "explicit EndMission abandonment");
        using var noIssuer = new Fixture();
        noIssuer.Observe([Hud("已接受合约：无发布方<EM4>[蓝图]</EM4>", 0)]);
        Check(noIssuer.Reader.Read().Entries.Single() is { Title: "接受合约：无发布方", Detail: "" },
            "blueprint markup cannot become an issuer when none was provided");
        return Task.CompletedTask;
    }

    internal static Task MissingCorruptRecoveryAndLegacy()
    {
        using var f = new Fixture();
        Check(f.Reader.Read().State == "missing", "both missing");
        Write(f.LegacyPath, [Entry("legacy", Now, "life")]);
        var before = File.ReadAllBytes(f.LegacyPath);
        var old = new LocalEventJournalReader(f.Root, () => Now).Read();
        var merged = f.Reader.Read();
        Check(old.State == merged.State && old.ContentRevision == merged.ContentRevision && old.Entries.SequenceEqual(merged.Entries),
            "legacy-only read is unchanged including revision");
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        foreach (var invalid in new[] { "[", "null", "[null]", "[{\"id\":\"invalid\"}]", "[]\nextra" })
        {
            File.WriteAllText(f.ContractPath, invalid);
            Check(f.Reader.Read().ContentRevision != old.ContentRevision && f.Reader.Read().State == old.State &&
                f.Reader.Read().UnavailableSources!.SequenceEqual(["contract"]) && File.ReadAllText(f.ContractPath) == invalid,
                "invalid contract source is reported and preserved");
        }
        Write(f.ContractPath + ".bak", [Entry("backup", Now.AddSeconds(-1), "contract")]);
        Check(f.Reader.Read() is { State: "recovered", Entries.Count: 2 }, "contract backup is explicit, no restore");
        Write(f.ContractPath, []);
        Check(f.Reader.Read() is { State: "ready", Entries.Count: 1 }, "valid empty contract primary wins");
        Write(f.ContractPath, [Entry("old", Now.AddDays(-31), "contract"), Entry("future", Now.AddMinutes(6), "contract")]);
        Check(f.Reader.Read().Entries.Count == 1, "contract retention and future bounds match legacy");
        Write(f.ContractPath, Enumerable.Range(0, 3100).Select(i => Entry("bounded-" + i, Now.AddSeconds(-i), "contract")));
        Check(f.Reader.Read().Entries.Count == 3000, "contract and combined history remain bounded");
        using (var large = File.Create(f.ContractPath)) large.SetLength(LocalEventJournalReader.MaximumFileBytes + 1L);
        File.Delete(f.ContractPath + ".bak");
        Check(f.Reader.Read().ContentRevision != old.ContentRevision && f.Reader.Read().UnavailableSources!.SequenceEqual(["contract"]),
            "oversized contract source is reflected in revision and availability");
        Check(before.SequenceEqual(File.ReadAllBytes(f.LegacyPath)), "legacy bytes never rewritten by reads");
        return Task.CompletedTask;
    }

    internal static async Task MergePaginationRevisionAndFilter()
    {
        using var f = new Fixture();
        Write(f.LegacyPath, Enumerable.Range(0, 60).Select(i => Entry("l" + i, Now.AddSeconds(-i * 2), "life")));
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        Write(f.ContractPath, Enumerable.Range(0, 60).Select(i => Entry("c" + i, Now.AddSeconds(-i * 2 - 1), "contract")));
        using var bridge = new LocalEventHistoryBridgeDispatcher(f.Reader, () => 2);
        var first = (await bridge.DispatchAsync(Request())).Response.Payload;
        var revision = first.GetProperty("revision").GetString();
        var second = (await bridge.DispatchAsync(Request(offset: 50, revision: revision))).Response.Payload;
        var last = (await bridge.DispatchAsync(Request(offset: 100, revision: revision))).Response.Payload;
        Check(first.GetProperty("totalCount").GetInt32() == 120 && last.GetProperty("entries").GetArrayLength() == 20, "combined pagination");
        var ids = first.GetProperty("entries").EnumerateArray().Concat(second.GetProperty("entries").EnumerateArray())
            .Concat(last.GetProperty("entries").EnumerateArray()).Select(e => e.GetProperty("id").GetString()).ToArray();
        Check(ids.Distinct().Count() == 120 && ids[0] == "l0" && ids[1] == "c0", "combined chronological ordering");
        var filtered = (await bridge.DispatchAsync(Request("contract"))).Response.Payload;
        Check(filtered.GetProperty("filteredCount").GetInt32() == 60 && filtered.GetProperty("entries").EnumerateArray()
            .All(e => e.GetProperty("category").GetString() == "contract"), "contract category whitelist and filter");
        var text = LocalEventJournalReader.FormatExport(f.Reader.Read());
        Check(text.Contains("title-l0") && text.Contains("title-c0"), "export covers both files");
        var exportRoot = Directory.CreateTempSubdirectory("sb-contract-export-").FullName;
        try
        {
            var destination = Path.Combine(exportRoot, "events.txt");
            using var exporter = new LocalEventExportDispatcher(f.Reader, () => 2, new Picker(destination), f.Root);
            var saved = (await exporter.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
                Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, locale = "zh-CN" }))).Response;
            Check(saved.Status == "ok" && saved.Payload.GetProperty("count").GetInt32() == 120 &&
                File.ReadAllText(destination).Contains("title-c0"), "Host export dispatcher includes contract rows");
        }
        finally { Directory.Delete(exportRoot, true); }
        foreach (var path in new[] { f.ContractPath, f.LegacyPath })
        {
            var current = (await bridge.DispatchAsync(Request())).Response.Payload.GetProperty("revision").GetString();
            Write(path, [Entry("same-id", Now, path == f.ContractPath ? "contract" : "life")]);
            Check((await bridge.DispatchAsync(Request(offset: 50, revision: current))).Response.Error?.Code == "localEvents.historyChanged",
                "either source invalidates paged revision");
            current = (await bridge.DispatchAsync(Request())).Response.Payload.GetProperty("revision").GetString();
            Write(path, [Entry("same-id", Now, path == f.ContractPath ? "contract" : "life") with { Title = "changed title" }]);
            Check((await bridge.DispatchAsync(Request(offset: 50, revision: current))).Response.Error?.Code == "localEvents.historyChanged",
                "same-ID content changes also invalidate revision");
        }
    }

    internal static async Task ClearIsolationAndWriteFailure()
    {
        using var f = new Fixture();
        f.Observe([Hud("已接受合约：本单", 0), End(8, "COMPLETED")]);
        using var journal = new LocalGameEventJournal(f.LegacyPath, () => Now);
        journal.Load(); journal.Append("life", "event", "原有事件"); await journal.FlushAsync();
        using var clear = new LocalEventClearDispatcher(journal, () => 2, f.History, () => Owner);
        var response = (await clear.DispatchAsync(BridgeEnvelope.Request(LocalEventClearDispatcher.RequestName,
            Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, confirmed = true }))).Response;
        Check(response.Status == "ok" && f.Reader.Read().Entries.Count == 0, "clear includes both journals");
        foreach (var path in new[] { f.LegacyPath, f.ContractPath })
        {
            Check(JsonDocument.Parse(File.ReadAllText(path)).RootElement.GetArrayLength() == 0 &&
                (!File.Exists(path + ".bak") || JsonDocument.Parse(File.ReadAllText(path + ".bak")).RootElement.GetArrayLength() == 0), "both primaries and backups empty");
        }
        f.Observe([End(8, "COMPLETED")]);
        Check(f.Reader.Read().Entries.Count == 0, "already processed outcome cannot resurrect after clear");
        var other = Owner with { Subject = "other-synthetic" };
        Check(f.History.DirectoryFor(other) != f.History.DirectoryFor(Owner), "account partition");
        var otherReader = new LocalEventJournalReader(f.Root, () => Now, () => f.History.DirectoryFor(other));
        Write(f.ContractPath, [Entry("owner-only", Now, "contract")]);
        Check(otherReader.Read().Entries.Count == 0, "other account never sees contract rows");
        using var failed = new Fixture();
        Directory.CreateDirectory(Path.GetDirectoryName(failed.ContractPath)!);
        File.WriteAllText(failed.ContractPath, "broken");
        failed.Observe(ContractAchievementTests.Lines().Select(l => l.Line.Replace(" ⏎ ", " ")));
        using var lease = new ContractAchievementStore(failed.Root).Open(Owner);
        Check(lease.Read().Runs.Single().Pending is not null && File.ReadAllText(failed.ContractPath) == "broken",
            "history storage failure does not change achievement observation or overwrite corruption");
    }

    private static BridgeEnvelope Request(string category = "all", int offset = 0, string? revision = null) =>
        BridgeEnvelope.Request(LocalEventHistoryBridgeDispatcher.RequestName, Guid.NewGuid().ToString("N"), 2,
            JsonSerializer.SerializeToElement(new { schemaVersion = 1, category, offset, pageSize = 50, revision }, Json));
    private sealed class Picker(string destination) : ILocalEventExportPicker
    {
        public Task<string?> ChooseNewTextFileAsync(string suggestedName, string locale, CancellationToken cancellation) =>
            Task.FromResult<string?>(destination);
    }
    private static string Stamp(int seconds) => $"<{Now.AddMinutes(-1).AddSeconds(-30 + seconds):O}> [Notice] ";
    private static string Hud(string text, int seconds, string objective = "") => Stamp(seconds) +
        $"<SHUDEvent_OnNotification> Added notification \"{text}: \" [58] to queue. New queue size: 1, MissionId: [{M}], ObjectiveId: [{objective}] [Team_CoreGameplayFeatures][Missions][Comms]";
    private static string Upsert(int seconds, string objective, string state) => Stamp(seconds) +
        $"<ObjectiveUpserted> Received ObjectiveUpserted push message for: mission_id {M} - objective_id {objective} - state MISSION_OBJECTIVE_STATE_{state} - created 0 - flags=ShowInLog|";
    private static string End(int seconds, string state) => Stamp(seconds) +
        $"<MissionEnded> Received MissionEnded push message for: mission_id {M} - mission_state MISSION_STATE_{state} [Team_GameServices][Missions]";
    private static LocalEventEntry Entry(string id, DateTimeOffset at, string category) => new(id, at, category, "SyntheticEvent", "title-" + id, "");
    private static void Write(string path, IEnumerable<LocalEventEntry> rows) => File.WriteAllText(path, JsonSerializer.Serialize(rows, Json));
    private static void Check(bool pass, string message) { if (!pass) throw new Exception(message); }
}
