using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.OfficialFleet;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    // Process-local addressing only: no roster, identity, visibility, permission,
    // bootstrap snapshot or persisted representation belongs in this entry.
    private sealed record FleetNavigation(BridgeAccountContext Owner, long Generation, Guid SessionVersion,
        string SourceRef, string Sid, DateTimeOffset SessionExpiresAt, long CheckedAt, long Revocation);
    private sealed class FleetNavigationRead(FleetNavigation? entry, long epoch)
    {
        internal FleetNavigation? Entry = entry;
        internal long Epoch = epoch;
    }
    private readonly object _fleetNavigationGate = new();
    private readonly SemaphoreSlim _fleetNavigationRead = new(1, 1);
    private FleetNavigation? _fleetNavigation;
    private long _fleetNavigationEpoch;
    private long _fleetMembershipObservationVersion;
    private bool _fleetMembershipKnown;
    private string? _fleetObservedSource;

    private void ClearFleetNavigation()
    {
        lock (_fleetNavigationGate) {
            _fleetNavigation = null; _fleetNavigationEpoch++;
            _fleetMembershipKnown = false; _fleetObservedSource = null;
        }
    }

    private void ClearFleetNavigation(BridgeAccountContext owner, long generation, FleetNavigationRead read)
    {
        lock (_fleetNavigationGate)
        {
            // An old request must never invalidate a replacement account's entry.
            if (CurrentContext != owner || Generation != generation ||
                !ReferenceEquals(_fleetNavigation, read.Entry) || _fleetNavigationEpoch != read.Epoch) return;
            _fleetNavigation = null; _fleetNavigationEpoch++;
        }
    }

    private void ObserveFleetNavigationMembership(BridgeAccountContext owner, long generation, string? source)
    {
        lock (_fleetNavigationGate)
        {
            if (CurrentContext != owner || Generation != generation) return;
            // Observation order is independent of revocation. A cold bootstrap
            // can overlap a confirmation of its own source without being revoked.
            if (source is null || (_fleetMembershipKnown && _fleetObservedSource != source) ||
                (_fleetNavigation is { } known && (known.Owner != owner ||
                    known.Generation != generation || known.SourceRef != source)))
            { _fleetNavigation = null; _fleetNavigationEpoch++; }
            _fleetMembershipKnown = true; _fleetObservedSource = source;
        }
    }

    private async Task<object> WithFleetNavigationFailureAsync(BridgeAccountContext owner, long generation, Func<FleetNavigationRead, Task<object>> read)
    {
        FleetNavigationRead use;
        lock (_fleetNavigationGate) use = new(_fleetNavigation, _fleetNavigationEpoch);
        try {
            var result = await read(use).ConfigureAwait(false);
            RequireFleetNavigationCurrent(owner, generation, use);
            return result;
        }
        catch { ClearFleetNavigation(owner, generation, use); throw; }
    }

    private FleetNavigation? ReuseFleetNavigation(BridgeAccountContext owner, long generation, string source, ScmOAuthSession session)
    {
        lock (_fleetNavigationGate)
        {
            var known = _fleetNavigation;
            if (known is not null && known.Owner == owner && known.Generation == generation &&
                known.SourceRef == source && known.SessionVersion == session.CredentialVersion &&
                _oauth.CanReuseResourceSession(session) &&
                known.SessionExpiresAt == session.ExpiresAt && session.ExpiresAt > _oauth.SessionNow.AddMinutes(1) &&
                _oauth.SessionClock.GetElapsedTime(known.CheckedAt) is var age && age >= TimeSpan.Zero && age < TimeSpan.FromMinutes(5))
                return known;
            // TTL expiry is a metadata refresh, not a revocation of readers
            // already using this address. Keep it until the replacement arrives.
            if (known is not null && (known.Owner != owner || known.Generation != generation ||
                known.SourceRef != source || known.SessionVersion != session.CredentialVersion ||
                !_oauth.CanReuseResourceSession(session)))
            { _fleetNavigation = null; _fleetNavigationEpoch++; }
            return null;
        }
    }

    private void RequireFleetNavigationOwner(BridgeAccountContext owner, long generation, FleetNavigation navigation)
    {
        RequireFleetReadOwner(owner, generation);
        lock (_fleetNavigationGate)
            if (_fleetNavigationEpoch != navigation.Revocation ||
                RequireSession(owner).CredentialVersion != navigation.SessionVersion ||
                _oauth.CurrentCredentialVersion != navigation.SessionVersion) throw OfficialFleetReadModel.Invalid();
    }

    private void RequireFleetNavigationCurrent(BridgeAccountContext owner, long generation, FleetNavigationRead use)
    {
        RequireFleetReadOwner(owner, generation);
        // Follow the read's revocation, not the cache entry reference/TTL. An
        // equivalent refresh may replace the entry without revoking this round.
        // Session lifecycle publication already revokes via ClearFleetNavigation;
        // resource authentication may still perform its normal same-owner refresh.
        lock (_fleetNavigationGate)
            if (use.Entry is null || use.Epoch != _fleetNavigationEpoch) throw OfficialFleetReadModel.Invalid();
    }

    private async Task<FleetNavigation> ReadFleetNavigationAsync(BridgeAccountContext owner, long generation,
        string source, FleetNavigationRead use, CancellationToken token)
    {
        RequireFleetReadOwner(owner, generation);
        var known = ReuseFleetNavigation(owner, generation, source, RequireSession(owner));
        if (known is not null) { use.Entry = known; use.Epoch = known.Revocation; return known; }
        await _fleetNavigationRead.WaitAsync(token).ConfigureAwait(false);
        try
        {
            RequireFleetReadOwner(owner, generation);
            var session = RequireSession(owner);
            known = ReuseFleetNavigation(owner, generation, source, session);
            if (known is not null) { use.Entry = known; use.Epoch = known.Revocation; return known; }
            long epoch, observation;
            lock (_fleetNavigationGate) { epoch = _fleetNavigationEpoch; observation = _fleetMembershipObservationVersion; }
            // Count the TTL from request start, so a slow response cannot extend it.
            var started = _oauth.SessionClock.GetTimestamp();
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
            var bootstrap = await _oauth.LoadBootstrapAsync(session, token).ConfigureAwait(false);
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.OwnerFence);
            RequireFleetReadOwner(owner, generation);
            RequireSameSession(session, bootstrap.ActiveSession);
            if (bootstrap.ResponseCredentialVersion != bootstrap.ActiveSession.CredentialVersion ||
                !_oauth.CanReuseResourceSession(bootstrap.ActiveSession)) throw OfficialFleetReadModel.Invalid();
            var fleet = ProjectOfficialFleet(bootstrap.Snapshot, _oauth.SessionNow).Fleet;
            lock (_fleetNavigationGate)
            {
                RequireFleetReadOwner(owner, generation);
                if (epoch != _fleetNavigationEpoch) throw OfficialFleetReadModel.Invalid();
                var superseded = observation != _fleetMembershipObservationVersion;
                if (superseded && (fleet is null || _fleetObservedSource != fleet.SourceRef))
                    throw OfficialFleetReadModel.Invalid();
                _session = bootstrap.ActiveSession;
                if (_fleetNavigation is { } prior && (fleet is null || prior.SourceRef != fleet.SourceRef ||
                    prior.Sid != fleet.Sid || prior.SessionVersion != bootstrap.ActiveSession.CredentialVersion))
                    _fleetNavigationEpoch++;
                // Apply a confirmed relationship change before stamping the new
                // entry's revocation version; its own observation must not revoke it.
                if (!superseded) ObserveFleetNavigationMembership(owner, generation, fleet?.SourceRef);
                known = fleet is null ? null : new(owner, generation, bootstrap.ActiveSession.CredentialVersion,
                    fleet.SourceRef, fleet.Sid, bootstrap.ActiveSession.ExpiresAt, started, _fleetNavigationEpoch);
                // Even a newer same-source observation wins publication order.
                // The current read may finish, but this response cannot fill cache.
                _fleetNavigation = superseded ? null : known;
                use.Entry = known; use.Epoch = _fleetNavigationEpoch;
                // Commit and publish as one ordered observation. A newer real
                // observation must never be followed by this older bootstrap.
                // Publish fresh absence/change even for a request for the old source.
                if (!superseded) ObserveFleetNotificationMembership(owner, generation, fleet?.SourceRef);
            }
            AccountReadTiming.Checkpoint(MemberReadCheckpoint.Bootstrap);
            if (known is null || known.SourceRef != source)
            { ClearFleetNavigation(owner, generation, use); throw OfficialFleetReadModel.Invalid(); }
            return known;
        }
        finally { _fleetNavigationRead.Release(); }
    }
}
