namespace StarBridge.HostRuntime.Lifecycle;

// One original async loop (or group of sibling loops). Reserve its completion
// before invoking user code, so retirement cannot miss a slow synchronous prefix.
// A dormant owner allocates no work; closing it never authorizes a later start.
internal sealed class DeferredAsyncDriver(Func<Task> run, Action stop)
{
    private readonly object _gate = new();
    private TaskCompletionSource? _started, _exit;
    private bool _closed;

    internal bool IsStarted { get { lock (_gate) return _started is not null; } }
    internal Task Completion { get { lock (_gate) return _exit?.Task ?? _started?.Task ?? Task.CompletedTask; } }

    internal bool Start()
    {
        TaskCompletionSource started;
        lock (_gate)
        {
            if (_closed) return false;
            if (_started is not null) return !_started.Task.IsFaulted;
            started = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _started = started;
        }
        _ = RunAsync(started);
        lock (_gate) return !_closed && !started.Task.IsFaulted;
    }

    private async Task RunAsync(TaskCompletionSource started)
    {
        Task? original = null;
        try
        {
            // A close before invocation needs no loop. If close races after this
            // check, stop() cancels the original owner's token and exit still
            // awaits this reserved receipt. Neither callback runs under _gate.
            bool closed;
            lock (_gate) closed = _closed;
            if (!closed)
            {
                original = run();
                await original.ConfigureAwait(false);
            }
            started.TrySetResult();
        }
        catch (Exception error)
        {
            lock (_gate) _closed = true;
            if (original?.Exception is { } failures) started.TrySetException(failures.InnerExceptions);
            else started.TrySetException(error);
        }
    }

    internal Task RetireAsync()
    {
        TaskCompletionSource exit;
        Task started;
        lock (_gate)
        {
            if (_exit is not null) return _exit.Task;
            _closed = true;
            exit = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _exit = exit;
            started = _started?.Task ?? Task.CompletedTask;
        }
        _ = DrainAsync(started, exit);
        return exit.Task;
    }

    private async Task DrainAsync(Task started, TaskCompletionSource exit)
    {
        var failures = new List<Exception>();
        try { stop(); }
        catch (Exception error) { failures.Add(error); }
        try { await started.ConfigureAwait(false); }
        catch (Exception error)
        {
            if (started.Exception is { } original) failures.AddRange(original.InnerExceptions);
            else failures.Add(error);
        }
        if (failures.Count == 0) exit.TrySetResult();
        else exit.TrySetException(failures);
    }
}
