using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

// One borrowed connection owns transport event ordering across actual domain
// owners. Sequence is freshness only: generation, context and payload stay exact.
internal sealed class BridgeConnectionWriter(IBridgeConnection connection) : IDisposable
{
    private readonly SemaphoreSlim _writer = new(1, 1);
    private long _sequence;
    internal async ValueTask SendAsync(BridgeEnvelope envelope, CancellationToken token)
    {
        await _writer.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (envelope.MessageType == BridgeMessageTypes.Event)
                envelope = envelope with { Sequence = checked(++_sequence) };
            await connection.SendAsync(envelope, token).ConfigureAwait(false);
        }
        finally { _writer.Release(); }
    }
    public void Dispose() => _writer.Dispose();
}
