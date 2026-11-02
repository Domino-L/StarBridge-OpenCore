namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private volatile bool _localModeSessionLoopsStopped;

    internal Auth.ScmCredentialRetirementStamp? ReadRetainedCredentialVersion(
        StarBridge.NativeBridge.BridgeAccountContext owner, long generation) =>
        !_disposed && Generation == generation && CurrentContext == owner &&
        !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
        _legacySession is null && _session is { } session
            ? _oauth.ReadRetainedCredentialVersion(session) : null;

    internal Task<bool> LogoutForLocalModeAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        long expectedGeneration, CancellationToken token) => LogoutCoreAsync(context, expectedGeneration, token);

    internal bool StopSessionLoopsForLocalMode(long generation)
    {
        lock (_realtimeGate)
        {
            if (_disposed || generation != Generation) return false;
            _localModeSessionLoopsStopped = true;
            StopAccountRealtime();
            StopRoomMembershipKeepalive();
            StopParticipantLoop();
            return true;
        }
    }

    // Preserve authorization while permanently sealing every loop on this
    // original host. A generation race cannot leave a newer loop alive, but
    // neither can this physical exit acknowledge the older identity as current.
    internal async Task RetireSessionLoopsPreservingSessionAsync()
    {
        lock (_realtimeGate) _localModeSessionLoopsStopped = true;
        var failures = new List<Exception>();
        foreach (var stop in new Action[] { StopAccountRealtime, StopRoomMembershipKeepalive, StopParticipantLoop })
            try { stop(); } catch (Exception error) { failures.Add(error); }
        try { await SessionLoopRetirement().ConfigureAwait(false); }
        catch (Exception error) { failures.Add(error); }
        if (failures.Count != 0) throw new AggregateException(failures);
    }
    // A null projection alone cannot prove that stored authorization was removed:
    // restore may not have run, or a credential may be temporarily unreadable.
    internal bool IsKnownSignedOutForLocalMode => !_disposed && !_retainedFirstUseOnly && _restoreAttempted && !_freshSignInPending &&
        _session is null && _legacySession is null && !_credentialTemporarilyUnavailable &&
        !_legacyRestoreUnavailable && !_reauthorizationRequired;

    internal async Task<bool> WaitForOriginalSessionLoopsAsync(StarBridge.NativeBridge.BridgeAccountContext context,
        long generation, CancellationToken token)
    {
        bool Current() => !_disposed && _localModeSessionLoopsStopped && Generation == generation && CurrentContext == context;
        if (!Current()) return false;
        await SessionLoopRetirement().WaitAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        return Current();
    }

    internal async Task<Auth.ScmCredentialRetirementStamp?> PrepareLocalCredentialRetirementAsync(
        StarBridge.NativeBridge.BridgeAccountContext context, long generation, CancellationToken token)
    {
        await _mutationGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (_disposed || !_localModeSessionLoopsStopped || Generation != generation || CurrentContext != context ||
                _legacySession is not null || _session is not { } session) return null;
            return await _oauth.PrepareCredentialRetirementAsync(session, token).ConfigureAwait(false);
        }
        finally { _mutationGate.Release(); }
    }

    internal bool IsLocalCredentialRetirementCurrent(StarBridge.NativeBridge.BridgeAccountContext context,
        long generation, Auth.ScmCredentialRetirementStamp expected) => !_disposed && _localModeSessionLoopsStopped &&
        Generation == generation && CurrentContext == context && _legacySession is null && _session is { } session &&
        _oauth.IsPreparedCredentialRetirementCurrent(session, expected);

    private Task SessionLoopRetirement()
    {
        Task realtime, rooms, participant;
        lock (_realtimeGate) realtime = _accountRealtimeStopCompletion;
        lock (_roomKeepaliveGate) rooms = Task.WhenAll(_roomKeepaliveStopCompletion, RoomKeepaliveCompletion);
        lock (_participantLoopGate) participant = Task.WhenAll(_participantLoopStopCompletion, ParticipantLoopCompletion);
        return Task.WhenAll(realtime, rooms, participant);
    }

    // This receipt covers only the three SCM-owned session loops. The caller must
    // separately drain requests, publication and other installed business owners.
    internal async Task<bool> WaitForSignedOutSessionLoopsAsync(long generation, CancellationToken token)
    {
        if (!IsKnownSignedOutForLocalMode || generation != Generation) return false;
        await SessionLoopRetirement().WaitAsync(token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        return IsKnownSignedOutForLocalMode && generation == Generation;
    }
}
