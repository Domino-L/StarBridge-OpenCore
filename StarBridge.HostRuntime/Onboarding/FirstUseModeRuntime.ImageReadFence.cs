namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // Cheap cancellation only, bracketed by original durable Current reads and
    // the live account owner. This fence never authenticates from a cache.
    internal Func<bool> CaptureOnlineReadFence(long revision)
    {
        var epoch = Interlocked.Read(ref _epoch);
        var accepted = Volatile.Read(ref _accepted);
        return () => !_closed && !_changing && accepted is not null && accepted.Revision == revision &&
            accepted.Phase is "online" or "unchosen" && Volatile.Read(ref _accepted) == accepted &&
            Interlocked.Read(ref _epoch) == epoch;
    }
}
