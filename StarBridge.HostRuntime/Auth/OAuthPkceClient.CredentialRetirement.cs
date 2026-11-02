using System.IO;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private volatile ScmCredentialRetirementStamp? _credentialRetirement;
    private volatile ScmOAuthSession? _locallyRevokedSession;
    private readonly object _installedLineageGate = new();
    internal event Action<string, string>? StoredCredentialRejected;
    private sealed record CommittedRefresh(Guid[] Ancestors, ScmOAuthSession Session);
    private CommittedRefresh? _committedRefresh;
    private sealed record RefreshLineage(ScmOAuthSession Original,
        ScmCredentialRetirementStamp Input, ScmCredentialRetirementStamp Output);

    private void RecordCommittedRefresh(RefreshLineage? proof, ScmCredentialRetirementStamp? committed, ScmOAuthSession refreshed)
    {
        if (proof is null || committed is null || proof.Output != committed || committed != _credentialRetirement ||
            proof.Input.VaultBinding != committed.VaultBinding || proof.Input.OwnerKey != committed.OwnerKey) return;
        var original = proof.Original;
        if (original.CredentialVersion == Guid.Empty || !SameOwner(original, refreshed) ||
            original.AuthoritativeGameIdentity != refreshed.AuthoritativeGameIdentity) return;
        var previous = Volatile.Read(ref _committedRefresh);
        Guid[] ancestors = previous?.Session.CredentialVersion == original.CredentialVersion
            ? [.. previous.Ancestors, original.CredentialVersion] : [original.CredentialVersion];
        Volatile.Write(ref _committedRefresh, new(ancestors, refreshed));
    }

    internal bool IsInstalledFirstUseSessionOrRefreshOf(ScmOAuthSession original, ScmOAuthSession active) =>
        IsInstalledFirstUseSessionCurrent(active) &&
        (SameCredential(original, active) && original.AccessToken == active.AccessToken ||
            ReadInstalledFirstUseRefreshSuccessor(original) is { } successor && SameCredential(successor, active) &&
            successor.AccessToken == active.AccessToken);

    // One coherent lineage observation for Host snapshots/receipts which may
    // both lag a concurrent resource refresh. Both must belong to the actual
    // installed credential chain; same-owner login or vault replacement fails.
    internal ScmOAuthSession? ReadInstalledFirstUseSessionOrRefresh(ScmOAuthSession original, ScmOAuthSession observed)
    {
        lock (_installedLineageGate)
        {
            var actual = Volatile.Read(ref _currentSession);
            var receipt = Volatile.Read(ref _committedRefresh);
            if (actual is null || !IsInstalledFirstUseSessionCurrent(actual)) return null;
            bool Belongs(ScmOAuthSession session) => SameOwner(session, actual) &&
                session.AuthoritativeGameIdentity == actual.AuthoritativeGameIdentity &&
                (SameCredential(session, actual) && session.AccessToken == actual.AccessToken ||
                 receipt is not null && SameCredential(receipt.Session, actual) &&
                 receipt.Ancestors.Contains(session.CredentialVersion));
            return Belongs(original) && Belongs(observed) ? actual : null;
        }
    }

    // Only a proven refresh descendant may reconnect an installed Host owner.
    // A same-subject login or a changed external vault is not such a receipt.
    internal ScmOAuthSession? ReadInstalledFirstUseRefreshSuccessor(ScmOAuthSession original)
    {
        lock (_installedLineageGate)
        {
            var actual = Volatile.Read(ref _currentSession);
            var receipt = Volatile.Read(ref _committedRefresh);
            return actual is not null && receipt is not null && SameCredential(actual, receipt.Session) &&
                receipt.Ancestors.Contains(original.CredentialVersion) && SameOwner(original, actual) &&
                original.AuthoritativeGameIdentity == actual.AuthoritativeGameIdentity && IsInstalledFirstUseSessionCurrent(actual)
                ? actual : null;
        }
    }

    private void ClearRestoreCredential(string accountKey, ScmResumeCredential? captured, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (tokenVault is WindowsTokenVault windows)
        {
            if (captured is null || !windows.TryClearRetirement(captured.Version,
                    () => !token.IsCancellationRequested, () => NotifyStoredCredentialRejected(accountKey)))
                throw new HttpRequestException("Stored session changed during restoration.");
        }
        else
        {
            tokenVault.DeleteRefreshToken(accountKey);
            NotifyStoredCredentialRejected(accountKey);
        }
    }

    private void NotifyStoredCredentialRejected(string accountKey)
    {
        // Only called for an authoritative rejection under the original
        // credential's writer fence, never for missing data or transport failure.
        var prefix = options.AuthorityId + ":";
        if (accountKey.StartsWith(prefix, StringComparison.Ordinal) && accountKey.Length > prefix.Length)
            StoredCredentialRejected?.Invoke(options.AuthorityId, accountKey[prefix.Length..]);
    }

    internal bool IsFreshFirstUseSessionCurrent(ScmOAuthSession session) =>
        ReferenceEquals(Volatile.Read(ref _currentSession), session) &&
        session.ExpiresAt > SessionNow && IsInstalledFirstUseSessionCurrent(session);

    // A consumed installation may renew an expired access token through its
    // existing refresh credential. Expiry is a staging fact, not revocation.
    internal bool IsInstalledFirstUseSessionCurrent(ScmOAuthSession session)
    {
        lock (_installedLineageGate)
        {
            var actual = Volatile.Read(ref _currentSession);
            // Resource operations may replace correlation/profile metadata before
            // Host adopts their returned session. That is not a replacement login.
            // Keep exact credential/access-token and authoritative Handle lineage;
            // staging above still requires the exact reviewed session object.
            if (actual is null || actual.AuthorityId != session.AuthorityId || actual.Subject != session.Subject ||
                actual.AccessToken != session.AccessToken || actual.AuthoritativeGameIdentity != session.AuthoritativeGameIdentity) return false;
            try { return tokenVault is not WindowsTokenVault || CurrentCredentialRetirement(session) is not null; }
            catch (Exception error) when (error is ScmRefreshTemporarilyUnavailableException or IOException or InvalidDataException or UnauthorizedAccessException or
                System.Security.Cryptography.CryptographicException or System.Text.Json.JsonException or
                System.Security.SecurityException or NotSupportedException) { return false; }
        }
    }

    internal async Task<bool> RetireFreshFirstUseSessionAsync()
    {
        ScmOAuthSession? session;
        await _refreshGate.WaitAsync(CancellationToken.None).ConfigureAwait(false);
        try { session = _currentSession; }
        finally { _refreshGate.Release(); }
        // A genuinely fresh, drained owner with no committed session has never
        // selected/read the old vault. Do not clear unrelated cached credentials.
        if (session is null) return true;
        try { await RevokeAsync(session, CancellationToken.None).ConfigureAwait(false); }
        catch (ScmLocalCredentialRetirementException) { return false; }
        catch (System.Net.Http.HttpRequestException) { }
        return _currentSession is null && (tokenVault is not WindowsTokenVault || ReferenceEquals(_locallyRevokedSession, session));
    }

    // Capture the exact commit in the existing credential writer, not a later
    // "current account" read. Non-Windows / test vaults retain their old contract
    // and do not manufacture support for cross-process credential retirement.
    private void SaveSessionRefreshToken(string accountKey, string token)
    {
        if (tokenVault is WindowsTokenVault windows)
            _credentialRetirement = windows.SaveRefreshTokenWithRetirement(accountKey, token);
        else
        {
            tokenVault.SaveRefreshToken(accountKey, token);
            _credentialRetirement = null;
        }
        _locallyRevokedSession = null;
    }

    internal async Task<ScmCredentialRetirementStamp?> PrepareCredentialRetirementAsync(
        ScmOAuthSession session, CancellationToken token)
    {
        ArgumentNullException.ThrowIfNull(session);
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var accepted = CurrentCredentialRetirement(session);
            token.ThrowIfCancellationRequested();
            return accepted;
        }
        finally { _refreshGate.Release(); }
    }

    private ScmCredentialRetirementStamp? CurrentCredentialRetirement(ScmOAuthSession session)
    {
        var accepted = _credentialRetirement;
        if (tokenVault is not WindowsTokenVault windows) return null;
        if (accepted is null)
            throw new ScmRefreshTemporarilyUnavailableException("Original credential stamp is unavailable.");
        // Revocation may be cancelled after our real local clear but before the
        // caller publishes sign-out. Only that original in-memory session may
        // finish; absence alone never grants a new lifecycle or credential owner.
        if (_currentSession is null && ReferenceEquals(_locallyRevokedSession, session) && windows.IsRetirementCleared(accepted))
            return accepted;
        // A preloaded session, missing credential, newer login or unknown writer
        // is not proof of the original lifecycle's storage version.
        if (_currentSession is { } installed && SameOwner(installed, session) && !SameCredential(installed, session))
            throw new ScmRefreshTemporarilyUnavailableException("Original credential version has changed.");
        if (_currentSession is not { } actual || actual.AuthorityId != session.AuthorityId ||
            actual.Subject != session.Subject || actual.AccessToken != session.AccessToken)
            throw new InvalidDataException("Original credential lifecycle cannot be verified.");
        if (!windows.IsRetirementCurrent(accepted))
            throw new ScmRefreshTemporarilyUnavailableException("Original credential version has changed.");
        return accepted;
    }

    internal ScmCredentialRetirementStamp? ReadRetainedCredentialVersion(ScmOAuthSession session)
    {
        try { return CurrentCredentialRetirement(session); }
        catch (Exception error) when (error is ScmRefreshTemporarilyUnavailableException || OfflineDisplayStorageFailure(error)) { return null; }
    }

    internal bool IsPreparedCredentialRetirementCurrent(ScmOAuthSession session, ScmCredentialRetirementStamp expected) =>
        CurrentCredentialRetirement(session) == expected;

    private void DeleteSessionRefreshToken(ScmOAuthSession session, string accountKey,
        ScmCredentialRetirementStamp? expected, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (tokenVault is WindowsTokenVault windows)
        {
            if (expected is null)
                throw new ScmRefreshTemporarilyUnavailableException("Original credential stamp is unavailable.");
            bool OwnsOriginalSession()
            {
                if (token.IsCancellationRequested || _credentialRetirement != expected) return false;
                var actual = _currentSession;
                return actual is null ? ReferenceEquals(_locallyRevokedSession, session) :
                    SameCredential(actual, session) &&
                    actual.AccessToken == session.AccessToken;
            }
            if (!windows.TryClearRetirement(expected, OwnsOriginalSession))
                throw new ScmRefreshTemporarilyUnavailableException("Original credential version changed before deletion.");
            _locallyRevokedSession = session;
        }
        else tokenVault.DeleteRefreshToken(accountKey);
    }
}
