namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // 2026-10-21 (0.7.1 sign-out during a Java deploy): when /me was temporarily
    // unavailable every restore attempt refreshed again, rotating the refresh
    // token several times a second; a process exit inside one rotation lost the
    // login. A refresh is committed to the vault before /me, so its access token
    // is kept, in memory only, until the identity read succeeds or is rejected,
    // the credential changes, or the token nears expiry. Only under _refreshGate.
    private sealed record RetainedRefresh(
        string AccountKey,
        ScmTokenResponse Response,
        DateTimeOffset ExpiresAt,
        ScmCredentialRetirementStamp? Version, Guid CredentialVersion, RefreshLineage? Lineage = null);

    private RetainedRefresh? _retainedRefresh;

    private void RetainRefresh(string accountKey, ScmTokenResponse response, DateTimeOffset receivedAt,
        ScmCredentialRetirementStamp? version, RefreshLineage? lineage = null)
    {
        DateTimeOffset expiresAt;
        try { expiresAt = receivedAt.AddSeconds(response.ExpiresIn); }
        catch (ArgumentOutOfRangeException) { _retainedRefresh = null; return; }
        _retainedRefresh = new(accountKey, response, expiresAt, version, Guid.NewGuid(), lineage);
    }

    // A retired sign-in leaves a credential-free note so a later start asks the
    // user to sign in again (WindowsTokenVault only; other vaults are fixtures).
    private void MarkSessionExpired()
    {
        if (tokenVault is WindowsTokenVault vault) vault.MarkSessionExpired(options.AuthorityId);
    }

    private bool SessionExpired() =>
        tokenVault is WindowsTokenVault vault && vault.IsSessionExpired(options.AuthorityId);

    private void ClearSessionExpired()
    {
        if (tokenVault is WindowsTokenVault vault) vault.ClearSessionExpired();
    }

    // Reuse only for the exact committed credential this refresh produced.
    private RetainedRefresh? ReusableRefresh(string accountKey, string refreshToken)
    {
        var retained = _retainedRefresh;
        if (retained is null) return null;
        var current = string.Equals(retained.AccountKey, accountKey, StringComparison.Ordinal) &&
            string.Equals(retained.Response.RefreshToken, refreshToken, StringComparison.Ordinal) &&
            retained.ExpiresAt > SessionNow.AddMinutes(1) &&
            (tokenVault is not WindowsTokenVault vault ||
                (retained.Version is not null && vault.IsRetirementCurrent(retained.Version)));
        if (!current) _retainedRefresh = null;
        return current ? retained : null;
    }
}
