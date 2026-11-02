using System.Text.Json;
using StarBridge.NativeBridge;
namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> SubmitAchievementIdeaAsync(BridgeAccountContext context, JsonElement payload, CancellationToken token)
    {
        var generation = Generation;
        // Background account reads can hold this gate. Wait briefly without replaying the mail write.
        if (!await _mutationGate.WaitAsync(TimeSpan.FromSeconds(5), token)) throw new AccountBridgeHostException("ideas.busy");
        try
        {
            var client = _achievementIdeas ?? throw new AccountBridgeHostException("ideas.unavailable");
            token.ThrowIfCancellationRequested();
            if (generation != Generation) throw new BridgeStaleGenerationException(generation, Generation);
            var session = RequireSession(context);
            if (_disposed || _reauthorizationRequired || _credentialTemporarilyUnavailable) throw new AccountBridgeHostException("ideas.sign_in");
            var result = await client.Send(session.AccessToken, payload, token);
            lock (_loginGate)
            {
                token.ThrowIfCancellationRequested();
                if (_disposed || generation != Generation || context != CurrentContext) throw new BridgeStaleGenerationException(generation, Generation);
                RequireSameSession(RequireSession(context), session);
            }
            return result;
        }
        finally { if (!_disposed) _mutationGate.Release(); }
    }
}
