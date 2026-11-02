namespace StarBridge.Desktop;

using System.Diagnostics;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime : IInformationOverlayUsageMeter
{
    private readonly OverlayUsageClock _usage = new();

    public bool IsOverlayOpen => _usage.IsOpen;

    public long TakeOpenSeconds() => _usage.TakeSeconds();

    // Called from every game-window check (750 ms) on the control thread.
    private void SampleOverlayUsage() => _usage.Sample(_window is not null, Stopwatch.GetTimestamp());
}

// Adds up open time in short steps. A step longer than MaxStep (sleep, a stalled
// dispatcher, a stopped timer) is dropped whole instead of being credited to whatever
// state the overlay happens to be in when sampling resumes.
internal sealed class OverlayUsageClock
{
    internal static readonly TimeSpan MaxStep = TimeSpan.FromSeconds(5);
    private readonly object _gate = new();
    private readonly long _frequency;
    private long _last;
    private bool _openAtLast;
    private long _ticks;

    internal OverlayUsageClock(long? frequency = null) => _frequency = frequency ?? Stopwatch.Frequency;

    internal bool IsOpen { get { lock (_gate) return _openAtLast; } }

    internal void Sample(bool open, long timestamp)
    {
        lock (_gate)
        {
            var step = timestamp - _last;
            if (_last != 0 && _openAtLast && step > 0 && step <= (long)(MaxStep.TotalSeconds * _frequency)) _ticks += step;
            _last = timestamp;
            _openAtLast = open;
        }
    }

    internal long TakeSeconds()
    {
        lock (_gate)
        {
            var seconds = _ticks / _frequency;
            _ticks -= seconds * _frequency;
            return seconds;
        }
    }
}
