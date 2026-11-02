namespace StarBridge.HostRuntime.Lifecycle;

using StarBridge.NativeBridge;
using System.Threading.Channels;

// Only the pipe reader enqueues/cancels. Workers remove under the same lock,
// making cancellation and the queued-to-running handoff mutually exclusive.
internal sealed class BridgeActivityWaitQueue(int workerCount, int queuedCapacity) : ChannelReader<BridgeEnvelope>
{
    private readonly object _gate = new();
    private readonly LinkedList<BridgeEnvelope> _pending = new();
    // A level signal, not one permit per request: cancellation cannot accumulate
    // stale permits while all workers are occupied. The list owns the bound.
    private readonly Channel<bool> _ready = Channel.CreateBounded<bool>(new BoundedChannelOptions(1)
    {
        SingleReader = false, SingleWriter = false, FullMode = BoundedChannelFullMode.DropWrite
    });
    private bool _completed;
    private int _running;

    internal bool TryWrite(BridgeEnvelope request)
    {
        lock (_gate)
        {
            // Reserve idle workers too: a burst must fit before those async
            // workers get scheduled. Once all run, only queuedCapacity remains.
            if (_completed || _pending.Count + _running >= workerCount + queuedCapacity) return false;
            _pending.AddLast(request);
            _ready.Writer.TryWrite(true);
            return true;
        }
    }

    public override bool TryRead(out BridgeEnvelope item)
    {
        lock (_gate)
        {
            if (_pending.First is not { } first) { item = null!; return false; }
            item = first.Value;
            _pending.RemoveFirst();
            _running++;
            if (_pending.Count == 0) _ready.Reader.TryRead(out _);
            return true;
        }
    }

    internal IReadOnlyList<BridgeEnvelope> RemoveCancelled(Func<BridgeEnvelope, CancellationToken> tokenFor)
    {
        lock (_gate)
        {
            List<BridgeEnvelope> removed = [];
            for (var node = _pending.First; node is not null;)
            {
                var next = node.Next;
                if (tokenFor(node.Value).IsCancellationRequested)
                {
                    removed.Add(node.Value);
                    _pending.Remove(node);
                }
                node = next;
            }
            if (_pending.Count == 0) _ready.Reader.TryRead(out _);
            return removed;
        }
    }

    public override ValueTask<bool> WaitToReadAsync(CancellationToken cancellationToken = default) =>
        _ready.Reader.WaitToReadAsync(cancellationToken);

    internal void CompleteRequest()
    {
        lock (_gate) _running--;
    }

    internal void Complete()
    {
        lock (_gate) { _completed = true; _ready.Writer.TryComplete(); }
    }
}
