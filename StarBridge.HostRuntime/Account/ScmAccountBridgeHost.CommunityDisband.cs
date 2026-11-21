using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadCommunityDisbandAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityDisbandAsync(context, payload, false, token);
    public Task<object> DisbandCommunityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityDisbandAsync(context, payload, true, token);

    private async Task<object> CommunityDisbandAsync(BridgeAccountContext context, JsonElement payload, bool execute, CancellationToken token)
    {
        if (execute) CommunityClient.ValidateDisband(payload, allowEmptyPassword: true);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_credentialTemporarilyUnavailable && !_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.CredentialTemporarilyUnavailable, retryable: true);
        if (_reauthorizationRequired)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        var result = await SendRelayRequestAsync<object>(session, (active, ct) => active.Legacy is not null
            ? execute ? client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "disband", Current, ct)
                : client.ReadWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), "disband", Current, ct)
            : execute
            ? client.DisbandAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct)
            : client.ReadDisbandAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
