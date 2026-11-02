using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Onboarding;

public sealed class FirstUseStartupBridgeDispatcher : IBridgeRequestDispatcher
{
    public const string Capability = "onboarding.startup.v1";
    public const string ReadRequest = "onboarding.startup.read";
    private readonly FirstUseStartupReader _reader;
    private readonly Func<long> _generation;
    private bool _disposed;
    internal FirstUseStartupBridgeDispatcher(FirstUseStartupReader reader, Func<long> generation)
    { _reader = reader; _generation = generation; }
    public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
    public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
    {
        BridgeDispatchBatch batch;
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (_disposed || request.SessionGeneration < 0 || request.SessionGeneration != _generation())
                return ValueTask.FromResult(Error(request, "firstUse.context_changed"));
            if (request.MessageType != BridgeMessageTypes.Request || request.AccountContext is not null ||
                request.Name != ReadRequest || request.Payload.ValueKind != JsonValueKind.Object ||
                request.Payload.EnumerateObject().Count() != 1 ||
                !request.Payload.TryGetProperty("schemaVersion", out var schema) ||
                schema.ValueKind != JsonValueKind.Number || !schema.TryGetInt32(out var version) || version != 1)
                return ValueTask.FromResult(Error(request, "firstUse.invalid_request"));
            var value = _reader.Read();
            token.ThrowIfCancellationRequested();
            batch = !_disposed && request.SessionGeneration == _generation()
                ? new(BridgeEnvelope.Response(request, new { schemaVersion = 1, eligibility = value.Eligibility,
                    reason = value.Reason, hasProgress = value.HasProgress }, preserveRequestAccountContext: false), [])
                : Error(request, "firstUse.context_changed");
        }
        catch (OperationCanceledException) { batch = new(BridgeEnvelope.CancelledResponse(request with { AccountContext = null }), []); }
        catch { batch = Error(request, "firstUse.invalid_request"); }
        return ValueTask.FromResult(batch);
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request with { AccountContext = null }, new(code, "Setup display could not be checked.", true)), []);
    public void Dispose() => _disposed = true;
}
