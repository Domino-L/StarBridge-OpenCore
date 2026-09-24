namespace StarBridge.NativeBridge;

using System.IO.Pipes;
using System.Runtime.CompilerServices;

public sealed class NamedPipeBridgeConnection : IBridgeConnection
{
    private readonly PipeStream _stream;
    private readonly SemaphoreSlim _writeLock = new(1, 1);
    private int _disposed;

    internal NamedPipeBridgeConnection(PipeStream stream)
    {
        _stream = stream ?? throw new ArgumentNullException(nameof(stream));
    }

    public async ValueTask SendAsync(
        BridgeEnvelope envelope,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        await _writeLock.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            await BridgeWireCodec.WriteFrameAsync(_stream, envelope, cancellationToken).ConfigureAwait(false);
        }
        finally
        {
            _writeLock.Release();
        }
    }

    public async IAsyncEnumerable<BridgeEnvelope> ReadAllAsync(
        [EnumeratorCancellation] CancellationToken cancellationToken = default)
    {
        while (Volatile.Read(ref _disposed) == 0)
        {
            var envelope = await BridgeWireCodec.ReadFrameAsync(_stream, cancellationToken).ConfigureAwait(false);
            if (envelope is null)
            {
                yield break;
            }

            yield return envelope;
        }
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        await _stream.DisposeAsync().ConfigureAwait(false);
        _writeLock.Dispose();
    }
}

public sealed class NamedPipeBridgeListener
{
    private readonly string _pipeName;

    public NamedPipeBridgeListener(string pipeName)
    {
        _pipeName = ValidatePipeName(pipeName);
    }

    public async Task<IBridgeConnection> AcceptAsync(CancellationToken cancellationToken = default)
    {
        var server = new NamedPipeServerStream(
            _pipeName,
            PipeDirection.InOut,
            1,
            PipeTransmissionMode.Byte,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly,
            BridgeProtocol.MaximumFrameBytes,
            BridgeProtocol.MaximumFrameBytes);
        try
        {
            await server.WaitForConnectionAsync(cancellationToken).ConfigureAwait(false);
            return new NamedPipeBridgeConnection(server);
        }
        catch
        {
            await server.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }

    internal static string ValidatePipeName(string pipeName)
    {
        if (string.IsNullOrWhiteSpace(pipeName) ||
            pipeName.Contains('\\') ||
            pipeName.Contains('/'))
        {
            throw new ArgumentException("Pipe name must be a non-empty local name.", nameof(pipeName));
        }

        return pipeName;
    }
}

public sealed class NamedPipeBridgeConnector
{
    private readonly string _pipeName;

    public NamedPipeBridgeConnector(string pipeName)
    {
        _pipeName = NamedPipeBridgeListener.ValidatePipeName(pipeName);
    }

    public async Task<IBridgeConnection> ConnectAsync(
        TimeSpan timeout,
        CancellationToken cancellationToken = default)
    {
        if (timeout <= TimeSpan.Zero)
        {
            throw new ArgumentOutOfRangeException(nameof(timeout));
        }

        var client = new NamedPipeClientStream(
            ".",
            _pipeName,
            PipeDirection.InOut,
            PipeOptions.Asynchronous | PipeOptions.CurrentUserOnly);
        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeoutSource.CancelAfter(timeout);
        try
        {
            await client.ConnectAsync(timeoutSource.Token).ConfigureAwait(false);
            return new NamedPipeBridgeConnection(client);
        }
        catch
        {
            await client.DisposeAsync().ConfigureAwait(false);
            throw;
        }
    }
}
