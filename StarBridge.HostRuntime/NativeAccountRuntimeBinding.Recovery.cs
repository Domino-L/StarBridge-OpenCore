namespace StarBridge.HostRuntime;

public sealed partial class NativeAccountRuntimeBinding
{
    // An abandoned installation may already have closed the original Native
    // lane. Reconstruct that lane only after its actual exit and a confirmed
    // local source graph; the old slot and every lease stay permanently closed.
    // The preparation is an identity for our original transaction, not an
    // authorization to install its now invalid online owner.
    internal async Task<bool> RestoreLocalCallbacksAsync(
        AccountBridgeRuntime.PreparedFirstUseBusinessOwner abandoned, long localGeneration,
        CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(abandoned);
        token.ThrowIfCancellationRequested();
        Slot stopped;
        Task<PreparedNativeCallbacks?> drain;
        lock (_gate)
        {
            if (_disposed || !ReferenceEquals(_pending, abandoned) || _preparation is null ||
                !CanRestore(_current, localGeneration) || !_root.HasCurrentFirstUseLocalSources(localGeneration)) return false;
            stopped = _current;
            drain = _preparation;
        }
        // Preparation can legitimately return null when explicit cancellation
        // invalidated the online facts while Native callbacks were still exiting.
        // Its actual physical drain must finish successfully in either case.
        await drain.WaitAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        lock (_gate)
        {
            if (_disposed || token.IsCancellationRequested || !ReferenceEquals(_current, stopped) ||
                !ReferenceEquals(_pending, abandoned) || !ReferenceEquals(_preparation, drain) ||
                !stopped.Work.IsClosed || !drain.IsCompletedSuccessfully ||
                !CanRestore(stopped, localGeneration) ||
                !_root.HasCurrentFirstUseLocalSources(localGeneration)) return false;
            var restored = new Slot(_root);
            restored.Handler = envelope => Publish(restored, envelope);
            restored.Subscribe();
            _current = restored;
            _pending = null;
            _preparation = null;
            return true;
        }
    }

    private bool CanRestore(Slot slot, long localGeneration) => ReferenceEquals(slot.Owner, _root) ||
        slot is { Installation.HasCompletedCandidateExit: true, Receipt.HasExitedSuccessfully: true } ||
        slot is { Installation: { } installation, Receipt.HasExitedSuccessfully: true } &&
        (_root.FirstUseMode?.OwnsPreservedOfflineInstallation(installation, localGeneration) == true ||
         _root.FirstUseMode?.OwnsPreservedResumeInstallation(installation, localGeneration) == true);
}
