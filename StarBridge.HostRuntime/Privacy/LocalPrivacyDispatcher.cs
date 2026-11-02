using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

public sealed class LocalPrivacyDispatcher(LocalPrivacyStore store,
    Func<(BridgeAccountContext? Context, long Generation)> current)
{
    private readonly object _sync = new();
    public BridgeDispatchBatch Dispatch(BridgeEnvelope request, CancellationToken cancellation = default)
    {
        lock (_sync)
        {
            try
            {
                BridgeEnvelopeValidator.ValidateWireShape(request);
                BridgeEnvelopeValidator.RequireCurrentVersion(request);
                var owner = current();
                if (request.MessageType != BridgeMessageTypes.Request || owner.Context is null ||
                    request.AccountContext != owner.Context || request.SessionGeneration != owner.Generation)
                    return Error(request, "privacy_local.account_changed");
                bool CanCommit() => !cancellation.IsCancellationRequested && current() == owner;
                if (!CanCommit()) return Error(request, "privacy_local.account_changed");
                if (request.Name is not ("privacy.localRead" or "privacy.localSave"))
                    return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                var body = request.Payload;
                if (body.GetRawText().Length > 192 * 1024 || body.GetProperty("schemaVersion").GetInt32() != 1)
                    return Error(request, "privacy_local.invalid_request");
                LocalPrivacyStore.RejectDuplicates(body);
                LocalPrivacySnapshot snapshot;
                if (request.Name == "privacy.localSave")
                {
                    if (body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "expectedRevision" or "operationId" or "settings")))
                        return Error(request, "privacy_local.invalid_request");
                    var settings = body.GetProperty("settings").Deserialize<LocalPrivacySettings>(LocalPrivacyStore.Json);
                    if (settings is null) return Error(request, "privacy_local.invalid_request");
                    // Event publication has its own contract; the realtime writer
                    // must not acknowledge event settings it cannot publish.
                    if (settings.Events is not null || settings.OfficialFleet is not null) return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                    // This generic editor may retain, never create/rebind, the separate official choice.
                    snapshot = store.SaveMerged(owner.Context, body.GetProperty("expectedRevision").GetInt64(),
                        body.GetProperty("operationId").GetString()!,
                        saved => settings with { OfficialFleet = saved.Settings?.OfficialFleet }, CanCommit, cancellation);
                }
                else
                {
                    if (body.EnumerateObject().Any(p => p.Name != "schemaVersion"))
                        return Error(request, "privacy_local.invalid_request");
                    snapshot = store.Read(owner.Context);
                }
                if (!CanCommit()) return Error(request, "privacy_local.account_changed");
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, snapshot.Revision,
                    snapshot.SavedAt, snapshot.OperationId, Settings = snapshot.Settings is null ? null : snapshot.Settings with { OfficialFleet = null }, publicationAvailable = false }), []);
            }
            catch (LocalPrivacyException error) { return Error(request, error.Code); }
            catch (TimeoutException) { return Error(request, "privacy_publication.timeout"); }
            catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
            catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException or ArgumentException)
            { return Error(request, "privacy_local.invalid_request"); }
        }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local privacy operation failed.", true)), []);
}
