namespace StarBridge.HostRuntime.Lifecycle;

// The live composition owns this sequence across original/candidate lifecycles.
// A number separates callbacks; it is never account approval or a handoff receipt.
internal sealed class AccountGenerationSequence
{
    private readonly object _gate = new();
    private long _last;
    internal void Observe(long generation)
    {
        if (generation < 0) throw new ArgumentOutOfRangeException(nameof(generation));
        lock (_gate) _last = Math.Max(_last, generation);
    }
    internal long Next(long generation)
    {
        if (generation < 0) throw new ArgumentOutOfRangeException(nameof(generation));
        lock (_gate)
        {
            var last = Math.Max(_last, generation);
            if (last == long.MaxValue) throw new InvalidOperationException("Account generation sequence is exhausted.");
            return _last = last + 1;
        }
    }
}
