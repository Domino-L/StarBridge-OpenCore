using System.Text.Json;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class LocalContractHistoryTests
{
    internal static Task ClearInvalidatesObjectiveText() => ClearInvalidatesObjectiveText(false);
    internal static Task ContinuationClearInvalidatesObjectiveText() => ClearInvalidatesObjectiveText(true);

    private static async Task ClearInvalidatesObjectiveText(bool continuationOnly)
    {
        // Historical runs exercise the independent display cache; live runs also retain
        // objective text in achievement state, which must not refill a cleared cache.
        foreach (var historical in new[] { true, false })
        {
            using var f = new Fixture();
            f.Observe([Hud("已接受合约：[发布方]清空前合约", 0)], live: !historical);
            f.Observe([Hud("新的任务：目标甲", 1, O)], continuationOnly: continuationOnly);
            string AchievementState()
            {
                using var lease = new ContractAchievementStore(f.Root).Open(Owner);
                return JsonSerializer.Serialize(lease.Read());
            }
            var before = AchievementState();
            Check(await f.History.ClearAsync(Owner, () => true, default) == LocalJournalClearResult.Cleared,
                "clear succeeds after live objective text");
            Check(AchievementState() == before, "clear leaves achievement state unchanged");
            f.Observe([Upsert(2, O, "COMPLETED")], continuationOnly: continuationOnly);
            Check(f.Reader.Read().Entries.Count == 0,
                "ID-only completion cannot reuse pre-clear objective text");
            if (historical)
            {
                using var lease = new ContractAchievementStore(f.Root).Open(Owner);
                var run = lease.Read().Runs.Single();
                Check(run.Historical && run.AcceptedAt is null && run.Pending is null && !run.Owner,
                    "historical run gains no achievement eligibility");
            }
            f.Observe([Hud("任务完成：清空后目标", 3, Guid.NewGuid().ToString())], continuationOnly: continuationOnly);
            Check(f.Reader.Read().Entries.Single().Title == "阶段目标完成：清空后目标",
                "new live text remains recordable after clear");
        }
    }

    internal static async Task MissingContractsPreserveUnavailableLegacyRead()
    {
        using var f = CorruptLegacyWithoutContracts();
        var legacy = new LocalEventJournalReader(f.Root, () => Now).Read();
        var snapshot = f.Reader.Read();
        Check(legacy.State == "unavailable" && snapshot.State == legacy.State &&
            snapshot.ContentRevision == legacy.ContentRevision && snapshot.Entries.SequenceEqual(legacy.Entries) &&
            snapshot.UnavailableSources is null, "missing contracts preserve unavailable legacy snapshot exactly");
        using var bridge = new LocalEventHistoryBridgeDispatcher(f.Reader, () => 2);
        using var legacyBridge = new LocalEventHistoryBridgeDispatcher(new(f.Root, () => Now), () => 2);
        var page = (await bridge.DispatchAsync(Request())).Response.Payload;
        var legacyPage = (await legacyBridge.DispatchAsync(Request())).Response.Payload;
        Check(page.GetRawText() == legacyPage.GetRawText() && !page.TryGetProperty("unavailableSources", out _),
            "legacy-only unavailable wire response is unchanged");
        Check(!File.Exists(f.ContractPath) && !File.Exists(f.ContractPath + ".bak"), "read creates no contract source");
    }

    internal static async Task MissingContractsPreserveUnavailableLegacyExport()
    {
        using var f = CorruptLegacyWithoutContracts();
        using var exportRoot = new Fixture();
        var picker = new CountingPicker(Path.Combine(exportRoot.Root, "events.txt"));
        using var exporter = new LocalEventExportDispatcher(f.Reader, () => 2, picker, f.Root);
        var receipt = (await exporter.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
            Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, locale = "zh-CN" }))).Response;
        Check(receipt.Error?.Code == "localEventsExport.data_unavailable" && picker.Calls == 0 &&
            !File.Exists(picker.Destination) && !receipt.Payload.TryGetProperty("unavailableSources", out _),
            "unavailable legacy export retains its error without prompting or source fields");
    }

    private static Fixture CorruptLegacyWithoutContracts()
    {
        var f = new Fixture();
        File.WriteAllText(f.LegacyPath, "[");
        File.WriteAllText(f.LegacyPath + ".bak", "broken");
        return f;
    }

    private sealed class CountingPicker(string destination) : ILocalEventExportPicker
    {
        internal string Destination => destination;
        internal int Calls { get; private set; }
        public Task<string?> ChooseNewTextFileAsync(string suggestedName, string locale, CancellationToken cancellation)
        {
            Calls++;
            return Task.FromResult<string?>(destination);
        }
    }
}
