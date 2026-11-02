using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class PrivacyPublication
{
    // Shared account/session authority for every positive live-sharing lane.
    // No publication gate/admission acquisition here: writers call this while
    // holding admission, and snapshot observation must remain non-blocking.
    internal bool IsPositivePublicationAllowed(BridgeAccountContext owner, long generation)
    {
        try
        {
            var input = _currentOwner();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation) return false;
            var snapshot = ReadVisibility(input);
            return IsPositivePublicationAllowed(input, snapshot);
        }
        catch { return false; }
    }

    private bool IsPositivePublicationAllowed(PrivacyPublicationInput input, PublicationVisibilitySnapshot snapshot) =>
        snapshot.Owner == input.Owner && snapshot.Generation == input.Generation &&
        snapshot.Mode is PlayerPresenceVisibilityMode.Online or PlayerPresenceVisibilityMode.InGame &&
        _store.HasPublicationConsent(input.Owner) && _store.Read(input.Owner).Settings?.PublicationEnabled == true &&
        !HasObservedPause(input) && !_store.IsPublicationPaused(input.Owner);

    // Membership keepalive is not consent to publish telemetry, but it must
    // still stop renewing this account's room presence while invisibly paused.
    internal bool IsPublicationSuspended(BridgeAccountContext owner, long generation)
    {
        try
        {
            var input = _currentOwner();
            if (_disposed || input is null || input.Owner != owner || input.Generation != generation) return true;
            var snapshot = ReadVisibility(input);
            return snapshot.Observation == 3 || HasObservedPause(input) || _store.IsPublicationPaused(owner);
        }
        catch { return true; }
    }

    private readonly object _observationGate = new();
    // Unlike _pendingPause, this remains latched after persistence. Repeated
    // invisible reads cannot enqueue an endless series of background ticks.
    private PrivacyPublicationInput? _observedPause;
    private long _observationVersion;

    // Every snapshot producer/consumer enters here, including bridge projections
    // used by friends/events/UI. This may run under the writer's admission lease:
    // latch synchronously, but never acquire admission or wait for _gate here.
    internal void ObserveVisibility(PublicationVisibilitySnapshot snapshot, bool wakePublication = false)
    {
        if (snapshot.Observation != 3 &&
            snapshot is not { Mode: PlayerPresenceVisibilityMode.Invisible, SuspensionError: null }) return;
        // Ownership must not read visibility or depend on positive evidence.
        // In particular, an authenticated app-only owner may have no Handle.
        var input = _currentOwner();
        if (_disposed || input is null || snapshot.Owner != input.Owner || snapshot.Generation != input.Generation) return;
        bool firstObservation;
        lock (_observationGate)
        {
            firstObservation = !SamePauseOwner(input, _observedPause);
            ++_observationVersion;
            _observedPause = input;
            _pendingPause = input;
        }
        // Publication-owned reads are drained by their current operation.
        // Independent bridge reads also wake that same serialized publisher.
        if (wakePublication && firstObservation) _ = TickAsync();
    }

    private bool HasObservedPause(PrivacyPublicationInput input)
    {
        lock (_observationGate) return SamePauseOwner(input, _observedPause);
    }

    private static bool SamePauseOwner(PrivacyPublicationInput input, PrivacyPublicationInput? other) =>
        other is not null && input.Owner == other.Owner && input.Generation == other.Generation;

    internal void RequireNoObservedPause(PrivacyPublicationInput input)
    {
        if (HasObservedPause(input)) throw new PositivePublicationSupersededException(null);
    }

    private long ObservationVersion()
    {
        lock (_observationGate) return _observationVersion;
    }

    private void ResetObservedPause(long version)
    {
        lock (_observationGate)
        {
            // An explicit action may clear older observations, never a new 3
            // captured while that action was awaiting its metadata commit.
            if (version != _observationVersion) return;
            _observedPause = null;
            _pendingPause = null;
        }
    }

    private async Task PersistObservedPauseAsync(PrivacyPublicationInput input, CancellationToken token)
    {
        PrivacyPublicationInput? pending;
        lock (_observationGate)
        {
            if (!SamePauseOwner(input, _observedPause)) return;
            pending = _pendingPause;
        }
        // Stop recovery before attempting I/O, including timeout/write failure.
        _recovery = null;
        _visibilitySuspended = null;
        _restoreBlocked = true;
        _manualPause = true;
        _publicationFailure = null;
        if (pending is null || !SamePauseOwner(input, pending)) return;
        // A read of a declined/unconfirmed inherited policy must remain read-only.
        // Room presence is independent of telemetry consent, and needs the same
        // durable fence. Accounts with neither lane still perform no writes.
        var saved = _store.Read(input.Owner);
        if (!(_store.HasPublicationConsent(input.Owner) && saved.Settings?.PublicationEnabled == true) &&
            _roomPublicationActive?.Invoke(input.Owner, input.Generation) != true) return;
        await _store.SetPublicationPausedAsync(input.Owner, saved.Revision, true,
            () => SamePauseOwner(input, _currentOwner()), token).ConfigureAwait(false);
        lock (_observationGate)
            if (ReferenceEquals(_pendingPause, pending)) _pendingPause = null;
    }
}
