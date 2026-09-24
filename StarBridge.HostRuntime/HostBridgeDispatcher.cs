namespace StarBridge.HostRuntime;

using StarBridge.NativeBridge;
using System.Text.Json;

/// <summary>
/// Owns the lifecycle handshake for the headless Native Host. Account and
/// feature dispatchers will be composed behind the same request seam instead
/// of leaking transport logic into Flutter or the retired WPF shell.
/// </summary>
public sealed class HostBridgeDispatcher : IBridgeRequestDispatcher
{
    private static readonly IReadOnlyList<string> DefaultCapabilities = ["host.lifecycle"];
    private readonly string _hostInstanceId;
    private readonly Func<long> _generation;
    private readonly IReadOnlyList<string> _capabilities;
    private readonly Presence.LocalGamePresenceReader? _gamePresence;

    public HostBridgeDispatcher(
        string hostInstanceId,
        Func<long>? generation = null,
        IReadOnlyList<string>? capabilities = null,
        Presence.LocalGamePresenceReader? gamePresence = null)
    {
        _hostInstanceId = string.IsNullOrWhiteSpace(hostInstanceId)
            ? throw new ArgumentException("Host instance ID is required.", nameof(hostInstanceId))
            : hostInstanceId.Trim();
        _generation = generation ?? (() => 0);
        _capabilities = capabilities ?? DefaultCapabilities;
        _gamePresence = gamePresence;
    }

    public event Action<BridgeEnvelope>? EventReady
    {
        add { }
        remove { }
    }

    public ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        cancellationToken.ThrowIfCancellationRequested();
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            if (request.MessageType != BridgeMessageTypes.Request)
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "Native Host only accepts bridge requests.");
            }

            var response = request.Name switch
            {
                "host.hello" => DispatchHello(request),
                "host.ready" => DispatchReady(request),
                "host.getGamePresence" => DispatchGamePresence(request),
                _ => throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    "The requested Native Host capability is not available.")
            };
            return ValueTask.FromResult(new BridgeDispatchBatch(response, []));
        }
        catch (BridgeProtocolException exception)
        {
            return ValueTask.FromResult(
                new BridgeDispatchBatch(
                    BridgeEnvelope.ErrorResponse(
                        request,
                        new BridgeError(exception.Code, "Native Host request was rejected.")),
                    []));
        }
    }

    private BridgeEnvelope DispatchGamePresence(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        var generation = _generation();
        if (request.SessionGeneration != generation)
            throw new BridgeStaleGenerationException(request.SessionGeneration, generation);
        if (_gamePresence is null || !_capabilities.Contains("host.gamePresence"))
            throw new BridgeProtocolException(BridgeErrorCodes.CapabilityUnavailable, "Game observation unavailable.");
        return BridgeEnvelope.Response(request, _gamePresence.Read(), preserveRequestAccountContext: false);
    }

    private BridgeEnvelope DispatchHello(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        var protocols = RequireObject(request.Payload, "protocols");
        var minimum = RequireInt32(protocols, "minimum");
        var maximum = RequireInt32(protocols, "maximum");
        var requestedCapabilities = RequireStringList(request.Payload, "capabilities");
        var response = BridgeHandshake.Negotiate(
            new BridgeHelloRequest(
                new BridgeProtocolRange(minimum, maximum),
                requestedCapabilities),
            _capabilities,
            _hostInstanceId,
            _generation());
        return BridgeEnvelope.Response(request, response, preserveRequestAccountContext: false);
    }

    private BridgeEnvelope DispatchReady(BridgeEnvelope request)
    {
        BridgeEnvelopeValidator.RequireCurrentVersion(request);
        var generation = _generation();
        if (request.SessionGeneration != generation)
        {
            throw new BridgeStaleGenerationException(
                request.SessionGeneration,
                generation);
        }

        return BridgeEnvelope.Response(
            request,
            new
            {
                ready = true,
                hostInstanceId = _hostInstanceId
            },
            preserveRequestAccountContext: false);
    }

    private static JsonElement RequireObject(JsonElement payload, string name)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Object)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be an object.");
        }

        return value;
    }

    private static int RequireInt32(JsonElement payload, string name)
    {
        if (!payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Number ||
            !value.TryGetInt32(out var result))
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be an integer.");
        }

        return result;
    }

    private static IReadOnlyList<string> RequireStringList(
        JsonElement payload,
        string name)
    {
        if (payload.ValueKind != JsonValueKind.Object ||
            !payload.TryGetProperty(name, out var value) ||
            value.ValueKind != JsonValueKind.Array)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"{name} must be a string list.");
        }

        var result = new List<string>();
        foreach (var item in value.EnumerateArray())
        {
            if (item.ValueKind != JsonValueKind.String ||
                string.IsNullOrWhiteSpace(item.GetString()))
            {
                throw new BridgeProtocolException(
                    BridgeErrorCodes.InvalidEnvelope,
                    $"{name} must contain non-empty strings.");
            }

            result.Add(item.GetString()!.Trim());
        }

        return result;
    }

    public void Dispose()
    {
        _gamePresence?.Dispose();
    }
}
