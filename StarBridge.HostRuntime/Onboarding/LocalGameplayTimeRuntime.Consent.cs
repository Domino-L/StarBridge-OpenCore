using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Public projection at the device bridge contains no source/profile/Handle.
internal sealed record LocalStatisticsChoice(string State, string? ChoiceKey = null,
    string Consent = "unknown", long? SavedSeconds = null, bool Recording = false);

internal sealed partial class LocalGameplayTimeRuntime
{
    private sealed record ConsentIssued(string Key, Owner Owner, GameplayRecordingConsent Consent, Func<bool> ScopeCurrent);
    private ConsentIssued? _issuedConsent;

    internal LocalStatisticsChoice ReadConsent(Func<bool> scopeCurrent, CancellationToken token = default)
    {
        using var work = _work.Enter(token);
        if (work is null) return new("inactive");
        lock (_gate) return ReadConsentCore(scopeCurrent, work.Token);
    }
    private LocalStatisticsChoice ReadConsentCore(Func<bool> scopeCurrent, CancellationToken token)
    {
        _issuedConsent = null;
        token.ThrowIfCancellationRequested();
        if (!Scope(scopeCurrent)) return new("unavailable");
        var owner = Resolve();
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
