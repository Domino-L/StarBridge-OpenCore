using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private bool _firstUseResumeActive;
    private bool _firstUseMutationGateDisposeRequested;

    internal bool FirstUseGameIdentityReauthorizationRequired =>
        Volatile.Read(ref _session)?.RequiresFirstUseGameIdentityReauthorization == true &&
        FirstUseSignInState == "identityCheckRequired";

    private void DisposeMutationGateAfterFirstUseResume()
    {
        lock (_loginGate)
        {
            _firstUseMutationGateDisposeRequested = true;
            if (!_firstUseResumeActive) _mutationGate.Dispose();
        }
    }

    // The constructor prevents ordinary getCurrent/legacy restore from selecting
    // any credential. Only the explicit Native mode owner calls this operation.
    internal async Task<FirstUseSessionResume> ResumeFirstUseSessionAsync(Func<bool> current,
        CancellationToken token)
        => await FirstUseSessionOperationAsync(current, token, reauthorize: false).ConfigureAwait(false);

    internal Task<FirstUseSessionResume> ReauthorizeFirstUseSessionAsync(Func<bool> current, CancellationToken token)
        => FirstUseSessionOperationAsync(current, token, reauthorize: true);

    private async Task<FirstUseSessionResume> FirstUseSessionOperationAsync(Func<bool> current,
        CancellationToken token, bool reauthorize)
    {
        ArgumentNullException.ThrowIfNull(current);
        lock (_loginGate)
        {
            if (_disposed) return new("contextChanged");
            if (_firstUseResumeActive) return new("operationInProgress");
            _firstUseResumeActive = true;
        }
        var acquired = false;
        try
        {
            acquired = await _mutationGate.WaitAsync(0, token).ConfigureAwait(false);
            if (!acquired) return new("operationInProgress");
            var generation = Generation;
            var originalSession = _session;
            bool Current() => !_disposed && _retainedFirstUseOnly && IsBusinessStartupDeferred &&
                !_localModeSessionLoopsStopped && ReferenceEquals(_session, originalSession) && _legacySession is null &&
                generation == Generation && current();
            if (!Current() || !reauthorize && originalSession is not null ||
                reauthorize && !_reauthorizationRequired && (originalSession is null ||
                    originalSession.ExpiresAt > _oauth.SessionNow && !originalSession.RequiresFirstUseGameIdentityReauthorization))
                return new("contextChanged");
            var result = reauthorize
                ? await _oauth.ReauthorizeFirstUseSessionAsync(Current, token).ConfigureAwait(false)
                : await _oauth.ResumeFirstUseSessionAsync(Current, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!Current()) return new("contextChanged");
            if (result.Session is { } session)
            {
                if (result.State != "observed" || !_oauth.IsFreshFirstUseSessionCurrent(session)) return new("contextChanged");
                PublishSession(session, reauthorizationRequired: false);
                return Generation > generation && ReferenceEquals(_session, session) && current() &&
                    !_disposed && IsBusinessStartupDeferred && _oauth.IsFreshFirstUseSessionCurrent(session)
                    ? result : new("contextChanged");
            }
            // No implicit browser, legacy fallback, logout, or general restore
            // retry. A mode-owned explicit retry may reuse the rotated vault.
            if (result.State == "reauthorizationRequired") _reauthorizationRequired = true;
            return result;
        }
        finally
        {
            // Dispose seals admission immediately but cannot destroy the gate
            // while this original request still owns its physical lease.
            lock (_loginGate)
            {
                if (acquired) _mutationGate.Release();
                _firstUseResumeActive = false;
                if (_firstUseMutationGateDisposeRequested) _mutationGate.Dispose();
            }
        }
    }
}
