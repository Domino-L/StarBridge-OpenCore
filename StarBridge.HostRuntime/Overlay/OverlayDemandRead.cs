namespace StarBridge.HostRuntime.Overlay;

/// <summary>Cancel a foreground read when its display/account scope disappears.
/// The caller still awaits transport completion, preserving one in-flight read
/// even if a handler does not honor cancellation promptly.</summary>
internal static class OverlayDemandRead
{
    internal static async Task<T> RunAsync<T>(Func<CancellationToken, Task<T>> read,
        Func<bool> isCurrent, CancellationToken token)
    {
        using var pending = CancellationTokenSource.CreateLinkedTokenSource(token);
        if (!isCurrent()) pending.Cancel();
        pending.Token.ThrowIfCancellationRequested();
        var monitor = MonitorAsync(isCurrent, pending);
        try
        {
            var result = await read(pending.Token).ConfigureAwait(false);
            pending.Token.ThrowIfCancellationRequested();
            if (!isCurrent()) throw new OperationCanceledException(pending.Token);
            return result;
        }
        finally
        {
            pending.Cancel();
            await monitor.ConfigureAwait(false);
        }
    }

    private static async Task MonitorAsync(Func<bool> isCurrent, CancellationTokenSource pending)
    {
        try
        {
            while (true)
            {
                await Task.Delay(100, pending.Token).ConfigureAwait(false);
                if (!isCurrent()) { pending.Cancel(); return; }
            }
        }
        catch (OperationCanceledException) when (pending.IsCancellationRequested) { }
    }
}
