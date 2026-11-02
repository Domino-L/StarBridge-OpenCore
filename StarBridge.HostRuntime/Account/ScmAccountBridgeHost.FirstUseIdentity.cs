using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

// Native-private original auth facts. The token/session object is never a bridge
// payload, profile association, migration request or online activation receipt.
internal sealed record FirstUseScmIdentityFacts(BridgeAccountContext Context, long Generation,
    ScmOAuthSession Session);
internal sealed record FirstUseScmIdentityRead(string State, FirstUseScmIdentityFacts? Facts = null);

internal sealed partial class ScmAccountBridgeHost
{
    internal string FirstUseSignInState
    {
        get
        {
            if (!IsFirstUseAuthenticationCandidate) return "contextChanged";
            lock (_loginGate) if (_loginCancellation is not null) return "authorizing";
            var session = Volatile.Read(ref _session);
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable) return "reauthorizationRequired";
            if (_freshSignInPending || session is null) return "signInRequired";
            if (session.ExpiresAt <= _oauth.SessionNow) return "sessionExpired";
            return IsFirstUseIdentityCurrent(new(ToContext(session), Generation, session))
                ? "identityCheckRequired" : "contextChanged";
        }
    }

    internal bool IsFirstUseIdentityCurrent(FirstUseScmIdentityFacts facts) => IsFirstUseAuthenticationCandidate &&
        Volatile.Read(ref _loginCancellation) is null &&
        !_freshSignInPending && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
        _legacySession is null && Generation == facts.Generation && CurrentContext == facts.Context &&
        ReferenceEquals(Volatile.Read(ref _session), facts.Session) && _oauth.IsFreshFirstUseSessionCurrent(facts.Session);

    internal async Task<FirstUseScmIdentityRead> ReadFirstUseIdentityAsync(CancellationToken token)
    {
        var installedReview = _firstUseBusinessAdmission is { IsActive: true } ||
            !IsFirstUseAuthenticationCandidate && _firstUseGameIdentityReady is not null;
        if (!await _mutationGate.WaitAsync(installedReview ? TimeSpan.FromSeconds(5) : TimeSpan.Zero, token).ConfigureAwait(false))
            return new("operationInProgress");
        try
        {
            installedReview = _firstUseBusinessAdmission is { IsActive: true } ||
                !IsFirstUseAuthenticationCandidate && _firstUseGameIdentityReady is not null;
            var coldReview = !IsFirstUseAuthenticationCandidate && _firstUseGameIdentityReady is not null;
            if ((!IsFirstUseAuthenticationCandidate && !coldReview) || _legacySession is not null) return new("unavailable");
            var session = Volatile.Read(ref _session);
            if (_reauthorizationRequired || _credentialTemporarilyUnavailable) return new("reauthorizationRequired");
            if (_freshSignInPending || session is null) return new("signInRequired");
            if (!installedReview && session.ExpiresAt <= _oauth.SessionNow) return new("sessionExpired");
            var context = ToContext(session); var generation = Generation;
            if (installedReview && !_oauth.IsInstalledFirstUseSessionCurrent(session))
                return new("contextChanged");
            var current = installedReview
                ? await _oauth.RefreshInstalledIdentityAsync(session, token).ConfigureAwait(false)
                : await _oauth.RefreshFirstUseIdentityAsync(session, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if ((!IsFirstUseAuthenticationCandidate && !coldReview) || Generation != generation || CurrentContext != context ||
                !ReferenceEquals(Volatile.Read(ref _session), session)) return new("contextChanged");
            RequireSameSession(session, current);
            if (current.ExpiresAt <= _oauth.SessionNow) return new("sessionExpired");
            if (installedReview && (_disposed || _localModeSessionLoopsStopped ||
                _reauthorizationRequired || _credentialTemporarilyUnavailable)) return new("contextChanged");
            // Keep the same actual authenticated owner; don't manufacture a new
            // generation or start its deferred business/participation consumers.
            Volatile.Write(ref _session, current);
            var facts = new FirstUseScmIdentityFacts(context, generation, current);
            return (installedReview ? InstalledFirstUseIdentityCurrent(facts) : IsFirstUseIdentityCurrent(facts))
                ? new("observed", facts) : new("contextChanged");
        }
        catch (ScmApiAuthenticationException) { return new("reauthorizationRequired"); }
        finally { _mutationGate.Release(); }
    }
}
