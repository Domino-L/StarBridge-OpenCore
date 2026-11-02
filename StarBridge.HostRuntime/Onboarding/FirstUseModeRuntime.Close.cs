namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private Task<bool>? CloseOnlineOwner()
    {
        TaskCompletionSource<bool>? completion = null;
        Task<AccountBridgeRuntime>? candidate;
        OnlineCommit? commit;
        OfflineTransition? offline;
        lock (_onlineCommitGate)
        {
            if (_closed) return _candidateCancel;
            _closed = true; Interlocked.Increment(ref _epoch);
            _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
            candidate = _candidateStart; commit = _onlineCommit; offline = _offline;
            if (candidate is null && _rootOffline is { } rootOffline && _candidateCancel is null)
                _candidateCancel = CloseRootOfflineAsync(rootOffline);
            if (candidate is not null && _candidateCancel is null)
            {
                completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
                _candidateCancel = completion.Task;
            }
        }
        // Reentrant cancellation sees the reserved original exit, never a gate
        // held by its caller. A write with unknown outcome decides preservation
        // before any close can select strict sign-out.
        CancelCandidateLifetime();
        if (completion is not null) _ = CompleteCloseAsync(candidate!, commit, offline, completion);
        return _candidateCancel;
    }

    private static async Task<bool> CloseRootOfflineAsync(RootOfflineTransition transition)
    {
        await transition.Completion.Task.ConfigureAwait(false);
        return transition.HasPhysicalExit;
    }

    private static async Task CompleteCloseAsync(Task<AccountBridgeRuntime> candidate, OnlineCommit? commit, OfflineTransition? offline,
        TaskCompletionSource<bool> completion)
    {
        try
        {
            var preserve = commit is not null && await commit.PreserveSession.Task.ConfigureAwait(false);
            bool exited;
            try
            {
                exited = !preserve ? await RetireCandidateAsync(candidate).ConfigureAwait(false) :
                    await (await candidate.ConfigureAwait(false)).ShutdownFirstUseOnlineCandidateAsync().ConfigureAwait(false);
            }
            finally
            {
                // Recovery never awaits this Close task; it owns the candidate's
                // original physical task directly. Wait even when candidate exit
                // faults: a partly rebuilt local sampler still belongs to commit.
                if (commit is not null) await commit.Completion.Task.ConfigureAwait(false);
                if (offline is not null) await offline.Completion.Task.ConfigureAwait(false);
            }
            completion.TrySetResult(exited);
        }
        catch (Exception error) { completion.TrySetException(error); }
    }
}
