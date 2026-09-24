using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadCommunityOwnershipTransferAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityOwnershipTransferAsync(context, payload, false, token);
    public Task<object> TransferCommunityOwnershipAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityOwnershipTransferAsync(context, payload, true, token);
    public Task<object> ReadCommunityOwnershipExitAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityOwnershipTransferAsync(context, payload, false, token, leaveAfterTransfer: true);
    public Task<object> LeaveCommunityWithSuccessorAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityOwnershipTransferAsync(context, payload, true, token, leaveAfterTransfer: true);

    private async Task<object> CommunityOwnershipTransferAsync(BridgeAccountContext context, JsonElement payload, bool transfer,
        CancellationToken token, bool leaveAfterTransfer = false)
    {
        if (transfer) CommunityClient.ValidateOwnershipTransfer(payload);
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
        var result = await SendRelayRequestAsync<object>(session, async (active, ct) => active.Legacy is not null
            ? transfer ? await client.WriteWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), leaveAfterTransfer ? "exit" : "transfer", Current, ct)
                : await client.ReadWpfS2GovernanceAsync(active.AccessToken, payload, FriendScope(context, generation), leaveAfterTransfer ? "exit" : "transfer", Current, ct)
            : transfer
            ? await client.TransferOwnershipAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct, leaveAfterTransfer)
            : await client.ReadOwnershipTransferAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct, leaveAfterTransfer), token);
        Current();
        _session = result.ActiveSession.Scm;
        // The workspace must reread after acceptance. Do not discard other organizations' drafts;
        // each subsequent governance write still rechecks current authority on the server.
        return result.Result;
    }
}
