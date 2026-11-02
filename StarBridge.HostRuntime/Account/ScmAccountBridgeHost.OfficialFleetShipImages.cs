using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadOfficialFleetShipImageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetShipMediaAsync(context, payload, "read", token);
    public Task<object> ReportOfficialFleetShipImageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetShipMediaAsync(context, payload, "report", token);
    public Task<object> ReadOfficialFleetShipImageReportStatusAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        OfficialFleetShipMediaAsync(context, payload, "status", token);

    private async Task<object> OfficialFleetShipMediaAsync(BridgeAccountContext context, JsonElement payload, string action, CancellationToken token)
    {
        _ = RequireSession(context); // No legacy/compatibility identity for official images.
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token); budget.CancelAfter(TimeSpan.FromSeconds(12));
        var generation = Generation; var session = RequireRelaySession(context);
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable) throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var accountScope = FriendScope(context, generation);
        var clock = _oauth.OfficialFleetIdentityObservationClock;
        CommunityClient.OfficialShipImageReference? bound = null;
        var descriptor = Volatile.Read(ref _fleetPublicSource);
        var observations = new Dictionary<long, OfficialFleetMemberIdentityObservation>();
        void CurrentOwner()
        {
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context); RequireSameRelaySession(RequireRelaySession(context), session);
        }
        void Current()
        {
            CurrentOwner();
            if (action == "status") return;
            RequireFleetReadOwner(context, generation);
            if (bound is null || descriptor is null || descriptor.Owner != context || descriptor.Generation != generation || descriptor.SourceRef != bound.SourceRef ||
                descriptor != Volatile.Read(ref _fleetPublicSource)) throw new AccountBridgeHostException("communities.identityUnavailable");
            if (client.LookupOfficialShipImage(payload, accountScope, clock, action == "report") != bound) throw new AccountBridgeHostException("communities.refreshRequired");
            OfficialFleetMemberIdentityObservation.EnsureCurrent(observations.Values, clock.GetUtcNow());
        }
        CurrentOwner();
        if (action != "status")
        {
            bound = client.LookupOfficialShipImage(payload, accountScope, clock, action == "report"); Current();
            var fresh = await ReadFleetIdentityObservationsAsync(context, generation, bound.SourceRef, [bound.MemberId], budget.Token);
            Current(); var observation = fresh[bound.MemberId];
            if (observation.Identity.State is not ("visible" or "restricted")) throw new AccountBridgeHostException("communities.identityUnavailable");
            observations.Add(bound.MemberId, observation); Current();
        }
        var response = await SendRelayRequestAsync<object>(session, (active, ct) => action switch
        {
            "status" => client.ReadOfficialShipImageReportStatusAsync(active.AccessToken, payload, accountScope, CurrentOwner, ct),
            "report" => client.ReportOfficialShipImageAsync(active.AccessToken, payload, accountScope, Current, clock, ct),
            _ => client.ReadOfficialShipImageAsync(active.AccessToken, payload, bound!.SourceRef, bound.AccountScope, Current, clock, ct)
        }, budget.Token);
        if (action == "read") Current(); else CurrentOwner();
        CommitSharingSession(session, response.ActiveSession); CurrentOwner();
        return response.Result;
    }
}
