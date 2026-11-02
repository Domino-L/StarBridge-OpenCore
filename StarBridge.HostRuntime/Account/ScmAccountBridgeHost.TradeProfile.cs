using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    public async Task<object> TradeProfileAsync(BridgeAccountContext context, bool write, JsonElement changes, CancellationToken token)
    {
        var generation = Generation;
        RequireAccountProfileReadOwner(context, generation);
        if (write && !await _marketplaceWriteGate.WaitAsync(0, token)) throw new AccountBridgeHostException("marketplace.busy");
        try {
            var session = RequireSession(context);
            bool Current() => !_disposed && Generation == generation && CurrentContext == context && !_localModeSessionLoopsStopped;
            var result = await _oauth.TradeProfileAsync(session, write, changes, Current, token);
            lock (_realtimeGate) {
                token.ThrowIfCancellationRequested();
                RequireAccountProfileReadOwner(context, generation);
                RequireSameSession(session, result.ActiveSession);
                _session = result.ActiveSession;
            }
            return new { schemaVersion = 1, data = result.Data };
        } finally { if (write) _marketplaceWriteGate.Release(); }
    }
}
