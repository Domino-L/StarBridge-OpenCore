namespace StarBridge.HostRuntime.Onboarding;

internal sealed partial class FirstUseModeRuntime
{
    private volatile AccountBridgeRuntime.PreparedFirstUseOnlineCandidate? _preparedOnline;
    private volatile bool _handoffPreparing;

    internal bool OwnsBusinessPreparation(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared) =>
        !_closed && _preparedOnline is { IsCurrent: true } candidate && prepared.IsFor(candidate) && prepared.IsCurrent;

    // Once the original graph is live, temporary review expiry is no longer
    // its lifetime. Retain the exact transaction and durable pending intent.
    internal bool OwnsActivatedBusinessPreparation(AccountBridgeRuntime.PreparedFirstUseBusinessOwner prepared)
    {
        if (_closed || _candidateCancel is not null || _preparedOnline is not { } candidate ||
            !prepared.IsFor(candidate) || _accepted is not { } pending) return false;
        // Called with Native binding gate held: never acquire the commit gate
        // or writer here. Read the original immutable provenance instead.
        try
        {
            var commit = _onlineCommit;
            if (commit is { IsCancellation: true }) return false;
            if (pending.Phase == "online" && commit?.Committed == pending)
                return ReferenceEquals(commit.Graph.Prepared, prepared) && commit.Graph.IsLive &&
                    store.Read() == pending && !_closed && ReferenceEquals(_onlineCommit, commit);
            return pending.Phase == "onlinePending" && store.Read() == pending && store.ReadOnlineOrigin()?.IsFor(pending) == true;
        }
        catch { return false; }
    }

    internal async Task<AccountBridgeRuntime.PreparedFirstUseBusinessOwner?> PrepareOnlineBusinessOwnerAsync(
        long revision, CancellationToken token = default)
    {
        var prepared = await PrepareOnlineHandoffAsync(revision, token).ConfigureAwait(false);
        if (prepared is null) return null;
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        var identityEntered = false;
        Task<AccountBridgeRuntime.PreparedFirstUseBusinessOwner?> read;
        try
        {
            identityEntered = await _identityGate.WaitAsync(0, token).ConfigureAwait(false);
            if (!identityEntered) throw new LocalFirstUseException("firstUse.operation_in_progress");
            if (_accepted?.Revision != revision || !ReferenceEquals(_preparedOnline, prepared) || !prepared.IsCurrent)
                return null;
            read = prepared.PrepareBusinessOwnerAsync(token);
        }
        finally
        {
            if (identityEntered) _identityGate.Release();
            _writer.Release();
        }
        // The original candidate owns the physical read lease. Don't hold the
        // mode writer across its IO: explicit Cancel must close that admission
        // immediately and then await real exit, without requiring UI wait-abandon.
        var result = await read.ConfigureAwait(false);
        return ReferenceEquals(_preparedOnline, prepared) && prepared.IsCurrent && result?.IsCurrent == true
            ? result : null;
    }

    // Serialize with actual mode writes and reviews, not an independently issued
    // approval boolean. Keep the local source/epoch and durable pending intent
    // until the later installed runtime/consumer handoff is actually committed.
    internal async Task<AccountBridgeRuntime.PreparedFirstUseOnlineCandidate?> PrepareOnlineHandoffAsync(
        long revision, CancellationToken token = default)
    {
        if (revision < 0) throw new LocalFirstUseException("firstUse.invalid_request");
        if (!await _writer.WaitAsync(0, token).ConfigureAwait(false))
            throw new LocalFirstUseException("firstUse.operation_in_progress");
        var identityEntered = false;
        IdentityReview confirmed;
        Task<AccountBridgeRuntime.PreparedFirstUseOnlineCandidate?> preparation;
        try
        {
            if (_handoffPreparing) throw new LocalFirstUseException("firstUse.operation_in_progress");
            identityEntered = await _identityGate.WaitAsync(0, token).ConfigureAwait(false);
            if (!identityEntered) throw new LocalFirstUseException("firstUse.operation_in_progress");
            if (_accepted?.Revision != revision) return null;
            if (_preparedOnline is { IsCurrent: true } prepared) return prepared;
            if (_confirmedIdentity is not { } review || review.Scope.Pending.Revision != revision || !IsReviewCurrent(review))
                return null;
            confirmed = review;
            confirmed.Scope.Candidate.RequireFirstUseGameIdentity(() => InstalledGameIdentityAllowed);
            _preparedOnline = null;
            bool Current() => ReferenceEquals(_confirmedIdentity, confirmed) && WithinReview(confirmed) &&
                IsIdentityScopeCurrent(confirmed.Scope);
            preparation = confirmed.Scope.Candidate.PrepareFirstUseOnlineHandoffAsync(
                OnlineIntent(confirmed.Scope.Pending), confirmed.Facts, Current, token);
            _handoffPreparing = true;
        }
        finally
        {
            if (identityEntered) _identityGate.Release();
            _writer.Release();
        }
        // The candidate owns its original drain. Do not retain either mode lane
        // while waiting: explicit Cancel must invalidate confirmation immediately
        // and then await that same physical request exit before credential clear.
        try
        {
            var result = await preparation.ConfigureAwait(false);
            await _writer.WaitAsync(token).ConfigureAwait(false);
            try
            {
                if (result is null || !ReferenceEquals(_confirmedIdentity, confirmed) ||
                    !WithinReview(confirmed) || !IsIdentityScopeCurrent(confirmed.Scope) || !result.IsCurrent) return null;
                _preparedOnline = result;
                return result;
            }
            finally { _writer.Release(); }
        }
        finally { _handoffPreparing = false; }
    }
}
