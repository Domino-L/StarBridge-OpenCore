using StarBridge.Core.Events;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

internal sealed class EventSharingRuntime : IDisposable
{
    private readonly IEventSharingRemote _settings;
    private readonly IEventFeedRemote _remote;
    private readonly Func<PrivacyPublicationInput?> _current;
    private readonly Func<bool> _allowed;
    private readonly SharedActivityEventSource _source;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private readonly ITimer? _timer;
    private EventSharingRemoteSnapshot? _saved;
    private PrivacyPublicationInput? _owner;
    private EventSourceLease? _lease;
    private string? _session;
    private long _sequence;
    private int _paused;
    private DateTimeOffset _lastRead;
    private bool _withdrawPending;
    private PrivacyPublicationInput? _shutdownOwner;
    private volatile bool _disposed;
    internal string State { get; private set; } = "inactive";

    internal EventSharingRuntime(IEventSharingRemote settings, IEventFeedRemote remote, LocalGameEventJournal journal,
        Func<PrivacyPublicationInput?> current, Func<bool> allowed, bool startTimer = true)
    {
        _settings = settings; _remote = remote; _current = current; _allowed = allowed;
        _source = new(journal);
        if (startTimer) _timer = TimeProvider.System.CreateTimer(_ => _ = TickAsync(), null, TimeSpan.FromSeconds(5), TimeSpan.FromSeconds(5));
    }
    internal void Pause() { Interlocked.Increment(ref _paused); _source.Activate(null); }
    internal void Resume() { Interlocked.Decrement(ref _paused); }
    private bool Same(PrivacyPublicationInput owner) => !_disposed && _current() is { } now &&
        now.Owner == owner.Owner && now.Generation == owner.Generation;
    private void Ensure(PrivacyPublicationInput owner)
    { if (!Same(owner)) throw new AccountBridgeHostException("events.account_changed"); }
    internal async Task<EventSharingRemoteSnapshot> ReadAsync(BridgeAccountContext owner, long generation, CancellationToken token)
    {
        var result = await _settings.ReadEventsAsync(owner, generation, token);
        if (_disposed || _current() is not { } now || now.Owner != owner || now.Generation != generation)
            throw new AccountBridgeHostException("events.account_changed");
        return result;
    }
    internal async Task<EventSharingRemoteSnapshot> SaveAsync(BridgeAccountContext owner, long generation, long revision,
        string operation, bool enabled, SharedEventPreferences preferences, CancellationToken token)
    {
        Pause();
        try
        {
            await _gate.WaitAsync(token);
            try
            {
                // A failed or uncertain write must be followed by an authoritative read.
                _saved = null; _lastRead = default;
                await StopLocked(token);
                var result = await _settings.SaveEventsAsync(owner, generation, revision, operation, enabled, preferences, token);
                if (_disposed || _current() is not { } now || now.Owner != owner || now.Generation != generation)
                    throw new AccountBridgeHostException("events.account_changed");
                _saved = null; _lastRead = default;
                State = "inactive";
                return result;
            }
            finally { _gate.Release(); }
        }
        finally { Resume(); }
    }
    internal async Task<bool> StopAsync(CancellationToken token)
    {
        await _gate.WaitAsync(token);
        try { await StopLocked(token); return true; }
        catch { _withdrawPending = true; State = "unconfirmed"; return false; }
        finally { _gate.Release(); }
    }
    internal Task<bool> StopForShutdownAsync(CancellationToken token)
    {
        _shutdownOwner = _current();
        _source.Activate(null);
        return StopAsync(token);
    }
    private async Task StopLocked(CancellationToken token)
    {
        _source.Activate(null);
        if (_session is not null && _owner is not null && _lease is not null)
        {
            _withdrawPending = true;
            await _remote.WriteEventFeedAsync(_owner.Owner, _owner.Generation, "stop", _lease.Revision,
                _session, ++_sequence, [], token);
        }
        _session = null; _lease = null;
        _withdrawPending = false;
        State = "inactive";
    }
    internal async Task TickAsync()
    {
        if (_disposed || !await _gate.WaitAsync(0)) return;
        try
        {
            var input = _current();
            if (_owner is not null && !Same(_owner))
            { _source.Activate(null); _session = null; _lease = null; _saved = null; _owner = null; _lastRead = default; }
            if (input is null) { State = "inactive"; return; }
            _owner = input;
            if (_withdrawPending) await StopLocked(_lifetime.Token);
            if (_shutdownOwner is not null && Same(_shutdownOwner)) { await StopLocked(_lifetime.Token); return; }
            _shutdownOwner = null;
            if (_paused != 0 || !_allowed() || !input.IdentityConfirmed)
            { await StopLocked(_lifetime.Token); return; }
            if (_saved is null || DateTimeOffset.UtcNow - _lastRead >= TimeSpan.FromSeconds(15))
            {
                var saved = await _settings.ReadEventsAsync(input.Owner, input.Generation, _lifetime.Token);
                Ensure(input);
                if (_saved?.Revision != saved.Revision) await StopLocked(_lifetime.Token);
                _saved = saved; _lastRead = DateTimeOffset.UtcNow;
            }
            var prefs = _saved.Settings;
            if (!_saved.PublicationEnabled || prefs is null) { await StopLocked(_lifetime.Token); return; }
            var mask = prefs.Room.EffectiveTypes;
            foreach (var row in prefs.Communities) mask |= row.Choice.EffectiveTypes;
            if (mask == 0) { await StopLocked(_lifetime.Token); return; }
            if (_session is null)
            {
                var start = await _remote.WriteEventFeedAsync(input.Owner, input.Generation, "start", _saved.Revision, null, 0, [], _lifetime.Token);
                Ensure(input);
                _session = start.SessionId; _sequence = 0;
                _lease = new(input.Owner, input.Generation, _saved.Revision, mask);
                // Subscribe only AFTER the server has accepted a fresh session.
                if (_paused == 0 && _allowed()) _source.Activate(_lease);
            }
            Ensure(input);
            if (_paused != 0 || !_allowed()) { await StopLocked(_lifetime.Token); return; }
            await _remote.WriteEventFeedAsync(input.Owner, input.Generation, "append", _saved.Revision,
                _session, ++_sequence, _source.Take(_lease!), _lifetime.Token);
            Ensure(input);
            State = "active";
        }
        catch
        {
            _source.Activate(null);
            _withdrawPending = true;
            // Keep the session only for a withdrawal attempt, never resend events.
            State = "unconfirmed";
            try { await StopLocked(_lifetime.Token); } catch { }
            _saved = null; _lastRead = default;
        }
        finally { _gate.Release(); }
    }
    public void Dispose()
    {
        _disposed = true; _timer?.Dispose(); _lifetime.Cancel();
        _ = DisposeSourceAsync();
    }
    private async Task DisposeSourceAsync()
    {
        await _gate.WaitAsync();
        try { _source.Dispose(); } finally { _gate.Release(); }
    }
}
