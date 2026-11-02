// Separate wall and monotonic controls: changing UTC must never replenish a request budget.
internal sealed class MarketplaceTestTime : TimeProvider
{
    internal DateTimeOffset Wall = new(2026, 10, 23, 0, 0, 0, TimeSpan.Zero);
    private long _timestamp;
    public override long TimestampFrequency => TimeSpan.TicksPerSecond;
    public override long GetTimestamp() => _timestamp;
    public override DateTimeOffset GetUtcNow() => Wall;
    internal void AdvanceMonotonic(TimeSpan elapsed) => _timestamp += elapsed.Ticks;
    internal void Advance(TimeSpan elapsed)
    {
        Wall += elapsed;
        AdvanceMonotonic(elapsed);
    }
}
