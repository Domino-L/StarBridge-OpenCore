using StarBridge.Core.Presence;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<CommunityMemberDirectoryPage> ReadCommunitySharingMembersAsync(
        BridgeAccountContext owner, long generation, CommunityMemberDirectoryRequest input, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            RequireOwner();
            var writer = _privacyWriter ?? throw new AccountBridgeHostException("privacy_publication.member_scopes_unavailable");
            var session = RequireRelaySession(owner);
            var result = await SendRelayRequestAsync(session, async (active, ct) => {
                RequireOwner();
                return await writer.ReadCommunityMembersAsync(active.AccessToken, input, ct).ConfigureAwait(false);
            }, token).ConfigureAwait(false);
            RequireOwner();
            RequireSameRelaySession(RequireRelaySession(owner), result.ActiveSession);
            _session = result.ActiveSession.Scm;
            return result.Result;
        }
        finally { _mutationGate.Release(); }

        void RequireOwner()
        {
            if (_disposed || Generation != generation || GameplayTimeContext != owner)
                throw new AccountBridgeHostException("privacy_publication.account_changed");
        }
    }
}
