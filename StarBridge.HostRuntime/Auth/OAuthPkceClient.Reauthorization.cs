namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Explicit browser authorization may replace only the exact retained
    // credential captured by this owner. Wrong accounts and newer logins are
    // never deleted, selected, merged or overwritten by this recovery path.
    internal async Task<FirstUseSessionResume> ReauthorizeFirstUseSessionAsync(Func<bool> current, CancellationToken token)
    {
        if (tokenVault is not WindowsTokenVault vault) return new("unavailable");
        ScmResumeCredential? original;
        ScmOAuthSession? originalSession;
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            originalSession = _currentSession;
            if (!current() || originalSession is not null && originalSession.ExpiresAt > SessionNow &&
                !originalSession.RequiresFirstUseGameIdentityReauthorization) return new("contextChanged");
            // Bind to the original explicit resume, not whichever login happens
            // to be selected when a later UI click arrives.
            original = _firstUseResumeCredential;
            if (original is null) return new("reauthorizationRequired");
        }
        finally { _refreshGate.Release(); }
        bool Accept(ScmOAuthSession session) => !token.IsCancellationRequested && current() &&
            ReferenceEquals(_currentSession, originalSession) &&
            AccountKey(session.Subject) == original.AccountKey && session.ExpiresAt > SessionNow &&
            vault.IsRetirementCurrent(original.Version);
        bool Commit(ScmOAuthSession session, string refreshToken)
        {
            if (!Accept(session)) return false;
            var next = vault.RotateResumeCredential(original, refreshToken, () => Accept(session));
            if (next is null) return false;
            _credentialRetirement = next; _locallyRevokedSession = null;
            _firstUseResumeCredential = new(original.AccountKey, refreshToken, next);
            return true;
        }
        try
        {
            token.ThrowIfCancellationRequested();
            if (!current() || !vault.IsRetirementCurrent(original.Version)) return new("contextChanged");
            var session = await SignInCoreAsync(token, null, Accept, Commit,
                () => current() && ReferenceEquals(_currentSession, originalSession) && vault.IsRetirementCurrent(original.Version)).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            return current() && IsFreshFirstUseSessionCurrent(session) ? new("observed", session) : new("contextChanged");
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (ScmApiAuthenticationException) { return new(current() ? "reauthorizationRequired" : "contextChanged"); }
    }
}
