using StarBridge.HostRuntime.Communities;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost : ICommunityNotificationReader
{
    public async Task<CommunityNotificationFeed> ReadNotificationsAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        var session = RequireRelaySession(owner);
        void Current() {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            RequireSameRelaySession(RequireRelaySession(owner), session);
        }
        Current();
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        var result = await SendRelayRequestAsync(session, (active, ct) => active.Legacy is {} legacy
            ? client.ReadWpfS2NotificationsAsync(active.AccessToken, FriendScope(owner, generation), legacy.AccountId, Current, ct)
            : throw new AccountBridgeHostException("communities.notificationsUnavailable"), token);
        Current(); _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
