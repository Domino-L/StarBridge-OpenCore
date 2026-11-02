using StarBridge.Core.Overlay;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

// The fleet has an independent membership/read lifetime. It shares the existing
// bounded source driver, roster receipts, backoff and chat-baseline policy.
internal interface IOverlayFleetReader
{
    Task<OverlayCommunityTarget?> ReadFleetTargetAsync(BridgeAccountContext owner, CancellationToken token);
    Task<InformationOverlayCommunityContent> ReadFleetContentAsync(BridgeAccountContext owner,
        OverlayCommunityTarget target, Action<InformationOverlayCommunityContent>? rosterReady,
        bool communication, CancellationToken token);
    Task<OverlayActivityCursor> WaitFleetChangesAsync(BridgeAccountContext owner, long generation,
        OverlayActivityCursor after, CancellationToken token);
}

internal sealed partial class OverlayCommunitySource
{
    internal const string FocusFleetRequest = "overlayScenes.focusFleet";
    internal const string FleetId = "fleet";
    private readonly OverlayCommunitySource? _fleetSource;
    private readonly bool _isFleetSession;
    private bool _pageFleet;
    private string? _fleetReference;
    private bool _fleetNotMember;

    private bool WantsFleet => _choice.Mode == "fleet" || _choice.Mode == "auto" && _pageFleet;
    internal bool IsFleetSelected { get { lock (_sync) { CheckScope(); return WantsFleet; } } }

    private sealed class FleetReader(IOverlayFleetReader reader) : IOverlayCommunityReader, IOverlayCommunityChangeReader
    {
        public async Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(BridgeAccountContext owner, CancellationToken token) =>
            await reader.ReadFleetTargetAsync(owner, token).ConfigureAwait(false) is { } target ? [target] : [];
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            reader.ReadFleetContentAsync(owner, target, null, true, token);
        public Task<InformationOverlayCommunityContent> ReadContentAsync(BridgeAccountContext owner, OverlayCommunityTarget target,
            Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token) =>
            reader.ReadFleetContentAsync(owner, target, rosterReady, true, token);
        public Task<InformationOverlayCommunityContent> ReadRosterAsync(BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
            reader.ReadFleetContentAsync(owner, target, null, false, token);
        public Task<OverlayActivityCursor> WaitForChangesAsync(BridgeAccountContext owner, long generation,
            OverlayActivityCursor after, CancellationToken token) => reader.WaitFleetChangesAsync(owner, generation, after, token);
    }

    internal void SetFleetDemand(bool requested)
    {
        if (requested) _fleetSource?.ReadForDisplay();
        else _fleetSource?.SuspendDisplayDemand();
    }

    internal Task RefreshFleetMembershipAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
        ProbeFleetAsync((owner, generation), token, true);

    private async Task ProbeFleetAsync((BridgeAccountContext? Owner, long Generation) scope, CancellationToken token, bool force = false)
    {
        if (_fleetSource is not { } fleet) return;
        try { await fleet.CatalogAsync(scope, force, token).ConfigureAwait(false); }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (Exception error)
        {
            lock (fleet._sync)
            {
                if (fleet._owner() != scope) return;
                fleet.CheckScope();
                if (IsTransientReadFailure(error)) fleet._transientFailures = Math.Min(4, fleet._transientFailures + 1);
                else
                {
                    // Rejection ends both pending read lifetimes. Cached membership
                    // must not authorize another read until a fresh probe succeeds.
                    fleet.RejectReadAuthority();
                }
            }
        }
    }

    // The fleet's own name from the confirmed membership read, so the picker can
    // list it like an organization. Null while unknown or not a member.
    private string? FleetName()
    {
        if (_fleetSource is not { } fleet) return null;
        lock (fleet._sync)
        {
            fleet.CheckScope();
            return fleet._fleetNotMember ? null : fleet._catalog.FirstOrDefault()?.Name;
        }
    }

    private string FleetStatus()
    {
        if (_fleetSource is not { } fleet) return "unavailable";
        lock (fleet._sync)
        {
            fleet.CheckScope();
            if (fleet._fleetNotMember) return "notMember";
            if (fleet._transientFailures > 0) return "unavailable";
            if (fleet._authorityRejectionVersion > 0 && fleet.Read() is null) return "unavailable";
            if (fleet._catalogAt != default && fleet._catalog.Count == 0) return "notMember";
            return fleet.Read() is not null ? "ready" : "loading";
        }
    }

    // A confirmed foreground membership result revokes the same resource before
    // the next HUD read; a late read cannot restore its old revision or catalog.
    internal void ObserveFleetMembership(BridgeAccountContext owner, long generation, string? sourceRef)
    {
        if (_fleetSource is not { } fleet) return;
        lock (fleet._sync)
        {
            fleet.CheckScope();
            if (fleet._disposed || fleet._scope != (owner, generation)) return;
            if (fleet._fleetReference == sourceRef && (sourceRef is not null || fleet._catalogAt != default)) return;
            var revoke = fleet._fleetReference is not null || sourceRef is null;
            fleet._fleetReference = sourceRef;
            fleet._fleetNotMember = sourceRef is null;
            if (!revoke)
            {
                if (fleet._catalogAt != default && fleet._catalog.Count == 0)
                { fleet._catalogAt = default; fleet._catalogRevision++; fleet.NotifyContentChanged(); }
                return;
            }
            fleet.InvalidateRead(); fleet._catalogRevision++;
            fleet._content = null; fleet.RevokeWorkspace(); fleet._catalog = [];
            fleet._catalogAt = sourceRef is null ? fleet._now() : default;
            fleet._transientFailures = 0;
            fleet.NotifyContentChanged();
        }
    }

    internal InformationOverlaySourceSnapshot? ReadFleetSource(BridgeAccountContext owner, long generation) =>
        _fleetSource?.ReadModuleSource(owner, generation, FleetId);
    internal bool IsFleetSourceCurrent(BridgeAccountContext owner, long generation, InformationOverlaySourceSnapshot snapshot) =>
        _fleetSource?.IsModuleSourceCurrent(owner, generation, snapshot) == true;

    private OverlaySourceLease? FleetLease(BridgeAccountContext owner, long generation)
    {
        if (_fleetSource is not { } fleet) return null;
        lock (fleet._sync)
        {
            // A probe may inspect an existing lease, but creates no authority
            // stamp, reads no saved choices and renews no resource lifetime.
            return !fleet._disposed && fleet._scope == (owner, generation) && fleet._owner() == (owner, generation) &&
                fleet._content is not null && fleet._now() < fleet._validUntil
                ? new(OverlaySourceMode.Fleet, FleetId, OverlaySceneChoiceStore.Hash(owner), generation, fleet._validUntil) : null;
        }
    }
}
