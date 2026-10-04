using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>The server does not yet notify every room presence transition.
/// Visible room/automatic module demand uses this same bounded fallback driver;
/// discovery intent does not authorize any displayed room content.</summary>
internal sealed class OverlayRoomRefreshDriver : IDisposable
{
    private readonly Func<(BridgeAccountContext? Owner, long Generation, bool Enabled)> _current;
    private readonly Func<BridgeAccountContext, CancellationToken, Task> _read;
    private readonly Func<TimeSpan, CancellationToken, Task> _wait;
    private readonly Func<TimeSpan>? _successInterval;
    private readonly Func<object?>? _demandIdentity;
    private readonly TimeProvider _clock;
    private readonly object _invalidIdentity = new();
    private readonly CancellationTokenSource _stop = new();
    internal Task Completion { get; }
    internal OverlayRoomRefreshDriver(Func<(BridgeAccountContext? Owner, long Generation, bool Enabled)> current,
        Func<BridgeAccountContext, CancellationToken, Task> read, Func<TimeSpan, CancellationToken, Task>? wait = null,
        Func<TimeSpan>? successInterval = null, Func<object?>? demandIdentity = null, TimeProvider? clock = null)
    {
        _current = current; _read = read; _wait = wait ?? Task.Delay;
        _successInterval = successInterval; _demandIdentity = demandIdentity; _clock = clock ?? TimeProvider.System;
        Completion = RunAsync();
    }
    private async Task RunAsync()
    {
        var failures = 0;
        try
        {
            while (!_stop.IsCancellationRequested)
            {
                var scope = SafeCurrent();
                var identity = SafeIdentity();
                if (!scope.Enabled || scope.Owner is null || ReferenceEquals(identity, _invalidIdentity))
                { failures = 0; await _wait(TimeSpan.FromMilliseconds(250), _stop.Token).ConfigureAwait(false); continue; }
                bool Current()
                {
                    var now = SafeCurrent();
                    return now.Enabled && now.Owner == scope.Owner && now.Generation == scope.Generation &&
                        Equals(identity, SafeIdentity());
                }
                try
                {
                    await OverlayDemandRead.RunAsync(async token =>
                    { await _read(scope.Owner, token).ConfigureAwait(false); return true; }, Current, _stop.Token).ConfigureAwait(false);
                    failures = 0;
                }
                catch (OperationCanceledException) when (_stop.IsCancellationRequested) { throw; }
                catch (OperationCanceledException) when (!Current()) { failures = 0; continue; }
                catch { failures = Math.Min(4, failures + 1); }
                await WaitForNextReadAsync(Current, failures).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) when (_stop.IsCancellationRequested) { }
    }
    private async Task WaitForNextReadAsync(Func<bool> current, int failures)
    {
        var retry = TimeSpan.FromSeconds(failures switch { 2 => 3, 3 => 5, 4 => 15, _ => 1 });
        if (_successInterval is null) { await _wait(retry, _stop.Token).ConfigureAwait(false); return; }
        var started = _clock.GetTimestamp();
        while (current())
        {
            // Waits are interruptible by visibility, owner and demand changes.
            // A confirmed room can promote discovery to live refresh immediately,
            // without adding another network timer or restarting failure backoff.
            var interval = SafeInterval();
            if (failures > 0 && retry > interval) interval = retry;
            interval = TimeSpan.FromSeconds(Math.Clamp(interval.TotalSeconds, 1, 15));
            var remaining = interval - _clock.GetElapsedTime(started);
            if (remaining <= TimeSpan.Zero) return;
            await _wait(remaining < TimeSpan.FromMilliseconds(250) ? remaining : TimeSpan.FromMilliseconds(250), _stop.Token).ConfigureAwait(false);
        }
    }
    private object? SafeIdentity()
    {
        try { return _demandIdentity?.Invoke(); }
        catch { return _invalidIdentity; }
    }
    private TimeSpan SafeInterval()
    {
        try { return _successInterval?.Invoke() ?? TimeSpan.FromSeconds(1); }
        catch { return TimeSpan.FromSeconds(15); }
    }
    private (BridgeAccountContext? Owner, long Generation, bool Enabled) SafeCurrent()
    {
        // Invalid/transient context is no demand, not a permanently faulted
        // driver. Also protects the in-flight cancellation monitor callback.
        try { return _current(); }
        catch { return (null, 0, false); }
    }
    public void Dispose() => _stop.Cancel();
}
