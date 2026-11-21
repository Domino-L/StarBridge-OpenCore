using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Public projection at the device bridge contains no source/profile/Handle.
internal sealed record LocalStatisticsChoice(string State, string? ChoiceKey = null,
    string Consent = "unknown", long? SavedSeconds = null, bool Recording = false);

internal sealed partial class LocalGameplayTimeRuntime
{
    private sealed record ConsentIssued(string Key, Owner Owner, GameplayRecordingConsent Consent, Func<bool> ScopeCurrent);
    private ConsentIssued? _issuedConsent;
    private (string Key, LocalFirstUseSnapshot Snapshot, long Generation, Func<bool> ScopeCurrent)? _deferredConsent;

    // Called only after the existing explicit Handle confirmation. Reuse the
    // per-profile consent writer, its lease and current-owner guards.
    internal void ApplyDeferredConsent(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            var snapshot = identities.Read();
            if (snapshot.DeferredStatisticsAllowed is not bool allowed) return;
            var owner = Resolve();
            bool CurrentChoice() => owner is not null && !work.Token.IsCancellationRequested &&
                Scope(scopeCurrent) && IsCurrent(owner) && identities.Read().Revision == snapshot.Revision;
            if (owner is null || !CurrentChoice()) throw new LocalFirstUseException("firstUse.evidence_required");
            var desired = allowed ? GameplayRecordingConsent.Allowed : GameplayRecordingConsent.Declined;
            var saved = statistics.Read(owner.Profile.Id);
            if (saved.Consent != desired)
            {
                var result = ChangeChoice(owner.Source.SourceKey, allowed, CurrentChoice);
                if (result.Error is not null) throw new LocalFirstUseException(result.Error);
            }
            else
            {
                // The profile write may have succeeded before consuming the
                // extension failed. Do not write consent or reset a live interval again.
                var entry = EntryFor(owner);
                entry.Lease ??= statistics.Open(owner.Profile.Id, CurrentChoice);
                if (statistics.Read(owner.Profile.Id) != saved)
                    throw new LocalFirstUseException("firstUse.context_changed");
                if (entry.Error is not null || entry.PendingChoice)
                {
                    entry.Counter.Suspend(); entry.LastEvidenceAt = null; _lastAttempt = null;
                    entry.Saved = saved; entry.Desired = saved.Consent; entry.PendingChoice = false;
                    entry.Error = null; entry.Counter.Restore(saved.Seconds);
                }
            }
            if (!CurrentChoice()) throw new LocalFirstUseException("firstUse.context_changed");
            identities.ClearDeferredStatistics(snapshot.Revision, Guid.NewGuid().ToString("N"), CurrentChoice);
        }
    }

    internal LocalStatisticsChoice ReadConsent(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("inactive");
        lock (_gate) return ReadConsentCore(scopeCurrent, work.Token);
    }
    private LocalStatisticsChoice ReadConsentCore(Func<bool> scopeCurrent, CancellationToken token)
    {
        _issuedConsent = null;
        _deferredConsent = null;
        token.ThrowIfCancellationRequested();
        if (!Scope(scopeCurrent)) return new("unavailable");
        var owner = Resolve();
        var local = identities.Read();
        var mode = localMode();
        if (owner is null && local.LogDeferred && mode.Active)
        {
            _deferredConsent = (Guid.NewGuid().ToString("N"), local, mode.Generation, scopeCurrent);
            return new(local.DeferredStatisticsAllowed is null ? "choiceRequired" : "saved", _deferredConsent.Value.Key,
                local.DeferredStatisticsAllowed switch { true => "allowed", false => "declined", _ => "unknown" }, 0, false);
        }
        if (owner is null) return new(Missing().State);
        var entry = EntryFor(owner);
        // A failed operation remains paused. Reading a repaired file never
        // retries it; only a fresh explicit choice may resume recording.
        var saved = statistics.Read(owner.Profile.Id);
        ValidateSaved(owner, entry);
        if (!IsCurrent(owner) || !Scope(scopeCurrent)) return new("unavailable");
        token.ThrowIfCancellationRequested();
        var state = entry.Error is not null || entry.PendingChoice ? "retryRequired" :
            saved.Consent == GameplayRecordingConsent.Unknown ? "choiceRequired" : "saved";
        var recording = state == "saved" && saved.Consent == GameplayRecordingConsent.Allowed && Current.Recording;
        if (!IsCurrent(owner) || !Scope(scopeCurrent)) return new("unavailable");
        _issuedConsent = new(Guid.NewGuid().ToString("N"), owner, saved.Consent, scopeCurrent);
        return new(state, _issuedConsent.Key, saved.Consent.ToString().ToLowerInvariant(), saved.Seconds, recording);
    }

    internal LocalStatisticsChoice ConfirmConsent(string choiceKey, bool allowed, Func<bool> scopeCurrent, CancellationToken token = default)
    {
        if (!LocalFirstUseValidation.Id(choiceKey)) throw new LocalFirstUseException("firstUse.invalid_request");
        using var work = _work.Enter(token);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            if (_deferredConsent is { } deferred)
            {
                _deferredConsent = null;
                bool CurrentDeferred() => !work.Token.IsCancellationRequested && Scope(scopeCurrent) &&
                    Scope(deferred.ScopeCurrent) &&
                    localMode() == (true, deferred.Generation) && identities.Read().Revision == deferred.Snapshot.Revision;
                if (choiceKey != deferred.Key || !CurrentDeferred())
                    throw new LocalFirstUseException("firstUse.context_changed");
                identities.SetDeferredStatistics(deferred.Snapshot.Revision, Guid.NewGuid().ToString("N"), allowed, CurrentDeferred);
                return ReadConsentCore(scopeCurrent, work.Token);
            }
            var issued = _issuedConsent;
            _issuedConsent = null; // Unknown results cannot replay the same consent.
            bool CurrentScope() => issued is not null && !work.Token.IsCancellationRequested &&
                Scope(scopeCurrent) && Scope(issued.ScopeCurrent) && IsCurrent(issued.Owner);
            if (issued is null || issued.Key != choiceKey || !CurrentScope() ||
                statistics.Read(issued.Owner.Profile.Id).Consent != issued.Consent)
                throw new LocalFirstUseException("firstUse.context_changed");
            ChangeChoice(issued.Owner.Source.SourceKey, allowed, CurrentScope);
            work.Token.ThrowIfCancellationRequested();
            if (!CurrentScope()) throw new LocalFirstUseException("firstUse.context_changed");
            return ReadConsentCore(scopeCurrent, work.Token);
        }
    }
    private static bool Scope(Func<bool> current) { try { return current(); } catch { return false; } }
}
