using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private sealed record FleetProfileTarget(BridgeAccountContext Owner, long Generation, string SourceRef,
        long MemberId, string BusinessSubjectId);
    private readonly object _fleetProfileTargetGate = new();
    private readonly Dictionary<string, FleetProfileTarget> _fleetProfileTargets = new(StringComparer.Ordinal);

    private void ClearOfficialFleetProfileTargets()
    {
        lock (_fleetProfileTargetGate) _fleetProfileTargets.Clear();
    }

    private void RememberFleetProfileTargets(BridgeAccountContext owner, long generation, string sourceRef,
        IReadOnlyDictionary<long, OfficialFleetMemberIdentity> identities)
    {
        lock (_fleetProfileTargetGate)
        {
            RequireFleetReadOwner(owner, generation);
            foreach (var identity in identities.Values)
            {
                var reference = OfficialFleetMemberReference(generation, sourceRef, identity.MemberId);
                _fleetProfileTargets.Remove(reference);
                if (identity.State != "visible") continue;
                while (_fleetProfileTargets.Count >= 500) _fleetProfileTargets.Remove(_fleetProfileTargets.Keys.First());
                _fleetProfileTargets.Add(reference, new(owner, generation, sourceRef, identity.MemberId, identity.BusinessSubjectId!));
            }
        }
    }

    private async Task<IReadOnlyDictionary<long, OfficialFleetMemberIdentity>> ReadFleetIdentitiesAsync(
        BridgeAccountContext owner, long generation, string sourceRef, IReadOnlyCollection<long> ids, CancellationToken token)
    {
        try
        {
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(owner, generation);
            if (ids.Count == 0) return new Dictionary<long, OfficialFleetMemberIdentity>();
            var session = RequireSession(owner);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.G1Read);
            var result = await _oauth.ReadOfficialFleetMemberIdentitiesAsync(session, sourceRef, ids, token);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(owner, generation);
            RequireSameSession(session, result.ActiveSession);
            _session = result.ActiveSession;
            return result.Result;
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (ScmApiAuthenticationException error)
        {
            Privacy.OfficialMemberReadObservation.Failure(error);
            AccountReadTiming.G1Failure(error);
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        }
        catch (AccountBridgeHostException error) { AccountReadTiming.G1Failure(error); throw; }
        catch (Exception error) when (error is HttpRequestException or IOException or InvalidOperationException or
            System.Text.Json.JsonException or KeyNotFoundException or FormatException or OverflowException or
            OperationCanceledException or ArgumentException or TimeoutException)
        {
            // Unknown privacy/linkage must clear former identities, not retain
            // them as a transient public-directory failure or fall back to SCM.
            Privacy.OfficialMemberReadObservation.Failure(error);
            AccountReadTiming.G1Failure(error);
            throw OfficialFleetMemberIdentity.Invalid();
        }
    }

    private async Task<string> ResolveOfficialFleetProfileTargetAsync(AvatarTarget target,
        BridgeAccountContext owner, long generation, CancellationToken token)
    {
        FleetProfileTarget? known;
        lock (_fleetProfileTargetGate) _fleetProfileTargets.TryGetValue(target.Reference, out known);
        if (known is null || known.Owner != owner || known.Generation != generation || known.SourceRef != target.Context)
            throw new AccountBridgeHostException("profile.visitor_not_visible");
        var identities = await ReadFleetIdentitiesAsync(owner, generation, known.SourceRef, [known.MemberId], token);
        var fresh = identities[known.MemberId];
        if (fresh.State != "visible" || fresh.BusinessSubjectId != known.BusinessSubjectId)
        {
            lock (_fleetProfileTargetGate) _fleetProfileTargets.Remove(target.Reference);
            throw new AccountBridgeHostException("profile.visitor_not_visible");
        }
        RequireFleetReadOwner(owner, generation);
        return fresh.BusinessSubjectId!;
    }
}
