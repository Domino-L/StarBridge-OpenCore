namespace StarBridge.HostRuntime.Presence;

public sealed partial class GameLogRuntime
{
    private readonly object _samplingStopGate = new();
    private Task? _samplingStop;

    // Whole-owner retirement is distinct from RetireAccountAsync: that operation
    // deliberately keeps the sole timer for the local slot. Runtime replacement
    // must instead await this original timer, every admitted command/sample and
    // the attached local reader's actual exit. Cancellation of a caller's wait
    // cannot reopen any of these admissions or manufacture a drain receipt.
    internal Task RetireAsync()
    {
        TaskCompletionSource completion;
        Onboarding.LocalGameLogRuntime? local;
        lock (_samplingStopGate)
        {
            if (_samplingStop is not null) return _samplingStop;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _samplingStop = completion.Task;
            local = _localSlot;
        }
        var sampling = _samplingWork.Close();
        var account = _accountWork.Close();
        // AttachLocalSlot uses _sync; waiting there would make retirement block
        // synchronously behind slow IO. Closed admission prevents a new slot.
        var localExit = local?.RetireAsync() ?? Task.CompletedTask;
        _ = DrainAsync(sampling, account, localExit, completion);
        return completion.Task;
    }

    private async Task DrainAsync(Task sampling, Task account, Task local, TaskCompletionSource completion)
    {
        Exception? failure = null;
        try
        {
            // A timer may acknowledge Dispose before its queued callbacks exit.
            // DisposeAsync is part of the proof, not just the admission latch.
            if (_timer is not null) await _timer.DisposeAsync().ConfigureAwait(false);
        }
        catch (Exception error) { failure = error; }
        try
        {
            await Task.WhenAll(sampling, account, local).ConfigureAwait(false);
            ReleaseSampling();
        }
        catch (Exception error) { failure ??= error; }
        if (failure is null) completion.TrySetResult();
        else completion.TrySetException(failure);
    }

    private void ReleaseSampling()
    {
        lock (_sync)
        {
            if (_disposed) return;
            _disposed = true;
            _localSlot?.Suspend();
            Suspend();
        }
    }

    public ValueTask DisposeAsync() => new(RetireAsync());

    public void Dispose()
    {
        _ = RetireAsync();
        // Keep the existing synchronous lease-release behaviour. This is not
        // evidence that queued timer callbacks exited; handoff must await above.
        ReleaseSampling();
    }
}
