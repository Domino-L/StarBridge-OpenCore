using StarBridge.Core.Events;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class LocalContractHistoryTests
{
    internal static Task HistoricalAcceptanceLiveEvidence()
    {
        foreach (var continuationOnly in new[] { false, true })
        foreach (var outcome in new[] { "COMPLETED", "FAILED", "ABANDONED", "WITHDRAWN" })
        {
            using var f = new Fixture();
            f.Observe([Hud("已接受合约：[发布方]启动前合约", 0)], live: false);
            Check(f.Reader.Read().Entries.Count == 0, "historical acceptance is presentation only");
            f.Observe([Hud("新的任务：目标甲", 1, O)], continuationOnly: continuationOnly);
            f.Observe([Upsert(2, O, "COMPLETED")], continuationOnly: continuationOnly);
            Check(f.Reader.Read().Entries.Single().Title == "阶段目标完成：目标甲",
                "historical acceptance retains live objective text for ID-only completion");
            f.Observe([Hud("任务完成：实时阶段", 3, Guid.NewGuid().ToString()), End(8, outcome)], continuationOnly: continuationOnly);
            var rows = f.Reader.Read().Entries;
            Check(rows.Count == 3 && rows.Any(e => e.Title == "阶段目标完成：实时阶段" && e.Detail == "启动前合约"),
                "historical run admits live stage: " + outcome);
            var end = rows.Single(e => e.EventType == nameof(FleetEventType.ContractEnded));
            Check(end.Title.EndsWith("启动前合约") && !end.Detail.Contains("接单到完成"), "no historical duration");
            if (outcome == "COMPLETED") Check(end.Detail == "发布方", "historical issuer for display");
            using var lease = new ContractAchievementStore(f.Root).Open(Owner);
            var run = lease.Read().Runs.Single();
            Check(run.Historical && run.AcceptedAt is null && run.Pending is null && !run.Owner,
                "achievement eligibility is unchanged");
        }
        return Task.CompletedTask;
    }

    internal static async Task CorruptContractsDoNotBlockLegacy()
    {
        using var f = new Fixture();
        using var journal = new LocalGameEventJournal(f.LegacyPath, () => Now);
        journal.Load(); journal.Append("life", "event", "仍可使用的旧日志"); await journal.FlushAsync();
        var legacy = new LocalEventJournalReader(f.Root, () => Now).Read();
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        File.WriteAllText(f.ContractPath, "["); File.WriteAllText(f.ContractPath + ".bak", "broken");
        var snapshot = f.Reader.Read();
        Check(snapshot.State == legacy.State && snapshot.ContentRevision != legacy.ContentRevision &&
            snapshot.Entries.SequenceEqual(legacy.Entries), "broken contract sources preserve rows but change revision");
        using var export = new Fixture();
        var destination = Path.Combine(export.Root, "export.txt");
        using var exporter = new LocalEventExportDispatcher(f.Reader, () => 2, new Picker(destination), f.Root);
        var exported = (await exporter.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
            Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, locale = "zh-CN" }))).Response;
        Check(exported.Status == "ok" && exported.Payload.GetProperty("count").GetInt32() == 1 &&
            File.ReadAllText(destination).Contains("仍可使用的旧日志"), "export available legacy source");
        using var clear = new LocalEventClearDispatcher(journal, () => 2, f.History, () => Owner);
        var cleared = (await clear.DispatchAsync(BridgeEnvelope.Request(LocalEventClearDispatcher.RequestName,
            Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, confirmed = true }))).Response;
        Check(cleared.Status == "ok" && f.Reader.Read().Entries.Count == 0 &&
            File.ReadAllText(f.ContractPath).Trim() == "[]" && !File.Exists(f.ContractPath + ".bak"),
            "clear replaces corrupt contracts under lease and clears legacy");
    }
    private static async Task Until(Func<bool> condition)
    {
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(5));
        while (!condition()) await Task.Delay(10, timeout.Token);
    }

    internal static async Task LeaseRetryAndNonBlockingObserve()
    {
        using var f = new Fixture();
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        using (var lease = new FileStream(f.ContractPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            var observed = Task.Run(() => f.Observe([Hud("已接受合约：等待租约", 0), End(8, "COMPLETED")], flush: false));
            await observed.WaitAsync(TimeSpan.FromSeconds(2));
            // Observe returned while disk was still unavailable: no synchronous file/flush on this caller.
            await Until(() => f.History.RetryCount > 0);
            Check(!File.Exists(f.ContractPath), "held lease prevents disk commit, not Observe return");
        }
        await f.History.FlushAsync();
        Check(f.Reader.Read().Entries.Count == 2, "retry commits both events after tracker already advanced");
        f.Observe([End(8, "COMPLETED")]);
        Check(f.Reader.Read().Entries.Count == 2, "retry success remains deduplicated");
    }

    internal static async Task ClearBarrierAndScope()
    {
        using var f = new Fixture();
        var parser = new StarBridge.Core.Parsing.RegexLogEventParser();
        var batch = new[] { Hud("已接受合约：旧批次", 0), End(8, "COMPLETED") }
            .Select(parser.TryParse).OfType<FleetEvent>().Select(e => (e, true)).ToArray();
        var revision = f.History.ClearRevision; // Capture at read, before submitting to the tracker.
        Check(await f.History.ClearAsync(Owner, () => true, default) == LocalJournalClearResult.Cleared, "clear before submit");
        f.Tracker.Observe(Owner, ContractAchievementTests.HandleHash, batch, () => true, true, historyRevision: revision);
        await f.History.FlushAsync();
        Check(f.Reader.Read().Entries.Count == 0, "pre-clear read batch never resurrects after successful clear");
        f.Observe([End(8, "FAILED").Replace(M, Guid.NewGuid().ToString())]);
        Check(f.Reader.Read().Entries.Count == 1, "new-generation evidence is admitted");
        using var cancellation = new CancellationTokenSource(); cancellation.Cancel();
        var before = File.ReadAllBytes(f.ContractPath);
        Check(await f.History.ClearAsync(Owner, () => true, cancellation.Token) == LocalJournalClearResult.Cancelled,
            "cancelled clear retains history");
        Check(await f.History.ClearAsync(Owner, () => false, default) != LocalJournalClearResult.Cleared &&
            before.SequenceEqual(File.ReadAllBytes(f.ContractPath)), "stale account cannot clear");
        // Also cover a queued/in-flight retry invalidated by clear, using the same production owner.
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        using (var lease = new FileStream(f.ContractPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            f.Observe([End(8, "FAILED").Replace(M, Guid.NewGuid().ToString())], flush: false);
            await Until(() => f.History.RetryCount > 0);
        }
        Check(await f.History.ClearAsync(Owner, () => true, default) == LocalJournalClearResult.Cleared, "clear racing retry");
        await f.History.FlushAsync();
        Check(f.Reader.Read().Entries.Count == 0, "queued pre-clear retry cannot write back");
    }

    internal static async Task QueueBoundAndUncommittedDedup()
    {
        using var f = new Fixture();
        var parser = new StarBridge.Core.Parsing.RegexLogEventParser();
        var evidence = parser.TryParse(End(8, "COMPLETED"))!;
        var run = new ContractAchievementStore.Run(M, ContractAchievementTests.HandleHash, Guid.NewGuid());
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        using (var lease = new FileStream(f.ContractPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            f.History.Observe(Owner, evidence, run, () => true);
            await Until(() => f.History.RetryCount > 0);
            for (var i = 0; i < 300; i++)
            {
                var next = evidence with { Contract = evidence.Contract! with { MissionId = Guid.NewGuid().ToString() } };
                f.History.Observe(Owner, next, run, () => true);
            }
            Check(f.History.PendingCount == 256 && f.History.OverflowDiagnostics == 1,
                "bounded FIFO drops oldest and diagnoses overflow once");
            // Exhaust bounded retries with the original evidence still uncommitted.
            await f.History.FlushAsync().WaitAsync(TimeSpan.FromSeconds(15));
            Check(f.History.LastWriteError is not null, "exhausted storage retries report failure");
        }
        f.History.Observe(Owner, evidence, run, () => true);
        await f.History.FlushAsync();
        Check(f.Reader.Read().Entries.Count == 1, "failed entries do not enter seen; same evidence can retry");
    }

    internal static Task HistoryFaultsPreserveAuthority()
    {
        foreach (var live in new[] { false, true })
        foreach (var error in new Exception[] { new IOException(), new OperationCanceledException(), new InvalidOperationException() })
        {
            using var f = new Fixture();
            using var diagnostics = StarBridge.HostRuntime.Support.IdentityGateJournal.Capture((_, _) => { });
            var parser = new StarBridge.Core.Parsing.RegexLogEventParser();
            var evidence = parser.TryParse(Hud("已接受合约：异常边界", 0))!;
            f.History.BeforeObserve = () => throw error;
            f.Tracker.Observe(Owner, ContractAchievementTests.HandleHash, [(evidence, live)], () => true, true);
            // A failure from the actual authority predicate is not display IO.
            // It must still abort the transaction, including IOException.
            using var guarded = new Fixture();
            var calls = 0;
            Exception? caught = null;
            bool Current() { if (++calls == 2) throw error; return true; }
            try { guarded.Tracker.Observe(Owner, ContractAchievementTests.HandleHash, [(evidence, live)], Current, true); }
            catch (Exception actual) { caught = actual; }
            Check(ReferenceEquals(error, caught), "History isolation must not swallow authority/cancellation predicate failures.");
        }
        return Task.CompletedTask;
    }}
