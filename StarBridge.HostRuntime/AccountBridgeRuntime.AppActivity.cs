using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private sealed record AppActivityObservation(BridgeAccountContext Owner, long Generation, bool Away);

    private BridgeDispatchBatch DispatchAppActivity(BridgeEnvelope request)
    {
        BridgeDispatchBatch Error() => new(BridgeEnvelope.ErrorResponse(request,
            new("presence.activity_invalid", "Activity state is unavailable.", false)), []);
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = GameplayOwner();
            if (_disposed || request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation ||
                request.Payload.GetRawText().Length > 128)
                return Error();
            Privacy.LocalPrivacyStore.RejectDuplicates(request.Payload);
            var fields = request.Payload.EnumerateObject().Select(item => item.Name).ToArray();
            if (fields.Length != 2 || fields.Any(name => name is not ("schemaVersion" or "away")) ||
                request.Payload.GetProperty("schemaVersion").GetInt32() != 1 ||
                request.Payload.GetProperty("away").ValueKind is not (System.Text.Json.JsonValueKind.True or System.Text.Json.JsonValueKind.False))
                return Error();
            Volatile.Write(ref _appActivity, new(owner.Context, owner.Generation, request.Payload.GetProperty("away").GetBoolean()));
            // A real UI state transition advances the existing publishers. No
            // new timer, account lookup, log reader or independent session.
            _ = _friendSharing?.TickAsync();
            _ = _privacyPublication?.TickAsync();
            return new(BridgeEnvelope.Response(request, new { schemaVersion = 1 }), []);
        }
        catch (Exception error) when (error is System.Text.Json.JsonException or InvalidOperationException or KeyNotFoundException or FormatException or ArgumentException)
        { return Error(); }
    }
}
