using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> GetOfficialFleetRuntimeMembersAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ObserveOfficialMembers("official-runtime-members", context, payload, () => ReadOfficialFleetRuntimeMembersCoreAsync(context, payload, false, token));
    public Task<object> WaitOfficialFleetRuntimeActivityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        ReadOfficialFleetRuntimeMembersCoreAsync(context, payload, true, token);
    private async Task<object> ReadOfficialFleetRuntimeMembersCoreAsync(BridgeAccountContext context, JsonElement payload, bool wait, CancellationToken token)
    {
        if (!OfficialRealtimeEnabled) throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
        var generation = Generation;
        try {
            if (payload.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "sourceRef" or "search" or "filter" or "pageNumber" or "pageSize")) ||
                payload.GetProperty("schemaVersion").GetInt32() != 2 || payload.GetProperty("filter").GetString() != "all") throw OfficialFleetReadModel.Invalid();
            var source = payload.GetProperty("sourceRef").GetString(); var search = payload.GetProperty("search").GetString();
            var page = payload.GetProperty("pageNumber").GetInt32(); var size = payload.GetProperty("pageSize").GetInt32();
            if (source is null || search is null || search.Length > 128 || search.Any(char.IsControl) || page is < 1 or > 100000 || size is not (25 or 50 or 100)) throw OfficialFleetReadModel.Invalid();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(context, generation);
            using var data = await ReadOfficialFleetMemberPageSourceAsync(context, generation, source, search, page, size, token);
            var ids = data.RootElement.GetProperty("list").EnumerateArray().Select(r => OfficialFleetPublicId.Read(r.GetProperty("userId"))).ToArray();
            var observations = await ReadFleetIdentityObservationsAsync(context, generation, source, ids, token);
            void Current() {
                AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
                RequireFleetReadOwner(context, generation);
                OfficialFleetMemberIdentityObservation.EnsureCurrent(observations.Values, _oauth.OfficialFleetIdentityObservationClock.GetUtcNow());
            }
            Current(); var identities = observations.ToDictionary(p => p.Key, p => p.Value.Identity);
            var subjects = identities.Values.Where(row => row.State == "visible").Select(row => row.BusinessSubjectId!).ToArray();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Relay);
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
            var session = RequireRelaySession(context);
            if (wait) {
                var activity = await SendRelayRequestAsync(session, async (active, ct) => {
                    Current(); var changed = await writer.WaitOfficialRuntimeAsync(active.AccessToken, source, subjects, ct,
                        () => RequireFleetReadOwner(context, generation));
                    RequireFleetReadOwner(context, generation); return changed;
                }, token);
                RequireFleetReadOwner(context, generation); RequireSameRelaySession(RequireRelaySession(context), activity.ActiveSession);
                CommitSharingSession(session, activity.ActiveSession);
                // The wait returns no identities/fields. End it with a new real
                // G1 observation; only the non-wait data path keeps the first deadline.
                var finalIdentity = await ReadFleetIdentityObservationsAsync(context, generation, source, ids, token);
                void HintCurrent() { RequireFleetReadOwner(context, generation);
                    OfficialFleetMemberIdentityObservation.EnsureCurrent(finalIdentity.Values, _oauth.OfficialFleetIdentityObservationClock.GetUtcNow()); }
                HintCurrent();
                var hint = JsonSerializer.SerializeToElement(new { schemaVersion = 2, sourceRef = source, changed = activity.Result });
                HintCurrent(); return hint;
            }
            var result = await SendRelayRequestAsync(session, async (active, ct) => {
                Current(); var value = await writer.ReadOfficialRuntimeAsync(active.AccessToken, source, subjects, ct, Current);
                Current(); return value;
            }, token);
            Current(); RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
            CommitSharingSession(session, result.ActiveSession); Current();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Materialize);
            var node = JsonSerializer.SerializeToNode(OfficialFleetReadModel.Members(data.RootElement, source, page, size, search,
                id => OfficialFleetMemberReference(generation, source, id), identities))!.AsObject();
            node["schemaVersion"] = 2;
            node["runtimeCapabilities"] = JsonSerializer.SerializeToNode(new { presence = true, server = true, ship = true, location = true, onlineCount = false, inGameCount = false });
            var refs = identities.Values.ToDictionary(row => OfficialFleetMemberReference(generation, source, row.MemberId));
            foreach (var memberNode in node["members"]!.AsArray()) {
                var member = memberNode!.AsObject(); var identity = refs[member["memberRef"]!.GetValue<string>()];
                var live = identity.State == "visible" ? result.Result[identity.BusinessSubjectId!] :
                    new OfficialRealtimeMemberWire("", "offline", new("notInGame", null, null), new("notInGame", null, null), new("notInGame", null, null), false, null);
                member["presence"] = live.Presence;
                member["server"] = JsonSerializer.SerializeToNode(live.Server, LocalPrivacyStore.Json);
                member["ship"] = JsonSerializer.SerializeToNode(live.Ship, LocalPrivacyStore.Json);
                member["location"] = JsonSerializer.SerializeToNode(live.Location, LocalPrivacyStore.Json);
                member["arrivalPending"] = live.ArrivalPending; member["arrivalTargetCode"] = live.ArrivalTargetCode;
                member["serverRegion"] = live.ServerRegion; member["hasServerSession"] = live.HasServerSession;
                member["locationHiddenReason"] = live.LocationHiddenReason;
            }
            var materialized = JsonSerializer.SerializeToElement(node); Current();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RememberFleetProfileTargets(context, generation, source, identities); Current();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Materialize); return materialized;
        } catch (Exception error) {
            OfficialMemberReadObservation.Failure(error);
            if (!_disposed && Generation == generation && CurrentContext == context) ClearOfficialFleetProfileTargets();
            if (error is OperationCanceledException && token.IsCancellationRequested) throw;
            if (error is AccountBridgeHostException) throw;
            if (error is Auth.ScmApiAuthenticationException)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            if (error is HttpRequestException or IOException or InvalidOperationException or JsonException or
                InvalidDataException or KeyNotFoundException or FormatException or OperationCanceledException or OverflowException or TimeoutException)
                throw OfficialFleetReadFailures.FromException(error, token);
            throw;
        }
    }
}
