using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> OfficialFleetRallyAsync(BridgeAccountContext context, JsonElement body, CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token);
        deadline.CancelAfter(TimeSpan.FromSeconds(12));
        _ = RequireSession(context);
        var session = RequireRelaySession(context);
        var generation = Generation;
        if (_reauthorizationRequired || _credentialTemporarilyUnavailable)
            throw new AccountBridgeHostException(AccountBridgeStableErrors.ReauthorizationRequired);
        var client = _communities ?? throw new AccountBridgeHostException("communities.unavailable");
        void Current()
        {
            deadline.Token.ThrowIfCancellationRequested();
            if (_disposed || Generation != generation) throw new BridgeStaleGenerationException(generation, Generation);
            _ = RequireSession(context);
            RequireSameRelaySession(RequireRelaySession(context), session);
        }
        Current();
        var result = await SendRelayRequestAsync<object>(session, (active, ct) =>
            client.OfficialRallyAsync(active.AccessToken, body, Current, ct), deadline.Token);
        Current();
        CommitSharingSession(session, result.ActiveSession);
        Current();
        return result.Result;
    }
}
