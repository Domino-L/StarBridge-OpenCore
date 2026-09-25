using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Updates;

public sealed class FlutterUpdateBridgeDispatcher(IApplicationUpdateSource? runtime,
    Func<string?> currentVersion, Func<long> generation,
    FlutterUpdateStartupReporter? startupReporter = null,
    FlutterUpdateInstallation? installation = null,
    Func<long, object, BridgeEnvelope>? progressEvent = null,
    Action? firstFrameReady = null) : IBridgeRequestDispatcher
{
    public const string RequestName = "applicationUpdates.check";
    public const string ReadyRequestName = "applicationUpdates.firstFrameReady";
    public const string PrepareRequestName = "applicationUpdates.prepare";
    public const string HandoffRequestName = "applicationUpdates.handoff";
    public const string ProgressEventName = "applicationUpdates.progress";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = [RequestName];
    private bool _disposed;
    public event Action<BridgeEnvelope>? EventReady;
    public async ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != generation()) return Error(request);
            var installing = request.Name is PrepareRequestName or HandoffRequestName;
            if (request.Name is not (RequestName or ReadyRequestName or PrepareRequestName or HandoffRequestName) || request.MessageType != BridgeMessageTypes.Request ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != (installing ? 2 : 1) ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) || schema.ValueKind != JsonValueKind.Number ||
                !schema.TryGetInt32(out var version) || version != 1)
                return new(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid update check request.")), []);
            if (installing)
            {
                if (installation is null) return Error(request);
                var key = request.Name == PrepareRequestName ? "version" : "ticket";
                if (!request.Payload.TryGetProperty(key, out var field) || field.ValueKind != JsonValueKind.String)
                    return Error(request);
                var value = field.GetString()!;
                if (request.Name == PrepareRequestName)
                {
                    if (value.Length > 96 || !Version.TryParse(value, out _)) return Error(request);
                    var active = true;
                    var lastTick = 0L;
                    string? lastPhase = null;
                    long lastBytes = -1;
                    // Use the shared domain event sequence supplied by composition.
                    // A private counter would suppress unrelated client events.
                    void Progress(FlutterUpdateProgress update)
                    {
                        if (!active || _disposed || cancellationToken.IsCancellationRequested ||
                            request.SessionGeneration != generation() || progressEvent is null ||
                            update.Phase is not ("downloading" or "verifying" or "verified") ||
                            update.ReceivedBytes < lastBytes || update.ReceivedBytes < 0 ||
                            update.ReceivedBytes > 1024L * 1024 * 1024 ||
                            update.TotalBytes is <= 0 or > 1024L * 1024 * 1024 ||
                            update.TotalBytes is long total && update.ReceivedBytes > total) return;
                        var now = Environment.TickCount64;
                        if (lastPhase == update.Phase && now - lastTick < 150 &&
                            update.ReceivedBytes != update.TotalBytes) return;
                        lastTick = now; lastPhase = update.Phase; lastBytes = update.ReceivedBytes;
                        EventReady?.Invoke(progressEvent(request.SessionGeneration, new Dictionary<string, object?> {
                            ["schemaVersion"] = 1, ["requestId"] = request.CorrelationId,
                            ["version"] = value, ["phase"] = update.Phase,
                            ["receivedBytes"] = update.ReceivedBytes, ["totalBytes"] = update.TotalBytes
                        }));
                    }
                    FlutterUpdatePrepared prepared;
                    try {
                        prepared = await installation.PrepareAsync(value,
                            () => !_disposed && request.SessionGeneration == generation(), cancellationToken, Progress);
                    }
                    finally { active = false; }
                    return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, ticket = prepared.Ticket,
                        version = prepared.Version }, preserveRequestAccountContext: false), []);
                }
                if (!Guid.TryParseExact(value, "N", out _)) return Error(request);
                await installation.HandoffAsync(value,
                    () => !_disposed && request.SessionGeneration == generation(), cancellationToken);
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, accepted = true },
                    preserveRequestAccountContext: false), []);
            }
            if (request.Name == ReadyRequestName)
            {
                if (startupReporter is null && firstFrameReady is null) return Error(request);
                if (startupReporter is not null) await startupReporter.ReportFirstFrameAsync(cancellationToken);
                cancellationToken.ThrowIfCancellationRequested();
                if (_disposed || request.SessionGeneration != generation()) return Error(request);
                firstFrameReady?.Invoke();
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, reported = true },
                    preserveRequestAccountContext: false), []);
            }
            ApplicationUpdateCheck result;
            try
            {
                result = runtime is null ? new("channel-unconfigured") : await runtime.CheckForUpdateAsync(cancellationToken);
            }
            catch (Exception error) when (error is InvalidDataException or JsonException or System.Security.Cryptography.CryptographicException)
            {
                // An untrusted/malformed release is not a transient network failure.
                // Never expose its version, notes, URL, or parser detail to the UI.
                result = new("verification-failed");
            }
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != generation()) return Error(request);
            // Dictionary values retain explicit nulls even when the envelope's
            // object serializer omits null properties. Flutter expects all five keys.
            return new(BridgeEnvelope.Response(request, new Dictionary<string, object?> {
                ["schemaVersion"] = 1, ["state"] = result.Status, ["currentVersion"] = currentVersion(),
                ["availableVersion"] = result.Version, ["notes"] = result.Notes
            }, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch { return Error(request); }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request) => new(
        BridgeEnvelope.ErrorResponse(request, new BridgeError("applicationUpdates.unavailable", "Update check unavailable.", true)), []);
    public void Dispose() { _disposed = true; runtime?.Dispose(); }
}
