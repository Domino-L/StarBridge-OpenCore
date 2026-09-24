namespace StarBridge.NativeBridge;

using System.Buffers.Binary;
using System.Text.Json;

internal static class BridgeWireCodec
{
    internal static byte[] Encode(BridgeEnvelope envelope)
    {
        BridgeEnvelopeValidator.ValidateWireShape(envelope);
        var bytes = JsonSerializer.SerializeToUtf8Bytes(envelope, BridgeProtocol.JsonOptions);
        if (bytes.Length == 0 || bytes.Length > BridgeProtocol.MaximumFrameBytes)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.Backpressure,
                $"Bridge frame length {bytes.Length} is outside the allowed range.");
        }

        return bytes;
    }

    internal static BridgeEnvelope Decode(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length == 0 || bytes.Length > BridgeProtocol.MaximumFrameBytes)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"Bridge frame length {bytes.Length} is outside the allowed range.");
        }

        var envelope = JsonSerializer.Deserialize<BridgeEnvelope>(bytes, BridgeProtocol.JsonOptions)
            ?? throw new BridgeProtocolException(BridgeErrorCodes.InvalidEnvelope, "Bridge envelope is empty.");
        BridgeEnvelopeValidator.ValidateWireShape(envelope);
        return envelope;
    }

    internal static async ValueTask WriteFrameAsync(
        Stream stream,
        BridgeEnvelope envelope,
        CancellationToken cancellationToken)
    {
        var payload = Encode(envelope);
        var header = new byte[sizeof(int)];
        BinaryPrimitives.WriteInt32LittleEndian(header, payload.Length);
        await stream.WriteAsync(header, cancellationToken).ConfigureAwait(false);
        await stream.WriteAsync(payload, cancellationToken).ConfigureAwait(false);
        await stream.FlushAsync(cancellationToken).ConfigureAwait(false);
    }

    internal static async ValueTask<BridgeEnvelope?> ReadFrameAsync(
        Stream stream,
        CancellationToken cancellationToken)
    {
        var header = new byte[sizeof(int)];
        var headerBytes = await ReadExactOrEndAsync(stream, header, cancellationToken).ConfigureAwait(false);
        if (headerBytes == 0)
        {
            return null;
        }

        if (headerBytes != header.Length)
        {
            throw new EndOfStreamException("Bridge frame header ended early.");
        }

        var length = BinaryPrimitives.ReadInt32LittleEndian(header);
        if (length <= 0 || length > BridgeProtocol.MaximumFrameBytes)
        {
            throw new BridgeProtocolException(
                BridgeErrorCodes.InvalidEnvelope,
                $"Bridge frame length {length} is outside the allowed range.");
        }

        var payload = new byte[length];
        var payloadBytes = await ReadExactOrEndAsync(stream, payload, cancellationToken).ConfigureAwait(false);
        if (payloadBytes != payload.Length)
        {
            throw new EndOfStreamException("Bridge frame payload ended early.");
        }

        return Decode(payload);
    }

    private static async ValueTask<int> ReadExactOrEndAsync(
        Stream stream,
        Memory<byte> buffer,
        CancellationToken cancellationToken)
    {
        var total = 0;
        while (total < buffer.Length)
        {
            var read = await stream.ReadAsync(buffer[total..], cancellationToken).ConfigureAwait(false);
            if (read == 0)
            {
                return total;
            }

            total += read;
        }

        return total;
    }
}
