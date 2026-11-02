using System.Text.Json;
using StarBridge.HostRuntime.Communities;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private long _officialActivityWaitGeneration = -1;
    private CommunityClient.OfficialActivityWaitSession? _officialActivityWaitSession;
    public async Task<object> WaitOfficialFleetActivityAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        CommunityClient.ParseOfficialActivity(payload);
        _ = RequireSession(context);
        var session = await ReadDirectRelaySessionAsync(context, token).ConfigureAwait(false);
        var generation = Generation;
        void Current() {
            token.ThrowIfCancellationRequested();
            if (_disposed || generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
                throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
            _ = RequireSession(context);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        if (_officialActivityWaitGeneration != generation)
        {
            _officialActivityWaitSession = new();
            _officialActivityWaitGeneration = generation;
        }
        // The actual wait does not hold the snapshot's short recovery lease.
        var result = await client.WaitOfficialActivityAsync(session.AccessToken, payload, Current, token, _officialActivityWaitSession);
        Current();
        return result;
    }
}
