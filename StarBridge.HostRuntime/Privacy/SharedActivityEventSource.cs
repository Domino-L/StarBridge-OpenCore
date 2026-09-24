using StarBridge.Core.Events;
using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Privacy;

/// <summary>Consumes the existing journal's live append stream, never its history.
/// The publication owner must replace the lease on consent/session/visibility changes.</summary>
internal sealed class SharedActivityEventSource(LocalGameEventJournal journal, TimeProvider? clock = null) : IDisposable
{
    private readonly object _gate = new();
    private readonly Queue<SharedActivityEvent> _pending = new();
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private IDisposable? _subscription;
    private EventSourceLease? _lease;
    private long _epoch;
    private bool _disposed;
    internal const int MaximumPending = 64;

    internal void Activate(EventSourceLease? lease)
    {
        lock (_gate)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            if (lease is not null && (lease.Owner is null || lease.Generation < 0 || lease.Revision <= 0 ||
                lease.Types == 0 || SharedEventChoice.Normalize(lease.Types) != lease.Types))
                throw new ArgumentException("Invalid event source lease.");
            if (_lease == lease) return;
            _subscription?.Dispose();
            _subscription = null;
            _lease = lease;
            _epoch++;
            _pending.Clear();
            if (lease is not null)
            {
                var epoch = _epoch;
                _subscription = journal.SubscribeNewEntries(entry => Observe(entry, epoch));
            }
        }
    }

    private void Observe(LocalEventEntry entry, long epoch)
    {
        lock (_gate)
        {
            if (_disposed || epoch != _epoch || _lease is null) return;
            var category = SharedActivityEvent.Category(entry.EventType);
            if (category == 0 || (_lease.Types & category) == 0) return;
            var item = new SharedActivityEvent(entry.Id, entry.EventType, entry.OccurredAt);
            if (!Guid.TryParseExact(item.Id, "N", out _) || !item.IsFresh(_clock.GetUtcNow())) return;
            if (_pending.Count == MaximumPending) _pending.Dequeue();
            _pending.Enqueue(item);
        }
    }

    // Destructive take: failed sends are not replayed after reconnection. The
    // transport must independently recheck this lease immediately before sending.
    internal SharedActivityEvent[] Take(EventSourceLease lease)
    {
        lock (_gate)
        {
            if (_disposed || _lease != lease) return [];
            var result = _pending.Where(item => item.IsFresh(_clock.GetUtcNow())).ToArray();
            _pending.Clear();
            return result;
        }
    }

    public void Dispose()
    {
        lock (_gate)
        {
            _disposed = true;
            _epoch++;
            _lease = null;
            _subscription?.Dispose();
            _subscription = null;
            _pending.Clear();
        }
    }
}

internal sealed record EventSourceLease(BridgeAccountContext Owner, long Generation, long Revision,
    SharedActivityEventTypes Types);
