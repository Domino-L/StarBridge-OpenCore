using StarBridge.Core.Parsing;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static partial class LocalContractHistoryTests
{
    internal static async Task SourceAvailabilityReadAndExport()
    {
        foreach (var (events, contract, expectedState, sources, count) in new[]
        {
            ("ready", "bad", "ready", new[] { "contract" }, 1),
            ("bad", "ready", "ready", new[] { "events" }, 1),
            ("missing", "bad", "ready", new[] { "contract" }, 0),
            ("bad", "bad", "unavailable", new[] { "events", "contract" }, 0)
        })
        {
            using var f = new Fixture();
            Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
            void SetSource(string path, string state, string category)
            {
                if (state == "missing") return;
                if (state == "ready") Write(path, [Entry(category, Now, category)]);
                else { File.WriteAllText(path, "["); File.WriteAllText(path + ".bak", "broken"); }
            }
            SetSource(f.LegacyPath, events, "life"); SetSource(f.ContractPath, contract, "contract");
            var snapshot = f.Reader.Read();
            Check(snapshot.State == expectedState && snapshot.Entries.Count == count &&
                snapshot.UnavailableSources!.SequenceEqual(sources), "read keeps available rows and reports each bad source");
            using var bridge = new LocalEventHistoryBridgeDispatcher(f.Reader, () => 2);
            var page = (await bridge.DispatchAsync(Request())).Response.Payload;
            var revision = page.GetProperty("revision").GetString();
            Check(page.GetProperty("unavailableSources").EnumerateArray().Select(v => v.GetString()).SequenceEqual(sources) &&
                page.GetProperty("state").GetString() == expectedState && revision is { Length: 64 },
                "wire availability includes faults even with no readable rows");

            using var exportRoot = new Fixture();
            var destination = Path.Combine(exportRoot.Root, "export.txt");
            using var exporter = new LocalEventExportDispatcher(f.Reader, () => 2, new Picker(destination), f.Root);
            var receipt = (await exporter.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
                Guid.NewGuid().ToString("N"), 2, new { schemaVersion = 1, locale = "en" }))).Response;
            if (count > 0)
                Check(receipt.Status == "ok" && receipt.Payload.GetProperty("partial").GetBoolean() &&
                    receipt.Payload.GetProperty("unavailableSources").EnumerateArray().Select(v => v.GetString()).SequenceEqual(sources) &&
                    receipt.Payload.GetProperty("count").GetInt32() == count &&
                    File.ReadAllText(destination).Contains("title-" + (events == "ready" ? "life" : "contract")),
                    "partial export saves readable rows and reports omission");
            else Check(receipt.Error?.Code == (expectedState == "unavailable" ? "localEventsExport.data_unavailable" : "localEventsExport.empty") &&
                !File.Exists(destination), "no success or file for empty or wholly unavailable history");

            // Repair without changing the surviving rows: source recovery alone changes revision.
            if (events == "bad") Write(f.LegacyPath, []);
            if (contract == "bad") Write(f.ContractPath, []);
            var repaired = (await bridge.DispatchAsync(Request())).Response.Payload;
            Check(!repaired.TryGetProperty("unavailableSources", out _) &&
                repaired.GetProperty("revision").GetString() != revision, "recovery removes optional field and changes revision");
            Check((await bridge.DispatchAsync(Request(offset: 50, revision: revision))).Response.Error?.Code == "localEvents.historyChanged",
                "source recovery invalidates old page revision");
            if (contract == "bad") File.WriteAllText(f.ContractPath, "[");
            if (events == "bad") File.WriteAllText(f.LegacyPath, "[");
            Check((await bridge.DispatchAsync(Request())).Response.Payload.GetProperty("revision").GetString() == revision,
                "same fault state returns the same revision");
        }
    }

    internal static async Task BackgroundFaultRecovers()
    {
        using var f = new Fixture();
        var evidence = new RegexLogEventParser().TryParse(End(8, "COMPLETED"))!;
        var run = new ContractAchievementStore.Run(M, ContractAchievementTests.HandleHash, Guid.NewGuid());
        var calls = 0;
        bool Current() => Interlocked.Increment(ref calls) == 1 ? true : throw new InvalidOperationException("fixture background failure");
        f.History.Observe(Owner, evidence, run, Current);
        await f.History.FlushAsync().WaitAsync(TimeSpan.FromSeconds(5));
        Check(f.History.BackgroundFaultDiagnostics == 1 && f.History.LastWriteError is not null &&
            f.Reader.Read().Entries.Count == 0, "background fault is observed once and drops the batch");
        f.History.Observe(Owner, evidence, run, () => true);
        await f.History.FlushAsync().WaitAsync(TimeSpan.FromSeconds(5));
        Check(f.Reader.Read().Entries.Count == 1 && f.History.LastWriteError is null,
            "later admission restarts worker and faulted entries were never deduplicated");
        calls = 0;
        f.History.Observe(Owner, evidence with { Contract = evidence.Contract! with { MissionId = "fault-on-close" } }, run, Current);
        await f.History.DisposeAsync().AsTask().WaitAsync(TimeSpan.FromSeconds(5));
        Check(f.History.BackgroundFaultDiagnostics == 2, "Dispose observes a fresh background fault without rethrowing it");
    }

    internal static async Task PendingRetirementAndDispose()
    {
        foreach (var mode in new[] { "account-switch", "close", "dispose" })
        {
            using var f = new Fixture();
            var backoff = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var resume = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            f.History.RetryDelay = _ => { backoff.TrySetResult(); return resume.Task; };
            var current = true;
            var run = new ContractAchievementStore.Run(M, ContractAchievementTests.HandleHash, Guid.NewGuid());
            var evidence = new RegexLogEventParser().TryParse(End(8, "COMPLETED"))!;
            Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
            try
            {
                using (var lease = new FileStream(f.ContractPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
                {
                    f.History.Observe(Owner, evidence, run, () => Volatile.Read(ref current));
                    await backoff.Task.WaitAsync(TimeSpan.FromSeconds(5));
                    f.History.Observe(Owner, evidence with { Contract = evidence.Contract! with { MissionId = "queued" } },
                        run, () => Volatile.Read(ref current));
                    Check(f.History.PendingCount == 1, "retirement begins with both an in-flight batch and queued tail");
                }
                Volatile.Write(ref current, false); // The account graph retires its Current predicate first.
                var shutdown = mode == "account-switch" ? f.History.FlushAsync() :
                    mode == "close" ? Task.Run(f.History.Dispose) : f.History.DisposeAsync().AsTask();
                resume.TrySetResult();
                await shutdown.WaitAsync(TimeSpan.FromSeconds(5));
                Check(f.History.PendingCount == 0 && f.Reader.Read().Entries.Count == 0,
                    "retired queued tail is skipped without throw or hang: " + mode);
                if (mode == "account-switch")
                {
                    var nextOwner = Owner with { Subject = "next-synthetic" };
                    f.History.Observe(nextOwner, evidence, run, () => true);
                    await f.History.FlushAsync().WaitAsync(TimeSpan.FromSeconds(5));
                    Check(new LocalEventJournalReader(f.Root, () => Now, () => f.History.DirectoryFor(nextOwner)).Read().Entries.Count == 1,
                        "shared history remains writable for the next account");
                }
            }
            finally { resume.TrySetResult(); }
        }
    }

    internal static async Task ClearDuringBackoffPreventsRetryCommit()
    {
        using var f = new Fixture();
        var backoff = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var resume = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        f.History.RetryDelay = _ => { backoff.TrySetResult(); return resume.Task; };
        Directory.CreateDirectory(Path.GetDirectoryName(f.ContractPath)!);
        try
        {
            using (var lease = new FileStream(f.ContractPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            {
                f.Observe([End(8, "COMPLETED")], flush: false);
                await backoff.Task.WaitAsync(TimeSpan.FromSeconds(5));
            }
            Check(await f.History.ClearAsync(Owner, () => true, default) == LocalJournalClearResult.Cleared,
                "clear succeeds while retry is explicitly paused in backoff");
            var cleared = File.ReadAllBytes(f.ContractPath);
            resume.TrySetResult();
            await f.History.FlushAsync().WaitAsync(TimeSpan.FromSeconds(5));
            Check(cleared.SequenceEqual(File.ReadAllBytes(f.ContractPath)) && f.Reader.Read().Entries.Count == 0,
                "resumed retry neither writes nor resurrects the pre-clear entry");
        }
        finally { resume.TrySetResult(); }
    }
}
