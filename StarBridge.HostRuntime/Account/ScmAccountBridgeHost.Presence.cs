using StarBridge.Core.Presence;
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
            void Ensure()
            {
                if (_disposed || generation != Generation || GameplayTimeContext != owner)
                    throw new AccountBridgeHostException("presence.account_changed");
            }
            Ensure();
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
            var result = await _oauth.UpdatePresenceStatusAsync(relay.Scm, requested, token).ConfigureAwait(false);
            Ensure();
            RequireSameSession(relay.Scm, result.ActiveSession);
            _session = result.ActiveSession;
            return result.Status.SignInStatus switch {
                1 => PlayerPresenceVisibilityMode.Online,
                2 => PlayerPresenceVisibilityMode.InGame,
                3 => PlayerPresenceVisibilityMode.Invisible,
                _ => throw new AccountBridgeHostException("presence.unconfirmed")
            };
        }
        finally { _mutationGate.Release(); }
    }
}
