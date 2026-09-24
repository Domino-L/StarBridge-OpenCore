using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Support;

/// <summary>Exports the current gameplay owner's read projection; owns no statistics store.</summary>
public sealed class GameplayDataExportDispatcher(
    Func<BridgeEnvelope, CancellationToken, BridgeDispatchBatch> readGameplay,
    Func<(BridgeAccountContext? Context, long Generation)> current,
    IGameplayExportPicker picker,
    string protectedDataRoot,
    TimeProvider? time = null) : IBridgeRequestDispatcher
{
    public const string RequestName = "gameplayTime.export";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["gameplayTime.export"];
    private readonly GameplayExportFileWriter _writer = new(protectedDataRoot);
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly object _pendingLock = new();
    private CancellationTokenSource? _pending;
    private int _busy;
    private bool _disposed;

    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        bool acquired = false;
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var body = request.Payload;
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                body.ValueKind != JsonValueKind.Object || body.EnumerateObject().Count() != 2 ||
                body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "locale")) ||
                body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.GetProperty("locale").GetString() is not ("zh-CN" or "zh-TW" or "en"))
                return Error(request, "gameplayExport.invalid_request");
            var owner = (request.AccountContext, request.SessionGeneration);
            bool Current() => !_disposed && owner.AccountContext is { IsComplete: true } && current() == owner;
            if (!Current()) return Error(request, "gameplayExport.account_changed");
            if (Interlocked.CompareExchange(ref _busy, 1, 0) != 0)
                return Error(request, "gameplayExport.busy");
            acquired = true;
            using var cancellation = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetime.Token);
            lock (_pendingLock) _pending = cancellation;
            cancellation.Token.ThrowIfCancellationRequested();
            _ = ReadSnapshot(request, cancellation.Token); // Do not show a picker for unreadable data.
            if (!Current()) return Error(request, "gameplayExport.account_changed");
            var destination = await picker.ChooseNewJsonFileAsync(
                $"StarBridge-gameplay-{_time.GetUtcNow():yyyyMMdd-HHmmss}.json",
                body.GetProperty("locale").GetString()!, cancellation.Token);
            cancellation.Token.ThrowIfCancellationRequested();
            if (!Current()) return Error(request, "gameplayExport.account_changed");
            if (destination is null) return Result(request, "cancelled");
            // Refresh after a potentially long save dialog; never reuse another account's snapshot.
            var snapshot = ReadSnapshot(request, cancellation.Token);
            _writer.WriteNew(destination, snapshot, Current, cancellation.Token);
            return Result(request, "saved");
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (GameplayExportException e) { return Error(request, e.Code); }
        catch (BridgeProtocolException) { return Error(request, "gameplayExport.invalid_request"); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error(request, "gameplayExport.data_unavailable"); }
        catch { return Error(request, "gameplayExport.save_failed"); }
        finally
        {
            if (acquired)
            {
                lock (_pendingLock) _pending = null;
                Interlocked.Exchange(ref _busy, 0);
            }
        }
    }

    public void Invalidate()
    {
        lock (_pendingLock)
        {
            try { _pending?.Cancel(); }
            catch (ObjectDisposedException) { } // Completion is clearing its linked source.
        }
    }

    private GameplayExportData ReadSnapshot(BridgeEnvelope request, CancellationToken cancellation)
    {
        var read = BridgeEnvelope.Request("gameplayTime.read", request.CorrelationId!, request.SessionGeneration,
            new { schemaVersion = 1 }, request.AccountContext);
        var response = readGameplay(read, cancellation).Response;
        if (response.Error?.Code == "gameplay.account_changed")
            throw new GameplayExportException("gameplayExport.account_changed");
        if (response.Status != BridgeResponseStatuses.Ok || response.AccountContext != request.AccountContext ||
            response.SessionGeneration != request.SessionGeneration)
            throw new GameplayExportException("gameplayExport.data_unavailable");
        return GameplayExportData.FromProjection(response.Payload, _time.GetUtcNow());
    }

    private static BridgeDispatchBatch Result(BridgeEnvelope request, string outcome) =>
        new(BridgeEnvelope.Response(request, new { schemaVersion = 1, outcome }), []);
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Gameplay data export did not complete.", true)), []);

    public void Dispose()
    {
        if (_disposed) return;
        _disposed = true;
        _lifetime.Cancel();
        // Existing operations own linked registrations until their picker has closed.
    }
}
