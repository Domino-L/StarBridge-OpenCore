namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    // Display discriminator only. Exact encrypted origin remains the authority
    // for refresh, cancellation and installation; this bool grants none of them.
    internal bool RetainsOnlineReviewSession
    {
        get
        {
            var accepted = _accepted;
            return accepted is not null && store.Read() == accepted &&
                (accepted.Phase == "offline" || accepted.Phase == "onlinePending" &&
                    store.ReadOnlineOrigin() is { Local.Phase: "offline" } origin && origin.IsFor(accepted));
        }
    }

    internal FirstUseModeObservation RequestResume(long revision, string operationId)
    {
        if (revision < 0 || !LocalFirstUseValidation.Id(operationId))
            throw new LocalFirstUseException("firstUse.invalid_request");
        if (!_writer.Wait(0)) throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var offline = _accepted;
            if (_closed || offline is null || offline.Revision != revision || store.Read() != offline || !LocalMode().Active)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (offline.Phase == "onlinePending" && OnlineIntent(offline).RetainSession) return Current;
            if (offline.Phase != "offline") throw new LocalFirstUseException("firstUse.mode_receipt_required");
            var pending = store.BeginResume(offline, operationId, () => !_closed && LocalMode().Active);
            lock (_onlineCommitGate)
            {
                _accepted = pending;
                _issuedIdentity = null; _confirmedIdentity = null; _preparedOnline = null;
                _candidateLifetime?.Dispose();
                _candidateStart = null; _candidateCancel = null; _candidateLifetime = null;
                _onlineCommit = null;
            }
            return Current;
        }
        finally { _writer.Release(); }
    }

    // UI cancellation leaves construction owned by StageOnlineCandidateAsync.
    // Mode cancellation closes and drains its real lease before returning offline.
    internal async Task<string> ResumeOnlineCandidateAsync(long revision, CancellationToken token = default)
        => await RetainedSessionOperationAsync(revision, token, false).ConfigureAwait(false);

    internal Task<string> ReauthorizeOnlineCandidateAsync(long revision, CancellationToken token = default)
        => RetainedSessionOperationAsync(revision, token, true);

    private async Task<string> RetainedSessionOperationAsync(long revision, CancellationToken token, bool reauthorize)
    {
        var candidate = await StageOnlineCandidateAsync(revision, token).ConfigureAwait(false);
        if (!await _identityGate.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        try
        {
            var pending = _accepted;
            if (_closed || pending is null || pending.Revision != revision || _candidateCancel is not null ||
                candidate.FirstUseAuthenticationSealed || !candidate.RetainsFirstUseSession || !LocalMode().Active)
                throw new LocalFirstUseException("firstUse.context_changed");
            if (reauthorize && candidate.FirstUseSignInState(OnlineIntent(pending)) is not ("reauthorizationRequired" or "sessionExpired") &&
                !candidate.RequiresFirstUseGameIdentityReauthorization(OnlineIntent(pending)))
                throw new LocalFirstUseException("firstUse.reauthorization_required");
            _issuedIdentity = null; _confirmedIdentity = null;
            return reauthorize
                ? await candidate.ReauthorizeFirstUseCandidateAsync(OnlineIntent(pending), token).ConfigureAwait(false)
                : await candidate.ResumeFirstUseCandidateAsync(OnlineIntent(pending), token).ConfigureAwait(false);
        }
        finally { _identityGate.Release(); }
    }
}
