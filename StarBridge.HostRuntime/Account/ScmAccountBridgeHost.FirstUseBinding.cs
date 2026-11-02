namespace StarBridge.HostRuntime.Account;

internal sealed partial class ScmAccountBridgeHost
{
    private Func<bool>? _firstUseGameIdentityReady;
    internal void RequireColdFirstUseGameIdentity(Func<bool> ready) => _firstUseGameIdentityReady ??= ready;
    internal FirstUseScmIdentityFacts? CurrentInstalledFirstUseFacts()
    {
        var session = Volatile.Read(ref _session);
        if (session is null || CurrentContext is not { } context) return null;
        var facts = new FirstUseScmIdentityFacts(context, Generation, session);
        return InstalledFirstUseIdentityCurrent(facts) ? facts : null;
    }
    internal void RequireFirstUseGameIdentity(Func<bool> ready)
    {
        if (!IsFirstUseAuthenticationCandidate || !IsBusinessStartupDeferred)
            throw new InvalidOperationException("Game identity guard requires the original deferred owner.");
        _firstUseGameIdentityReady ??= ready;
    }
    private bool FirstUseGameIdentityReady
    {
        get { try { return _firstUseGameIdentityReady?.Invoke() ?? true; } catch { return false; } }
    }
    internal bool InstalledFirstUseIdentityCurrent(FirstUseScmIdentityFacts facts) =>
        !_disposed && !_localModeSessionLoopsStopped && !_reauthorizationRequired && !_credentialTemporarilyUnavailable &&
        (_firstUseBusinessAdmission is { IsActive: true } || !IsFirstUseAuthenticationCandidate && _firstUseGameIdentityReady is not null) && _session is { } session &&
        // Access-token expiry is handled by the installed resource refresh lane;
        // it is not a replacement identity or a recording-owner transition.
        Generation == facts.Generation && CurrentContext == facts.Context &&
        session.AuthoritativeGameIdentity == facts.Session.AuthoritativeGameIdentity &&
        _oauth.IsInstalledFirstUseSessionCurrent(session);
}
