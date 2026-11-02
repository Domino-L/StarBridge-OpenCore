namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class EventSharingRuntime
{
    private readonly Lifecycle.AsyncWorkRetirement _work = new();
    private Task? _exit;

    internal Task RetireAsync()
    {
        TaskCompletionSource completion;
        lock (_timerLifecycle)
        {
            if (_exit is not null) return _exit;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _exit = completion.Task;
            _disposed = true;
            if (_liveEventsAttached) { _source.PendingChanged -= WakeLiveEvents; _liveEventsAttached = false; }
        }
        _ = DrainAsync(completion);
        return completion.Task;
    }
    private async Task DrainAsync(TaskCompletionSource completion)
    {
        Exception? failure = null;
        try
        {
            var work = _work.Close();
            var timer = _timer.RetireAsync();
            try { _lifetime.Cancel(); } catch (Exception error) { failure = error; }
            try { await Task.WhenAll(work, timer).ConfigureAwait(false); }
            catch (Exception error) { failure ??= error; }
            // Detach the source only after original manual/timer/live-journal
            // operations have really left, including cancellation-ignoring IO.
            await DisposeSourceAsync().ConfigureAwait(false);
            if (failure is not null) throw failure;
            completion.TrySetResult();
        }
        catch (Exception error) { completion.TrySetException(error); }
    }
    public void Dispose()
    {
        _ = RetireAsync().ContinueWith(task => _ = task.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }
}
