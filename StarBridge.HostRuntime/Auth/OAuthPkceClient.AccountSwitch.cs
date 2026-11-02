using System.IO;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private bool _startupCredentialCleanupAttempted;
    private sealed record SignInPreviousCredential(ScmCredentialRetirementStamp? Version,
        string? AccountKey = null, string? Token = null);

    private void CleanupStartupCredentials()
    {
        if (_startupCredentialCleanupAttempted) return;
        _startupCredentialCleanupAttempted = true;
        if (tokenVault is not WindowsTokenVault windows) return;
        try { windows.CleanupUnselectedCredentials(); }
        catch (Exception error) when (CredentialStorageFailure(error))
        { SwitchCleanupDiagnostic("deferred"); }
    }

    private static bool CredentialStorageFailure(Exception error) =>
        error is IOException or UnauthorizedAccessException or InvalidDataException or
            System.Security.Cryptography.CryptographicException;

    private static void SwitchCleanupDiagnostic(string outcome) =>
        ScmAuthDiagnostics.Write("account-switch", "previous-credential-cleanup", outcome);

    private SignInPreviousCredential CaptureSignInPreviousVersion()
    {
        try
        {
            if (tokenVault is not WindowsTokenVault windows)
            {
                var key = tokenVault.LoadActiveAccountKey();
                return new(null, key, key is null ? null : tokenVault.LoadRefreshToken(key));
            }
            var selected = windows.CaptureSelectedCredentialVersion();
            // If this owner already knows an older version, do not adopt an
            // external writer's replacement merely because login was requested.
            return new(_credentialRetirement ?? selected);
        }
        catch (Exception error) when (CredentialStorageFailure(error))
        { SwitchCleanupDiagnostic("unavailable"); return new(null); }
    }

    // Called only after explicit authorization succeeds, inside _refreshGate.
    private void SaveSignInCredential(string accountKey, string token, SignInPreviousCredential? previous)
    {
        // Any remaining conflict belongs to the next startup's sweep, not to
        // a resource retry in this newly signed-in owner.
        _startupCredentialCleanupAttempted = true;
        if (tokenVault is WindowsTokenVault windows)
        {
            _credentialRetirement = windows.SaveSignInCredential(accountKey, token, previous?.Version, out var outcome);
            SwitchCleanupDiagnostic(outcome);
        }
        else
        {
            tokenVault.SaveRefreshToken(accountKey, token);
            _credentialRetirement = null;
            var oldKey = previous?.AccountKey;
            if (oldKey is not null && oldKey != accountKey)
            {
                try
                {
                    if (tokenVault.LoadActiveAccountKey() == accountKey && tokenVault.LoadRefreshToken(oldKey) == previous!.Token)
                        tokenVault.DeleteRefreshToken(oldKey);
                    else SwitchCleanupDiagnostic("version-conflict");
                }
                catch (Exception error) when (CredentialStorageFailure(error)) { SwitchCleanupDiagnostic("deferred"); }
            }
        }
        _locallyRevokedSession = null;
    }
}

// Explicit phase boundaries: Host never infers a committed local logout from
// the base HTTP exception type. Neither exception carries credential material.
public sealed class ScmLocalCredentialRetirementException(Exception inner)
    : Exception("Local credential retirement did not complete.", inner);

public sealed class ScmRemoteRevocationException(HttpRequestException inner)
    : HttpRequestException("Remote revocation failed after local retirement committed.", inner);
