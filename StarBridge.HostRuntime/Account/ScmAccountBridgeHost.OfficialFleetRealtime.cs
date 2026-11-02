using System.Text.Json;
using StarBridge.HostRuntime.Privacy;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    internal bool OfficialRealtimeEnabled { get; private set; }
    internal void ConfigureOfficialRealtime(bool enabled) => OfficialRealtimeEnabled = enabled;
    internal bool HasOfficialRealtimeProtocol => OfficialRealtimeEnabled && _privacyWriter is not null;
    internal async Task<OfficialRealtimeContextWire> ReadOfficialRealtimeContextAsync(
        BridgeAccountContext context, long generation, CancellationToken token)
    {
        if (!OfficialRealtimeEnabled) throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
        RequireFleetReadOwner(context, generation);
        var session = RequireRelaySession(context);
        var writer = _privacyWriter ?? throw new AccountBridgeHostException("official_fleet.runtime_unavailable");
        var result = await SendRelayRequestAsync(session, async (active, ct) => {
            RequireFleetReadOwner(context, generation);
            var value = await writer.ReadOfficialRealtimeContextAsync(active.AccessToken, ct);
            RequireFleetReadOwner(context, generation); return value;
        }, token);
        RequireSameRelaySession(RequireRelaySession(context), result.ActiveSession);
        CommitSharingSession(session, result.ActiveSession);
        RequireFleetReadOwner(context, generation);
        return result.Result;
    }
}
