namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // Only an actually live original installation can transfer cancellation
    // into this recovery. Auth-only cancellation still owns its old local lane.
    private Task<FirstUseModeObservation>? BeginInstalledCancellation(FirstUseModeChoice pending,
        string operationId, FirstUseOnlineOrigin origin)
    {
        var prepared = _preparedOnline;
        if (prepared is null || _candidateStart is not { IsCompletedSuccessfully: true } started ||
            _confirmedIdentity is not { } confirmed ||
            started.Result.CaptureInstalledFirstUseGraph(this, prepared) is not { } graph) return null;
        var cancellation = new OnlineCommit(this, pending, operationId, origin, graph, prepared,
            confirmed.Scope.Local, Interlocked.Read(ref _epoch), isCancellation: true);
        lock (_onlineCommitGate)
        {
            if (_closed || _onlineCommit is not null || _accepted != pending ||
                !ReferenceEquals(_preparedOnline, prepared))
                throw new LocalFirstUseException("firstUse.context_changed");
            _onlineCommit = cancellation;
            _changing = true;
            cancellation.PreserveSession.TrySetResult(origin.Local.Phase == "offline");
        }
        _ = CompleteInstalledCancellationAsync(cancellation);
        return cancellation.Completion.Task;
    }

    private async Task CompleteInstalledCancellationAsync(OnlineCommit cancellation)
    {
        await Task.Yield();
        FirstUseModeObservation result = new("recoveryRequired", cancellation.Pending.Revision);
        try { result = await RestoreAfterOnlineWriteFailureAsync(cancellation).ConfigureAwait(false); }
        catch { }
        finally
        {
            _changing = false;
            _writer.Release();
            cancellation.Completion.TrySetResult(result);
        }
    }
}
