using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

public interface ILocalEventExportPicker
{
    Task<string?> ChooseNewTextFileAsync(string suggestedName, string locale, CancellationToken cancellation);
}

/// <summary>Exports the existing device journal, without owning or changing it.</summary>
public sealed class LocalEventExportDispatcher(LocalEventJournalReader reader, Func<long> generation,
    ILocalEventExportPicker picker, string protectedDataRoot, TimeProvider? time = null) : IBridgeRequestDispatcher
{
    public const string RequestName = "diagnostics.exportLocalEvents";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["diagnostics.localEventsExport"];
    private readonly LocalEventExportFileWriter _writer = new(protectedDataRoot);
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly CancellationTokenSource _lifetime = new();
    private int _busy, _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        var acquired = false;
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var p = request.Payload;
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.AccountContext is not null || p.ValueKind != JsonValueKind.Object ||
                p.EnumerateObject().Count() != 2 || !p.TryGetProperty("schemaVersion", out var version) ||
                version.ValueKind != JsonValueKind.Number || !version.TryGetInt32(out var schema) || schema != 1 ||
                !p.TryGetProperty("locale", out var locale) || locale.ValueKind != JsonValueKind.String ||
                locale.GetString() is not ("zh-CN" or "zh-TW" or "en"))
                return Error(request, "localEventsExport.invalid_request");
            bool Current() => Volatile.Read(ref _disposed) == 0 && generation() == request.SessionGeneration;
            if (!Current()) return Error(request, "localEventsExport.unavailable");
            if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0) return Error(request, "localEventsExport.busy");
            acquired = true;
            using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetime.Token);
            _ = Read(); // Do not prompt for missing, corrupt or empty history.
            cancellation.Token.ThrowIfCancellationRequested();
            if (!Current()) return Error(request, "localEventsExport.unavailable");
            var destination = await picker.ChooseNewTextFileAsync(
                $"StarBridge-Local-Events-{_time.GetUtcNow():yyyyMMdd-HHmmss}.txt", locale.GetString()!, cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            if (!Current()) return Error(request, "localEventsExport.unavailable");
            if (destination is null) return Result(request, "cancelled", 0, false);
            var snapshot = Read(); // Refresh after the picker: cleared/corrupt history is not resurrected.
            _writer.WriteNew(destination, LocalEventJournalReader.FormatExport(snapshot), Current, cancellation.Token);
            return Result(request, "saved", snapshot.Entries.Count, snapshot.State == "recovered");
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (LocalEventExportException e) { return Error(request, e.Code); }
        catch (BridgeProtocolException) { return Error(request, "localEventsExport.invalid_request"); }
        catch { return Error(request, "localEventsExport.save_failed"); }
        finally { if (acquired) Interlocked.Exchange(ref _busy, 0); }
    }

    private LocalEventJournalSnapshot Read()
    {
        var snapshot = reader.Read();
        if (!snapshot.Available) throw new LocalEventExportException("data_unavailable");
        if (snapshot.Entries.Count == 0) throw new LocalEventExportException("empty");
        return snapshot;
    }
    private static BridgeDispatchBatch Result(BridgeEnvelope request, string outcome, int count, bool recovered) =>
        new(BridgeEnvelope.Response(request, new { schemaVersion = 1, outcome, count, recovered },
            preserveRequestAccountContext: false), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) => new(
        BridgeEnvelope.ErrorResponse(request, new(code, "Local event history export did not complete.", true)), []);
    public void Dispose()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 0) _lifetime.Cancel();
        // Active operations retain linked registrations until the native dialog closes.
    }
}
