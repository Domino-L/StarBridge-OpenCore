namespace StarBridge.HostRuntime.Presence;

public sealed record LocalGamePresenceSnapshot(int SchemaVersion, string State, string? Version = null);
public sealed record LocalGameProcessObservation(bool Running, string? Version = null);

/// <summary>Local process observation with an optional borrowed event journal.
/// No login, network publication, new poller or playtime recording.</summary>
public sealed class LocalGamePresenceReader : IDisposable
{
    private readonly Func<LocalGameProcessObservation?> _probe;
    private readonly object _sync = new();
    private readonly Support.LocalGameEventJournal? _journal;
    private bool _disposed;
    private readonly Func<string?>? _trustedVersion;
    private readonly TimeProvider _time;
    private bool _running;
    private string? _version;
    private DateTimeOffset? _missingSince;

    public LocalGamePresenceReader(Func<bool?>? probe = null, TimeProvider? time = null,
        Func<string?>? trustedVersion = null, Support.LocalGameEventJournal? journal = null)
    {
        _probe = probe is null ? Probe : () => probe() is { } running ? new(running) : null;
        _time = time ?? TimeProvider.System;
        _trustedVersion = trustedVersion;
        _journal = journal;
    }
    public LocalGamePresenceReader(Func<LocalGameProcessObservation?> probe, TimeProvider? time = null,
        Func<string?>? trustedVersion = null, Support.LocalGameEventJournal? journal = null)
    {
        _probe = probe ?? throw new ArgumentNullException(nameof(probe));
        _time = time ?? TimeProvider.System;
        _trustedVersion = trustedVersion;
        _journal = journal;
    }

    public LocalGamePresenceSnapshot Read()
    {
        lock (_sync)
        {
            if (_disposed) return new(1, "unknown");
            var clearRevision = _journal?.ClearRevision;
            LocalGameProcessObservation? observed;
            try { observed = _probe(); }
            catch { observed = null; }
            if (observed is null)
            {
                // Unknown must not turn the previous positive observation into a
                // stop/start pair. A new run of negative observations is required.
                _version = null;
                _missingSince = null;
                return new(1, "unknown");
            }
            var now = _time.GetUtcNow();
            var wasRunning = _running;
            if (observed.Running)
            {
                _running = true;
                string? version;
                try { version = _trustedVersion is null ? observed.Version : _trustedVersion(); }
                catch { version = null; }
                _version = GameLogLocator.ValidChannel(version) ? version : null;
                _missingSince = null;
            }
            else if (_running)
            {
                if (_missingSince is null || _missingSince > now) _missingSince = now;
                // Same existing WPF-compatible 10-second exit confirmation.
                if (now - _missingSince >= TimeSpan.FromSeconds(10))
                {
                    _running = false;
                    _version = null;
                    _missingSince = null;
                }
            }
            if (wasRunning != _running && _journal is not null)
            {
                var entry = Support.LocalGameEventPresentation.Process(_running);
                // A history error cannot turn a confirmed process observation into unknown.
                // Journal owns persistence errors, lifetime and the clear/append lock.
                try
                {
                    _journal.Append(entry.Category, entry.EventType, entry.Title, entry.Detail,
                        now, expectedClearRevision: clearRevision);
                }
                catch { }
            }
            return new(1, _running ? "running" : "notRunning", _running ? _version : null);
        }
    }

    public void Dispose()
    {
        lock (_sync) { _disposed = true; _missingSince = null; _version = null; }
        // The Native Host owns the journal. Disposing observation never emits an exit.
    }

    private static LocalGameProcessObservation? Probe()
    {
        var process = GameLogIdentityReader.Probe();
        if (process.State == "notRunning") return new(false);
        if (process.State != "running" || process.LogPath is null) return null;
        var version = GameLogLocator.ChannelOf(process.LogPath);
        if (version is null) return null;
        try
        {
            var path = GameLogIdentityReader.ValidatePath(process.LogPath);
            using var log = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
            _ = log.Length;
            return new(true, version);
        }
        catch { return null; }
    }
}
