using System.Text.Json;
using StarBridge.HostRuntime.Hangar;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Profiles;

public sealed class LocalPersonalProfileDispatcher(LocalPersonalProfileStore store, LocalHangarStore hangar,
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
                    return Error(request, "profile_local.account_changed");
                bool CanCommit() => !cancellation.IsCancellationRequested && current() == owner;
                var body = request.Payload;
                if (body.GetRawText().Length > 64 * 1024 || body.GetProperty("schemaVersion").GetInt32() != 1)
                    return Error(request, "profile_local.invalid_request");
                LocalPersonalProfileStore.RejectDuplicates(body);
                var snapshot = store.Read(owner.Context);
                if (request.Name == "personalProfile.localSave")
                {
                    if (body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "expectedRevision" or "operationId" or "content")))
                        return Error(request, "profile_local.invalid_request");
                    var content = body.GetProperty("content").Deserialize<LocalProfileContent>(LocalPersonalProfileStore.Json);
                    LocalPersonalProfileStore.Validate(content);
                    // Existing references survive removals/reordering. Only newly
                    // selected IDs require membership in this owner's current hangar.
                    if (content!.FavoriteShipIds is { } ids &&
                        !(snapshot.Content?.FavoriteShipIds?.SequenceEqual(ids) ?? false))
                    {
                        var added = ids.Except(snapshot.Content?.FavoriteShipIds ?? [], StringComparer.Ordinal).ToArray();
                        if (added.Length > 0)
                        {
                            var inventory = hangar.Read(owner.Context);
                            var known = inventory.Ships.Concat(inventory.FormerShips ?? []).Select(s => s.Id).ToHashSet(StringComparer.Ordinal);
                            if (inventory.Revision == 0 || added.Any(id => !known.Contains(id)))
                                return Error(request, "profile_local.hangar_changed");
                        }
                    }
                    snapshot = store.Save(owner.Context, body.GetProperty("expectedRevision").GetInt64(),
                        body.GetProperty("operationId").GetString()!, content, CanCommit);
                }
                else if (request.Name != "personalProfile.localRead") return Error(request, BridgeErrorCodes.CapabilityUnavailable);
                else if (body.EnumerateObject().Any(p => p.Name != "schemaVersion"))
                    return Error(request, "profile_local.invalid_request");
                if (!CanCommit()) return Error(request, "profile_local.account_changed");
                return new(BridgeEnvelope.Response(request, new { schemaVersion = 1, snapshot.Revision,
                    snapshot.SavedAt, snapshot.OperationId, snapshot.Content,
                    timeZones = TimeZoneInfo.GetSystemTimeZones().Select(zone => new { id = zone.Id, label = zone.DisplayName })
                }), []);
            }
            catch (LocalProfileException error) { return Error(request, error.Code); }
            catch (LocalHangarStoreException) { return Error(request, "profile_local.hangar_changed"); }
            catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or
                FormatException or OverflowException or BridgeProtocolException or ArgumentException)
            { return Error(request, "profile_local.invalid_request"); }
        }
    }
    private static BridgeDispatchBatch Error(BridgeEnvelope request, string code) =>
        new(BridgeEnvelope.ErrorResponse(request, new(code, "Local personal profile operation failed.", true)), []);
}
