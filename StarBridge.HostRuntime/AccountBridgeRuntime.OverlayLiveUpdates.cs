namespace StarBridge.HostRuntime;

using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Account;
using StarBridge.Core.Overlay;

public sealed partial class AccountBridgeRuntime
{
    private IInformationOverlayLiveUpdateSink? _liveOverlaySink;
    private OverlayRoomRefreshDriver? _liveRoomRefresh;
    private OverlayRoomRefreshDriver? _liveModuleCommunities;
    public void ConfigureLiveOverlayUpdates(IInformationOverlayLiveUpdateSink sink)
    {
        using var configuration = EnterAccountBusinessConfiguration();
        if (configuration is null) throw new InvalidOperationException("Account background work has retired.");
        if (_liveOverlaySink is not null) throw new InvalidOperationException("Live overlay updates already configured.");
        _liveOverlaySink = sink;
        _overlayCommunities?.SetModuleMode(() => sink.ModuleDemand is not null,
            () => CaptureModuleCommunityRequest()?.Identity);
        _host.AccountChanged += InvalidateLiveOverlay;
        if (_overlayCommunities is not null) _overlayCommunities.ContentChanged += sink.RequestContentRefresh;
        if (_host is ScmAccountBridgeHost roomHost)
        {
            roomHost.RoomOverlayContentChanged += sink.RequestContentRefresh;
            roomHost.RoomOverlayMembershipConfirmed += ConfirmModuleRoomMembership;
        }
        _liveRoomRefresh = new(() =>
        {
            var owner = GameplayOwner();
            var enabled = !_disposed && !_localBusinessRetired &&
                (sink.HasDisplayDemand || sink.ModuleDemand is not null && sink.HasStandbyDemand) && (sink.ModuleDemand is { } demand
                ? ModuleRequestsRoomRefresh(demand, owner.Context, owner.Generation)
                : CurrentOverlaySceneMode == "room" || CurrentOverlaySceneMode == "auto" && CurrentRoomOverlay is not null);
            return (owner.Context, owner.Generation, enabled);
        }, async (owner, token) =>
        {
            try { await _host.GetPartyRoomsAsync(owner, token).ConfigureAwait(false); }
            finally { if (!_disposed && !_localBusinessRetired) sink.RequestContentRefresh(); }
        }, successInterval: () => ModuleRoomRefreshInterval(sink),
            demandIdentity: () => sink.ModuleDemand?.RefreshIdentity, startDriver: !_firstUseCandidate);
        if (_moduleCommunityDriverEnabled && _overlayCommunities is not null)
            _liveModuleCommunities = new(() =>
            {
                var request = CaptureModuleCommunityRequest();
                return (request?.Owner, request?.Generation ?? Generation, request is not null);
            }, async (owner, token) =>
            {
                var request = CaptureModuleCommunityRequest();
                if (request is not null && request.Owner == owner)
                {
                    if (request.FleetConfirmation)
                        await _overlayCommunities.RefreshFleetMembershipAsync(owner, request.Generation, token).ConfigureAwait(false);
                    await _overlayCommunities.RefreshModuleSourcesAsync(owner, request.Generation, request.Codes, token,
                        request.CommunicationCodes).ConfigureAwait(false);
                }
            }, successInterval: () => _overlayCommunities.ModuleRefreshDelay,
                demandIdentity: () => CaptureModuleCommunityRequest()?.Identity, startDriver: !_firstUseCandidate);
    }

    private TimeSpan ModuleRoomRefreshInterval(IInformationOverlayLiveUpdateSink sink)
    {
        if (sink.ModuleDemand is null) return TimeSpan.FromSeconds(1);
        // Background renewal only needs to beat the 30-second room lease.
        if (!sink.HasDisplayDemand) return TimeSpan.FromSeconds(15);
        var owner = GameplayOwner();
        var confirmingLimit = owner.Context is not null &&
            _moduleSourceBudget.RequiresRoomConfirmation(OverlaySceneChoiceStore.Hash(owner.Context), owner.Generation);
        return TimeSpan.FromSeconds(CurrentRoomOverlay is null || confirmingLimit ? 15 : 1);
    }

    private void ConfirmModuleRoomMembership(StarBridge.NativeBridge.BridgeAccountContext owner, long generation, string? room)
    {
        _moduleSourceBudget.ConfirmRoom(OverlaySceneChoiceStore.Hash(owner), generation, room);
        _liveOverlaySink?.RequestContentRefresh();
    }

    private bool ModuleRequestsRoomRefresh(InformationOverlayModuleDemand demand,
        StarBridge.NativeBridge.BridgeAccountContext? owner, long generation)
    {
        if (owner is null || demand.Sources is null || demand.ActiveModules.Count == 0) return false;
        var evidenceVersion = _moduleSourceBudget.EvidenceVersion;
        var room = (_host as ScmAccountBridgeHost)?.CurrentRoomOverlaySource;
        var context = _overlayCommunities?.CaptureResolutionContext(owner, generation, room?.Lease);
        if (context is null) return false;
        var temporary = demand.TemporarySource?.ForScope(context.OwnerKey, generation);
        try
        {
            if (!_moduleSourceBudget.TryResolve(demand.Sources, context, evidenceVersion, temporary, demand.ActiveModules)) return false;
            return OverlayModuleSourceResolver.RequestsRoomRefresh(demand.Sources, context, demand.ActiveModules, temporary);
        }
        catch (OverlaySourceLimitException)
        {
            // Keep low-frequency authenticated membership confirmation alive:
            // remote leave/kick/closure must resolve without visiting a page.
            return _moduleSourceBudget.RequiresRoomConfirmation(OverlaySceneChoiceStore.Hash(owner), generation);
        }
    }

    private void InvalidateLiveOverlay(long generation)
    {
        _ = generation;
        // The render-thread read rechecks the actual owner. Waking it must not
        // wait for a source poll, or turn a completed logout into a UI failure.
        if (!_disposed && !_localBusinessRetired)
            try { _liveOverlaySink?.RequestContentRefresh(); } catch { }
    }

    private Task RetireLiveOverlayUpdatesAsync()
    {
        var rooms = _liveRoomRefresh;
        var communities = _liveModuleCommunities;
        DisposeLiveOverlayUpdates();
        return Task.WhenAll(rooms?.Completion ?? Task.CompletedTask, communities?.Completion ?? Task.CompletedTask);
    }

    private void DisposeLiveOverlayUpdates()
    {
        _liveRoomRefresh?.Dispose();
        _liveModuleCommunities?.Dispose();
        _host.AccountChanged -= InvalidateLiveOverlay;
        if (_liveOverlaySink is { } sink && _overlayCommunities is not null)
            _overlayCommunities.ContentChanged -= sink.RequestContentRefresh;
        if (_liveOverlaySink is { } roomSink && _host is ScmAccountBridgeHost roomHost)
        {
            roomHost.RoomOverlayContentChanged -= roomSink.RequestContentRefresh;
            roomHost.RoomOverlayMembershipConfirmed -= ConfirmModuleRoomMembership;
        }
        _liveOverlaySink = null;
    }
}
