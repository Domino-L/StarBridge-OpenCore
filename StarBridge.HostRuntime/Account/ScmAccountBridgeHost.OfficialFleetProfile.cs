using System.Text.Json;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : IAccountBridgeOfficialFleetProfileReader
{
    // One public routing descriptor, never an authorization or credential cache.
    // No membership/rank/capability is returned or granted by the public read.
    private sealed record FleetPublicSource(BridgeAccountContext Owner, long Generation, string SourceRef, string Sid);
    private FleetPublicSource? _fleetPublicSource;

    public async Task<AccountBridgeOfficialFleetPublicProfile> GetOfficialFleetPublicProfileAsync(
        BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var generation = Generation;
        RequireFleetReadOwner(context, generation);
        var source = Volatile.Read(ref _fleetPublicSource);
        if (source is null || source.Owner != context || source.Generation != generation ||
            payload.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "sourceRef")) ||
            !payload.TryGetProperty("sourceRef", out var value) || value.ValueKind != JsonValueKind.String ||
            value.GetString() != source.SourceRef)
            throw OfficialFleetReadModel.Invalid();
        try {
            // Existing public core route. No token, refresh, account mutation or
            // fresh authorization is taken from the routing descriptor.
            using var data = await _oauth.ReadPublicOrganizationAsync("get?sid=" + Uri.EscapeDataString(source.Sid), token);
            RequireFleetReadOwner(context, generation);
            if (source != Volatile.Read(ref _fleetPublicSource))
                throw OfficialFleetReadModel.Invalid();
            var profile = OfficialFleetReadModel.Profile(data.RootElement, source.SourceRef, source.Sid);
            return new(source.SourceRef, source.Sid, profile, new("available", DateTimeOffset.UtcNow));
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error) {
            RequireFleetReadOwner(context, generation);
            if (source != Volatile.Read(ref _fleetPublicSource))
                return new(source.SourceRef, source.Sid, null, new("invalid"));
            return new(source.SourceRef, source.Sid, null, OfficialFleetReadFailures.ForProfile(error, token));
        }
    }
}
