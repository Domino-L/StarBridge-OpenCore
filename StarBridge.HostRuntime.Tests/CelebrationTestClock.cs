internal sealed class CelebrationTestClock : TimeProvider
{
    private readonly object _gate = new();
    private DateTimeOffset _now = DateTimeOffset.UtcNow.AddMinutes(-1);
    private long _ticks;
    private readonly List<Timer> _timers = [];
    public override TimeZoneInfo LocalTimeZone => TimeZoneInfo.Utc;
    public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    public override long GetTimestamp() { lock (_gate) return _ticks; }
    internal void ShiftWall(TimeSpan amount) { lock (_gate) _now += amount; }
    public override DateTimeOffset GetUtcNow() { lock (_gate) return _now; }
    public override ITimer CreateTimer(TimerCallback callback, object? state, TimeSpan dueTime, TimeSpan period)
    {
        lock (_gate) { var timer = new Timer(this, callback, state); _timers.Add(timer); timer.Change(dueTime, period); return timer; }
    }
    internal bool Waiting(TimeSpan delay) { lock (_gate) return _timers.Any(t => t.Due == _now + delay); }
    internal void Advance(TimeSpan amount)
    {
        Timer[] due;
        lock (_gate) { _now += amount; _ticks += Math.Max(0, amount.Ticks); due = _timers.Where(t => t.Due <= _now).ToArray(); foreach (var t in due) t.Due = DateTimeOffset.MaxValue; }
        foreach (var timer in due) timer.Fire();
    }
    private sealed class Timer(CelebrationTestClock clock, TimerCallback callback, object? state) : ITimer
    {
        internal DateTimeOffset Due = DateTimeOffset.MaxValue;
        private bool _disposed;
        internal void Fire() { if (!_disposed) callback(state); }
        public bool Change(TimeSpan dueTime, TimeSpan period)
        { lock (clock._gate) { Due = _disposed || dueTime == Timeout.InfiniteTimeSpan ? DateTimeOffset.MaxValue : clock._now + dueTime; return !_disposed; } }
        public void Dispose() { lock (clock._gate) { _disposed = true; Due = DateTimeOffset.MaxValue; } }
        public ValueTask DisposeAsync() { Dispose(); return ValueTask.CompletedTask; }
    }
    internal static async Task Until(Func<bool> check)
    {
        var timeout = global::System.Diagnostics.Stopwatch.StartNew();
        while (!check()) { if (timeout.Elapsed > TimeSpan.FromSeconds(5)) throw new Exception("Synthetic scheduler did not reach expected boundary"); await Task.Delay(1); }
    }
}
