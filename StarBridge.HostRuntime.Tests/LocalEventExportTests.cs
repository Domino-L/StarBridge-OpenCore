using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class LocalEventExportTests
{
    internal static async Task CompositeAndAccountlessPolicy()
    {
        using var f = new Fixture { CancelPicker = true };
        Check(!BridgeRequestPolicy.RequiresAccountContext(LocalEventExportDispatcher.RequestName), "device allowlist");
        var other = new UnusedDispatcher();
        using var composite = new CompositeBridgeDispatcher(other, other, other, localEventExport: f.Dispatcher);
        var request = BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName, "route", f.Generation,
            new { schemaVersion = 1, locale = "en" });
        Check((await composite.DispatchAsync(request)).Response.Status == "ok", "exact route");
        Check((await composite.DispatchAsync(request with { Name = "diagnostics.exportOther" })).Response.Status == "error", "no broad export route");
        composite.Dispose();
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.unavailable", "lifetime disposed");
    }

    internal static async Task ExportsFreshCompleteHistoryWithBom()
    {
        using var f = new Fixture();
        f.AfterPick = () => f.Seed(125);
        var result = await f.Export();
        Check(result.Response.Status == "ok" && result.Response.Payload.GetProperty("count").GetInt32() == 125, "all pages");
        var bytes = File.ReadAllBytes(f.Destination);
        Check(bytes.AsSpan().StartsWith(Encoding.UTF8.GetPreamble()), "UTF8 BOM");
        var text = File.ReadAllText(f.Destination);
        Check(text.Contains("Title 0") && text.Contains("Title 124"), "complete retained history");
        Check(text.IndexOf("Title 124", StringComparison.Ordinal) < text.IndexOf("Title 0", StringComparison.Ordinal), "chronological order");
        Check(!result.Response.Payload.GetRawText().Contains(f.Root), "no exported path");
        Check(result.Response.Payload.EnumerateObject().Count() == 4, "small response whitelist");
        Check(f.PickerCalls == 1, "one picker");
        Check(File.ReadAllBytes(f.Journal).SequenceEqual(f.LastSeed), "source unchanged");
    }

    internal static async Task MissingEmptyCorruptAndBackup()
    {
        using var f = new Fixture();
        File.Delete(f.Journal);
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.empty", "missing");
        f.Seed(0);
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.empty", "valid empty");
        File.WriteAllText(f.Journal, "bad");
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.data_unavailable", "corrupt");
        Check(f.PickerCalls == 0, "no picker without readable records");
        f.Seed(2);
        File.Move(f.Journal, f.Journal + ".bak");
        File.WriteAllText(f.Journal, "bad");
        var result = await f.Export();
        Check(result.Response.Payload.GetProperty("recovered").GetBoolean(), "backup outcome explicit");
        Check(File.ReadAllText(f.Journal) == "bad", "primary not restored");
        Check(File.ReadAllBytes(f.Journal + ".bak").SequenceEqual(f.LastSeed), "backup unchanged");
    }

    internal static async Task CancelSwitchAndChangedSourceWriteNothing()
    {
        using var cancelled = new Fixture { CancelPicker = true };
        Check((await cancelled.Export()).Response.Payload.GetProperty("outcome").GetString() == "cancelled", "cancel outcome");
        Check(!File.Exists(cancelled.Destination), "no cancelled file");
        using var switched = new Fixture();
        switched.AfterPick = () => switched.Generation++;
        Check((await switched.Export()).Response.Error?.Code == "localEventsExport.unavailable", "stale generation");
        Check(!File.Exists(switched.Destination), "no stale file");
        using var cleared = new Fixture();
        cleared.AfterPick = () => cleared.Seed(0);
        Check((await cleared.Export()).Response.Error?.Code == "localEventsExport.empty", "cleared during picker");
        Check(!File.Exists(cleared.Destination), "no resurrection");
        using var corrupt = new Fixture();
        corrupt.AfterPick = () => File.WriteAllText(corrupt.Journal, "bad");
        Check((await corrupt.Export()).Response.Error?.Code == "localEventsExport.data_unavailable", "corrupted during picker");
        Check(!File.Exists(corrupt.Destination), "no old snapshot saved");
    }

    internal static async Task DestinationProtectionAndFailedCommit()
    {
        using var f = new Fixture();
        File.WriteAllText(f.Destination, "keep");
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.file_exists", "existing");
        Check(File.ReadAllText(f.Destination) == "keep", "not overwritten");
        foreach (var path in new[] { Path.Combine(f.DataRoot, "out.txt"), Path.Combine(f.Root, "out.json"),
                     Path.Combine(f.Root, "missing", "out.txt"), Path.Combine(f.Root, "stream:out.txt"), "relative.txt" })
        {
            f.Destination = path;
            Check((await f.Export()).Response.Error?.Code == "localEventsExport.invalid_destination", "invalid destination");
        }
        var destination = Path.Combine(f.Root, "guarded.txt");
        int guards = 0;
        try
        {
            new LocalEventExportFileWriter(f.DataRoot).WriteNew(destination, "text", () => ++guards == 1, CancellationToken.None);
            throw new Exception("Expected commit guard failure");
        }
        catch (LocalEventExportException e) { Check(e.Code == "localEventsExport.unavailable", "commit guard"); }
        Check(!File.Exists(destination) && !Directory.EnumerateFiles(f.Root, "*.tmp").Any(), "failed temp cleaned");
    }

    internal static async Task BusyCancellationAndDispose()
    {
        using var f = new Fixture { Pending = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var cancellation = new CancellationTokenSource();
        var pending = f.Export(cancellation.Token).AsTask();
        await f.Started.Task.WaitAsync(TimeSpan.FromSeconds(3));
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.busy", "duplicate blocked");
        Check(f.PickerCalls == 1, "one native picker");
        cancellation.Cancel();
        Check((await pending).Response.Status == BridgeResponseStatuses.Cancelled, "cancellation");
        Check(!File.Exists(f.Destination), "no file after cancellation");
        var disposed = f.Export().AsTask();
        f.Dispatcher.Dispose();
        Check((await disposed).Response.Status == BridgeResponseStatuses.Cancelled, "dispose cancels picker");
        Check((await f.Export()).Response.Error?.Code == "localEventsExport.unavailable", "disposed cannot reopen");
    }

    internal static async Task StrictDeviceScopeAndCancelledRequests()
    {
        using var f = new Fixture();
        foreach (var payload in new object[] { new { schemaVersion = 1, locale = "en", path = f.Destination },
                     new { schemaVersion = 1, locale = "en", category = "life" }, new { schemaVersion = 2, locale = "en" },
                     new { schemaVersion = 1, locale = "unknown" } })
            Check((await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
                "invalid", f.Generation, payload))).Response.Error?.Code == "localEventsExport.invalid_request", "strict payload");
        var scoped = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName,
            "account", f.Generation, new { schemaVersion = 1, locale = "en" }, new("test", "local", "fixture")));
        Check(scoped.Response.Error?.Code == "localEventsExport.invalid_request", "device scope only");
        using var cancellation = new CancellationTokenSource();
        cancellation.Cancel();
        Check((await f.Export(cancellation.Token)).Response.Status == BridgeResponseStatuses.Cancelled, "pre-cancelled");
        Check(f.PickerCalls == 0, "invalid never opens picker");
    }

    private static void Check(bool condition, string label)
    { if (!condition) throw new InvalidOperationException(label); }
    private sealed class UnusedDispatcher : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Unrelated dispatcher must not handle local export.");
        public void Dispose() { }
    }
    private sealed class Fixture : IDisposable, ILocalEventExportPicker
    {
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-events-export-test-" + Guid.NewGuid().ToString("N"));
        internal readonly string DataRoot, Journal;
        internal string Destination;
        internal byte[] LastSeed = [];
        internal long Generation = 2;
        internal int PickerCalls;
        internal bool CancelPicker;
        internal Action? AfterPick;
        internal TaskCompletionSource<string?>? Pending;
        internal readonly TaskCompletionSource Started = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly LocalEventExportDispatcher Dispatcher;
        internal Fixture()
        {
            DataRoot = Path.Combine(Root, "app-data");
            Directory.CreateDirectory(DataRoot);
            Journal = Path.Combine(DataRoot, "local-event-log.json");
            Destination = Path.Combine(Root, "events.txt");
            Seed(2);
            Dispatcher = new(new(DataRoot), () => Generation, this, DataRoot);
        }
        internal void Seed(int count)
        {
            var now = DateTimeOffset.UtcNow;
            var entries = Enumerable.Range(0, count).Select(i => new LocalEventEntry("event-" + i,
                now.AddSeconds(-i), i % 2 == 0 ? "session" : "life", "test", "Title " + i, "Detail")).ToArray();
            LastSeed = JsonSerializer.SerializeToUtf8Bytes(entries, new JsonSerializerOptions(JsonSerializerDefaults.Web));
            File.WriteAllBytes(Journal, LastSeed);
        }
        internal ValueTask<BridgeDispatchBatch> Export(CancellationToken cancellation = default) => Dispatcher.DispatchAsync(
            BridgeEnvelope.Request(LocalEventExportDispatcher.RequestName, Guid.NewGuid().ToString("N"), Generation,
                new { schemaVersion = 1, locale = "zh-CN" }), cancellation);
        public async Task<string?> ChooseNewTextFileAsync(string suggestedName, string locale, CancellationToken cancellation)
        {
            Check(suggestedName.StartsWith("StarBridge-Local-Events-") && suggestedName.EndsWith(".txt"), "filename");
            PickerCalls++;
            Started.TrySetResult();
            if (Pending is not null) return await Pending.Task.WaitAsync(cancellation);
            AfterPick?.Invoke();
            return CancelPicker ? null : Destination;
        }
        public void Dispose() { Dispatcher.Dispose(); Directory.Delete(Root, recursive: true); }
    }
}
