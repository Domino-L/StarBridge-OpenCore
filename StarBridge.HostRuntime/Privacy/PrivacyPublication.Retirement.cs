namespace StarBridge.HostRuntime.Privacy;

internal sealed partial class PrivacyPublication
{
    private readonly Lifecycle.AsyncWorkRetirement _work = new();
    private readonly object _exitGate = new();
    private Task? _exit;

    internal Task RetireAsync()
    {
        TaskCompletionSource completion;
        lock (_exitGate)
        {
            if (_exit is not null) return _exit;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _exit = completion.Task;
            _disposed = true;
        }
        _ = DrainAsync(completion);
        return completion.Task;
    }
    private async Task DrainAsync(TaskCompletionSource completion)
    {
        try
        {
            var work = _work.Close();
            var timer = _timer.RetireAsync();
            Exception? cancellationFailure = null;
            try { _lifetime.Cancel(); } catch (Exception error) { cancellationFailure = error; }
            await Task.WhenAll(work, timer).ConfigureAwait(false);
            _active = null; _recovery = null; _visibilitySuspended = null;
            if (cancellationFailure is not null) throw cancellationFailure;
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
