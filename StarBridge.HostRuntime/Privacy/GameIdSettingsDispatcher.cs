using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed class GameIdSettingsDispatcher(IGameIdSettingsRemote remote, Func<(BridgeAccountContext? Context, long Generation)> current)
{
    internal async Task<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request); BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = current();
            if (owner.Context is null || owner.Context != request.AccountContext || owner.Generation != request.SessionGeneration)
                throw new AccountBridgeHostException("gameId.account_changed");
            var body = request.Payload;
            LocalPrivacyStore.RejectDuplicates(body);
            if (request.MessageType != BridgeMessageTypes.Request || body.GetRawText().Length > 1024 || body.GetProperty("schemaVersion").GetInt32() != 1) throw new JsonException();
            GameIdSettingsSnapshot result;
            if (request.Name == "gameIdVisibility.read" && body.EnumerateObject().Count() == 1)
                result = await remote.ReadGameIdAsync(owner.Context, owner.Generation, token);
            else if (request.Name == "gameIdVisibility.save" && body.EnumerateObject().Count() == 4 &&
                body.EnumerateObject().All(p => p.Name is "schemaVersion" or "expectedRevision" or "identityStamp" or "locations"))
            {
                var revision = body.GetProperty("expectedRevision").GetInt64();
                var stamp = body.GetProperty("identityStamp").GetString();
                var locations = body.GetProperty("locations").GetInt32();
                if (revision < 0 || revision == long.MaxValue || locations is < 0 or > 15 || stamp is not { Length: 64 } || stamp.Any(c => !char.IsAsciiHexDigit(c))) throw new JsonException();
                result = await remote.SaveGameIdAsync(owner.Context, owner.Generation, revision, stamp, locations, token);
            }
            else throw new JsonException();
            if (owner != current()) throw new AccountBridgeHostException("gameId.account_changed");
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (AccountBridgeHostException e) { return Error(e.Code); }
        catch (Exception e) when (e is JsonException or ArgumentException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException)
        { return Error("gameId.invalid_response"); }
        catch (HttpRequestException) { return Error("gameId.unavailable"); }
        BridgeDispatchBatch Error(string code) => new(BridgeEnvelope.ErrorResponse(request, new(code, "Game ID visibility is unavailable.", true)), []);
    }
}
