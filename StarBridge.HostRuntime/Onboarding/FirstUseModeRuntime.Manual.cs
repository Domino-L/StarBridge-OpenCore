namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    internal bool CanEnterManualOffline(NativeAccountRuntimeBinding native)
    {
        if (_closed || _changing || Current.State != "online" || !native.OwnsRoot(account)) return false;
        if (_onlineCommit is { } committed)
            return committed.Committed == _accepted && committed.Graph.IsLive &&
                native.Generation == committed.Graph.Installation.Owner.Generation;
        return native.CaptureRootOnlineCallbacks(account, native.Generation) is not null;
    }

    internal Task<FirstUseModeObservation> ApplyManualOfflineAsync(long revision, string operationId,
        NativeAccountRuntimeBinding native, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (!CanEnterManualOffline(native)) throw new LocalFirstUseException("firstUse.context_changed");
        return _onlineCommit is not null
            ? ApplyOfflineAsync(revision, operationId, native.Generation, token)
            : ApplyRootOfflineAsync(revision, operationId, native.Generation, native, token);
    }
}
