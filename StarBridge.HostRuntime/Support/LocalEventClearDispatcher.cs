using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

// Borrows the single existing journal owner. Does not open its own store.
public sealed class LocalEventClearDispatcher(LocalGameEventJournal journal,
    Func<long> generation) : IBridgeRequestDispatcher
{
    public const string RequestName = "diagnostics.clearLocalEvents";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["diagnostics.localEventsClear"];
    private readonly CancellationTokenSource _lifetime = new();
    private int _disposed, _busy;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        bool acquired = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var p = request.Payload;
            if (request.Name != RequestName || request.MessageType != BridgeMessageTypes.Request || request.AccountContext != null ||
                p.ValueKind != JsonValueKind.Object || p.EnumerateObject().Count() != 2 ||
                !p.TryGetProperty("schemaVersion", out var v) || v.ValueKind != JsonValueKind.Number || !v.TryGetInt32(out var schema) || schema != 1 ||
                !p.TryGetProperty("confirmed", out var confirmed) || confirmed.ValueKind != JsonValueKind.True)
                return Error(request, "localEventsClear.invalid_request");
            bool Current() => Volatile.Read(ref _disposed) == 0 && generation() == request.SessionGeneration && journal.IsWritable;
            if (!Current()) return Error(request, "localEventsClear.unavailable");
            if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return Error(request, "localEventsClear.busy");
            acquired = true;
            using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetime.Token);
            var result = await journal.ClearAsync(Current, cancellation.Token);
            if (result == LocalJournalClearResult.Cancelled) return new(BridgeEnvelope.CancelledResponse(request), []);
            if (result != LocalJournalClearResult.Cleared) return Error(request, "localEventsClear.failed");
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, outcome = "cleared" },
                preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Error(request, "localEventsClear.failed"); }
        finally { if (acquired) Interlocked.Exchange(ref _busy, 0); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(
        BridgeEnvelope.ErrorResponse(request, new(code, "Local event history was not cleared.", true)), []);
    public void Dispose() { if (Interlocked.Exchange(ref _disposed, 1) == 0) _lifetime.Cancel(); }
}
