using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : ICommunityNotificationReader
{
    internal event Action<BridgeAccountContext, long>? NotificationMembershipChanged;
    internal void ObserveFleetNotificationMembership(BridgeAccountContext owner, long generation, string? source)
    {
        // Serialize delivery too, so a bootstrap cannot publish after a newer
        // notification has already reached the announcement/overlay consumers.
        lock (_fleetNavigationGate)
        {
            if (_disposed || generation != Generation || owner != GameplayTimeContext) return;
            var observation = ++_fleetMembershipObservationVersion;
            ObserveFleetNavigationMembership(owner, generation, source);
            var changed = false;
            _communities?.ObserveOfficialNotificationMembership(FriendScope(owner, generation), source, out changed);
            // This path is also used by foreground membership refreshes, independently
            // of whether the overlay or the notification polling loop is active.
            if (_communities != null && changed) {
                // Navigation for a different source was cleared above. A bootstrap
                // which just confirmed this new source is already fresh.
                NotificationMembershipChanged?.Invoke(owner, generation);
            }
            // A subscriber may synchronously report a newer observation.
            if (observation == _fleetMembershipObservationVersion)
                FleetMembershipObserved?.Invoke(owner, generation, source);
        }
    }
    public async Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        var session = RequireRelaySession(owner);
        void Current() {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            if (_credentialTemporarilyUnavailable && !_reauthorizationRequired)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, retryable: true);
        if (_reauthorizationRequired)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            RequireSameRelaySession(RequireRelaySession(owner), session);
        }
        Current();
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var expectedScope = FriendScope(owner, generation);
        void Observed(string scope, string? source) {
            lock (_fleetNavigationGate)
            {
                if (scope != expectedScope) return;
                Current();
                ++_fleetMembershipObservationVersion;
                ObserveFleetNavigationMembership(owner, generation, source);
                FleetMembershipObserved?.Invoke(owner, generation, source);
            }
        }
        client.OfficialNotificationMembershipObserved += Observed;
        try {
            var result = await SendRelayRequestAsync(session, (active, ct) => active.Legacy is {} legacy
                ? client.ReadWpfS2NotificationsAsync(active.AccessToken, expectedScope, legacy.AccountId, Current, ct)
                : client.ReadScmNotificationsWithOfficialAsync(active.AccessToken, expectedScope, Current, ct), token);
            Current(); _session = result.ActiveSession.Scm;
            return result.Result;
        } finally { client.OfficialNotificationMembershipObserved -= Observed; }
    }
}
