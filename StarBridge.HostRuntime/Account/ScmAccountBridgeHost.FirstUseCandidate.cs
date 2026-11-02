namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private Lifecycle.AccountGenerationSequence? _firstUseGenerations;
    internal void BindFirstUseGenerations(Lifecycle.AccountGenerationSequence generations)
    {
        ArgumentNullException.ThrowIfNull(generations);
        // Composition calls only before handing out this fresh auth dispatcher.
        // Never relabel a live authorization or attach a new sequence after login.
        lock (_realtimeGate)
        {
            if (!IsFirstUseAuthenticationCandidate || _freshSignInOnly && !_freshSignInPending || _session is not null ||
                _legacySession is not null || _firstUseGenerations is not null || _localModeSessionLoopsStopped)
                throw new InvalidOperationException("Account generation source cannot be rebound.");
            var next = generations.Next(Generation);
            _firstUseGenerations = generations;
            Interlocked.Exchange(ref _generation, next);
        }
    }

    private long ReserveSessionGeneration() => _firstUseGenerations?.Next(Generation) ?? checked(Generation + 1);

    internal bool IsFreshFirstUseCandidate => !_disposed && _freshSignInOnly && _businessStartupDeferred;
    internal bool IsRetainedFirstUseCandidate => !_disposed && _retainedFirstUseOnly && _businessStartupDeferred;
    internal bool IsFirstUseAuthenticationCandidate => IsFreshFirstUseCandidate || IsRetainedFirstUseCandidate;

    // Caller first seals and drains the candidate dispatcher, including an OAuth
    // transport that ignores cancellation. We then use the real mutation lane
    // and OAuth owner, not the nullable public account projection, to clean up a
    // credential committed just before host session publication failed.
    internal async Task<bool> RetireFreshFirstUseSessionAsync()
    {
        await _mutationGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try
        {
            if (!IsFreshFirstUseCandidate || _legacySession is not null ||
                _firstUseBusinessAdmission is { HasExited: false }) return false;
            if (!await _oauth.RetireFreshFirstUseSessionAsync().ConfigureAwait(false)) return false;
            _freshSignInPending = false;
            PublishSession(null, reauthorizationRequired: false);
            return IsKnownSignedOutForLocalMode;
        }
        finally { _mutationGate.Release(); }
    }
}
