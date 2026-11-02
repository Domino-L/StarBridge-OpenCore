namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private volatile Task<AccountBridgeRuntime>? _candidateStart;
    private volatile Task<bool>? _candidateCancel;
    private volatile CancellationTokenSource? _candidateLifetime;
    private readonly Lifecycle.AccountGenerationSequence _onlineGenerations = new();
    internal bool HasAuthenticatedOnlineCandidate
    {
        get
        {
            try
            {
                var start = _candidateStart;
                return !_closed && _candidateCancel is null && _accepted is { Phase: "onlinePending" } pending &&
                    store.Read() == pending && start is { IsCompletedSuccessfully: true } &&
                    start.Result.FirstUseSignInState(OnlineIntent(pending)) == "identityCheckRequired";
            }
            catch { return false; }
        }
    }
    private FirstUseOnlineCandidateIntent OnlineIntent(FirstUseModeChoice pending) => new(store, pending, _onlineGenerations,
        store.ReadOnlineOrigin() is { Local.Phase: "offline" } origin && origin.IsFor(pending));

    private void CancelCandidateLifetime()
    {
        try { _candidateLifetime?.Cancel(); }
        catch (ObjectDisposedException) { }
        catch (AggregateException) { /* Actual factory and admission exits still own the receipt. */ }
    }

    // Native-only staging. Construction cannot authenticate before returning its
    // auth-only dispatcher; all callers use this owner rather than a free-floating
    // factory. A cancelled UI wait does not detach or dispose unfinished work.
    internal async Task<AccountBridgeRuntime> StageOnlineCandidateAsync(long revision, CancellationToken token = default)
    {
        Task<AccountBridgeRuntime> work;
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var pending = _accepted;
            if (_closed || pending is null || pending.Phase != "onlinePending" || pending.Revision != revision ||
                store.Read() != pending || !LocalMode().Active || _candidateCancel is not null)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (_candidateStart is null)
            {
                store.MarkOnlineCandidateStarted(pending, () => !_closed && LocalMode().Active);
                _onlineGenerations.Observe(account.Generation);
                var intent = OnlineIntent(pending);
                var lifetime = new CancellationTokenSource();
                var completion = new TaskCompletionSource<AccountBridgeRuntime>(TaskCreationOptions.RunContinuationsAsynchronously);
                lock (_onlineCommitGate)
                {
                    // Close either sees this reserved original construction or
                    // wins before it: no late factory can escape total exit.
                    if (_closed)
                    {
                        lifetime.Dispose();
                        throw new LocalFirstUseException("firstUse.context_changed");
                    }
                    _candidateLifetime = lifetime;
                    _candidateStart = completion.Task;
                }
                _ = DeliverOnlineCandidateAsync(intent, lifetime.Token, completion);
            }
            work = _candidateStart;
        }
        finally { _writer.Release(); }
        var candidate = await work.WaitAsync(token).ConfigureAwait(false);
        if (_closed || _candidateCancel is not null || !candidate.IsFirstUseOnlineCandidateFor(OnlineIntent(_accepted!)))
            throw new LocalFirstUseException("firstUse.context_changed");
        return candidate;
    }

    private async Task<AccountBridgeRuntime> BuildCandidateAsync(FirstUseOnlineCandidateIntent intent, CancellationToken token)
    {
        await Task.Yield(); // Do not execute factory code in the mode writer lane.
        return await (candidateFactory ?? account.ConstructFirstUseOnlineCandidateAsync)(intent, token).ConfigureAwait(false);
    }

    private async Task DeliverOnlineCandidateAsync(FirstUseOnlineCandidateIntent intent, CancellationToken token,
        TaskCompletionSource<AccountBridgeRuntime> completion)
    {
        try { completion.TrySetResult(await BuildCandidateAsync(intent, token).ConfigureAwait(false)); }
        catch (OperationCanceledException error) { completion.TrySetCanceled(error.CancellationToken); }
        catch (Exception error) { completion.TrySetException(error); }
    }

    // Actual login shares the identity review lane. A failed/replaced login
    // cannot resurrect an earlier confirmation, and no candidate events or
    // account payloads are transferred to the installed runtime by this call.
    internal async Task<bool> AuthenticateOnlineCandidateAsync(long revision, CancellationToken token)
    {
        var candidate = await StageOnlineCandidateAsync(revision, token).ConfigureAwait(false);
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            if (candidate.FirstUseAuthenticationSealed) return false;
            if (candidate.RetainsFirstUseSession) throw new LocalFirstUseException("firstUse.resume_required");
            _issuedIdentity = null; _confirmedIdentity = null;
            if (_closed || _candidateCancel is not null || _accepted is not { } pending ||
                pending.Revision != revision || !LocalMode().Active ||
                !candidate.IsFirstUseOnlineCandidateFor(OnlineIntent(pending)))
                throw new LocalFirstUseException("firstUse.context_changed");
            var result = await candidate.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("account.login",
                Guid.NewGuid().ToString("N"), candidate.Generation, new { schemaVersion = 1 }), token).ConfigureAwait(false);
            return result.Response.Status == StarBridge.NativeBridge.BridgeResponseStatuses.Ok && result.Response.Error is null &&
                !_closed && _candidateCancel is null && LocalMode().Active &&
                candidate.IsFirstUseOnlineCandidateFor(OnlineIntent(pending));
        }
        finally { _identityGate.Release(); }
    }

    internal async Task<FirstUseModeObservation> CancelOnlineAsync(long revision, string operationId,
        CancellationToken token = default)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (_onlineCommit is { IsCancellation: true } cancelling)
        {
            if (cancelling.Pending.Revision != revision || cancelling.OperationId != operationId)
                throw new LocalFirstUseException("firstUse.context_changed");
            return await Observe(cancelling.Completion.Task, token).ConfigureAwait(false);
        }
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        var releaseWriter = true;
        try
        {
            var pending = _accepted;
            if (_closed || pending is null || pending.Phase != "onlinePending" || pending.Revision != revision ||
                pending.OperationId == operationId || store.Read() != pending || !LocalMode().Active)
                throw new LocalFirstUseException("firstUse.context_changed");
            var origin = store.ReadOnlineOrigin();
            if (origin?.IsFor(pending) != true) throw new LocalFirstUseException("firstUse.mode_receipt_required");
            if (BeginInstalledCancellation(pending, operationId, origin) is { } installed)
            {
                releaseWriter = false;
                return await Observe(installed, token).ConfigureAwait(false);
            }
            _issuedIdentity = null; _confirmedIdentity = null;
            _preparedOnline = null;
            if (_candidateStart is null && origin.CandidateStarted)
                return new("recoveryRequired", pending.Revision, "local", true);
            if (_candidateStart is { } candidate)
            {
                CancelCandidateLifetime();
                _candidateCancel ??= RetireCandidateAsync(candidate);
                if (!await _candidateCancel.WaitAsync(token).ConfigureAwait(false))
                    return new("recoveryRequired", pending.Revision, "local", true);
            }
            // The same retired local graph stays installed; no profile, setting,
            // listening generation or local statistic is reset by this return.
            _accepted = store.ReturnFromOnline(pending, operationId, () => !_closed && LocalMode().Active &&
                store.ReadOnlineOrigin() == origin && (_candidateStart is null && !origin.CandidateStarted ||
                    _candidateCancel is { IsCompletedSuccessfully: true, Result: true }));
            if (_accepted.Phase == "offline" && _offline is { LocalRestored: true } prior && prior.Completed == origin.Local)
                prior.Completed = _accepted;
            if (_accepted.Phase == "offline" && _rootOffline is { LocalRestored: true } root && root.Completed == origin.Local)
                root.Completed = _accepted;
            if (_accepted.Phase == "offline" && origin.Local.Phase == "offline")
                account.ReturnOfflineAccount(origin.Local.Revision, _accepted.Revision,
                    () => !_closed && store.Read() == _accepted && LocalMode().Active);
            return Current;
        }
        finally { if (releaseWriter) _writer.Release(); }
    }

    private static async Task<bool> RetireCandidateAsync(Task<AccountBridgeRuntime> started)
    {
        AccountBridgeRuntime candidate;
        try { candidate = await started.ConfigureAwait(false); }
        // The factory is construction-only: no caller received its dispatcher
        // when construction failed, so no auth operation could be admitted.
        catch { return true; }
        try { return await (candidate.RetainsFirstUseSession ? candidate.ShutdownFirstUseOnlineCandidateAsync() :
            candidate.RetireFirstUseOnlineCandidateAsync()).ConfigureAwait(false); }
        catch { return false; }
    }
}
