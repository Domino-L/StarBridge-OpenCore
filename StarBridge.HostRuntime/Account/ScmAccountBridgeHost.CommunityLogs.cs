using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> DeleteCommunityLogAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
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
        var result = await SendRelayRequestAsync<object>(session,
            (active, ct) => active.Legacy is not null
                ? client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "log", Current, ct)
                : client.DeleteLogAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
