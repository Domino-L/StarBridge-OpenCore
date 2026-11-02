using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task RefreshStatusRejection()
    {
        foreach (var (status, body) in new[] {
            (HttpStatusCode.Unauthorized, "{\"error\":\"invalid_grant\"}"),
            (HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}"),
        })
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var vault = new MemoryTokenVault();
            vault.SaveRefreshToken($"{options.AuthorityId}:subject-1", "synthetic-refresh");
            var calls = 0;
            using var handler = new ScriptedHandler(request => {
                AssertEqual(options.TokenEndpoint, request.RequestUri, "rejected restore cannot request identity");
                calls++;
                return JsonResponse(status, body);
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            AssertEqual<ScmOAuthSession?>(null, await oauth.TryRestoreSessionAsync(default), "cold restore rejects credential");
            AssertEqual(ScmSessionRestoreOutcome.ReauthorizationRequired, oauth.LastSessionRestoreOutcome,
                "cold refresh rejection must require authorization");
            AssertEqual<string?>(null, vault.LoadRefreshToken($"{options.AuthorityId}:subject-1"),
                "explicit invalid_grant must retire the credential");
            AssertEqual<string?>(null, vault.LoadActiveAccountKey(), "rejection clears active credential selection");
            AssertEqual<ScmOAuthSession?>(null, await oauth.TryRestoreSessionAsync(default), "rejected restore stays signed out");
            AssertEqual(1, calls, "cold restore cannot retry a rejected credential");
            Console.WriteLine("PASS explicit refresh invalid_grant: " + (int)status);
        }
    }

    internal static async Task RefreshStatusTransient()
    {
        foreach (var (status, body) in new[] {
            (HttpStatusCode.Unauthorized, ""),
            (HttpStatusCode.Unauthorized, "<html>Unauthorized</html>"),
            (HttpStatusCode.Unauthorized, "{"),
            (HttpStatusCode.Unauthorized, "{}"),
            (HttpStatusCode.Unauthorized, "{\"error\":\"invalid_client\"}"),
            (HttpStatusCode.Unauthorized, "{\"error\":\"untrusted-error\",\"error_description\":\"untrusted-description\"}"),
            (HttpStatusCode.Unauthorized, "{\"error\":42}"),
            (HttpStatusCode.Unauthorized, "[]"),
            (HttpStatusCode.BadRequest, "<html>Bad Request</html>"),
        })
        {
            var settings = CreateEnvironmentSettings();
            var options = ScmOAuthOptions.Create(settings);
            var accountKey = $"{options.AuthorityId}:subject-1";
            var vault = new MemoryTokenVault();
            vault.SaveRefreshToken(accountKey, "synthetic-refresh");
            var recovered = false;
            var calls = 0;
            var invalidations = 0;
            using var handler = new ScriptedHandler(request => {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    calls++;
                    return !recovered ? new HttpResponseMessage(status) {
                        Content = new StringContent(body, System.Text.Encoding.UTF8, "text/html") }
                        : JsonResponse(HttpStatusCode.OK,
                            "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                }
                AssertEqual(true, recovered, "failed refresh cannot proceed to identity reads");
                return JsonResponse(HttpStatusCode.OK,
                    "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
            oauth.SessionInvalidated += (_, _) => invalidations++;
            using var account = new AccountBridgeRuntime(new ScmAccountBridgeHost(oauth,
                new ScmProfileCacheStore(), settings.EnvironmentName, () => null));
            var generation = account.Generation;
            var first = await ReadCurrent(account, "refresh-transient");
            AssertEqual(BridgeResponseStatuses.Ok, first.Response.Status, "temporary refresh response");
            AssertEqual("credentialTemporarilyUnavailable", first.Response.Payload.GetProperty("state").GetString(),
                "ambiguous refresh failure must not ask for authorization");
            AssertEqual(ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable, oauth.LastSessionRestoreOutcome,
                "temporary refresh outcome");
            AssertEqual("synthetic-refresh", vault.LoadRefreshToken(accountKey), "temporary failure retains credential");
            AssertEqual(accountKey, vault.LoadActiveAccountKey(), "temporary failure retains active selection");
            AssertEqual(1, calls, "one refresh request per restore attempt");
            AssertEqual(0, invalidations, "temporary refresh cannot invalidate session");
            AssertEqual(generation, account.Generation, "temporary refresh preserves generation");
            if (status == HttpStatusCode.Unauthorized)
            {
                var diagnostic = File.ReadLines(Path.Combine(HostDataRoot.CurrentRoot, "scm-auth-diagnostics.log"))
                    .Last(line => line.Contains("step=refresh-token outcome=http-error", StringComparison.Ordinal));
                var expectedError = body == "{\"error\":\"invalid_client\"}" ? "invalid_client" : "unparsed";
                AssertEqual(true, diagnostic.EndsWith("status=401 error=" + expectedError, StringComparison.Ordinal),
                    "401 diagnostic uses only the fixed error allowlist");
            }
            recovered = true;
            var retry = await ReadCurrent(account, "refresh-recovered");
            AssertEqual("signedIn", retry.Response.Payload.GetProperty("state").GetString(), "200 restores without login");
            AssertEqual(2, calls, "recovery uses one existing refresh attempt");
            AssertEqual("synthetic-next", vault.LoadRefreshToken(accountKey), "successful recovery rotates credential");
            Console.WriteLine("PASS transient refresh recovery: " + (int)status);
        }
        await CredentialVersionRegression();
    }
}
