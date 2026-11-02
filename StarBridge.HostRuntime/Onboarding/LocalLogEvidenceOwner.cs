using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// No path, file identity, numeric game ID or account context leaves this observation.
internal sealed record LocalLogEvidenceObservation(string State, string? SourceKey = null,
    string? EvidenceKey = null, bool RequiresFreshEvidence = false, string? Handle = null,
    DateTimeOffset? ObservedAt = null, string? Origin = null, bool ScopeChecked = false,
    bool IdentityConfirmed = false);

/// <summary>
/// Device-local source/evidence owner. Select/Refresh are explicit commands;
/// Current is a side-effect-free read, not a hidden scan or progress write.
/// Confirm revalidates real evidence under the store's commit guard.
/// </summary>
internal sealed class LocalLogEvidenceOwner(LocalFirstUseStore store,
    Func<GameProcessSession>? processProbe = null, TimeProvider? time = null, Func<bool>? current = null)
{
    private readonly object _gate = new();
    private readonly TimeProvider _clock = time ?? TimeProvider.System;
    private readonly Func<GameProcessSession> _probe = processProbe ?? GameLogIdentityReader.Probe;
    private readonly Func<bool> _current = current ?? (() => true);
    private readonly FreshGameEvidenceReader _fresh = new(processProbe, time);
    private readonly LocalIdentityDiscovery _history = new(time);
    private LocalLogEvidenceObservation? _cached;
    private LocalFirstUseSource? _cachedSource;
    private string? _stamp;
    private DateTimeOffset _checkedAt;

    internal LocalLogEvidenceObservation Current
    {
        get
        {
            lock (_gate)
            {
                var snapshot = store.Read();
                var source = Selected(snapshot);
                var now = _clock.GetUtcNow();
                if (_current() && source == _cachedSource && _cached is not null &&
                    now >= _checkedAt && now - _checkedAt <= TimeSpan.FromSeconds(10)) return _cached;
                return new(source is null ? "unselected" : "checking", source?.SourceKey,
                    RequiresFreshEvidence: source?.NeedsFreshGameEvidence == true);
            }
        }
    }

    internal void Invalidate() { lock (_gate) { _cached = null; _cachedSource = null; _stamp = null; } }

    internal LocalLogEvidenceObservation Select(long revision, string logPath, string version)
    {
        lock (_gate)
        {
            Invalidate();
            var path = _fresh.CheckSelection(logPath, version);
            var saved = store.SelectSource(revision, Op(), path, version, _current);
            return Refresh(saved.SelectedSourceKey!);
        }
    }

    internal LocalLogEvidenceObservation Refresh(string expectedSourceKey, CancellationToken cancellation = default)
    {
        lock (_gate)
        {
            if (!_current()) throw new LocalFirstUseException("firstUse.context_changed");
            var snapshot = store.Read();
            var source = Selected(snapshot);
            if (source is null || source.SourceKey != expectedSourceKey) throw new LocalFirstUseException("firstUse.source_changed");
            if (source.NeedsFreshGameEvidence)
            {
                if (source.Baseline is null)
                {
                    var baseline = _fresh.Capture(source.LogPath, source.Version, cancellation);
                    snapshot = store.RequireFreshGameEvidence(snapshot.Revision, Op(), source.SourceKey, baseline, _current);
                    source = Selected(snapshot)!;
                }
                var fresh = _fresh.Read(source.LogPath, source.Version, source.Baseline!, cancellation);
                if (fresh.State == "candidate") return Remember(snapshot, source, fresh.State, fresh.Handle,
                    fresh.ObservedAt, "freshSession", false, fresh.EvidenceStamp);
                if (fresh.State == "changed")
                {
                    var replacement = _fresh.Capture(source.LogPath, source.Version, cancellation);
                    snapshot = store.RequireFreshGameEvidence(snapshot.Revision, Op(), source.SourceKey, replacement,
                        _current, LocalGameEvidenceValidation.Key(source.Baseline!));
                    source = Selected(snapshot)!;
                    return Remember(snapshot, source, "waiting");
                }
                return Remember(snapshot, source, fresh.State);
            }

            var live = _fresh.ReadCurrent(source.LogPath, source.Version, cancellation);
            if (live.State == "candidate")
            {
                var profile = snapshot.Profiles.SingleOrDefault(p => p.Id == source.ConfirmedProfileId);
                if (profile is not null && !profile.Handle.Equals(live.Handle, StringComparison.OrdinalIgnoreCase))
                {
                    snapshot = store.InvalidateSourceIdentity(snapshot.Revision, Op(), source.SourceKey, _current);
                    source = Selected(snapshot)!;
                }
                return Remember(snapshot, source, live.State, live.Handle, live.ObservedAt, "current", false, live.EvidenceStamp);
            }
            if (live.State is not ("notRunning" or "processUnknown" or "waiting")) return Remember(snapshot, source, live.State);
            if (source.ConfirmedProfileId is { } profileId)
            {
                // A confirmed local association survives game exit. It does NOT claim
                // current-game identity; a dedicated origin must be projected by the bridge.
                var profile = snapshot.Profiles.Single(p => p.Id == profileId);
                return Remember(snapshot, source, "candidate", profile.Handle, source.ConfirmedObservedAt,
                    "confirmedLocal", false, profileId + source.ConfirmedObservedAt!.Value.UtcTicks);
            }

            var before = _probe();
            var history = _history.Scan(source.LogPath, source.Version, cancellation);
            if (history.ScopeChecked && history.State is "missing" or "conflict")
            {
                var baseline = history.Baseline!;
                var after = _probe();
                if (FreshGameEvidenceReader.Matches(before, source.LogPath, baseline.CapturedAt) &&
                    before.SessionId == after.SessionId && before.StartedAt == after.StartedAt &&
                    FreshGameEvidenceReader.Matches(after, source.LogPath, _clock.GetUtcNow()))
                    baseline = baseline with { ProcessSessionKey = FreshGameEvidenceReader.SessionKey(before), ProcessStartedAt = before.StartedAt };
                snapshot = store.RequireFreshGameEvidence(snapshot.Revision, Op(), source.SourceKey, baseline, _current);
                source = Selected(snapshot)!;
            }
            return Remember(snapshot, source, history.State, history.Handle, history.ObservedAt,
                history.State == "candidate" ? "history" : null, history.ScopeChecked, history.ScopeStamp);
        }
    }

    internal LocalLogEvidenceObservation Confirm(string sourceKey, string evidenceKey)
    {
        lock (_gate)
        {
            var observed = Current;
            if (observed.State != "candidate" || observed.SourceKey != sourceKey || observed.EvidenceKey != evidenceKey ||
                observed.RequiresFreshEvidence || _cachedSource is null || _stamp is null)
                throw new LocalFirstUseException("firstUse.evidence_required");
            var source = _cachedSource;
            var stamp = _stamp;
            bool Check()
            {
                if (!_current() || Selected(store.Read()) != source) return false;
                if (observed.Origin == "confirmedLocal")
                {
                    _fresh.CheckSelection(source.LogPath, source.Version);
                    var live = _fresh.ReadCurrent(source.LogPath, source.Version);
                    // Returning to a confirmed source is an explicit reactivation,
                    // not automatic profile merging or SCM verification.
                    return source.ConfirmedProfileId is not null && !source.NeedsFreshGameEvidence &&
                        (live.State is "notRunning" or "waiting" || live.State == "candidate" &&
                            observed.Handle!.Equals(live.Handle, StringComparison.OrdinalIgnoreCase));
                }
                if (observed.Origin == "history")
                {
                    var value = _history.Scan(source.LogPath, source.Version);
                    return value.State == "candidate" && value.ScopeChecked && value.ScopeStamp == stamp;
                }
                var fresh = observed.Origin == "freshSession" ? _fresh.Read(source.LogPath, source.Version, source.Baseline!) :
                    _fresh.ReadCurrent(source.LogPath, source.Version);
                return fresh.State == "candidate" && fresh.EvidenceStamp == stamp;
            }
            var proof = new LocalIdentityProof(sourceKey, evidenceKey, observed.Handle!, observed.ObservedAt!.Value,
                observed.Origin == "confirmedLocal" ? source.ConfirmedOrigin! : observed.Origin!, observed.ScopeChecked,
                false, source.Baseline is null ? null : LocalGameEvidenceValidation.Key(source.Baseline));
            // Historical confirmed receipts already passed complete-scope confirmation.
            if (observed.Origin == "confirmedLocal" && proof.Origin == "history") proof = proof with { ScopeChecked = true };
            try
            {
                var saved = store.Read();
                store.ConfirmIdentity(saved.Revision, Op(), proof, Check);
            }
            catch { Invalidate(); throw; }
            Invalidate();
            return Refresh(sourceKey);
        }
    }

    private LocalLogEvidenceObservation Remember(LocalFirstUseSnapshot snapshot, LocalFirstUseSource source,
        string state, string? handle = null, DateTimeOffset? at = null, string? origin = null,
        bool scopeChecked = false, string? stamp = null)
    {
        var candidate = state == "candidate";
        var key = candidate && _cachedSource == source && _stamp == stamp && _cached?.Origin == origin
            ? _cached!.EvidenceKey : candidate ? Op() : null;
        var profile = snapshot.Profiles.SingleOrDefault(p => p.Id == source.ConfirmedProfileId);
        _cached = new(state, source.SourceKey, key, source.NeedsFreshGameEvidence && origin != "freshSession",
            candidate ? handle : null, candidate ? at : null, origin, scopeChecked,
            candidate && profile is not null && snapshot.ActiveProfileId == profile.Id &&
                profile.Handle.Equals(handle, StringComparison.OrdinalIgnoreCase));
        _cachedSource = source; _stamp = stamp; _checkedAt = _clock.GetUtcNow();
        return _cached;
    }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static LocalFirstUseSource? Selected(LocalFirstUseSnapshot snapshot) =>
        snapshot.Sources.SingleOrDefault(s => s.SourceKey == snapshot.SelectedSourceKey);
}
