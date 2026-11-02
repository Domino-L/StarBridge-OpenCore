using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

// Observations only: no readiness, human acceptance, settings or completion grant.
// FirstFrameCommitted means this surface has made a checked DComp frame commit.
// NativeWindowVisible is an HWND observation, not visual/device acceptance.
public sealed record NativeOverlayObservation(string RuntimeId, long AppliedRevision,
    string WindowState, bool NativeWindowVisible, bool FirstFrameCommitted,
    NativeOverlayHotkeyObservation Hotkey, NativeOverlayPreviewObservation Preview);
public sealed record NativeOverlayHotkeyObservation(string State, string? Binding,
    long ConfigurationRevision, long AcceptedInputCount, string? LastOutcome);
public sealed record NativeOverlayPreviewObservation(string? SessionId, long? AppliedRevision,
    bool NativeWindowVisible, bool FirstFrameCommitted);

public interface INativeOverlayObservationReader
{
    // Must read the existing native owner only. Never synchronize, open, register
    // shortcuts, load settings or create a preview as a consequence of this read.
    ValueTask<NativeOverlayObservation?> ReadNativeOverlayObservationAsync(CancellationToken token = default);
}

public sealed class NativeOverlayObservationBridgeDispatcher(
    INativeOverlayObservationReader reader, Func<long> generation) : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.nativeOverlayObservation.v1";
    public const string ReadRequest = "onboarding.nativeOverlayObservation.read";
    private const long MaximumWireInteger = 9007199254740991;
    private volatile bool _disposed;
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != generation()) return Error(request, "firstUse.context_changed");
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != ReadRequest ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                return Error(request, "firstUse.invalid_request");
            var value = await reader.ReadNativeOverlayObservationAsync(token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != generation()) return Error(request, "firstUse.context_changed");
            if (value is null || !Valid(value)) return Error(request, "firstUse.native_observation_unavailable");
            // Dictionaries preserve explicit nulls under the shared protocol's
            // null-ignoring serializer. Missing outcomes/sessions are still facts.
            return new(BridgeEnvelope.Response(request, new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1, ["runtimeId"] = value.RuntimeId, ["appliedRevision"] = value.AppliedRevision,
                ["windowState"] = value.WindowState, ["nativeWindowVisible"] = value.NativeWindowVisible,
                ["firstFrameCommitted"] = value.FirstFrameCommitted,
                ["hotkey"] = new Dictionary<string, object?> { ["state"] = value.Hotkey.State, ["binding"] = value.Hotkey.Binding,
                    ["configurationRevision"] = value.Hotkey.ConfigurationRevision, ["acceptedInputCount"] = value.Hotkey.AcceptedInputCount,
                    ["lastOutcome"] = value.Hotkey.LastOutcome },
                ["preview"] = new Dictionary<string, object?> { ["sessionId"] = value.Preview.SessionId, ["appliedRevision"] = value.Preview.AppliedRevision,
                    ["nativeWindowVisible"] = value.Preview.NativeWindowVisible, ["firstFrameCommitted"] = value.Preview.FirstFrameCommitted }
            },
                preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Error(request, "firstUse.native_observation_unavailable"); }
    }

    private static bool Number(long number) => number is >= 0 and <= MaximumWireInteger;
    private static bool Id(string? id) => id is { Length: 32 } && id.All(c => c is >= '0' and <= '9' or >= 'a' and <= 'f');
    private static bool WindowState(string? state) => state is "open" or "closed" or "opening" or "suppressed" or "failed" or "unavailable";
    private static bool Valid(NativeOverlayObservation value)
    {
        var hotkey = value.Hotkey; var preview = value.Preview;
        return Id(value.RuntimeId) && Number(value.AppliedRevision) && WindowState(value.WindowState) &&
            hotkey is not null && (hotkey.State is "unavailable" or "disabled" or "invalid" or "registered" or
                "gameCompatibleOnly" or "desktopOnly" or "conflict" or "failed") &&
            (hotkey.Binding is null || hotkey.Binding.Length <= 128 && !hotkey.Binding.Any(char.IsControl)) &&
            Number(hotkey.ConfigurationRevision) && Number(hotkey.AcceptedInputCount) &&
            (hotkey.AcceptedInputCount == 0 ? hotkey.LastOutcome is null : WindowState(hotkey.LastOutcome)) &&
            preview is not null && (preview.SessionId is null ? preview.AppliedRevision is null &&
                !preview.NativeWindowVisible && !preview.FirstFrameCommitted : Id(preview.SessionId) &&
                preview.AppliedRevision is { } revision && Number(revision));
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Native overlay observation is unavailable.", true)), []);
    // Borrowed reader: closing this bridge must not dispose or mutate the Native owner.
    public void Dispose() => _disposed = true;
}
