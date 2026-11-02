using System.Net;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    // 2026-10-21 (0.7.1 sign-out during the Hong Kong Java deploy): /me answered
    // 502 for four minutes. Every restore attempt refreshed again, so the relay
    // rotated the refresh token several times a second. The Host exited while one
    // rotation was in flight; the next process sent the consumed token, got
    // invalid_grant and deleted the credential. A refresh whose identity read is
    // only temporarily unavailable is now reused until it nears expiry.
    internal static async Task UnavailableIdentityReusesCommittedRefresh()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-retained-refresh-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var key = options.AuthorityId + ":synthetic-owner";
            var vault = new WindowsTokenVault(System.IO.Path.Combine(root, "vault.json"));
            vault.SaveRefreshToken(key, "synthetic-refresh");
            var refreshes = 0;
            var identityReads = 0;
            var identityAvailable = false;
            var lifetime = 3600;
            var handler = new ScriptedHandler(request =>
            {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    var n = Interlocked.Increment(ref refreshes);
                    return JsonResponse(HttpStatusCode.OK,
                        $"{{\"access_token\":\"synthetic-access-{n}\",\"refresh_token\":\"synthetic-rotated-{n}\",\"token_type\":\"Bearer\",\"expires_in\":{lifetime}}}");
                }
                Interlocked.Increment(ref identityReads);
                return identityAvailable
                    ? JsonResponse(HttpStatusCode.OK,
                        "{\"subject\":\"synthetic-owner\",\"displayName\":\"Synthetic\",\"capabilities\":[\"profile.read\"]}")
                    : JsonResponse(HttpStatusCode.BadGateway, "{\"message\":\"Synthetic deploy\"}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            var rejected = 0;
            oauth.StoredCredentialRejected += (_, _) => rejected++;
            async Task Unavailable()
            {
                try { await oauth.TryRestoreSessionAsync(default); throw new Exception("Expected a temporarily unavailable identity"); }
                catch (HttpRequestException) { }
            }

            for (var attempt = 0; attempt < 4; attempt++) await Unavailable();
            AssertEqual(4, identityReads, "every attempt retries the identity read");
            AssertEqual(1, refreshes,
                "An unavailable identity read refreshes the credential again on every restore attempt.");
            AssertEqual("synthetic-rotated-1", vault.LoadRefreshToken(key), "the one rotation stays committed");

            identityAvailable = true;
            var restored = await oauth.TryRestoreSessionAsync(default);
            AssertEqual("synthetic-owner", restored?.Subject, "the retained refresh restores once identity answers");
            AssertEqual("synthetic-access-1", restored?.AccessToken, "the restored session uses the committed access token");
            AssertEqual(1, refreshes, "restoring from the retained refresh does not rotate again");
            AssertEqual(ScmSessionRestoreOutcome.Restored, oauth.LastSessionRestoreOutcome, "restored outcome");
            AssertEqual(0, rejected, "an outage never retires the credential");

            // A short-lived access token is not worth keeping: near expiry each
            // attempt refreshes as before.
            var shortVault = new WindowsTokenVault(System.IO.Path.Combine(root, "short.json"));
            shortVault.SaveRefreshToken(key, "synthetic-refresh");
            refreshes = 0;
            identityAvailable = false;
            lifetime = 30;
            var shortLived = new OAuthPkceClient(new ScmHttpClient(handler), shortVault, options);
            for (var attempt = 0; attempt < 2; attempt++)
            {
                try { await shortLived.TryRestoreSessionAsync(default); throw new Exception("Expected outage"); }
                catch (HttpRequestException) { }
            }
            AssertEqual(2, refreshes, "a token about to expire is refreshed again");

            // A credential replaced after the outage (another login) drops the
            // retained refresh: the next attempt uses the new credential.
            lifetime = 3600;
            var replacedVault = new WindowsTokenVault(System.IO.Path.Combine(root, "replaced.json"));
            replacedVault.SaveRefreshToken(key, "synthetic-refresh");
            refreshes = 0;
            var replaced = new OAuthPkceClient(new ScmHttpClient(handler), replacedVault, options);
            try { await replaced.TryRestoreSessionAsync(default); throw new Exception("Expected outage"); }
            catch (HttpRequestException) { }
            replacedVault.SaveRefreshToken(key, "synthetic-new-login");
            try { await replaced.TryRestoreSessionAsync(default); throw new Exception("Expected outage"); }
            catch (HttpRequestException) { }
            AssertEqual(2, refreshes, "a replaced credential is refreshed, never served from the old retained token");
            Console.WriteLine("PASS unavailable identity reuses the committed refresh until it nears expiry or the credential changes");
        }
        finally { System.IO.Directory.Delete(root, recursive: true); }
    }
}
