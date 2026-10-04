using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private readonly OverlayModuleSourceBudget _moduleSourceBudget = new();
    private Privacy.SharedActivitySubscription CaptureModuleActivityContext(InformationOverlayModuleDemand demand,
        StarBridge.NativeBridge.BridgeAccountContext? owner, long generation)
    {
        Privacy.SharedActivitySubscription Empty() => new(null, generation, null, null);
        if (owner is null || demand.Sources is null || !demand.ActiveModules.Contains(OverlaySourceModule.Events)) return Empty();
        // Reuse the display admission and display-time authority checks. This is
        // memory-only, and checks the budget for ALL visible modules, not merely
        // Events, so a fourth source cannot bypass the stable limit state.
        var temporary = demand.TemporarySource?.ForScope(OverlaySceneChoiceStore.Hash(owner), generation);
        var result = ReadOverlayModules(demand.Sources, temporary, demand.ActiveModules, out var admission);
        var content = result.Frame?.ReadModules(DateTimeOffset.UtcNow)[OverlaySourceModule.Events];
        var sink = _liveOverlaySink;
        if (admission is null || content?.Snapshot is not { AuthorityStamp: { } stamp } || !content.Source.Available ||
            GameplayOwner() != (owner, generation) || sink?.IsVisible != true ||
            sink.ModuleDemand?.RefreshIdentity != demand.RefreshIdentity) return Empty();
        var source = content.Source; // Retain authority metadata, not the roster payload.
        return source.Mode switch
        {
            OverlaySourceMode.Community => new(owner, generation, "organization", source.Id, stamp)
                { IsAuthorized = () => ProbeModuleActivity(owner, generation, demand.RefreshIdentity, admission, source, stamp) },
            OverlaySourceMode.Room => new(owner, generation, "room", source.Id, stamp)
                { IsAuthorized = () => ProbeModuleActivity(owner, generation, demand.RefreshIdentity, admission, source, stamp) },
            _ => Empty()
        };
    }
    private bool ProbeModuleActivity(StarBridge.NativeBridge.BridgeAccountContext owner, long generation,
        string demandKey, OverlayModuleSourceBudget.Admission admission, OverlayResolvedSource expected, object stamp)
    {
        var sink = _liveOverlaySink;
        if (_disposed || GameplayOwner() != (owner, generation) || sink?.IsVisible != true ||
            sink.ModuleDemand?.RefreshIdentity != demandKey) return false;
        var room = (_host as ScmAccountBridgeHost)?.PeekRoomOverlayAuthority(owner, generation);
        var context = _overlayCommunities?.PeekResolutionContext(owner, generation, room?.Lease);
        if (context is null || _moduleSourceBudget.Inspect(admission, context)?.Modules[OverlaySourceModule.Events] != expected) return false;
        var authorized = expected.Mode == OverlaySourceMode.Room
            ? (_host as ScmAccountBridgeHost)?.PeekRoomOverlayAuthority(owner, generation) is { } currentRoom &&
                currentRoom.Lease.Id == expected.Id && ReferenceEquals(stamp, currentRoom.Stamp)
            : expected.Mode == OverlaySourceMode.Community &&
                _overlayCommunities!.IsModuleAuthorityCurrent(owner, generation, expected.Id!, stamp);
        return authorized && !_disposed && GameplayOwner() == (owner, generation) && sink.IsVisible &&
            sink.ModuleDemand?.RefreshIdentity == demandKey;
    }
    /// <summary>Host-only batch read; not a Bridge request accepting caller authority.</summary>
    public InformationOverlayModuleReadResult ReadOverlayModules(InformationOverlayRuntimeWorkspace workspace)
    {
        var owner = GameplayOwner();
        var temporary = owner.Context is null ? null : workspace.TemporarySource?.ForScope(
            OverlaySceneChoiceStore.Hash(owner.Context), owner.Generation);
        return ReadOverlayModules(workspace.Sources!, temporary,
            OverlayModuleSourceResolver.VisibleModules(workspace.Settings));
    }

    public InformationOverlayModuleReadResult ReadOverlayModules(OverlayPresetSources preset,
        OverlaySourceBinding? temporaryChoice = null, IReadOnlyCollection<OverlaySourceModule>? activeModules = null) =>
        ReadOverlayModules(preset, temporaryChoice, activeModules, out _, captureAdmission: false);

    private InformationOverlayModuleReadResult ReadOverlayModules(OverlayPresetSources preset,
        OverlaySourceBinding? temporaryChoice, IReadOnlyCollection<OverlaySourceModule>? activeModules,
        out OverlayModuleSourceBudget.Admission? admission, bool captureAdmission = true)
    {
        admission = null;
        var owner = GameplayOwner();
        if (_disposed) return new(null, "overlay.identity_unavailable");
        if (owner.Context is null)
        {
            // Anonymous local display is not a synthetic signed-in account.
            // No remote lease, directory, network read or account choice is supplied.
            var local = new OverlaySourceResolutionContext("anonymous-local", owner.Generation, DateTimeOffset.UtcNow,
                OverlaySourceBinding.Automatic, null, null, new Dictionary<string, OverlaySourceLease>());
            return InformationOverlayModuleFrame.TryCapture(preset, local, _ => null,
                () => !_disposed && GameplayOwner() == owner, _ => false, temporaryChoice, activeModules);
        }
        if (_overlayCommunities is null) return new(null, "overlay.identity_unavailable");
        for (var attempt = 0; attempt < 3; attempt++)
        {
            var evidenceVersion = _moduleSourceBudget.EvidenceVersion;
            var room = (_host as ScmAccountBridgeHost)?.CurrentRoomOverlaySource;
            var context = _overlayCommunities.CaptureResolutionContext(owner.Context, owner.Generation, room?.Lease);
            if (context is null) return new(null, "overlay.source_unavailable");
            try
            {
                if (!_moduleSourceBudget.TryResolve(preset, context, evidenceVersion, temporaryChoice, activeModules)) continue;
            }
            catch (OverlaySourceLimitException) { return new(null, "overlay.sources_limit_exceeded"); }
            if (captureAdmission)
            {
                admission = _moduleSourceBudget.CaptureAdmission(preset, context, temporaryChoice, activeModules);
                if (admission is null) continue;
            }
            bool Current() => !_disposed && GameplayOwner() == owner;
            InformationOverlaySourceSnapshot? Read(OverlayResolvedSource source) => source.Mode switch
            {
                OverlaySourceMode.Room => (_host as ScmAccountBridgeHost)?.CurrentRoomOverlaySource,
                OverlaySourceMode.Community => _overlayCommunities.ReadModuleSource(owner.Context, owner.Generation, source.Id!),
                _ => null
            };
            bool Authorized(InformationOverlaySourceSnapshot snapshot)
            {
                if (!Current()) return false;
                if (snapshot.Lease.Mode == OverlaySourceMode.Community)
                    return _overlayCommunities.IsModuleSourceCurrent(owner.Context, owner.Generation, snapshot);
                return (_host as ScmAccountBridgeHost)?.IsRoomOverlaySourceCurrent(snapshot) == true;
            }
            return InformationOverlayModuleFrame.TryCapture(preset, context, Read, Current, Authorized, temporaryChoice, activeModules);
        }
        return new(null, "overlay.source_unavailable");
    }
}
