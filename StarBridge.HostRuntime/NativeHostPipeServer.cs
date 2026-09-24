namespace StarBridge.HostRuntime;

using StarBridge.NativeBridge;
using System.IO;
using System.Threading.Channels;

/// <summary>
/// Owns connection replacement, bounded event delivery and response-before-
/// event ordering for one headless Native Host. Callers only provide the pipe
/// name and one feature dispatcher.
/// </summary>
public sealed class NativeHostPipeServer(
    string pipeName,
    IBridgeRequestDispatcher dispatcher) : IAsyncDisposable
{
    private const int RequestWorkerCount = 4;

    private readonly NamedPipeBridgeListener _listener = new(pipeName);
    private readonly IBridgeRequestDispatcher _dispatcher = dispatcher ??
        throw new ArgumentNullException(nameof(dispatcher));
    private int _disposed;

    public async Task RunAsync(CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        while (!cancellationToken.IsCancellationRequested)
        {
            IBridgeConnection? connection = null;
            try
            {
                connection = await _listener.AcceptAsync(cancellationToken).ConfigureAwait(false);
                await ServeConnectionAsync(connection, _dispatcher, cancellationToken).ConfigureAwait(false);
            }
            catch (OperationCanceledException) when (cancellationToken.IsCancellationRequested)
            {
                return;
            }
            catch (Exception exception) when (exception is IOException or BridgeProtocolException)
            {
                // A broken or malformed client only ends its own lease. The
                // next Flutter process can reconnect to a fresh pipe instance.
            }
            finally
            {
                if (connection is not null)
                {
                    await connection.DisposeAsync().ConfigureAwait(false);
                }
            }
        }
    }

    public static async Task ServeConnectionAsync(
        IBridgeConnection connection,
        IBridgeRequestDispatcher dispatcher,
        CancellationToken cancellationToken = default)
    {
        ArgumentNullException.ThrowIfNull(connection);
        ArgumentNullException.ThrowIfNull(dispatcher);

        using var connectionLifetime = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        var events = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(
            BridgeProtocol.DefaultQueueCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = true,
            SingleWriter = false
        });
        var requests = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(
            BridgeProtocol.DefaultQueueCapacity)
        {
            // The reader loop intentionally uses TryWrite so a saturated Host
            // returns bridge.backpressure immediately instead of silently
            // dropping a request or waiting forever behind long-lived work.
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = false,
            SingleWriter = true
        });
        var controls = Channel.CreateUnbounded<BridgeEnvelope>(new UnboundedChannelOptions
        {
            SingleReader = true,
            SingleWriter = true
        });

        void QueueEvent(BridgeEnvelope envelope)
        {
            if (!events.Writer.TryWrite(envelope))
            {
                connectionLifetime.Cancel();
            }
        }

        dispatcher.EventReady += QueueEvent;
        var eventPump = PumpEventsAsync(
            connection,
            events.Reader,
            connectionLifetime);
        var requestPumps = Enumerable
            .Range(0, RequestWorkerCount)
            .Select(_ => PumpRequestsAsync(
                connection,
                dispatcher,
                requests.Reader,
                connectionLifetime))
            .ToArray();
        var controlPump = PumpRequestsAsync(
            connection,
            dispatcher,
            controls.Reader,
            connectionLifetime);
        try
        {
            await foreach (var request in connection
                .ReadAllAsync(connectionLifetime.Token)
                .WithCancellation(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                if (BridgeRequestPolicy.IsOutOfBandControl(request.Name))
                {
                    if (!controls.Writer.TryWrite(request))
                    {
                        connectionLifetime.Cancel();
                    }

                    continue;
                }

                if (!requests.Writer.TryWrite(request))
                {
                    await connection.SendAsync(
                        BridgeEnvelope.ErrorResponse(
                            request,
                            new BridgeError(
                                BridgeErrorCodes.Backpressure,
                                "Native Host request capacity is exhausted.",
                                true)),
                        connectionLifetime.Token).ConfigureAwait(false);
                }
            }
        }
        finally
        {
            dispatcher.EventReady -= QueueEvent;
            events.Writer.TryComplete();
            requests.Writer.TryComplete();
            controls.Writer.TryComplete();
            connectionLifetime.Cancel();
            try
            {
                await Task.WhenAll(requestPumps.Append(controlPump).Append(eventPump))
                    .ConfigureAwait(false);
            }
            catch (OperationCanceledException)
            {
                // Expected when the client disconnects or the Host exits.
            }
        }
    }

    private static async Task PumpRequestsAsync(
        IBridgeConnection connection,
        IBridgeRequestDispatcher dispatcher,
        ChannelReader<BridgeEnvelope> requests,
        CancellationTokenSource connectionLifetime)
    {
        try
        {
            await foreach (var request in requests
                .ReadAllAsync(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                var batch = await dispatcher
                    .DispatchAsync(request, connectionLifetime.Token)
                    .ConfigureAwait(false);
                await connection
                    .SendAsync(batch.Response, connectionLifetime.Token)
                    .ConfigureAwait(false);
                foreach (var envelope in batch.Events)
                {
                    await connection
                        .SendAsync(envelope, connectionLifetime.Token)
                        .ConfigureAwait(false);
                }
            }
        }
        catch
        {
            connectionLifetime.Cancel();
            throw;
        }
    }

    private static async Task PumpEventsAsync(
        IBridgeConnection connection,
        ChannelReader<BridgeEnvelope> events,
        CancellationTokenSource connectionLifetime)
    {
        try
        {
            await foreach (var envelope in events
                .ReadAllAsync(connectionLifetime.Token)
                .ConfigureAwait(false))
            {
                await connection
                    .SendAsync(envelope, connectionLifetime.Token)
                    .ConfigureAwait(false);
            }
        }
        catch
        {
            connectionLifetime.Cancel();
            throw;
        }
    }

    public ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) == 0)
        {
            _dispatcher.Dispose();
        }

        return ValueTask.CompletedTask;
    }
}
