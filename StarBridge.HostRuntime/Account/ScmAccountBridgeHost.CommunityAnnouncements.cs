using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadCommunityAnnouncementsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityAnnouncementsAsync(context, payload, "read", token);
    public Task<object> ReadCommunityAnnouncementDetailAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityAnnouncementsAsync(context, payload, "detail", token);
    public Task<object> ManageCommunityAnnouncementsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityAnnouncementsAsync(context, payload, "manage", token);
    private async Task<object> CommunityAnnouncementsAsync(BridgeAccountContext context, JsonElement payload, string action, CancellationToken token)
    {
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, (active, ct) => action switch
        {
            "detail" => client.ReadAnnouncementDetailAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
            "manage" => client.ManageAnnouncementsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
            _ => client.ReadAnnouncementsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
        }, token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
