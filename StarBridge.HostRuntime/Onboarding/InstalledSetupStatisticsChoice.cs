using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// Consent for the independent local profile while its sampler is stopped.
// Never starts a timer, transfers totals or changes the online account's consent.
internal sealed class InstalledSetupStatisticsChoice(string root, FirstUseModeRuntime mode)
{
    private readonly LocalFirstUseStore _local = new(root);
    private readonly LocalGameplayTimeStore _store = new(root);
    private readonly object _gate = new();
    private sealed record Scope(long Generation, long ModeRevision, LocalFirstUseSnapshot Local, string Profile);
    private sealed record Issued(string Key, Scope Scope, LocalGameplayTimeSaved Saved);
    private Issued? _issued;
    internal bool Active => mode.HasInstalledOnlineAccount;
    private Scope? Capture()
    {
        if (!mode.HasInstalledOnlineForCompletion) return null;
        var snapshot = _local.Read();
        var source = snapshot.Sources.SingleOrDefault(s => s.SourceKey == snapshot.SelectedSourceKey);
        return source is { ConfirmedProfileId: not null, NeedsFreshGameEvidence: false } && snapshot.ActiveProfileId == source.ConfirmedProfileId
            ? new(mode.ControlGeneration, mode.Current.Revision, snapshot, source.ConfirmedProfileId) : null;
    }
    private bool Current(Scope scope) => Capture() is { } now && now.Generation == scope.Generation &&
        now.ModeRevision == scope.ModeRevision && now.Local.Revision == scope.Local.Revision && now.Profile == scope.Profile;
    internal LocalStatisticsChoice Read(Func<bool> current, CancellationToken token)
    {
        lock (_gate) return ReadCore(current, token);
    }
    private LocalStatisticsChoice ReadCore(Func<bool> current, CancellationToken token)
    {
        _issued = null; token.ThrowIfCancellationRequested();
        if (!current() || Capture() is not { } scope) return new("inactive");
        var saved = _store.Read(scope.Profile);
        if (!current() || !Current(scope)) return new("unavailable");
        var issued = new Issued(Guid.NewGuid().ToString("N"), scope, saved);
        _issued = issued;
        return new(saved.Consent == GameplayRecordingConsent.Unknown ? "choiceRequired" : "saved", issued.Key,
            saved.Consent.ToString().ToLowerInvariant(), saved.Seconds, false);
    }
    internal LocalStatisticsChoice Confirm(string key, bool allowed, Func<bool> current, CancellationToken token)
    {
        lock (_gate)
        {
            var issued = _issued; _issued = null;
            bool Valid() => issued is not null && !token.IsCancellationRequested && current() && Current(issued.Scope);
            if (issued is null || issued.Key != key || !Valid()) throw new LocalFirstUseException("firstUse.context_changed");
            using var lease = _store.Open(issued.Scope.Profile, Valid);
            lease.Save(issued.Saved, issued.Saved with { Consent = allowed ? GameplayRecordingConsent.Allowed : GameplayRecordingConsent.Declined }, Valid);
            return ReadCore(current, token);
        }
    }
}
