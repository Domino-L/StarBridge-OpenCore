namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Installed identity review renews through the existing resource lane, but
    // cannot substitute the vault's newly selected account for the reviewed one.
    internal async Task<ScmOAuthSession> RefreshInstalledIdentityAsync(ScmOAuthSession session, CancellationToken token)
    {
        if (!IsInstalledFirstUseSessionCurrent(session))
            throw new ScmApiAuthenticationException("SCM authorization changed.");
        var correlationId = ScmAuthDiagnostics.NewCorrelationId();
        var (identity, active) = await SendResourceRequestAsync(session, async (current, ct) =>
        {
            if (current.AuthorityId != session.AuthorityId || current.Subject != session.Subject ||
                !IsInstalledFirstUseSessionCurrent(current))
                throw new ScmApiAuthenticationException("SCM authorization changed.");
            return await LoadIdentityAsync(correlationId, current.AccessToken, ct).ConfigureAwait(false);
        }, token).ConfigureAwait(false);
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            if (!IsFreshFirstUseSessionCurrent(active) || identity.Subject != session.Subject)
                throw new ScmApiAuthenticationException("SCM authorization changed.");
            ValidateFirstUseIdentity(identity.GameIdentity);
            return _currentSession = RefreshedIdentity(active, identity, correlationId);
        }
        finally { _refreshGate.Release(); }
    }
}
