namespace StarBridge.NativeBridge;

using System.Runtime.CompilerServices;
using System.Threading.Channels;

public sealed class InMemoryBridgeConnection : IBridgeConnection
{
    private readonly ChannelReader<BridgeEnvelope> _incoming;
    private readonly ChannelWriter<BridgeEnvelope> _outgoing;
    private int _disposed;

    private InMemoryBridgeConnection(
        ChannelReader<BridgeEnvelope> incoming,
        ChannelWriter<BridgeEnvelope> outgoing)
    {
        _incoming = incoming;
        _outgoing = outgoing;
    }

    public static (IBridgeConnection Left, IBridgeConnection Right) CreatePair(
        int capacity = BridgeProtocol.DefaultQueueCapacity)
    {
        if (capacity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(capacity));
        }

        var leftToRight = CreateChannel(capacity);
        var rightToLeft = CreateChannel(capacity);
        return (
            new InMemoryBridgeConnection(rightToLeft.Reader, leftToRight.Writer),
            new InMemoryBridgeConnection(leftToRight.Reader, rightToLeft.Writer));
    }

    public async ValueTask SendAsync(
        BridgeEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        var wireCopy = BridgeWireCodec.Decode(BridgeWireCodec.Encode(envelope));
        await _outgoing.WriteAsync(wireCopy, cancellationToken).ConfigureAwait(false);
    }

    public async IAsyncEnumerable<BridgeEnvelope> ReadAllAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        await foreach (var envelope in _incoming.ReadAllAsync(cancellationToken).ConfigureAwait(false))
        {
            yield return envelope;
        }
    }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 0)
        {
            _outgoing.TryComplete();
        }

        return ValueTask.CompletedTask;
    }

    private static Channel<BridgeEnvelope> CreateChannel(int capacity)
    {
        return Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(capacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false,
            AllowSynchronousContinuations = false
        });
    }
}
