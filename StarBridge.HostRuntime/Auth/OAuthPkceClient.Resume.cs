using System.IO;
using System.Net.Http;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

// Only the Native resume owner consumes these facts. Restoring authentication
// neither approves a local Handle nor starts/installs an online business graph.
internal sealed record FirstUseSessionResume(string State, ScmOAuthSession? Session = null);

public sealed partial class OAuthPkceClient
{
    private ScmResumeCredential? _firstUseResumeCredential;
    internal async Task<FirstUseSessionResume> ResumeFirstUseSessionAsync(Func<bool> current,
        CancellationToken token)
    {
        ArgumentNullException.ThrowIfNull(current);
        await _refreshGate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            // Never reuse a preloaded/current authorization or adopt an ordinary
            // restore owner. The candidate must still be auth-only and original.
            if (!current() || _currentSession is not null) return new("contextChanged");
            CleanupStartupCredentials();
            if (tokenVault is not WindowsTokenVault vault) return new("unavailable");
            if (_firstUseResumeCredential is { } previous && !vault.IsRetirementCurrent(previous.Version))
                return new("contextChanged");
            var original = vault.CaptureResumeCredential(options.AuthorityId);
            token.ThrowIfCancellationRequested();
            if (!current()) return new("contextChanged");
            if (original is null) return new("signInRequired");
            if (!vault.IsRetirementCurrent(original.Version)) return new("contextChanged");
            _firstUseResumeCredential = original;
            var correlation = ScmAuthDiagnostics.NewCorrelationId();
            ScmTokenResponse response;
            try { response = await RefreshTokenAsync(correlation, original.RefreshToken, token).ConfigureAwait(false); }
            catch (ScmRefreshTokenRejectedException)
            {
                token.ThrowIfCancellationRequested();
                return ObserveFirstUseCredentialRejection(current, token);
            }
            var receivedAt = SessionNow;
            token.ThrowIfCancellationRequested();
            if (!current()) return new("contextChanged");
            var rotated = vault.RotateResumeCredential(original, response.RefreshToken, current);
            if (rotated is null) return new("contextChanged");
            // Refresh rotation is retained even if /me is temporarily unavailable:
            // the server may have consumed the previous refresh credential.
            _credentialRetirement = rotated;
            _firstUseResumeCredential = new(original.AccountKey, response.RefreshToken, rotated);
            _locallyRevokedSession = null;
            bool StillCurrent() => current() && vault.IsRetirementCurrent(rotated);
            if (response.ExpiresIn <= 0) return new("reauthorizationRequired");
            DateTimeOffset expiresAt;
            try { expiresAt = receivedAt.AddSeconds(response.ExpiresIn); }
            catch (ArgumentOutOfRangeException) { return new("reauthorizationRequired"); }
            var identity = await LoadIdentityAsync(correlation, response.AccessToken, token).ConfigureAwait(false);
            token.ThrowIfCancellationRequested();
            if (!StillCurrent()) return new("contextChanged");
            if (string.IsNullOrWhiteSpace(identity.Subject) || AccountKey(identity.Subject) != original.AccountKey)
                return ObserveFirstUseCredentialRejection(current, token);
            ValidateFirstUseIdentity(identity.GameIdentity);
            // Ordinary restoration's historical expiry clamp is not a resume
            // authorization receipt for an already expired token response.
            var session = CreateSession(identity, response, correlation, expiresAt);
            if (session.ExpiresAt <= SessionNow) return new("reauthorizationRequired");
            if (deviceIdProvider is not null)
            {
                var device = await GetDesktopDeviceStatusAsync(session, deviceIdProvider(), token).ConfigureAwait(false);
                token.ThrowIfCancellationRequested();
                if (!StillCurrent()) return new("contextChanged");
                if (!device.Trusted)
                    return ObserveFirstUseCredentialRejection(current, token);
            }
            if (!StillCurrent()) return new("contextChanged");
            if (session.ExpiresAt <= SessionNow) return new("reauthorizationRequired");
            _currentSession = session;
            _sessionWasInstalled = true;
            _retainedRefresh = null;
            _rejectedSession = null;
            if (!IsFreshFirstUseSessionCurrent(session))
            { _currentSession = null; return new("contextChanged"); }
            RouteState?.LoginSucceeded();
            return new("observed", session);
        }
        catch (OperationCanceledException) when (token.IsCancellationRequested) { throw; }
        catch (ScmApiAuthenticationException)
        { return new("unavailable"); }
        catch (Exception error) when (error is HttpRequestException or IOException or JsonException or
            System.Security.Cryptography.CryptographicException or UnauthorizedAccessException or
            System.Security.SecurityException or NotSupportedException or OperationCanceledException or InvalidOperationException)
        { return new("unavailable"); }
        finally { _refreshGate.Release(); }
    }

    private FirstUseSessionResume ObserveFirstUseCredentialRejection(Func<bool> current, CancellationToken token)
    {
        _sessionWasInstalled = true;
        token.ThrowIfCancellationRequested();
        try
        {
            var observed = tokenVault is WindowsTokenVault vault && _firstUseResumeCredential is { } original &&
                vault.ObserveCurrentRetirement(original.Version, () => !token.IsCancellationRequested && current(),
                    () => NotifyStoredCredentialRejected(original.AccountKey));
            return new(observed ? "reauthorizationRequired" : "contextChanged");
        }
        catch (Exception error) when (OfflineDisplayStorageFailure(error))
        {
            // This also runs from an authentication exception handler: sibling
            // catches cannot handle a storage failure thrown inside that catch.
            return new("unavailable");
        }
    }
}
