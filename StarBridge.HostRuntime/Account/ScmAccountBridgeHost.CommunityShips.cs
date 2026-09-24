using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> ReportCommunityShipImageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
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
        var result = await SendRelayRequestAsync<object>(session, (active, ct) =>
            client.ReportShipImageAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    public async Task<object> ReadCommunityShipImageAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
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
        var result = await SendRelayRequestAsync<object>(session, (active, ct) =>
            client.ReadShipImageAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
    public async Task<object> ReadCommunityShipsAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
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
        var result = await SendRelayRequestAsync<object>(session, (active, ct) =>
            client.ReadShipsAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct), token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
