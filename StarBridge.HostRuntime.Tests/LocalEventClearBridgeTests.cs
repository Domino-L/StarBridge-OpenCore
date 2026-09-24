using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class LocalEventClearBridgeTests
{
    internal static async Task ExactScopeConfirmationAndSharedOwner()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-clear-bridge-").FullName;
        try
        {
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"));
            journal.Load();
            journal.Append("ship", "enter", "keep");
            await journal.FlushAsync();
            using var clear = new LocalEventClearDispatcher(journal, () => 2);
            foreach (var payload in new object[] { new { schemaVersion = 1, confirmed = false },
                new { schemaVersion = 1, confirmed = true, path = "injected" }, new { schemaVersion = "1", confirmed = true } })
                Check((await clear.DispatchAsync(Request(payload))).Response.Error?.Code == "localEventsClear.invalid_request", "strict request");
            Check((await clear.DispatchAsync(Request() with { AccountContext = new("test", "local", "fixture") })).Response.Error?.Code == "localEventsClear.invalid_request", "no account");
            Check((await clear.DispatchAsync(Request() with { SessionGeneration = 1 })).Response.Error?.Code == "localEventsClear.unavailable", "stale");
            Check(journal.Entries.Length == 1, "invalid never clears");
            Check(!BridgeRequestPolicy.RequiresAccountContext(LocalEventClearDispatcher.RequestName), "allowlist");
            var other = new Unused();
            using var router = new CompositeBridgeDispatcher(other, other, other, localEventClear: clear);
            var result = await router.DispatchAsync(Request());
            Check(result.Response.Payload.GetProperty("outcome").GetString() == "cleared", "explicit receipt");
            Check(new LocalEventJournalReader(root).Read().Entries.Count == 0, "actual disk changed");
            Check(journal.IsWritable, "borrowed owner remains alive");
            router.Dispose();
            Check(journal.IsWritable, "dispatcher does not dispose borrowed owner");
        }
        finally { Directory.Delete(root, true); }
    }
    internal static async Task CancellationAndDisposedAreNotSuccess()
    {
        var root = Directory.CreateTempSubdirectory("starbridge-clear-cancel-").FullName;
        try
        {
            using var journal = new LocalGameEventJournal(Path.Combine(root, "local-event-log.json"));
            journal.Load();
            journal.Append("ship", "enter", "keep");
            await journal.FlushAsync();
            using var clear = new LocalEventClearDispatcher(journal, () => 2);
            using var cts = new CancellationTokenSource();
            cts.Cancel();
            Check((await clear.DispatchAsync(Request(), cts.Token)).Response.Status == BridgeResponseStatuses.Cancelled, "cancelled");
            clear.Dispose();
            Check((await clear.DispatchAsync(Request())).Response.Status == "error", "disposed");
            Check(journal.Entries.Length == 1, "data remains");
        }
        finally { Directory.Delete(root, true); }
    }
    private static BridgeEnvelope Request(object? payload = null) => BridgeEnvelope.Request(
        LocalEventClearDispatcher.RequestName, Guid.NewGuid().ToString("N"), 2, payload ?? new { schemaVersion = 1, confirmed = true });
    private static void Check(bool value, string label) { if (!value) throw new InvalidOperationException(label); }
    private sealed class Unused : IBridgeRequestDispatcher
    {
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default) =>
            throw new InvalidOperationException("Unrelated dispatcher invoked");
        public void Dispose() { }
    }
}
