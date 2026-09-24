using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Hangar;

internal enum HangarPublicationOutcome { Complete, Retryable, Rejected, Unknown }

/// <summary>One latest committed import for the current session; no stored credentials or blind write replay.</summary>
internal sealed class HangarAutoSync : IDisposable
{
    private sealed record Work(BridgeAccountContext Owner, long Generation, long Revision);
    private readonly object _gate = new();
    private readonly Func<BridgeAccountContext, long, long, CancellationToken, Task<HangarPublicationOutcome>> _publish;
    private readonly Action<long> _changed;
    private readonly Func<TimeSpan, CancellationToken, Task> _delay;
    private CancellationTokenSource? _pending;
    private Work? _last;
    private Task _running = Task.CompletedTask;
    private bool _disposed;

    internal HangarAutoSync(
        Func<BridgeAccountContext, long, long, CancellationToken, Task<HangarPublicationOutcome>> publish,
        Action<long> changed, Func<TimeSpan, CancellationToken, Task>? delay = null)
    { _publish = publish; _changed = changed; _delay = delay ?? Task.Delay; }

    internal Task Queue(BridgeAccountContext owner, long generation, long revision)
    {
        var work = new Work(owner, generation, revision);
        lock (_gate)
        {
            if (_disposed) return Task.CompletedTask;
            if (work == _last) return _running;
            _pending?.Cancel();
            _last = work;
            var cancellation = _pending = new();
            // Never put even the initial synchronous part of a remote operation
            // on the local save response path.
            return _running = Task.Run(() => Run(work, cancellation));
        }
    }

    private async Task Run(Work work, CancellationTokenSource cancellation)
    {
        var token = cancellation.Token;
        try
        {
            var attempt = 0;
            while (!token.IsCancellationRequested)
            {
                var result = await _publish(work.Owner, work.Generation, work.Revision, token).ConfigureAwait(false);
                lock (_gate)
                {
                    if (_disposed || _pending != cancellation || token.IsCancellationRequested) return;
                }
                // Subscribers have their own generation guard. Do not call them
                // under the queue lock (account changes take the event lock first).
                if (result == HangarPublicationOutcome.Complete) _changed(work.Generation);
                if (result != HangarPublicationOutcome.Retryable) return;
                // Retry only failures certified to have happened before sending.
                // Each attempt must read fresh consent and the same local revision.
                var seconds = Math.Min(60, 2 * (1 << Math.Min(attempt++, 5)));
                await _delay(TimeSpan.FromSeconds(seconds), token).ConfigureAwait(false);
            }
        }
        catch (OperationCanceledException) { }
        catch (Exception error) when (error is Account.AccountBridgeHostException or BridgeStaleGenerationException or IOException or HttpRequestException) { }
        finally
        {
            lock (_gate) { if (_pending == cancellation) _pending = null; }
            cancellation.Dispose();
        }
    }

    internal void Invalidate(long _ = 0)
    {
        lock (_gate)
        {
            _last = null;
            _pending?.Cancel();
            _pending = null;
        }
    }
    public void Dispose() { lock (_gate) { _disposed = true; Invalidate(); } }
}
