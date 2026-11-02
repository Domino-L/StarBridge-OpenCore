namespace StarBridge.HostRuntime.Lifecycle;

// Owns exactly one physical timer. Deferred construction allocates no timer or
// callback. Retirement closes admission immediately, but acknowledges only after
// construction, original timer disposal and asynchronous callback exit all drain.
internal sealed class DeferredWorkTimer(TimeProvider clock, Func<Task> callback,
    TimeSpan dueTime, TimeSpan period) : ITimer
{
    private readonly object _gate = new();
    private readonly AsyncWorkRetirement _callbacks = new();
    private ITimer? _timer;
    private TaskCompletionSource? _construction;
    private Task? _retirement;
    private Exception? _failure;
    private bool _ready, _closed;

    internal bool Start()
    {
        TaskCompletionSource construction;
        lock (_gate)
        {
            if (_closed) return false;
            if (_construction is not null) return _construction.Task.IsCompleted && _ready;
            construction = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _construction = construction;
        }
        try
        {
            // Keep factories and callbacks outside the lifecycle lock: slow native
            // work cannot prevent retirement from closing admission.
            var timer = clock.CreateTimer(_ => _ = InvokeAsync(), null,
                Timeout.InfiniteTimeSpan, Timeout.InfiniteTimeSpan);
            lock (_gate)
            {
                _timer = timer;
                _ready = !_closed;
                if (_closed) return false;
            }
            if (!timer.Change(dueTime, period))
                throw new InvalidOperationException("Deferred timer could not start.");
            lock (_gate) return !_closed;
        }
        catch (ObjectDisposedException) when (IsClosed) { return false; }
        catch (Exception error)
        {
            Interlocked.CompareExchange(ref _failure, error, null);
            Dispose();
            throw;
        }
        finally { construction.TrySetResult(); }
    }

    private bool IsClosed { get { lock (_gate) return _closed; } }

    private async Task InvokeAsync()
    {
        AsyncWorkRetirement.Lease? admitted;
        lock (_gate)
        {
            if (_closed || !_ready) return;
            admitted = _callbacks.Enter(default);
        }
        using var work = admitted;
        if (work is null) return;
        try { await callback().ConfigureAwait(false); }
        catch (Exception error)
        {
            // Observe callback faults and preserve them in the retirement receipt.
            // An unexpected fault cannot silently leave a supposedly healthy loop.
            Interlocked.CompareExchange(ref _failure, error, null);
            Dispose();
        }
    }

    public bool Change(TimeSpan dueTime, TimeSpan period)
    {
        ITimer? timer;
        lock (_gate) { timer = _closed || !_ready ? null : _timer; }
        return timer?.Change(dueTime, period) ?? false;
    }

    internal Task RetireAsync()
    {
        TaskCompletionSource completion;
        Task construction;
        lock (_gate)
        {
            if (_retirement is not null) return _retirement;
            _closed = true;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _retirement = completion.Task;
            construction = _construction?.Task ?? Task.CompletedTask;
        }
        var callbacks = _callbacks.Close();
        _ = DrainAsync(construction, callbacks, completion);
        return completion.Task;
    }

    private async Task DrainAsync(Task construction, Task callbacks, TaskCompletionSource completion)
    {
        Exception? failure = null;
        await construction.ConfigureAwait(false);
        try
        {
            ITimer? timer;
            lock (_gate) timer = _timer;
            if (timer is not null) await timer.DisposeAsync().ConfigureAwait(false);
        }
        catch (Exception error) { failure = error; }
        await callbacks.ConfigureAwait(false);
        failure ??= Volatile.Read(ref _failure);
        if (failure is null) completion.TrySetResult();
        else completion.TrySetException(failure);
    }

    public ValueTask DisposeAsync() => new(RetireAsync());
    public void Dispose()
    {
        var retirement = RetireAsync();
        // Synchronous IDisposable does not acknowledge drain. Observe errors here;
        // asynchronous owners still receive the same original faulted receipt.
        _ = retirement.ContinueWith(task => _ = task.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously,
            TaskScheduler.Default);
    }
}
