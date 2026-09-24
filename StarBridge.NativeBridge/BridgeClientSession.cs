namespace StarBridge.NativeBridge;

using System.Collections.Concurrent;
using System.Threading.Channels;

public sealed class BridgeClientSession : IAsyncDisposable
{
    private readonly IBridgeConnection _connection;
    private readonly IBridgeDiagnostics _diagnostics;
    private readonly ConcurrentDictionary<string, PendingRequest> _pending = new(StringComparer.Ordinal);
    private readonly Channel<BridgeEnvelope> _events;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly Task _readerTask;
    private long _activeGeneration;
    private long _highestEventSequence = -1;
    private int _disposed;

    public BridgeClientSession(
        IBridgeConnection connection,
        long sessionGeneration,
        IBridgeDiagnostics? diagnostics = null,
        int eventCapacity = BridgeProtocol.DefaultQueueCapacity)
    {
        _connection = connection ?? throw new ArgumentNullException(nameof(connection));
        if (sessionGeneration < 0)
        {
            throw new ArgumentOutOfRangeException(nameof(sessionGeneration));
        }

        if (eventCapacity <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(eventCapacity));
        }

        _activeGeneration = sessionGeneration;
        _diagnostics = diagnostics ?? NullBridgeDiagnostics.Instance;
        _events = Channel.CreateBounded<BridgeEnvelope>(new BoundedChannelOptions(eventCapacity)
        {
            FullMode = BoundedChannelFullMode.Wait,
            SingleReader = false,
            SingleWriter = true,
            AllowSynchronousContinuations = false
        });
        _readerTask = RunReaderAsync();
    }

    public long ActiveGeneration => Volatile.Read(ref _activeGeneration);

    public async Task<BridgeEnvelope> RequestAsync(
        string name,
        object? payload = null,
        BridgeAccountContext? accountContext = null,
        TimeSpan? timeout = null,
        CancellationToken cancellationToken = default)
    {
        ObjectDisposedException.ThrowIf(Volatile.Read(ref _disposed) != 0, this);
        BridgeEnvelopeValidator.RequireAccountContext(name, accountContext);

        var generation = ActiveGeneration;
        var correlationId = Guid.NewGuid().ToString("N");
        var request = BridgeEnvelope.Request(name, correlationId, generation, payload, accountContext);
        var completion = new TaskCompletionSource<BridgeEnvelope>(TaskCreationOptions.RunContinuationsAsynchronously);
        var pending = new PendingRequest(generation, completion);
        if (!_pending.TryAdd(correlationId, pending))
        {
            throw new InvalidOperationException("Generated duplicate bridge correlation ID.");
        }

        try
        {
            await _connection.SendAsync(request, cancellationToken).ConfigureAwait(false);
        }
        catch
        {
            _pending.TryRemove(correlationId, out _);
            throw;
        }

        using var timeoutSource = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken, _lifetime.Token);
        timeoutSource.CancelAfter(timeout ?? BridgeProtocol.DefaultRequestTimeout);
        using var registration = timeoutSource.Token.Register(
            static state => ((TaskCompletionSource<BridgeEnvelope>)state!).TrySetCanceled(),
            completion);

        try
        {
            return await completion.Task.ConfigureAwait(false);
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested && !_lifetime.IsCancellationRequested)
        {
            _pending.TryRemove(correlationId, out _);
            await SendCancellationBestEffortAsync(correlationId, generation).ConfigureAwait(false);
            throw new TimeoutException($"Bridge request '{name}' timed out.");
        }
        catch (OperationCanceledException)
        {
            _pending.TryRemove(correlationId, out _);
            await SendCancellationBestEffortAsync(correlationId, generation).ConfigureAwait(false);
            throw;
        }
    }

    public IAsyncEnumerable<BridgeEnvelope> ReadEventsAsync(CancellationToken cancellationToken = default) =>
        _events.Reader.ReadAllAsync(cancellationToken);

    public void AdvanceGeneration(long nextGeneration)
    {
        var previous = ActiveGeneration;
        if (nextGeneration <= previous)
        {
            throw new ArgumentOutOfRangeException(
                nameof(nextGeneration),
                "Session generation must increase monotonically.");
        }

        Interlocked.Exchange(ref _activeGeneration, nextGeneration);
        Interlocked.Exchange(ref _highestEventSequence, -1);
        foreach (var entry in _pending)
        {
            if (_pending.TryRemove(entry.Key, out var pending))
            {
                pending.Completion.TrySetException(
                    new BridgeStaleGenerationException(pending.Generation, nextGeneration));
            }
        }

        _diagnostics.Record(new BridgeDiagnosticEvent("generation_advanced", "active"));
    }

    public async ValueTask DisposeAsync()
    {
        if (Interlocked.Exchange(ref _disposed, 1) != 0)
        {
            return;
        }

        _lifetime.Cancel();
        await _connection.DisposeAsync().ConfigureAwait(false);
        try
        {
            await _readerTask.ConfigureAwait(false);
        }
        catch (OperationCanceledException)
        {
        }

        _lifetime.Dispose();
    }

    private async Task RunReaderAsync()
    {
        Exception? terminalError = null;
        try
        {
            await foreach (var envelope in _connection.ReadAllAsync(_lifetime.Token).ConfigureAwait(false))
            {
                BridgeEnvelopeValidator.RequireCurrentVersion(envelope);
                if (envelope.MessageType == BridgeMessageTypes.Response)
                {
                    HandleResponse(envelope);
                }
                else if (envelope.MessageType == BridgeMessageTypes.Event)
                {
                    await HandleEventAsync(envelope).ConfigureAwait(false);
                }
                else
                {
                    _diagnostics.Record(new BridgeDiagnosticEvent("unexpected_request", "dropped", envelope.Name));
                }
            }
        }
        catch (OperationCanceledException) when (_lifetime.IsCancellationRequested)
        {
        }
        catch (Exception exception)
        {
            terminalError = exception;
        }
        finally
        {
            var failure = terminalError as BridgeProtocolException ??
                new BridgeDisconnectedException("The Native Bridge connection ended.", terminalError);
            FailPending(failure);
            _events.Writer.TryComplete(terminalError);
        }
    }

    private void HandleResponse(BridgeEnvelope envelope)
    {
        if (envelope.SessionGeneration != ActiveGeneration)
        {
            _diagnostics.Record(new BridgeDiagnosticEvent("stale_response", "dropped", envelope.Name));
            return;
        }

        if (envelope.CorrelationId is null || !_pending.TryRemove(envelope.CorrelationId, out var pending))
        {
            _diagnostics.Record(new BridgeDiagnosticEvent("duplicate_or_unknown_response", "dropped", envelope.Name));
            return;
        }

        if (pending.Generation != envelope.SessionGeneration)
        {
            pending.Completion.TrySetException(
                new BridgeStaleGenerationException(pending.Generation, ActiveGeneration));
            return;
        }

        switch (envelope.Status)
        {
            case BridgeResponseStatuses.Ok:
                pending.Completion.TrySetResult(envelope);
                break;
            case BridgeResponseStatuses.Cancelled:
                pending.Completion.TrySetCanceled();
                break;
            case BridgeResponseStatuses.Error:
                pending.Completion.TrySetException(
                    new BridgeRemoteException(
                        envelope.Error ?? new BridgeError(BridgeErrorCodes.InvalidEnvelope, "Missing remote error.")));
                break;
        }
    }

    private async Task HandleEventAsync(BridgeEnvelope envelope)
    {
        if (envelope.Name == "account.changed" && envelope.SessionGeneration > ActiveGeneration)
        {
            AdvanceGeneration(envelope.SessionGeneration);
        }

        if (envelope.SessionGeneration != ActiveGeneration)
        {
            _diagnostics.Record(new BridgeDiagnosticEvent("stale_event", "dropped", envelope.Name));
            return;
        }

        var sequence = envelope.Sequence ?? -1;
        var previous = Interlocked.Read(ref _highestEventSequence);
        if (sequence <= previous)
        {
            _diagnostics.Record(new BridgeDiagnosticEvent("duplicate_or_out_of_order_event", "dropped", envelope.Name));
            return;
        }

        Interlocked.Exchange(ref _highestEventSequence, sequence);
        await _events.Writer.WriteAsync(envelope, _lifetime.Token).ConfigureAwait(false);
    }

    private async Task SendCancellationBestEffortAsync(string targetCorrelationId, long generation)
    {
        try
        {
            var cancellation = BridgeEnvelope.Request(
                "bridge.cancel",
                Guid.NewGuid().ToString("N"),
                generation,
                new { targetCorrelationId });
            await _connection.SendAsync(cancellation, CancellationToken.None).ConfigureAwait(false);
        }
        catch
        {
            _diagnostics.Record(new BridgeDiagnosticEvent("cancel_delivery_failed", "ignored"));
        }
    }

    private void FailPending(Exception exception)
    {
        foreach (var entry in _pending)
        {
            if (_pending.TryRemove(entry.Key, out var pending))
            {
                pending.Completion.TrySetException(exception);
            }
        }
    }

    private sealed record PendingRequest(
        long Generation,
        TaskCompletionSource<BridgeEnvelope> Completion);
}
