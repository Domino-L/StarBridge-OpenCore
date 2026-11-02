namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Like RefreshFirstUseIdentityAsync: exact original candidate, no selected
    // vault restore, resource publication, 401 replay or deferred business work.
    // Expired/rejected authorization requires explicit candidate reauthorization.
    internal Task<ScmGameIdentityVerificationCode> GetFirstUseGameIdentityCodeAsync(
        ScmOAuthSession session, string gameName, CancellationToken token) =>
        SendFirstUseGameIdentityAsync<ScmGameIdentityVerificationCode>(session,
            "verification-code", new { gameName }, token);

    internal async Task<ScmGameIdentityVerificationResult> VerifyFirstUseGameIdentityAsync(
        ScmOAuthSession session, string gameName, string contact, CancellationToken token,
        Action<ScmOAuthSession>? sessionReady) =>
        await SendFirstUseGameIdentityAsync<ScmGameIdentityVerificationResult>(session,
            "verify", new { gameName, userMobile = contact }, token).ConfigureAwait(false);

    private async Task<T> SendFirstUseGameIdentityAsync<T>(ScmOAuthSession session,
        string operation, object body, CancellationToken token)
    {
        token.ThrowIfCancellationRequested();
        if (!IsFreshFirstUseSessionCurrent(session))
            throw new ScmApiAuthenticationException("SCM authorization changed.");
        var result = await SendGameIdentityRequestAsync<T>(new Uri(options.ResourceServerBaseUri,
            "app-api/starbridge/v1/game-identity/" + operation), session, body, token).ConfigureAwait(false);
        token.ThrowIfCancellationRequested();
        if (!IsFreshFirstUseSessionCurrent(session))
            throw new ScmApiAuthenticationException("SCM authorization changed.");
        return result;
    }
}
