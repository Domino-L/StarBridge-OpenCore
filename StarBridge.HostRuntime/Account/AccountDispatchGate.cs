namespace StarBridge.HostRuntime.Account;

internal enum AccountDispatchPriority { Background, Normal, Foreground }

/// <summary>How a request enters the account lane. Shared reads may overlap;
/// exclusive entries run alone. Only known reads are reorderable: they may pass
/// other queued reads of lower priority, never a queued barrier (a mutation,
/// an unclassified request or an event-draining read).</summary>
internal readonly record struct AccountDispatchAccess(bool Shared, bool Reorderable, AccountDispatchPriority Priority)
{
    internal static AccountDispatchAccess Barrier => new(false, false, AccountDispatchPriority.Normal);
}

/// <summary>
/// A small read lane behind an exclusive mutation barrier. A waiting barrier
/// holds admission so new reads cannot indefinitely delay login/logout/writes.
/// Between barriers, queued reads are admitted by priority (FIFO within one
/// priority), so a page read is not stuck behind background media reads.
/// </summary>
internal sealed class AccountDispatchGate : IDisposable
{
    private const int ReadSlots = 4;
    private readonly object _sync = new();
    private readonly LinkedList<Waiter> _queue = new();
    private int _readers;
    private int _projections;
    private bool _exclusive;
    private bool _barrierActive;
    private bool _disposed;

    /// <summary>A synchronous in-memory projection beside reads, never beside
    /// or ahead of a barrier: refused while one runs or waits, and a barrier
    /// is not admitted until projections already inside have left.</summary>
    internal bool TryEnterProjection(out IAsyncDisposable lease)
        => TryEnterProjection(out lease, out _);

    internal void Observe(AccountCurrentDiagnostics diagnostic)
    {
        lock (_sync)
        {
            diagnostic.Readers = _readers;
            diagnostic.QueuedShared = _queue.Count(waiter => waiter.Access.Shared);
        }
    }

    internal bool TryEnterProjection(out IAsyncDisposable lease, out CurrentProjectionReason reason)
    {
        lock (_sync)
        {
            lease = null!;
            reason = CurrentProjectionReason.none;
            if (_disposed) { reason = CurrentProjectionReason.gateDisposed; return false; }
            if (_barrierActive) { reason = CurrentProjectionReason.gateBarrierRunning; return false; }
            foreach (var waiter in _queue)
                if (!waiter.Access.Reorderable) { reason = CurrentProjectionReason.gateNonReorderableQueued; return false; }
            _projections++;
            lease = new Lease(this, LeaseKind.Projection);
            return true;
        }
    }

    internal ValueTask<IAsyncDisposable> EnterAsync(bool read, CancellationToken token) =>
        EnterAsync(read ? new(true, true, AccountDispatchPriority.Normal) : AccountDispatchAccess.Barrier, token);

    internal async ValueTask<IAsyncDisposable> EnterAsync(AccountDispatchAccess access, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        var waiter = new Waiter(access);
        lock (_sync)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            waiter.Node = _queue.AddLast(waiter);
            Grant();
        }
        using (token.Register(() => Cancel(waiter, token)))
            await waiter.Completion.Task;
        return new Lease(this, access.Shared ? LeaseKind.Shared : LeaseKind.Exclusive);
    }

    private void Cancel(Waiter waiter, CancellationToken token)
    {
        lock (_sync)
        {
            // Already admitted: the caller owns the lease and releases it.
            if (waiter.Node is not { } node) return;
            _queue.Remove(node);
            waiter.Node = null;
            waiter.Completion.TrySetCanceled(token);
            Grant();
        }
    }

    // Called under _sync. Admits as many waiters as the current state allows.
    private void Grant()
    {
        while (_queue.First is { } head)
        {
            LinkedListNode<Waiter> next = head;
            if (head.Value.Access.Reorderable)
            {
                for (var node = head.Next; node is not null && node.Value.Access.Reorderable; node = node.Next)
                    if (node.Value.Access.Priority > next.Value.Access.Priority) next = node;
            }
            var access = next.Value.Access;
            if (_exclusive || (access.Shared ? _readers >= ReadSlots : _readers > 0)) return;
            if (!access.Reorderable && _projections > 0) return;
            _queue.Remove(next);
            next.Value.Node = null;
            if (access.Shared) _readers++;
            else { _exclusive = true; _barrierActive = !access.Reorderable; }
            next.Value.Completion.TrySetResult();
        }
    }

    private void Exit(LeaseKind kind)
    {
        lock (_sync)
        {
            switch (kind)
            {
                case LeaseKind.Shared: _readers--; break;
                case LeaseKind.Projection: _projections--; break;
                default: _exclusive = false; _barrierActive = false; break;
            }
            if (!_disposed) Grant();
        }
    }

    private enum LeaseKind { Shared, Exclusive, Projection }

    private sealed class Waiter(AccountDispatchAccess access)
    {
        internal readonly AccountDispatchAccess Access = access;
        internal readonly TaskCompletionSource Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal LinkedListNode<Waiter>? Node;
    }

    private sealed class Lease(AccountDispatchGate gate, LeaseKind kind) : IAsyncDisposable
    {
        private AccountDispatchGate? _gate = gate;
        public ValueTask DisposeAsync()
        {
            Interlocked.Exchange(ref _gate, null)?.Exit(kind);
            return ValueTask.CompletedTask;
        }
    }

    // The pipe owner drains all request workers before disposing its dispatcher.
    public void Dispose()
    {
        lock (_sync)
        {
            _disposed = true;
            foreach (var waiter in _queue)
            {
                waiter.Node = null;
                waiter.Completion.TrySetException(new ObjectDisposedException(nameof(AccountDispatchGate)));
            }
            _queue.Clear();
        }
    }
}
