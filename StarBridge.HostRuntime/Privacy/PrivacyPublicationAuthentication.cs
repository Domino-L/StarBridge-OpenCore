using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Privacy;

// Adapt the Relay's stable exception to the existing OAuth refresh contract.
// OAuth remains the sole owner of refresh, serialization and session persistence.
internal static class PrivacyPublicationAuthentication
{
    internal static async Task<(T Result, ScmOAuthSession ActiveSession)> SendAsync<T>(
        OAuthPkceClient oauth, ScmOAuthSession session,
        Func<ScmOAuthSession, CancellationToken, Task<T>> send, CancellationToken token)
    {
        try
        {
            return await oauth.SendResourceRequestAsync(session, async (active, ct) => {
                try { return await send(active, ct).ConfigureAwait(false); }
                catch (AccountBridgeHostException error) when (error.HttpStatus == HttpStatusCode.Unauthorized &&
                    error.Code == "privacy_publication.identity_unavailable")
                {
                    throw new ScmApiAuthenticationException("Privacy publication authorization expired.");
                }
            }, token).ConfigureAwait(false);
        }
        catch (ScmApiAuthenticationException) when (!token.IsCancellationRequested)
        {
            // Only a definitive credential rejection requires identity. Refresh
            // transport, timeout, permission and protocol failures retain their cause.
            throw new AccountBridgeHostException("privacy_publication.identity_unavailable");
        }
        catch (ScmRefreshTemporarilyUnavailableException) when (!token.IsCancellationRequested)
        {
            // Refresh HTTP 401 without invalid_grant is a client/gateway outage.
            // Keep it out of the resource-401 identity threshold and use existing backoff.
            throw new AccountBridgeHostException("privacy_publication.temporarily_unavailable", retryable: true);
        }
    }
}
