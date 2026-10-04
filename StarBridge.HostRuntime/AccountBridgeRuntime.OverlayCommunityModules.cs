using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private sealed record CommunityModuleRequest(BridgeAccountContext Owner, long Generation,
        IReadOnlyList<string> Codes, IReadOnlyList<string> CommunicationCodes, object Identity);

    private CommunityModuleRequest? CaptureModuleCommunityRequest()
    {
        var sink = _liveOverlaySink;
        var owner = GameplayOwner();
        if (_disposed || owner.Context is null || sink?.HasDisplayDemand != true || sink.ModuleDemand is not { Sources: { } preset } demand ||
            demand.ActiveModules.Count == 0 || _overlayCommunities is null) return null;
        var evidence = _moduleSourceBudget.EvidenceVersion;
        var room = (_host as ScmAccountBridgeHost)?.CurrentRoomOverlaySource;
        var context = _overlayCommunities.CaptureResolutionContext(owner.Context, owner.Generation, room?.Lease);
        if (context is null) return null;
        var temporary = demand.TemporarySource?.ForScope(context.OwnerKey, owner.Generation);
        object Identity(string sources) => (demand.RefreshIdentity, context.AccountChoice, sources);
        try
        {
            if (!_moduleSourceBudget.TryResolve(preset, context, evidence, temporary, demand.ActiveModules)) return null;
            var codes = OverlayModuleSourceResolver.RequestedCommunities(preset, context, demand.ActiveModules, temporary);
            var communication = OverlayModuleSourceResolver.RequestedCommunities(preset, context,
                demand.ActiveModules.Where(m => m is OverlaySourceModule.Notice or OverlaySourceModule.Chat).ToArray(), temporary);
            return codes.Count == 0 ? null : new(owner.Context, owner.Generation, codes, communication, Identity(string.Join("|", codes)));
        }
        catch (OverlaySourceLimitException)
        {
            // Retain only a low-frequency complete membership check while the
            // stable limit is latched. No content read and no expiry-based unlock.
            return _moduleSourceBudget.RequiresCommunityConfirmation(context.OwnerKey, owner.Generation)
                ? new(owner.Context, owner.Generation, [], [], Identity("limit-confirmation")) : null;
        }
    }
}
