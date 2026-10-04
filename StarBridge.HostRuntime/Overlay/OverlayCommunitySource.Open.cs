namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    private TaskCompletionSource _readProgress = NewReadProgress();

    // An open request joins the source's existing retry driver. It must not
    // mistake a completed-but-transiently-failed read for completed preparation,
    // or start a second retry loop alongside the normal refresh schedule.
    internal async Task PrepareForDisplayAsync(CancellationToken token)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _stop.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(20));
        (StarBridge.NativeBridge.BridgeAccountContext? Owner, long Generation) scope;
        long revision;
        lock (_sync) { CheckScope(); scope = _scope; revision = _revision; }
        await RefreshAsync(deadline.Token, waitForGate: true).ConfigureAwait(false);
        while (true)
        {
            Task progress;
            lock (_sync)
            {
                // Authoritative empty/rejected results, scope changes and
                // cancellation are not transient transport failures. Never
                // revive an old source or renew its authorization here.
                if (!Current(scope, revision) || Read() is not null ||
                    _transientFailures == 0 || _driver is null) return;
                progress = _readProgress.Task;
            }
            await progress.WaitAsync(deadline.Token).ConfigureAwait(false);
        }
    }

    private static TaskCompletionSource NewReadProgress() =>
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    private void SignalReadProgress()
    {
        lock (_sync)
        {
            var previous = _readProgress;
            _readProgress = NewReadProgress();
            previous.TrySetResult();
        }
    }
}
