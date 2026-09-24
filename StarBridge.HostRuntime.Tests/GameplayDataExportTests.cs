using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class GameplayDataExportTests
{
    internal static async Task ExportsOnlyWhitelistedCurrentStatistics()
    {
        using var fixture = new Fixture();
        fixture.AfterPick = () => fixture.Seconds = 180;
        var result = await fixture.Dispatch();
        Check(result.Response.Status == "ok", "success");
        Check(result.Response.Payload.GetProperty("outcome").GetString() == "saved", "saved");
        using var document = JsonDocument.Parse(File.ReadAllText(fixture.Destination));
        var data = document.RootElement;
        Check(data.GetProperty("totalSeconds").GetInt64() == 180, "read fresh after picker");
        Check(data.EnumerateObject().Count() == 8, "export whitelist");
        Check(!data.GetRawText().Contains("secret") && !data.GetRawText().Contains("ownerHash"), "no extra fields");
        Check(!result.Response.Payload.GetRawText().Contains(fixture.Root), "no paths in response");
        Check(fixture.Reads == 2, "uses existing read projection twice");
    }

    internal static async Task CancellationAndAccountSwitchWriteNothing()
    {
        using var cancelled = new Fixture { CancelPicker = true };
        var result = await cancelled.Dispatch();
        Check(result.Response.Payload.GetProperty("outcome").GetString() == "cancelled", "picker cancellation");
        Check(!File.Exists(cancelled.Destination), "cancel writes nothing");
        using var switched = new Fixture();
        switched.AfterPick = () => switched.Generation++;
        var changed = await switched.Dispatch();
        Check(changed.Response.Error?.Code == "gameplayExport.account_changed", "switch rejected");
        Check(!File.Exists(switched.Destination), "switch writes nothing");
    }

    internal static async Task InvalidDataDoesNotOpenPicker()
    {
        using var fixture = new Fixture { ReadError = true };
        var result = await fixture.Dispatch();
        Check(result.Response.Error?.Code == "gameplayExport.data_unavailable", "read error");
        Check(fixture.PickerCalls == 0, "no picker");
        fixture.ReadError = false;
        fixture.Seconds = -1;
        result = await fixture.Dispatch();
        Check(result.Response.Error?.Code == "gameplayExport.data_unavailable", "negative total");
        Check(fixture.PickerCalls == 0, "no picker for invalid stats");
    }

    internal static async Task ExistingFilesAndOwnedStorageAreProtected()
    {
        using var fixture = new Fixture();
        File.WriteAllText(fixture.Destination, "keep existing file");
        var exists = await fixture.Dispatch();
        Check(exists.Response.Error?.Code == "gameplayExport.file_exists", "existing file");
        Check(File.ReadAllText(fixture.Destination) == "keep existing file", "no overwrite");
        fixture.Destination = Path.Combine(fixture.DataRoot, "export.json");
        var protectedResult = await fixture.Dispatch();
        Check(protectedResult.Response.Error?.Code == "gameplayExport.invalid_destination", "owned root protected");
        Check(!File.Exists(fixture.Destination), "owned root untouched");
        fixture.Destination = Path.Combine(fixture.Root, "output.txt");
        var wrongExtension = await fixture.Dispatch();
        Check(wrongExtension.Response.Error?.Code == "gameplayExport.invalid_destination", "json only");
    }

    internal static async Task DuplicateRequestsDoNotOpenAnotherPicker()
    {
        using var fixture = new Fixture { HoldPicker = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        var first = fixture.Dispatch().AsTask();
        await fixture.PickerStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var second = await fixture.Dispatch();
        Check(second.Response.Error?.Code == "gameplayExport.busy", "duplicate rejected");
        Check(fixture.PickerCalls == 1, "one dialog");
        fixture.HoldPicker.SetResult(null);
        await first;
    }

    internal static async Task CancellationTokenStopsBeforeWrite()
    {
        using var fixture = new Fixture { HoldPicker = new(TaskCreationOptions.RunContinuationsAsynchronously) };
        using var cancellation = new CancellationTokenSource();
        var task = fixture.Dispatch(cancellation.Token).AsTask();
        await fixture.PickerStarted.Task.WaitAsync(TimeSpan.FromSeconds(3));
        cancellation.Cancel();
        var result = await task;
        Check(result.Response.Status == BridgeResponseStatuses.Cancelled, "cancel status");
        Check(!File.Exists(fixture.Destination), "cancel no output");
    }

    internal static async Task RequestRequiresCurrentAccountAndNoInjectedData()
    {
        using var fixture = new Fixture();
        Check(BridgeRequestPolicy.RequiresAccountContext(GameplayDataExportDispatcher.RequestName), "account required");
        var unsigned = await fixture.Dispatcher.DispatchAsync(BridgeEnvelope.Request(
            GameplayDataExportDispatcher.RequestName, "unsigned", 2, new { schemaVersion = 1, locale = "en" }));
        Check(unsigned.Response.Error?.Code == "gameplayExport.account_changed", "signed out rejected");
        var injected = await fixture.Dispatcher.DispatchAsync(BridgeEnvelope.Request(
            GameplayDataExportDispatcher.RequestName, "injected", 2,
            new { schemaVersion = 1, locale = "en", path = fixture.Destination }, Fixture.Owner));
        Check(injected.Response.Error?.Code == "gameplayExport.invalid_request", "caller cannot choose arbitrary path");
        Check(fixture.PickerCalls == 0, "invalid requests no dialog");
    }

    internal static void FailedCommitCleansTemporaryFile()
    {
        using var fixture = new Fixture();
        var writer = new GameplayExportFileWriter(fixture.DataRoot);
        var calls = 0;
        try
        {
            writer.WriteNew(fixture.Destination,
                new(1, DateTimeOffset.UtcNow, "declined", 100, 100, 0, null, false),
                () => ++calls == 1, CancellationToken.None);
            throw new Exception("Expected account guard failure.");
        }
        catch (GameplayExportException e) { Check(e.Code == "gameplayExport.account_changed", "commit guard"); }
        Check(!File.Exists(fixture.Destination), "no published file");
        Check(!Directory.EnumerateFiles(fixture.Root).Any(), "own temporary file removed");
    }

    private static void Check(bool value, string label)
    { if (!value) throw new InvalidOperationException(label); }

    private sealed class Fixture : IDisposable, IGameplayExportPicker
    {
        internal static readonly BridgeAccountContext Owner = new("test", "local", "fixture");
        internal readonly string Root = Path.Combine(Path.GetTempPath(), "starbridge-export-test-" + Guid.NewGuid().ToString("N"));
        internal readonly string DataRoot;
        internal string Destination;
        internal long Generation = 2;
        internal long Seconds = 120;
        internal bool CancelPicker;
        internal bool ReadError;
        internal int PickerCalls;
        internal int Reads;
        internal Action? AfterPick;
        internal TaskCompletionSource<string?>? HoldPicker;
        internal readonly TaskCompletionSource PickerStarted = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly GameplayDataExportDispatcher Dispatcher;

        internal Fixture()
        {
            DataRoot = Path.Combine(Root, "app-data");
            Directory.CreateDirectory(DataRoot);
            Destination = Path.Combine(Root, "gameplay.json");
            Dispatcher = new(Read, () => (Owner, Generation), this, DataRoot);
        }
        internal ValueTask<BridgeDispatchBatch> Dispatch(CancellationToken cancellation = default) =>
            Dispatcher.DispatchAsync(BridgeEnvelope.Request(GameplayDataExportDispatcher.RequestName,
                Guid.NewGuid().ToString("N"), Generation, new { schemaVersion = 1, locale = "en" }, Owner), cancellation);
        private BridgeDispatchBatch Read(BridgeEnvelope request, CancellationToken cancellation)
        {
            Reads++;
            Check(request.Name == "gameplayTime.read" && request.AccountContext == Owner, "existing owner read");
            return new(BridgeEnvelope.Response(request, new
            {
                schemaVersion = 1, consent = "declined", seconds = Seconds, savedSeconds = 100L,
                historicalSeconds = 0L, historyImportedAt = (DateTimeOffset?)null, showOnProfile = false,
                error = ReadError ? "storage_failed" : null, ownerHash = "secret", importReceipt = "secret", token = "secret"
            }), []);
        }
        public async Task<string?> ChooseNewJsonFileAsync(string suggestedName, string locale, CancellationToken cancellation)
        {
            PickerCalls++;
            PickerStarted.TrySetResult();
            if (HoldPicker is not null) return await HoldPicker.Task.WaitAsync(cancellation);
            AfterPick?.Invoke();
            return CancelPicker ? null : Destination;
        }
        public void Dispose()
        {
            Dispatcher.Dispose();
            Directory.Delete(Root, recursive: true);
        }
    }
}
