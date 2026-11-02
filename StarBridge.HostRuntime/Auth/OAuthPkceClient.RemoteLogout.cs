namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // An explicit server device revocation is authoritative. Unlike a resource
    // or ticket failure, it deletes this account even if its token has rotated.
    // DeleteRefreshToken also clears the active selection for this account.
    public async Task DeleteCredentialForRemoteLogoutAsync(
        ScmOAuthSession? session, CancellationToken cancellationToken)
    {
        await _refreshGate.WaitAsync(cancellationToken).ConfigureAwait(false);
        try
        {
            // A resource 401 may already have cleared the caller's session.
            // Resolve only the selected account, under the same refresh gate.
            var accountKey = session is not null
                ? $"{session.AuthorityId}:{session.Subject}"
                : tokenVault.LoadActiveAccountKey();
            if (string.IsNullOrWhiteSpace(accountKey)) return;
            tokenVault.DeleteRefreshToken(accountKey);
            _sessionWasInstalled = true;
            if (_currentSession is { } current && $"{current.AuthorityId}:{current.Subject}" == accountKey)
            {
                _currentSession = null;
                _credentialRetirement = null;
            }
            if (_retainedRefresh?.AccountKey == accountKey) _retainedRefresh = null;
        }
        finally { _refreshGate.Release(); }
    }
}
