using System.Net;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task LateResponsesAndUnconfirmedRotation()
    {
        foreach (var unconfirmed in new[] { false, true })
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var vault = new RaceVault();
            var key = options.AuthorityId + ":subject-1";
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var refreshes = 0;
            var failIdentity = false;
            var profileEntered = Signal();
            var releaseProfile = Signal();
            using var handler = new RaceHandler(async (request, token) => {
                if (request.RequestUri == options.TokenEndpoint)
                    return JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + (++refreshes) +
                        "\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
                if (request.RequestUri?.AbsolutePath == options.MeEndpoint.AbsolutePath)
                {
                    if (failIdentity) throw new HttpRequestException("Synthetic identity transport failure");
                    return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
                }
                profileEntered.TrySetResult();
                await releaseProfile.Task.WaitAsync(token);
                return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic late metadata\"}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            var initial = (await oauth.TryRestoreSessionAsync(default))!;
            var oldProfile = oauth.LoadProfileAsync(initial, default);
            await profileEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            failIdentity = unconfirmed;
            try
            {
                await oauth.SendResourceRequestAsync(initial, (active, _) => active.CredentialVersion == initial.CredentialVersion
                    ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic 401")) : Task.FromResult(true), default);
            }
            catch (HttpRequestException) when (unconfirmed) { }
            var latestVersion = oauth.CurrentCredentialVersion;
            AssertEqual(false, latestVersion == initial.CredentialVersion, "committed rotation immediately has a distinct version");
            releaseProfile.TrySetResult();
            await oldProfile.WaitAsync(TimeSpan.FromSeconds(5));
            AssertEqual(latestVersion, oauth.CurrentCredentialVersion, "late successful metadata cannot reinstall old credential");
            await oauth.ClearLocalCredentialAsync(initial, default);
            AssertEqual(0, vault.Deletes, "late realtime rejection cannot clear rotated or unconfirmed credential");
            AssertEqual(key, vault.LoadActiveAccountKey(), "late realtime clear preserves selection");
            if (unconfirmed)
            {
                failIdentity = false;
                var restored = await oauth.TryRestoreSessionAsync(default);
                AssertEqual(latestVersion, restored?.CredentialVersion, "identity retry preserves committed version");
                AssertEqual(2, refreshes, "identity retry must not rotate again");
            }
        }

        // The first 401 can also arrive after a completed user logout.
        var logoutOptions = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var logoutVault = new RaceVault();
        logoutVault.SaveRefreshToken(logoutOptions.AuthorityId + ":subject-1", "synthetic-refresh");
        using var logoutHandler = new ScriptedHandler(request => request.RequestUri == logoutOptions.TokenEndpoint
            ? JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}")
            : JsonResponse(HttpStatusCode.OK, request.RequestUri == logoutOptions.RevokeEndpoint ? "{}" : "{\"subject\":\"subject-1\"}"));
        var logout = new OAuthPkceClient(new ScmHttpClient(logoutHandler), logoutVault, logoutOptions);
        var session = (await logout.TryRestoreSessionAsync(default))!;
        var entered = Signal();
        var release = Signal();
        var pending = logout.SendResourceRequestAsync<bool>(session, async (_, token) => {
            entered.TrySetResult();
            await release.Task.WaitAsync(token);
            throw new ScmApiAuthenticationException("Synthetic late first 401");
        }, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await logout.RevokeAsync(session, default);
        release.TrySetResult();
        try { await pending; throw new InvalidOperationException("Logged-out request unexpectedly succeeded"); }
        catch (ScmRefreshTemporarilyUnavailableException) { }
        AssertEqual(1, logoutVault.Deletes, "logout remains the only deletion");
        AssertEqual<Guid?>(null, logout.CurrentCredentialVersion, "late first 401 cannot resurrect a logged-out version");
        await Late401RejectsNewerExpiredCredential();
    }

    private static async Task Late401RejectsNewerExpiredCredential()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-refresh");
        var refreshes = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.TokenEndpoint)
                return ++refreshes == 3 ? JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}") :
                    JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + refreshes +
                        "\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}");
            return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
        });
        var clock = new CredentialClock();
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options) { SessionClock = clock };
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var entered = Signal();
        var release = Signal();
        var invalidations = 0;
        oauth.SessionInvalidated += (_, _) => invalidations++;
        var old = oauth.SendResourceRequestAsync<bool>(initial, async (_, token) => {
            entered.TrySetResult();
            await release.Task.WaitAsync(token);
            throw new ScmApiAuthenticationException("Synthetic delayed first 401");
        }, default);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await oauth.SendResourceRequestAsync(initial, (active, _) => active.CredentialVersion == initial.CredentialVersion
            ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic other resource 401")) : Task.FromResult(true), default);
        clock.Now = clock.Now.AddHours(2);
        release.TrySetResult();
        try { await old; throw new InvalidOperationException("Current invalid_grant must still require login"); }
        catch (ScmApiAuthenticationException) { }
        AssertEqual(3, refreshes, "current expired version refresh rejected once");
        AssertEqual(1, vault.Deletes, "current invalid_grant deletes once even for an old caller");
        AssertEqual(1, invalidations, "current invalid_grant projects one authentication invalidation");
    }
}
