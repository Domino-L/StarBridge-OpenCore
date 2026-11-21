using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Presence;

// Authentication fences continuity independently of the temporarily missing
// gameplay owner. Identity is match, not-observed, or an explicit refusal.
public sealed record GameplayContinuity(BridgeAccountContext? Authentication, long Generation,
    bool OwnerAvailable, string Identity, DateTimeOffset? ConfirmedAt = null, long IdentityRejectionVersion = 0);

public sealed partial class GameplayTimeRuntime
{
    private readonly Func<GameplayContinuity>? _continuity;
    private static readonly TimeSpan OwnerGrace = TimeSpan.FromMinutes(30);
    private (BridgeAccountContext? Context, long Generation) _confirmedAuthentication;
    private DateTimeOffset? _ownerConfirmedAt;
    private bool _hadIdentityMatch;
    private long _identityRejectionVersion;

    private GameplayContinuity Continuity()
    {
        if (_continuity is not null) return _continuity();
        var owner = _current();
        return new(owner.Context, owner.Generation, owner.Context is not null,
            RecordingAllowed() ? "match" : "identity", _time.GetUtcNow());
    }

    private (BridgeAccountContext? Context, long Generation) DispatchOwner()
    {
        var state = Continuity();
        return !state.OwnerAvailable && state.Authentication is not null &&
            (state.Authentication, state.Generation) == _confirmedAuthentication && _ownerConfirmedAt is not null
            ? _active : _current();
    }

    // Retirement closes admission before cancelling this runtime's work tokens.
    // Its cancellation must follow failure/exit cleanup, never connection continuity.
    private bool TemporaryOwnerFailure(Exception error) => IsActive &&
        error is Privacy.LocalPrivacyOwnerUnavailableException or IOException or TimeoutException or
            System.Net.Http.HttpRequestException or OperationCanceledException;

    private bool HasConfirmedLogin()
    {
        if (!IsActive || _ownerConfirmedAt is null) return false;
        var state = Continuity();
        return state.Authentication is not null &&
            (state.Authentication, state.Generation) == _confirmedAuthentication &&
            state.Generation == _active.Generation;
    }

    private void DiscardTransient(Entry entry, string reason)
    {
        if (entry.PauseReason is "connection" or "connectionPaused")
        {
            entry.Accumulator.Restore(_active.Context, _active.Generation, entry.Desired, entry.Saved?.Seconds ?? 0);
            entry.FirstRecordedAt = entry.Saved?.FirstRecordedAt;
            _store.Journal.RecordChange("gameplay-runtime", "code=transient-discarded reason=" + reason);
        }
        entry.PauseReason = null;
    }

    private bool ResolveContinuity(out Entry? retained)
    {
        retained = null;
        var state = Continuity();
        var authentication = (state.Authentication, state.Generation);
        if (_confirmedAuthentication != authentication)
        {
            foreach (var old in _entries.Values) DiscardTransient(old, "account");
            _ownerConfirmedAt = null;
            _hadIdentityMatch = false;
            _confirmedAuthentication = authentication;
            _identityRejectionVersion = state.IdentityRejectionVersion;
        }
        if (_active.Context is null || !_entries.TryGetValue(_active.Context, out var entry)) return false;
        if (_identityRejectionVersion != state.IdentityRejectionVersion)
        {
            DiscardTransient(entry, "identity");
            entry.Accumulator.Suspend();
            _hadIdentityMatch = false;
            _identityRejectionVersion = state.IdentityRejectionVersion;
        }
        var sameLogin = state.Authentication is not null && authentication == _confirmedAuthentication &&
            state.Generation == _active.Generation && _ownerConfirmedAt is not null;
        if (!sameLogin) return false;
        var unavailable = !state.OwnerAvailable;
        if (!unavailable)
        {
            try { entry.Lease?.ValidateOwner(); }
            catch (Exception error) when (TemporaryOwnerFailure(error)) { unavailable = true; }
            catch (GameplayTimeException)
            {
                DiscardTransient(entry, "owner");
                _hadIdentityMatch = false;
                return false;
            }
        }
        if (state.Identity != "match" && !(state.Identity == "not-observed" && _hadIdentityMatch))
        {
            DiscardTransient(entry, "identity");
            _hadIdentityMatch = false;
            entry.Accumulator.Suspend();
            entry.PauseReason = "identity";
            if (unavailable) { retained = entry; return true; }
            return false;
        }
        if (unavailable)
        {
            var now = _time.GetUtcNow();
            var deadline = _ownerConfirmedAt!.Value + OwnerGrace;
            entry.PauseReason = now >= deadline ? "connectionPaused" : "connection";
            _store.Journal.RecordChange("gameplay-runtime", "code=owner-transient");
            // Clamp the last interval at the confirmation deadline. Repeated
            // failed reads never extend the window or start another allowance.
            if (_hadIdentityMatch && entry.Saved is { PendingReset: null, PendingImport: null } &&
                entry.Error is null && entry.Desired == GameplayRecordingConsent.Allowed)
            {
                LocalGamePresenceSnapshot presence;
                try { presence = _presence(); }
                catch { entry.Accumulator.Suspend(); retained = entry; return true; }
                entry.GameState = presence.State is "running" or "notRunning" ? presence.State : "unknown";
                entry.Accumulator.Observe(_active.Context, _active.Generation, presence,
                    now < deadline ? now : deadline);
                var maximum = entry.Saved.Seconds > long.MaxValue - 1800 ? long.MaxValue : entry.Saved.Seconds + 1800;
                if (entry.Accumulator.PlayTimeSeconds > maximum)
                    entry.Accumulator.Restore(_active.Context, _active.Generation, entry.Desired, maximum);
            }
            if (now >= deadline) entry.Accumulator.Suspend();
            retained = entry;
            return true;
        }
        if (entry.PauseReason is "connection" or "connectionPaused")
        {
            // No observation after the deadline is counted. Commit only through
            // the original lease, which rechecks the actual storage owner.
            try
            {
                if (state.Identity == "not-observed" && _hadIdentityMatch)
                    entry.RecoveryIdentityRetained = true;
                if (!RecordingOwnerIsCurrent(_active)) { retained = entry; return true; }
                // Settle against the OLD confirmation before accepting recovery.
                // An expired gap must not become the next ordinary sample interval.
                var now = _time.GetUtcNow();
                var deadline = _ownerConfirmedAt!.Value + OwnerGrace;
                if (_hadIdentityMatch && entry.Saved is { PendingReset: null, PendingImport: null } &&
                    entry.Error is null && entry.Desired == GameplayRecordingConsent.Allowed)
                {
                    var presence = _presence();
                    entry.Accumulator.Observe(_active.Context, _active.Generation, presence,
                        now < deadline ? now : deadline);
                    var maximum = entry.Saved.Seconds > long.MaxValue - 1800
                        ? long.MaxValue : entry.Saved.Seconds + 1800;
                    if (entry.Accumulator.PlayTimeSeconds > maximum)
                        entry.Accumulator.Restore(_active.Context, _active.Generation, entry.Desired, maximum);
                }
                if (now >= deadline) entry.Accumulator.Suspend();
                var pending = entry.Accumulator.PlayTimeSeconds - (entry.Saved?.Seconds ?? 0);
                var owner = _active;
                Persist(entry, () => RecordingOwnerIsCurrent(owner));
                entry.PauseReason = null;
                _store.Journal.RecordChange("gameplay-runtime", "code=transient-committed seconds-bucket=" +
                    (pending == 0 ? "0" : pending < 60 ? "under-minute" : "under-30-minutes"));
            }
            catch (Exception error) when (TemporaryOwnerFailure(error)) { retained = entry; return true; }
            catch (Exception error) { Fail(entry, error); retained = entry; return true; }
        }
        _ownerConfirmedAt = state.ConfirmedAt ?? _time.GetUtcNow();
        _hadIdentityMatch = state.Identity == "match" || _hadIdentityMatch;
        entry.PauseReason = null;
        return false;
    }

    private void ConfirmLoadedOwner()
    {
        var state = Continuity();
        if (!state.OwnerAvailable || state.Authentication is null) return;
        _confirmedAuthentication = (state.Authentication, state.Generation);
        _ownerConfirmedAt = state.ConfirmedAt ?? _time.GetUtcNow();
        _hadIdentityMatch = state.Identity == "match";
        _identityRejectionVersion = state.IdentityRejectionVersion;
    }

    // Admission concerns the current login, not the login of the last sampled
    // entry. Tickets and receipts still check their own owner and generation.
    // Reconciliation uses the stricter ConfirmedForWrite fence below.
    private bool CurrentOwnerAllowsWrite()
    {
        try
        {
            var state = Continuity();
            if (!state.OwnerAvailable || state.Authentication is null || state.Identity != "match") return false;
            if (_active == _current() && _entries.TryGetValue(_active.Context!, out var entry))
                entry.Lease?.ValidateOwner();
            return true;
        }
        catch { return false; }
    }

    private void RetryWhenOwnerReturns(Entry entry)
    {
        if (entry.RetryOwner is not { } failed) return;
        var state = Continuity();
        var notified = (state.Authentication, state.Generation) != (failed.Authentication, failed.Generation) ||
            !failed.OwnerAvailable && state.OwnerAvailable;
        // Older callers expose availability only through the owner resolver.
        // Probe that boundary without opening a file or taking a second lease.
        if (_continuity is null && entry.RetryOwnerProbe && state.Authentication is not null)
        {
            // A successful probe is not a successful Load: Read may still reject
            // the owner. Allow only one early reload until Load actually succeeds.
            if (entry.RetryOwnerProbeUsed) return;
            try { _store.ResolveOwner?.Invoke(state.Authentication); notified = true; }
            catch { return; }
            entry.RetryOwnerProbeUsed = true;
        }
        if (!notified || !state.OwnerAvailable || state.Authentication is null) return;
        entry.RetryAt = _time.GetUtcNow();
        entry.RetryOwner = null;
    }

    private bool ConfirmedForWrite()
    {
        try
        {
            var state = Continuity();
            if (!state.OwnerAvailable || state.Authentication is null ||
                state.IdentityRejectionVersion != _identityRejectionVersion ||
                _confirmedAuthentication.Context is not null &&
                (state.Authentication, state.Generation) != _confirmedAuthentication) return false;
            if (_active.Context is not null && _entries.TryGetValue(_active.Context, out var entry))
            {
                entry.Lease?.ValidateOwner();
                return state.Identity == "match" ||
                    state.Identity == "not-observed" && entry.RecoveryIdentityRetained && _hadIdentityMatch;
            }
            return state.Identity == "match";
        }
        catch { return false; }
    }

    private bool LostOwnerDuringCommit(Exception error)
    {
        if (error is not GameplayTimeException { Code: "gameplay.account_changed" } || _ownerConfirmedAt is null)
            return false;
        var state = Continuity();
        return !state.OwnerAvailable && state.Authentication is not null &&
            (state.Authentication, state.Generation) == _confirmedAuthentication && _hadIdentityMatch &&
            state.Identity is "match" or "not-observed";
    }

    // The retained identity exception is for sampled time only. User mutations,
    // reset/import and publication still require the original RecordingAllowed.
    private bool RecordingOwnerIsCurrent((BridgeAccountContext? Context, long Generation) owner,
        CancellationToken cancellation = default) => IsActive && !cancellation.IsCancellationRequested &&
        _current() == owner && ConfirmedForWrite() && IsActive && !cancellation.IsCancellationRequested;
}
