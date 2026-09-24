using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public Task<object> ReadCommunityChatAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityChatAsync(context, payload, "read", token);
    public Task<object> ReadCommunityChatDetailAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityChatAsync(context, payload, "detail", token);
    public Task<object> MarkCommunityChatReadAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityChatAsync(context, payload, "markRead", token);
    public Task<object> SendCommunityChatAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token) =>
        CommunityChatAsync(context, payload, "send", token);
    private async Task<object> CommunityChatAsync(BridgeAccountContext context, JsonElement payload, string action, CancellationToken token)
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
            "detail" => client.ReadChatDetailAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
            "markRead" => client.MarkChatReadAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
            "send" => client.SendChatAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct),
            _ => client.ReadChatAsync(active.AccessToken, payload, FriendScope(context, generation), Current, ct, JsonSerializer.Serialize(context)),
        }, token);
        Current();
        _session = result.ActiveSession.Scm;
        return result.Result;
    }
}
