namespace StarBridge.HostRuntime.Support;

using System.Text.Json;
using StarBridge.NativeBridge;

public sealed record RuntimeOverlayStatus(string WindowState, string HotkeyState,
    string? HotkeyBinding, long AppliedRevision);

/// <summary>Observe existing native state without applying a workspace or evaluating window rules.</summary>
public interface IRuntimeOverlayStatusReader
{
    ValueTask<RuntimeOverlayStatus> ReadStatusAsync(CancellationToken cancellationToken = default);
}

public sealed class OverlayRuntimeStatusBridgeDispatcher(
    IRuntimeOverlayStatusReader reader, Func<long> generation) : IBridgeRequestDispatcher
{
    public const string RequestName = "diagnostics.getOverlayRuntimeStatus";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["diagnostics.overlayRuntimeStatus"];
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != generation()) return Unavailable(request);
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                return new(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid runtime status request.")), []);
            var state = await reader.ReadStatusAsync(cancellationToken).ConfigureAwait(false);
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != generation()) return Unavailable(request);
            return new(BridgeEnvelope.Response(request, new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1, ["windowState"] = state.WindowState,
                ["hotkeyState"] = state.HotkeyState, ["hotkeyBinding"] = state.HotkeyBinding,
                ["appliedRevision"] = state.AppliedRevision
            }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Unavailable(request); }
    }
    private static BridgeDispatchBatch Unavailable(BridgeEnvelope request) => new(
        BridgeEnvelope.ErrorResponse(request, new BridgeError("diagnostics.runtime_unavailable", "Runtime status is unavailable.", true)), []);
    public void Dispose() => _disposed = true;
}
