namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    private Task? _disposal;
    public ValueTask DisposeAsync() => new(BeginDisposal());
    public void Dispose()
    {
        var exit = BeginDisposal();
        _ = exit.ContinueWith(task => _ = task.Exception, CancellationToken.None,
            TaskContinuationOptions.OnlyOnFaulted | TaskContinuationOptions.ExecuteSynchronously, TaskScheduler.Default);
    }

    private Task BeginDisposal()
    {
        Slot slot;
        TaskCompletionSource completion;
        lock (_gate)
        {
            if (_disposal is not null) return _disposal;
            _disposed = true;
            slot = _current;
            completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
            _disposal = completion.Task;
        }
        // Reserve first, but run cancellation outside the binding lock. Never
        // dispose the candidate before root mode has owned its full retirement.
        _ = CompleteDisposalAsync(slot, completion);
        return completion.Task;
    }

    private async Task CompleteDisposalAsync(Slot slot, TaskCompletionSource completion)
    {
        var deviceNetworkExit = _root.DeviceNetwork.RetireAsync();
        Exception? failure = null;
        Task? installation;
        lock (_gate) installation = _onlineInstallation?.Completion.Task;
        try
        {
            var callbacks = slot.Receipt?.RetireAsync() ?? CloseSlot(slot);
            var candidateExit = _root.FirstUseMode?.CloseOwnedOnlineAsync() ?? slot.Installation?.RetireAsync();
            if (candidateExit is not null)
            {
                await Task.WhenAll(callbacks, candidateExit).ConfigureAwait(false);
                if (!await candidateExit.ConfigureAwait(false))
                    throw new InvalidOperationException("The installed first-use candidate did not confirm complete exit.");
            }
            else await callbacks.ConfigureAwait(false);
        }
        catch (Exception error) { failure = error; }
        // A composition callback may still own device consumers even after
        // candidate cancellation. Its original attempt must leave before any
        // synchronous account/device disposal or final source capture below.
        if (installation is not null)
            try { await installation.ConfigureAwait(false); }
            catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        // Ordinary startup has no first-use candidate receipt. Its original
        // background consumers still borrow Native device sinks, so callback
        // exit alone cannot acknowledge shutdown. Drain both original owners
        // before synchronous disposal, even when an earlier exit failed.
        static Task Stop(AccountBridgeRuntime owner)
        { try { return owner.RetireNativeBusinessConsumersAsync(); } catch (Exception error) { return Task.FromException(error); } }
        try
        {
            var rootExit = Stop(_root);
            await (ReferenceEquals(slot.Owner, _root)
                ? rootExit : Task.WhenAll(rootExit, Stop(slot.Owner))).ConfigureAwait(false);
        }
        catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        // The mode-owned recovery above has actually exited. Only now can we
        // capture the final local source batch (possibly rebuilt during failure)
        // rather than reusing an older, already completed source-exit receipt.
        try { await _root.RetireFirstUseLocalSourcesAsync().ConfigureAwait(false); }
        catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        try { await Task.WhenAll(deviceNetworkExit, _root.RetireFirstUseControlsAsync()).ConfigureAwait(false); }
        catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        // Actual callback/candidate tasks above have exited, including a failed
        // retirement. A failed receipt stays failed; no credential clear is
        // substituted by synchronous disposal and root ownership is retained.
        try { slot.Owner.Dispose(); }
        catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        finally
        {
            if (!ReferenceEquals(slot.Owner, _root))
                try { _root.Dispose(); }
                catch (Exception error) { failure = failure is null ? error : new AggregateException(failure, error); }
        }
        if (failure is null) completion.TrySetResult();
        else completion.TrySetException(failure);
    }
}
