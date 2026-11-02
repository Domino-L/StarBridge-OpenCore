using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    internal ScmRouteState? RouteState { get; set; }

    private BridgeDispatchBatch DispatchScmRoute(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            token.ThrowIfCancellationRequested();
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            if (request.SessionGeneration != Generation)
                throw new BridgeStaleGenerationException(request.SessionGeneration, Generation);
            if (request.AccountContext is not null || request.MessageType != BridgeMessageTypes.Request || RouteState is null)
                throw new ArgumentException();
            var save = request.Name == "account.scmRouteSave";
            var fields = request.Payload.EnumerateObject().Select(p => p.Name).ToArray();
            var expected = save ? new[] { "schemaVersion", "mode" } : new[] { "schemaVersion" };
            if (fields.Length != expected.Length || fields.Except(expected).Any() || fields.Distinct().Count() != fields.Length ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                throw new ArgumentException();
            var projection = save ? RouteState.SaveMode(request.Payload.GetProperty("mode").GetString()!) : RouteState.Inspect();
            return new(BridgeEnvelope.Response(request, projection, preserveRequestAccountContext: false), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (BridgeProtocolException exception)
        { return new(BridgeEnvelope.ErrorResponse(request, new(exception.Code, "Route preference request rejected.")), []); }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        { return new(BridgeEnvelope.ErrorResponse(request, new("scmRoute.write_failed", "Route preference could not be saved.")), []); }
        catch (Exception exception) when (exception is ArgumentException or InvalidOperationException or JsonException or FormatException or KeyNotFoundException)
        { return new(BridgeEnvelope.ErrorResponse(request, new("scmRoute.invalid_request", "Route preference request rejected.")), []); }
    }
}
