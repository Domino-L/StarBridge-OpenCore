using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

internal sealed record LocalGameplayTimeView(string State, string? SourceKey = null,
    string Consent = "unknown", long? Seconds = null, long? SavedSeconds = null, bool Recording = false, string? Error = null);

// No account projection, network, own timer, history replay or automatic consent.
// The existing local log slot drives this owner after the real mode handoff.
internal sealed partial class LocalGameplayTimeRuntime(LocalFirstUseStore identities, LocalGameplayTimeStore statistics,
    LocalGameLogRuntime game, Func<(bool Active, long Generation)> localMode, TimeProvider? time = null)
{
    private readonly object _gate = new();
    private readonly AsyncWorkRetirement _work = new();
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private readonly Dictionary<string, Entry> _entries = [];
    private Owner? _owner;
    private DateTimeOffset? _lastAttempt;
    private sealed record Owner(long Generation, LocalFirstUseSource Source, LocalDeviceProfile Profile);
    private sealed class Entry
    {
        internal LocalGameplayTimeStore.Lease? Lease;
        internal LocalGameplayTimeSaved? Saved;
        internal readonly GameplayTimeSampleCounter Counter = new();
        internal GameplayRecordingConsent Desired;
        internal bool PendingChoice;
        internal DateTimeOffset? LastEvidenceAt;
        internal string? Error;
    }
    internal bool IsFor(LocalGameLogRuntime value) => ReferenceEquals(value, game);
    // Read-only view of the same confirmed local log slot for the setup check.
    internal LocalGameLogView Recognition => game.Current;
    internal LocalGameplayTimeView Current
    {
        get
        {
            using var work = _work.Enter(default);
            if (work is null) return new("inactive");
            lock (_gate)
            {
                try
                {
                    var owner = Resolve();
                    if (owner is null) return Missing();
                    var entry = EntryFor(owner);
                    ValidateSaved(owner, entry);
                    if (!IsCurrent(owner)) return new("unavailable");
                    var view = game.Current;
                    var state = entry.Error is not null ? "unavailable" : entry.Desired == GameplayRecordingConsent.Unknown ? "choiceRequired" :
                        entry.Desired == GameplayRecordingConsent.Declined ? "declined" : owner.Source.ListeningEnabled != true ? "listeningStopped" :
                        ValidView(view, owner) ? "ready" : "waiting";
                    return IsCurrent(owner) ? Projection(state, owner, entry,
                        state == "ready" && view.State == "ready" && entry.Counter.IsRecording) : new("unavailable");
                }
                catch (LocalFirstUseException) { Pause(); return new("unavailable"); }
            }
        }
    }
    internal LocalGameplayTimeView ApplyConsent(string sourceKey, bool allowed) => ChangeChoice(sourceKey, allowed);
    internal LocalGameplayTimeView Retry(string sourceKey) => ChangeChoice(sourceKey, null);
    private LocalGameplayTimeView ChangeChoice(string sourceKey, bool? allowed, Func<bool>? admitted = null)
    {
        using var work = _work.Enter(default);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            _issuedConsent = null;
            var owner = Resolve();
            if (owner is null || owner.Source.SourceKey != sourceKey) throw new LocalFirstUseException("firstUse.evidence_required");
            var entry = EntryFor(owner); entry.Counter.Suspend(); entry.LastEvidenceAt = null; _lastAttempt = null;
            if (allowed is not null)
            {
                entry.Desired = allowed.Value ? GameplayRecordingConsent.Allowed : GameplayRecordingConsent.Declined;
                entry.PendingChoice = true;
            }
            try
            {
                if (!IsCurrent(owner) || admitted?.Invoke() == false) throw new LocalFirstUseException("firstUse.context_changed");
                var saved = statistics.Read(owner.Profile.Id);
                var total = Math.Max(saved.Seconds, entry.Counter.Seconds);
                var choice = entry.PendingChoice ? entry.Desired : saved.Consent;
                if (choice == GameplayRecordingConsent.Unknown)
                { entry.Saved = saved; entry.Desired = choice; entry.Counter.Restore(saved.Seconds); entry.Error = null; return Current; }
                entry.Lease ??= statistics.Open(owner.Profile.Id, () => IsCurrent(owner));
                entry.Saved = entry.Lease.Save(saved, saved with { Consent = choice, Seconds = total,
                    FirstRecordedAt = saved.FirstRecordedAt ?? entry.Saved?.FirstRecordedAt }, () => IsCurrent(owner) && admitted?.Invoke() != false);
                entry.Desired = choice; entry.PendingChoice = false; entry.Error = null; entry.Counter.Restore(total);
            }
            catch (LocalFirstUseException error) { Fail(entry, error); }
            return Current;
        }
    }
    // Invoked by the unique log sampler, never by another process watcher. The
    // half-second log cadence is coalesced to the original five-second policy.
    internal void Sample()
    {
        using var work = _work.Enter(default);
        if (work is null || !Monitor.TryEnter(_gate)) return;
        try
        {
            var owner = Resolve();
            if (owner is null) { Pause(); return; }
            var entry = EntryFor(owner);
            if (entry.Error is not null || entry.PendingChoice || entry.Desired != GameplayRecordingConsent.Allowed ||
                owner.Source.ListeningEnabled != true) { entry.Counter.Suspend(); entry.LastEvidenceAt = null; _lastAttempt = null; return; }
            var now = _time.GetUtcNow();
            var view = game.Current;
            if (!ValidView(view, owner))
            { entry.Counter.Suspend(); entry.LastEvidenceAt = null; _lastAttempt = null; return; }
            if (_lastAttempt is { } attempted && now >= attempted && now - attempted < TimeSpan.FromSeconds(5)) return;
            _lastAttempt = now;
            if (view.ObservedAt is not { } observed ||
                entry.LastEvidenceAt is { } previous && observed <= previous)
            { entry.Counter.Suspend(); entry.LastEvidenceAt = null; return; }
            if (!IsCurrent(owner)) { Pause(); return; }
            try
            {
                ValidateSaved(owner, entry);
                if (entry.Error is not null) return;
                entry.Lease ??= statistics.Open(owner.Profile.Id, () => IsCurrent(owner));
                entry.Counter.Observe(view.State == "ready", observed); entry.LastEvidenceAt = observed;
                var saved = entry.Saved!;
                var next = saved with { Seconds = entry.Counter.Seconds,
                    FirstRecordedAt = saved.FirstRecordedAt ?? (view.State == "ready" ? observed : null) };
                if (next != saved)
                    entry.Saved = entry.Lease.Save(saved, next, () => IsCurrent(owner) && game.Current == view && IsCurrent(owner));
                if (!IsCurrent(owner)) Pause();
            }
            catch (LocalFirstUseException error) { Fail(entry, error); }
            catch (Exception error) when (error is OverflowException or ArgumentException)
            { Fail(entry, new("firstUse.statistics_unavailable")); }
        }
        catch (LocalFirstUseException) { Pause(); }
        finally { Monitor.Exit(_gate); }
    }
    private Entry EntryFor(Owner owner)
    {
        if (!_entries.TryGetValue(owner.Profile.Id, out var entry))
        {
            entry = new(); _entries.Add(owner.Profile.Id, entry);
            try
            {
                entry.Saved = statistics.Read(owner.Profile.Id); entry.Desired = entry.Saved.Consent;
                entry.Counter.Restore(entry.Saved.Seconds);
            }
            catch (LocalFirstUseException error) { Fail(entry, error); }
        }
        return entry;
    }
    private void ValidateSaved(Owner owner, Entry entry)
    {
        if (entry.Error is not null || entry.Saved is null) return;
        try
        {
            if (statistics.Read(owner.Profile.Id) != entry.Saved)
                Fail(entry, new("firstUse.revision_conflict"));
        }
        catch (LocalFirstUseException error) { Fail(entry, error); }
    }
    private Owner? Resolve()
    {
        var mode = Mode();
        var owner = mode.Active && mode.Generation >= 0 && !_work.IsClosed ? From(identities.Read(), mode.Generation) : null;
        if (_owner != owner) { Pause(); _owner = owner; }
        return owner;
    }
    private bool IsCurrent(Owner owner)
    {
        try
        {
            var mode = Mode();
            return !_work.IsClosed && mode == (true, owner.Generation) && From(identities.Read(), mode.Generation) == owner &&
                Mode() == mode && !_work.IsClosed;
        }
        catch (LocalFirstUseException) { return false; }
    }
    private static Owner? From(LocalFirstUseSnapshot snapshot, long generation)
    {
        var source = snapshot.Sources.SingleOrDefault(s => s.SourceKey == snapshot.SelectedSourceKey);
        var profile = snapshot.Profiles.SingleOrDefault(p => p.Id == source?.ConfirmedProfileId);
        return source is not null && profile is not null && !source.NeedsFreshGameEvidence &&
            snapshot.ActiveProfileId == profile.Id ? new(generation, source, profile) : null;
    }
    private bool ValidView(LocalGameLogView view, Owner owner) => view.SourceKey == owner.Source.SourceKey &&
        view.Version == owner.Source.Version && view.ListeningEnabled == true && view.State is "ready" or "notRunning" &&
        view.ObservedAt is { } at && _time.GetUtcNow() >= at && _time.GetUtcNow() - at <= TimeSpan.FromSeconds(10) &&
        (view.State == "notRunning" || owner.Profile.Handle.Equals(view.Handle, StringComparison.OrdinalIgnoreCase));
    private LocalGameplayTimeView Missing()
    {
        var mode = Mode();
        return new(!mode.Active ? "inactive" : mode.Generation < 0 ? "unavailable" : "needsIdentity");
    }
    private static LocalGameplayTimeView Projection(string state, Owner owner, Entry entry, bool recording) =>
        new(state, owner.Source.SourceKey, entry.Desired.ToString().ToLowerInvariant(), entry.Saved is null ? null : entry.Counter.Seconds,
            entry.Saved?.Seconds, recording, entry.Error);
    private static void Fail(Entry entry, LocalFirstUseException error)
    { entry.Counter.Suspend(); entry.LastEvidenceAt = null; entry.Error = error.Code; }
    private (bool Active, long Generation) Mode()
    {
        try { return localMode(); }
        catch { throw new LocalFirstUseException("firstUse.context_changed"); }
    }
    private void Pause()
    {
        _issuedConsent = null;
        CancelHistory();
        foreach (var entry in _entries.Values)
        { entry.Counter.Suspend(); entry.LastEvidenceAt = null; entry.Lease?.Dispose(); entry.Lease = null; }
        _lastAttempt = null;
    }
    internal void Suspend() { lock (_gate) { Pause(); _owner = null; } }
    internal async Task RetireAsync()
    {
        await _work.Close().ConfigureAwait(false);
        Suspend();
    }
}
