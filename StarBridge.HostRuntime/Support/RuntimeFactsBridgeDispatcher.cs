namespace StarBridge.HostRuntime.Support;

using System.Text.Json;
using StarBridge.NativeBridge;

public sealed class RuntimeFactsBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string RequestName = "diagnostics.getRuntimeFacts";
    public static IReadOnlyList<string> AdvertisedCapabilities { get; } = ["diagnostics.runtimeFacts"];
    private readonly ApplicationRuntimeFactsReader _reader;
    private readonly Func<long> _generation;
    private volatile bool _disposed;

    public RuntimeFactsBridgeDispatcher(ApplicationRuntimeFactsReader reader, Func<long> generation)
    {
        _reader = reader;
        _generation = generation;
    }

    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }

    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        try
        {
            cancellationToken.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration != _generation())
                return Result(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError("diagnostics.runtime_unavailable", "Runtime facts are unavailable.", true)));
            if (request.MessageType != BridgeMessageTypes.Request || request.Name != RequestName ||
                request.AccountContext is not null || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                return Result(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Invalid runtime facts request.")));
            var facts = _reader.Read();
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || request.SessionGeneration != _generation())
                return Result(BridgeEnvelope.ErrorResponse(request,
                    new BridgeError("diagnostics.runtime_unavailable", "Runtime facts are unavailable.", true)));
            return Result(BridgeEnvelope.Response(request, new Dictionary<string, object?>
            {
                ["schemaVersion"] = 1,
                ["applicationVersion"] = facts.ApplicationVersion,
                ["dataDirectory"] = facts.DataDirectory,
                ["imageCacheDirectory"] = facts.ImageCacheDirectory,
                ["imageCacheExists"] = facts.ImageCacheExists,
                ["serverOrigin"] = facts.ServerOrigin
            }, preserveRequestAccountContext: false));
        }
        catch (OperationCanceledException) { return Result(BridgeEnvelope.CancelledResponse(request)); }
        catch (BridgeProtocolException error)
        {
            return Result(BridgeEnvelope.ErrorResponse(request,
                new BridgeError(error.Code, "Invalid runtime facts request.")));
        }
        catch
        {
            return Result(BridgeEnvelope.ErrorResponse(request,
                new BridgeError("diagnostics.runtime_unavailable", "Runtime facts are unavailable.", true)));
        }
    }

    private static ValueTask<BridgeDispatchBatch> Result(BridgeEnvelope envelope) =>
        ValueTask.FromResult(new BridgeDispatchBatch(envelope, []));

    public void Dispose() => _disposed = true;
}
