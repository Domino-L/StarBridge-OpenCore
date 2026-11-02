using StarBridge.HostRuntime.Presence;

namespace StarBridge.HostRuntime.Onboarding;

// This local view is not Presence, an SCM identity receipt or a publication grant.
// Raw paths, process IDs, GEIDs and profile IDs never enter this projection.
internal sealed record LocalGameLogView(string State, string? SourceKey = null, string? Version = null,
    bool? ListeningEnabled = null, DateTimeOffset? ObservedAt = null, string? Handle = null,
    GameLogSessionSnapshot? Session = null)
{
    internal GameLogSessionSnapshot LocalSession => Session ?? GameLogSessionSnapshot.Empty;
}

/// <summary>
/// Independent local-profile Adapter for the existing log/session parser. No timer,
/// journal, history replay, network writer or fabricated account context. An explicitly
/// attached independent statistics owner is driven after this reader, not by a second timer.
/// The one GameLogRuntime sampler may select this slot only after its mode owner has
/// actually stopped online work; this slot alone cannot acknowledge that transition.
/// </summary>
internal sealed class LocalGameLogRuntime(LocalFirstUseStore store,
    Func<(bool Active, long Generation)> localMode, Func<GameProcessSession>? probe = null, TimeProvider? time = null)
{
    private readonly object _gate = new();
    private readonly Lifecycle.AsyncWorkRetirement _work = new();
    private readonly Func<GameProcessSession> _probe = probe ?? GameLogIdentityReader.Probe;
    private readonly TimeProvider _clock = time ?? TimeProvider.System;
    private readonly GameLogIdentityReader _reader = new(new GameLogSessionTracker(), strictLocalEvidence: true);
    private sealed record Owner(long Generation, LocalFirstUseSource Source, LocalDeviceProfile Profile);
    private sealed record Observation(Owner Owner, LocalGameLogView View, DateTimeOffset At);
    private Observation? _published;
    private Owner? _readerOwner;
    private LocalGameplayTimeRuntime? _statistics;
    internal void AttachStatistics(LocalGameplayTimeRuntime value)
    {
        lock (_gate)
        {
            if (_work.IsClosed || !value.IsFor(this) || _statistics is not null && !ReferenceEquals(_statistics, value))
                throw new InvalidOperationException("The local statistics slot is already owned.");
            _statistics = value;
        }
    }

    // Unknown/failed mode observations must not fall back to an authorized account
    // slot. This is a suppression gate, never acknowledgement that local mode is ready.
    internal bool BlocksAccountSlot
    {
        get
        {
            try { var mode = ReadMode(); return mode.Active || mode.Generation < 0; }
            catch (LocalFirstUseException) { return true; }
        }
    }
    internal LocalGameLogView Current
    {
        get
        {
            try
            {
                var mode = ReadMode();
                if (mode.Generation < 0) return new("unavailable");
                if (!mode.Active) return new("inactive");
                var snapshot = store.Read(); var source = Selected(snapshot);
                var owner = Resolve(snapshot, mode.Generation);
                var seen = Volatile.Read(ref _published); var now = _clock.GetUtcNow();
                if (owner is not null && seen?.Owner == owner && now >= seen.At &&
                    now - seen.At <= TimeSpan.FromSeconds(10) && ReadMode() == mode) return seen.View;
                return View(source is null ? "unselected" : source.ListeningEnabled == false ? "stopped" :
                    owner is null ? "needsIdentity" : source.ListeningEnabled is null ? "choiceRequired" : "waiting", source);
            }
            catch (LocalFirstUseException) { return new("unavailable"); }
        }
    }

    internal LocalGameLogView ApplyListening(string sourceKey, bool enabled)
    {
        using var work = _work.Enter(default);
        if (work is null) throw new LocalFirstUseException("firstUse.context_changed");
        lock (_gate)
        {
            var mode = ReadMode();
            if (!mode.Active || mode.Generation < 0) throw new LocalFirstUseException("firstUse.context_changed");
            var old = store.Read(); var source = Selected(old);
            if (source is null || source.SourceKey != sourceKey) throw new LocalFirstUseException("firstUse.source_changed");
            store.SetListening(old.Revision, Op(), sourceKey, enabled,
                () => ReadMode() == mode && Selected(store.Read()) == source);
            Suspend(); Sample();
            var saved = store.Read();
            if (saved.SelectedSourceKey != sourceKey || Selected(saved)?.ListeningEnabled != enabled || ReadMode() != mode)
                throw new LocalFirstUseException("firstUse.context_changed");
            return Current;
        }
    }

    internal void Suspend()
    {
        lock (_gate) { Volatile.Write(ref _published, null); _readerOwner = null; _reader.Reset(); _statistics?.Suspend(); }
    }

    // Called by the owning sampler; elapsed ticks do not queue behind IO/commands.
    internal void Sample()
    {
        using var work = _work.Enter(default);
        if (work is null) return;
        if (!Monitor.TryEnter(_gate)) return;
        try
        {
            var mode = ReadMode();
            if (!mode.Active || mode.Generation < 0) { Suspend(); return; }
            var before = store.Read(); var source = Selected(before); var owner = Resolve(before, mode.Generation);
            if (owner != _readerOwner) { _reader.Reset(); _readerOwner = owner; Volatile.Write(ref _published, null); }
            if (owner is null || source!.ListeningEnabled != true) { Suspend(); return; }
            var process = _probe(); var now = _clock.GetUtcNow();
            if (!FreshGameEvidenceReader.Matches(process, source.LogPath, now))
            {
                _reader.Reset();
                Publish(process.State == "notRunning" ? "notRunning" : process.State == "unknown" ? "processUnknown" : "otherSource",
                    owner, mode, now); return;
            }
            var observation = _reader.ReadCurrent(source.LogPath, process, now);
            var after = _probe();
            if (after != process || ReadMode() != mode || Resolve(store.Read(), mode.Generation) != owner || _clock.GetUtcNow() < now)
            { Suspend(); return; }
            if (observation.State == "ambiguous" || observation.State == "identified" &&
                !owner.Profile.Handle.Equals(observation.Handle, StringComparison.OrdinalIgnoreCase))
            {
                // Keep all profiles/data. This selected source no longer activates
                // the old Handle; explicit rechecking/confirmation must choose again.
                store.InvalidateSourceIdentity(before.Revision, Op(), source.SourceKey,
                    () => ReadMode() == mode && Resolve(store.Read(), mode.Generation) == owner && _probe() == process);
                Suspend(); return;
            }
            Publish(observation.State == "identified" ? "ready" : observation.State, owner, mode, now,
                observation.State == "identified" ? _reader.SessionSnapshot(now) : null);
        }
        catch (Exception error) when (error is LocalFirstUseException or IOException or UnauthorizedAccessException or
            InvalidOperationException or ArgumentException or NotSupportedException or System.Security.SecurityException)
        { Suspend(); }
        finally { Monitor.Exit(_gate); if (!_work.IsClosed) _statistics?.Sample(); }
    }

    internal async Task RetireAsync()
    {
        await _work.Close().ConfigureAwait(false);
        Suspend();
    }

    private void Publish(string state, Owner owner, (bool Active, long Generation) mode, DateTimeOffset at,
        GameLogSessionSnapshot? session = null)
    {
        if (ReadMode() != mode || Resolve(store.Read(), mode.Generation) != owner) { Suspend(); return; }
        Volatile.Write(ref _published, new(owner, View(state, owner.Source, at,
            state == "ready" ? owner.Profile.Handle : null, session), at));
    }
    private static LocalGameLogView View(string state, LocalFirstUseSource? source, DateTimeOffset? at = null,
        string? handle = null, GameLogSessionSnapshot? session = null) =>
        new(state, source?.SourceKey, source?.Version, source?.ListeningEnabled, at, handle, session);
    private static Owner? Resolve(LocalFirstUseSnapshot snapshot, long generation)
    {
        var source = Selected(snapshot);
        var profile = snapshot.Profiles.SingleOrDefault(p => p.Id == source?.ConfirmedProfileId);
        return source is not null && profile is not null && !source.NeedsFreshGameEvidence &&
            snapshot.ActiveProfileId == profile.Id ? new(generation, source, profile) : null;
    }
    private static LocalFirstUseSource? Selected(LocalFirstUseSnapshot snapshot) =>
        snapshot.Sources.SingleOrDefault(s => s.SourceKey == snapshot.SelectedSourceKey);
    private static string Op() => Guid.NewGuid().ToString("N");
    private (bool Active, long Generation) ReadMode()
    {
        if (_work.IsClosed) return (false, -1);
        try
        {
            var mode = localMode();
            return _work.IsClosed ? (false, -1) : mode;
        }
        catch { throw new LocalFirstUseException("firstUse.context_changed"); }
    }
}
