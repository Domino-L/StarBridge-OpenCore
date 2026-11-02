using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private Ships.ScmShipSpecificationReader? _shipSpecifications;

    private async ValueTask<BridgeDispatchBatch> ReadShipSpecificationsAsync(
        BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _host.HangarIdentity;
            if (request.MessageType != BridgeMessageTypes.Request || owner is null ||
                request.AccountContext != owner.Account || request.SessionGeneration != owner.Generation)
                return ShipSpecificationError(request, "hangar.account_changed");
            var body = request.Payload;
            if (body.ValueKind != JsonValueKind.Object || body.GetRawText().Length > 1024 ||
                body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Select(p => p.Name).Distinct().Count() != body.EnumerateObject().Count() ||
                body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "model" or "refresh")) ||
                body.GetProperty("model").GetString() is not { Length: > 0 and <= 240 } model || model.Any(char.IsControl))
                return ShipSpecificationError(request, "ships.invalid_request");
            if (_shipSpecifications is null) return ShipSpecificationError(request, "ships.unavailable");
            var refresh = body.TryGetProperty("refresh", out var field) && field.GetBoolean();
            var result = await _shipSpecifications.ReadAsync(model, refresh, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (_disposed || _host.HangarIdentity != owner) return ShipSpecificationError(request, "hangar.account_changed");
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, specifications = result }), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException error)
        { return new(BridgeEnvelope.ErrorResponse(request, new(error.Code, error.Message)), []); }
        catch (HttpRequestException) { return ShipSpecificationError(request, "ships.unavailable"); }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return ShipSpecificationError(request, "ships.invalid_request"); }
    }

    private static BridgeDispatchBatch ShipSpecificationError(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Ship specifications could not be loaded.", code == "ships.unavailable")), []);
}
