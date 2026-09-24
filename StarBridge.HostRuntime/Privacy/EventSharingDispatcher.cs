using System.Text.Json;
using System.Text.Json.Serialization;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed class EventSharingDispatcher(EventSharingRuntime runtime, Func<(BridgeAccountContext? Context, long Generation)> current)
{
    private sealed record Save([property: JsonRequired] int SchemaVersion, [property: JsonRequired] long ExpectedRevision,
        [property: JsonRequired] string OperationId, [property: JsonRequired] bool PublicationEnabled,
        [property: JsonRequired] SharedEventPreferences Settings);
    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = current();
            if (owner.Context is null || request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                throw new AccountBridgeHostException("events.account_changed");
            if (request.MessageType != BridgeMessageTypes.Request || request.Payload.GetRawText().Length > 96 * 1024)
                throw new JsonException();
            LocalPrivacyStore.RejectDuplicates(request.Payload);
            EventSharingRemoteSnapshot result;
            if (request.Name == "eventSharing.read")
            {
                if (request.Payload.EnumerateObject().Count() != 1 || request.Payload.GetProperty("schemaVersion").GetInt32() != 1)
                    throw new JsonException();
                result = await runtime.ReadAsync(owner.Context, owner.Generation, token);
            }
            else if (request.Name == "eventSharing.save")
            {
                var input = request.Payload.Deserialize<Save>(LocalPrivacyStore.Json) ?? throw new JsonException();
                if (input.SchemaVersion != 1 || input.ExpectedRevision < 0 || input.ExpectedRevision == long.MaxValue ||
                    !Guid.TryParseExact(input.OperationId, "N", out _) || input.Settings is null) throw new JsonException();
                result = await runtime.SaveAsync(owner.Context, owner.Generation, input.ExpectedRevision,
                    input.OperationId, input.PublicationEnabled, input.Settings.ValidatedCopy(), token);
            }
            else throw new JsonException();
            if (owner != current()) throw new AccountBridgeHostException("events.account_changed");
            return new(BridgeEnvelope.Response(request, new { snapshot = result, state = runtime.State }), []);
        }
        catch (AccountBridgeHostException e) { return Error(e.Code); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception e) when (e is JsonException or InvalidOperationException or ArgumentException or KeyNotFoundException or FormatException)
        { return Error("events.invalid_request"); }
        catch (HttpRequestException) { return Error("events.temporarily_unavailable"); }
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request,
            new(code, "Event sharing is unavailable.", true)), []);
    }
}
