namespace StarBridge.HostRuntime.Reminders;

/// <summary>Device-local reminder schedule, independent from accounts and cumulative-playtime consent.</summary>
public sealed class ContinuousPlayReminderRuntime : IDisposable
{
    private readonly IContinuousPlayStore _store;
    private readonly Func<PlayProcessObservation> _process;
    private readonly IContinuousPlayReminderSink _sink;
    private readonly TimeProvider _time;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly CancellationTokenSource _lifetime = new();
    private ContinuousPlayState? _state;
    private DateTimeOffset _lastSaved;
    private DateTimeOffset _nextStorageRetry;
    private int _epoch;
    private int _pendingSaves;
    private bool _disposed;
    public ContinuousPlayReminderRuntime(string dataRoot, Func<PlayProcessObservation> process,
        IContinuousPlayReminderSink sink, TimeProvider? time = null) : this(new ContinuousPlayStore(dataRoot), process, sink, time) { }
    internal ContinuousPlayReminderRuntime(IContinuousPlayStore store, Func<PlayProcessObservation> process,
        IContinuousPlayReminderSink sink, TimeProvider? time = null)
    { _store = store; _process = process; _sink = sink; _time = time ?? TimeProvider.System; }
    public async Task<ContinuousPlaySettings> ReadAsync(CancellationToken cancellation = default)
    {
        await _gate.WaitAsync(cancellation);
        try { ObjectDisposedException.ThrowIf(_disposed, this); _ = _store.ReadState(); return _store.ReadSettings(); }
        finally { _gate.Release(); }
    }
    public async Task<ContinuousPlaySettings> SaveAsync(ContinuousPlaySettings desired, int expectedRevision,
        CancellationToken cancellation = default, Func<bool>? canCommit = null)
    {
        if (!desired.Valid) throw new ArgumentException();
        Interlocked.Increment(ref _epoch);
        Interlocked.Increment(ref _pendingSaves);
        var acquired = false;
        try
        {
            await _gate.WaitAsync(cancellation);
            acquired = true;
            ObjectDisposedException.ThrowIf(_disposed, this);
            var current = _store.ReadSettings();
            if (current.Revision != expectedRevision) throw new ContinuousPlayConflictException();
            cancellation.ThrowIfCancellationRequested();
            if (canCommit?.Invoke() == false) throw new OperationCanceledException(cancellation);
            var saved = desired with { Revision = checked(current.Revision + 1) };
            _store.SaveSettings(saved);
            return saved; // Reconfigure schedule on next tick, including after a restart.
        }
        finally
        {
            Interlocked.Decrement(ref _pendingSaves);
            Interlocked.Increment(ref _epoch);
            if (acquired) _gate.Release();
        }
    }
    public async Task TickAsync(CancellationToken cancellation = default)
    {
        if (_disposed || !await _gate.WaitAsync(0, cancellation)) return;
        try
        {
            var now = _time.GetUtcNow();
            if (now < _nextStorageRetry) return;
            using var linked = CancellationTokenSource.CreateLinkedTokenSource(cancellation, _lifetime.Token);
            var settings = _store.ReadSettings();
            _state ??= _store.ReadState();
            var process = _process();
            var previous = _state;
            _state = _state.Configure(settings).Observe(process, now, settings);
            var due = !_disposed && settings.Enabled && process.State == "running" && _state.NextReminderAtUtc <= now &&
                (_state.RetryNotBeforeUtc is null || _state.RetryNotBeforeUtc <= now);
            if (due)
            {
                _state = _state with { RetryNotBeforeUtc = now.AddMinutes(1) };
                _store.SaveState(_state); _lastSaved = now;
                var epoch = Volatile.Read(ref _epoch);
                bool Current() => !_disposed && Volatile.Read(ref _pendingSaves) == 0 &&
                    epoch == Volatile.Read(ref _epoch) && !linked.IsCancellationRequested;
                var accepted = false;
                try { accepted = await _sink.TryQueueAsync(new(now - _state.SessionStartedAtUtc!.Value, Current), linked.Token); }
                catch (OperationCanceledException) { return; }
                catch { /* Retain bounded retry, not a shown acknowledgement. */ }
                if (accepted && Current())
                {
                    _state = _state with { LastReminderAtUtc = now, NextReminderAtUtc = now.AddMinutes(settings.RepeatReminderMinutes), RetryNotBeforeUtc = null };
                    _store.SaveState(_state);
                }
            }
            else if (_state != previous && (now - _lastSaved >= TimeSpan.FromMinutes(1) ||
                _state.SessionStartedAtUtc != previous.SessionStartedAtUtc || _state.MissingSinceUtc != previous.MissingSinceUtc))
            { _store.SaveState(_state); _lastSaved = now; }
        }
        catch (OperationCanceledException) { }
        catch { _nextStorageRetry = _time.GetUtcNow().AddMinutes(1); }
        finally { _gate.Release(); }
    }
    public void Dispose() { _disposed = true; Interlocked.Increment(ref _epoch); _lifetime.Cancel(); }
}
public sealed class ContinuousPlayConflictException : Exception;
