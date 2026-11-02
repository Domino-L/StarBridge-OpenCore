using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public bool PresenceRequiresSessionConfirmation => _session is not null || _legacySession is null;
    public async Task<PlayerPresenceVisibilityMode> SetPresenceVisibilityAuthorityAsync(
        BridgeAccountContext owner, long generation, PlayerPresenceVisibilityMode mode, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            RequirePresenceOwner(owner, generation);
            var relay = RequireRelaySession(owner);
            if (relay.Scm is null)
                // Legacy visibility is the existing local preference + the existing
                // publisher's clear/resume, never a fabricated SCM session.
                return mode;
            var requested = mode switch {
                PlayerPresenceVisibilityMode.Online => 1,
                PlayerPresenceVisibilityMode.InGame => 2,
                PlayerPresenceVisibilityMode.Invisible => 3,
                _ => throw new AccountBridgeHostException("presence.invalid_request")
            };
            long versionBefore;
            lock (_realtimeGate)
                versionBefore = _realtimeObservationVersion;
            var result = await _oauth.UpdatePresenceStatusAsync(relay.Scm, requested, token).ConfigureAwait(false);
            return CommitPresenceVisibilityReceipt(owner, generation, relay.Scm, result, versionBefore);
        }
        finally { _mutationGate.Release(); }
    }

    // Synchronous continuation of the authority request, under _mutationGate.
    // A different resource lane can refresh after OAuth returns its PUT receipt.
    // Retain that receipt only for its proven original identity/credential chain.
    internal PlayerPresenceVisibilityMode CommitPresenceVisibilityReceipt(BridgeAccountContext owner, long generation,
        ScmOAuthSession original, ScmPresenceStatusResult result, long versionBefore)
    {
        if (_disposed || generation != Generation || CurrentContext != ToContext(original))
            throw new AccountBridgeHostException("presence.account_changed");
        var active = result.ActiveSession;
        if (IsFirstUseAuthenticationCandidate)
            active = _oauth.ReadInstalledFirstUseSessionOrRefresh(original, active) ??
                throw new AccountBridgeHostException("presence.account_changed");
        RequireSameSession(original, active);
        CommitSharingSession(new(original), new(active));
        RequirePresenceOwner(owner, generation);
        var confirmed = result.Status.SignInStatus switch {
            1 => PlayerPresenceVisibilityMode.Online,
            2 => PlayerPresenceVisibilityMode.InGame,
            3 => PlayerPresenceVisibilityMode.Invisible,
            _ => throw new AccountBridgeHostException("presence.unconfirmed")
        };
        lock (_realtimeGate)
        {
            RequirePresenceOwner(owner, generation);
            // Any observation or disconnect during PUT takes precedence
            // over the receipt; fail closed.
            if (_realtimeObservationVersion == versionBefore)
                SetRealtimeObservation(new(generation, result.Status.SignInStatus, DateTimeOffset.UtcNow.AddSeconds(30)));
        }
        return confirmed;
    }

    private void RequirePresenceOwner(BridgeAccountContext owner, long generation)
    {
        if (_disposed || generation != Generation || GameplayTimeContext != owner)
            throw new AccountBridgeHostException("presence.account_changed");
    }
}
