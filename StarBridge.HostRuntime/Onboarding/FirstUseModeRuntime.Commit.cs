namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private readonly object _onlineCommitGate = new();
    private FirstUseModeStore ModeStore => store;
    private volatile OnlineCommit? _onlineCommit;

    internal bool HasInstalledOnlineForCompletion
    {
        get
        {
            try
            {
                return InstalledIdentityBound;
            }
            catch { return false; }
        }
    }

    // The observer may leave; the original writer and physical recovery do not.
    // This is mode completion, not the separate device/onboarding receipt.
    internal Task<FirstUseModeObservation> CommitOnlineAsync(long revision, string operationId,
        AccountBridgeRuntime.FirstUseBusinessInstallation installation, CancellationToken token = default)
    {
        ArgumentNullException.ThrowIfNull(installation);
        token.ThrowIfCancellationRequested();
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        var existing = _onlineCommit;
        if (existing is not null)
        {
            if (existing.Pending.Revision != revision || existing.OperationId != operationId ||
                !ReferenceEquals(existing.Graph.Installation, installation))
                throw new LocalFirstUseException("firstUse.context_changed");
            return Observe(existing.Completion.Task, token);
        }
        if (!_writer.Wait(0)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        OnlineCommit commit;
        try
        {
            var pending = _accepted;
            var candidate = _preparedOnline;
            var confirmed = _confirmedIdentity;
            var origin = store.ReadOnlineOrigin();
            if (_closed || _changing || pending is not { Phase: "onlinePending" } || pending.Revision != revision ||
                pending.OperationId == operationId || store.Read() != pending || candidate is null || confirmed is null ||
                origin is not { CandidateStarted: true } || !origin.IsFor(pending) ||
                confirmed.Scope.Pending != pending || !confirmed.Scope.AccountOnly && CaptureLocalIdentity() != confirmed.Scope.Local ||
                _candidateCancel is not null || _candidateStart is not { IsCompletedSuccessfully: true } started ||
                !ReferenceEquals(started.Result, installation.Owner) ||
                !ReferenceEquals(confirmed.Scope.Candidate, installation.Owner))
                throw new LocalFirstUseException("firstUse.context_changed");
            var graph = installation.CaptureOnlineGraph(this, candidate);
            if (graph is null || !ReferenceEquals(graph.Root, account))
                throw new LocalFirstUseException("firstUse.mode_receipt_required");
            commit = new(this, pending, operationId, origin, graph, candidate,
                confirmed.Scope.AccountOnly ? null : confirmed.Scope.Local, Interlocked.Read(ref _epoch),
                bindingFacts: confirmed.Scope.AccountOnly ? null : confirmed.Facts);
            lock (_onlineCommitGate)
            {
                if (_closed || _onlineCommit is not null || !ReferenceEquals(_preparedOnline, candidate))
                    throw new LocalFirstUseException("firstUse.context_changed");
                _onlineCommit = commit; _changing = true;
            }
        }
        catch { _writer.Release(); throw; }
        _ = CompleteOnlineCommitAsync(commit);
        return Observe(commit.Completion.Task, token);
    }

    private static Task<FirstUseModeObservation> Observe(Task<FirstUseModeObservation> work, CancellationToken token) =>
        token.CanBeCanceled ? work.WaitAsync(token) : work;

    internal sealed class OnlineCommit
    {
        private readonly FirstUseModeRuntime _mode;
        private readonly AccountBridgeRuntime.PreparedFirstUseOnlineCandidate _candidate;
        private readonly LocalIdentityScope? _local;
        private readonly Account.FirstUseScmIdentityFacts? _bindingFacts;
        internal LocalIdentityScope? CompletionLocalScope => _local;
        internal readonly FirstUseModeChoice Pending;
        internal readonly string OperationId;
        internal readonly FirstUseOnlineOrigin Origin;
        internal readonly AccountBridgeRuntime.FirstUseBusinessInstallation.OnlineGraph Graph;
        internal readonly long Epoch;
        internal readonly bool IsCancellation;
        internal readonly TaskCompletionSource<FirstUseModeObservation> Completion = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource<bool> PreserveSession = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal volatile FirstUseModeChoice? Expected, Committed, ReturnedLocal;
        internal volatile bool LocalRestored;

        internal OnlineCommit(FirstUseModeRuntime mode, FirstUseModeChoice pending, string operationId,
            FirstUseOnlineOrigin origin, AccountBridgeRuntime.FirstUseBusinessInstallation.OnlineGraph graph,
            AccountBridgeRuntime.PreparedFirstUseOnlineCandidate candidate, LocalIdentityScope? local, long epoch,
            bool isCancellation = false, Account.FirstUseScmIdentityFacts? bindingFacts = null)
        { _mode = mode; Pending = pending; OperationId = operationId; Origin = origin; Graph = graph;
            _candidate = candidate; _local = local; _bindingFacts = bindingFacts; Epoch = epoch; IsCancellation = isCancellation; }

        internal bool IsCurrent()
        {
            try
            {
                return !_mode._closed && ReferenceEquals(_mode._onlineCommit, this) && _mode._accepted == Pending &&
                    Interlocked.Read(ref _mode._epoch) == Epoch && ReferenceEquals(_mode._preparedOnline, _candidate) &&
                    _mode._candidateCancel is null && _mode.ModeStore.Read() == Pending && _mode.ModeStore.ReadOnlineOrigin() == Origin &&
                    (_local is null || _mode.CaptureLocalIdentity() == _local) && Graph.IsLive;
            }
            catch { return false; }
        }

        internal void WriteAndAdopt(FirstUseModeChoice next, Action write)
        {
            // The store already holds its exclusive writer and verified the
            // source/identity just before this call. No clock, cancellation,
            // configuration or external callback is invoked under this gate.
            lock (_mode._onlineCommitGate)
            {
                if (_mode._closed || !ReferenceEquals(_mode._onlineCommit, this) ||
                    Interlocked.Read(ref _mode._epoch) != Epoch || !Graph.IsLive)
                    throw new LocalFirstUseException("firstUse.context_changed");
                Expected = next;
                write();
                Adopt(next);
            }
        }

        internal void Adopt(FirstUseModeChoice value)
        {
            Committed = value;
            _mode._offline = null; // The prior offline graph has physically exited before this installation.
            Volatile.Write(ref _mode._accepted, value);
            if (_local is not null && _bindingFacts is { } facts && Assess(facts, _local.Profile.Handle) == "match")
                _mode._installedBinding = new(Guid.NewGuid().ToString("N"), this, Graph.Installation.Owner,
                    value, _local, facts, DateTimeOffset.MaxValue);
            PreserveSession.TrySetResult(true);
        }
    }

    private async Task CompleteOnlineCommitAsync(OnlineCommit commit)
    {
        await Task.Yield(); // Publication of the original task precedes all IO/callbacks.
        FirstUseModeObservation result = new("recoveryRequired", commit.Pending.Revision);
        try
        {
            try { store.CompleteOnline(commit); }
            catch
            {
                // An interrupted/failed write is not proof it never happened.
                // Reconcile the exact proposed value, never merely phase=online.
                FirstUseModeChoice? observed = null;
                try { observed = store.Read(); } catch { }
                if (commit.Expected is { } expected && observed == expected)
                {
                    lock (_onlineCommitGate) commit.Adopt(expected);
                }
                else if (observed == commit.Pending)
                {
                    commit.PreserveSession.TrySetResult(commit.Origin.Local.Phase == "offline");
                    result = await RestoreAfterOnlineWriteFailureAsync(commit).ConfigureAwait(false);
                    return;
                }
                else
                {
                    // Unknown/external state: no overwriting it, no sign-out
                    // receipt. Drain the exact graph but preserve credentials.
                    commit.PreserveSession.TrySetResult(true);
                    _preparedOnline = null;
                    CancelCandidateLifetime();
                    await commit.Graph.Installation.Owner.ShutdownFirstUseOnlineCandidateAsync().ConfigureAwait(false);
                    result = new("recoveryRequired", _accepted?.Revision ?? commit.Pending.Revision);
                    return;
                }
            }
            result = new("online", commit.Committed!.Revision, "online");
        }
        catch
        {
            commit.PreserveSession.TrySetResult(commit.Committed is not null || commit.Origin.Local.Phase == "offline");
            result = new("recoveryRequired", _accepted?.Revision ?? commit.Pending.Revision);
        }
        finally { _changing = false; _writer.Release(); commit.Completion.TrySetResult(result); }
    }

    private async Task<FirstUseModeObservation> RestoreAfterOnlineWriteFailureAsync(OnlineCommit commit)
    {
        _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
        CancelCandidateLifetime();
        var retained = commit.Origin.Local.Phase == "offline";
        if (!await (retained ? commit.Graph.Installation.Owner.ShutdownFirstUseOnlineCandidateAsync() :
                commit.Graph.Installation.RetireAsync()).ConfigureAwait(false) || _closed ||
            store.Read() != commit.Pending || store.ReadOnlineOrigin() != commit.Origin)
            return new("recoveryRequired", _accepted?.Revision ?? commit.Pending.Revision);
        bool Current() => !_closed && ReferenceEquals(_onlineCommit, commit) &&
            Interlocked.Read(ref _epoch) == commit.Epoch && HasOriginalRecoveryExit(commit) &&
            store.ReadOnlineOrigin() == commit.Origin;
        var local = store.ReturnFromOnline(commit.Pending, Guid.NewGuid().ToString("N"), Current);
        commit.ReturnedLocal = local; _accepted = local;
        if (retained)
            account.ReturnOfflineAccount(commit.Origin.Local.Revision, local.Revision,
                () => Current() && store.Read() == local);
        if (!await account.RestoreFirstUseLocalSourcesAsync(commit.Graph.Sources, commit.Epoch).ConfigureAwait(false) ||
            !await commit.Graph.RestoreNativeAsync(commit.Epoch).ConfigureAwait(false) || !Current())
            return new("recoveryRequired", local.Revision);
        commit.LocalRestored = true;
        if (retained && _offline is { LocalRestored: true } prior && prior.Completed == commit.Origin.Local)
            prior.Completed = local;
        if (retained && _rootOffline is { LocalRestored: true } root && root.Completed == commit.Origin.Local && root.HasPhysicalExit)
            root.Completed = local;
        return new(local.Phase, local.Revision, "local", true);
    }

    private static bool HasOriginalRecoveryExit(OnlineCommit commit) => commit.Graph.Installation.HasCompletedCandidateExit ||
        commit.Origin.Local.Phase == "offline" && commit.Graph.Installation.Owner.HasPreservedFirstUseSessionExit &&
        commit.Graph.HasNativeExit;

    internal bool OwnsPreservedResumeInstallation(AccountBridgeRuntime.FirstUseBusinessInstallation installation, long epoch) =>
        _onlineCommit is { ReturnedLocal.Phase: "offline" } commit && commit.Epoch == epoch &&
        ReferenceEquals(commit.Graph.Installation, installation) && HasOriginalRecoveryExit(commit) && AllowsLocalSourceReconstruction(epoch);

    internal bool AllowsLocalSourceReconstruction(long epoch)
    {
        try
        {
            if (_closed || Interlocked.Read(ref _epoch) != epoch || _accepted is not { } local ||
                store.Read() != local) return false;
            if (local.Phase == "offline")
                return _rootOffline is { } root && root.Completed == local && root.Epoch == epoch && root.HasPhysicalExit ||
                    _onlineCommit is { } resumed && resumed.ReturnedLocal == local && resumed.Epoch == epoch && HasOriginalRecoveryExit(resumed) ||
                    _offline is { } offline && offline.Completed == local && offline.Epoch == epoch && offline.HasPhysicalExit ||
                    !_changing && LocalMode() == (true, epoch);
            if (local.Phase != "local") return false;
            var commit = _onlineCommit;
            return commit?.ReturnedLocal == local && commit.Epoch == epoch && commit.Graph.Installation.HasCompletedCandidateExit ||
                !_changing && LocalMode() == (true, epoch);
        }
        catch { return false; }
    }

    private long _controlHighWater;
    internal long ControlGeneration
    {
        get
        {
            if (_closed) return -1;
            // Transport freshness is not account authority. Rebuilding the
            // original device owner must not rewind a client's installed epoch.
            var observed = _onlineCommit is { Committed: not null } commit
                ? Math.Max(account.Generation, commit.Graph.Installation.Owner.Generation) : account.Generation;
            return ObserveNativeControlGeneration(observed);
        }
    }

    // Called only after an original activated installation attaches its real
    // Native slot, or from this mode's actual owner. This number grants no
    // account authority, mode completion, source reconstruction or admission.
    internal long ObserveNativeControlGeneration(long observed)
    {
        if (_closed) return -1;
        long prior;
        do { prior = Interlocked.Read(ref _controlHighWater); }
        while (observed > prior && Interlocked.CompareExchange(ref _controlHighWater, observed, prior) != prior);
        return _closed ? -1 : Math.Max(prior, observed);
    }
}
