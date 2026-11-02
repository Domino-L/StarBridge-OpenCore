namespace StarBridge.HostRuntime.Lifecycle;

// One-way retirement: every admitted operation owns its lease through actual
// completion, including cancellation-ignoring transports and native callbacks.
// Cancellation closes admission; only lease exit completes the drain receipt.
internal sealed class AsyncWorkRetirement
{
    private readonly object _gate = new();
    private readonly HashSet<Lease> _active = [];
    private readonly TaskCompletionSource _drained = new(TaskCreationOptions.RunContinuationsAsynchronously);
    private bool _closed;
    internal bool IsClosed { get { lock (_gate) return _closed; } }

    internal Lease? Enter(CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (_closed) return null;
            var lease = new Lease(this, CancellationTokenSource.CreateLinkedTokenSource(cancellationToken));
            _active.Add(lease);
            return lease;
        }
    }

    internal Task Close()
    {
        Lease[] pending;
        lock (_gate)
        {
            _closed = true;
            pending = _active.ToArray();
            if (pending.Length == 0) _drained.TrySetResult();
        }
        // Cancellation callbacks may finish a lease. Never call them under _gate.
        foreach (var lease in pending) lease.Cancel();
        return _drained.Task;
    }

    private void Exit(Lease lease)
    {
        lock (_gate)
        {
            _active.Remove(lease);
            if (_closed && _active.Count == 0) _drained.TrySetResult();
        }
    }

    internal sealed class Lease(AsyncWorkRetirement owner, CancellationTokenSource lifetime) : IDisposable
    {
        private int _disposed;
        internal CancellationToken Token { get; } = lifetime.Token;
        internal bool IsCurrent => !owner.IsClosed && !Token.IsCancellationRequested;
        internal void Cancel()
        {
            try { lifetime.Cancel(); }
            catch (ObjectDisposedException) { }
            catch (AggregateException) { /* Admission remains closed; drain still waits for actual exit. */ }
        }
        public void Dispose()
        {
            if (Interlocked.Exchange(ref _disposed, 1) != 0) return;
            owner.Exit(this);
            lifetime.Dispose();
        }
    }
}
