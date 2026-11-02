using System.Net;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    // 2026-10-21 (0.7.1 sign-out at 16:25:05): a refresh reached the server, which
    // rotated the token, but the Host exited before the reply arrived. The next
    // process sent the consumed token, got invalid_grant and deleted the
    // credential. That deletion is unavoidable - the server no longer accepts the
    // token - but every later start showed a plain "signed out" with no reason.
    // The rejection now leaves a credential-free marker so later starts ask the
    // user to sign in again; a successful sign-in or restore clears it.
    internal static async Task RejectedCredentialAsksToSignInAgainAfterRestart()
    {
        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-expired-session-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        try
        {
            var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
            var key = options.AuthorityId + ":synthetic-owner";
            var path = System.IO.Path.Combine(root, "vault.json");
            new WindowsTokenVault(path).SaveRefreshToken(key, "synthetic-refresh-1");

            // A server that accepts each refresh token once and rotates it.
            var accepted = "synthetic-refresh-1";
            var rotations = 0;
            var replyLost = true;
            var identityAvailable = true;
            using var lost = new CancellationTokenSource();
            var handler = new ScriptedHandler(request =>
            {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    var body = request.Content!.ReadAsStringAsync().GetAwaiter().GetResult();
                    if (!body.Contains("refresh_token=" + accepted, StringComparison.Ordinal))
                        return JsonResponse(HttpStatusCode.BadRequest, "{\"error\":\"invalid_grant\"}");
                    accepted = $"synthetic-refresh-{++rotations + 1}";
                    if (replyLost)
                    {
                        // The server rotated; the process exits before the reply.
                        lost.Cancel();
                        throw new TaskCanceledException("Synthetic process exit during refresh");
                    }
                    return JsonResponse(HttpStatusCode.OK,
                        $"{{\"access_token\":\"synthetic-access\",\"refresh_token\":\"{accepted}\",\"token_type\":\"Bearer\",\"expires_in\":3600}}");
                }
                return identityAvailable
                    ? JsonResponse(HttpStatusCode.OK, "{\"subject\":\"synthetic-owner\",\"displayName\":\"Synthetic\",\"capabilities\":[\"profile.read\"]}")
                    : JsonResponse(HttpStatusCode.BadGateway, "{\"message\":\"Synthetic deploy\"}");
            });

            var exited = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
            try { await exited.TryRestoreSessionAsync(lost.Token); throw new Exception("Expected the lost refresh reply"); }
            catch (OperationCanceledException) { }
            AssertEqual("synthetic-refresh-1", new WindowsTokenVault(path).LoadRefreshToken(key),
                "the vault still holds the token the server already consumed");

            replyLost = false;
            var next = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
            AssertEqual<ScmOAuthSession?>(null, await next.TryRestoreSessionAsync(default), "a consumed token cannot restore");
            AssertEqual(ScmSessionRestoreOutcome.ReauthorizationRequired, next.LastSessionRestoreOutcome, "rejection in this process");
            AssertEqual<string?>(null, new WindowsTokenVault(path).LoadRefreshToken(key), "the rejected credential is retired");

            var restarted = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
            AssertEqual<ScmOAuthSession?>(null, await restarted.TryRestoreSessionAsync(default), "no credential after restart");
            AssertEqual(ScmSessionRestoreOutcome.ReauthorizationRequired, restarted.LastSessionRestoreOutcome,
                "After a rejected credential a restarted client shows a plain sign-out instead of asking to sign in again.");
            var marker = System.IO.Directory.GetFiles(root).Select(System.IO.Path.GetFileName).Single(n => n!.Contains("expired"));
            var text = System.IO.File.ReadAllText(System.IO.Path.Combine(root, marker!));
            AssertEqual(false, text.Contains("synthetic-owner") || text.Contains("synthetic-refresh") || text.Contains("synthetic-access"),
                "the marker carries no account, refresh token or access token");

            // A new sign-in (here: a stored credential that restores) clears it.
            new WindowsTokenVault(path).SaveRefreshToken(key, accepted);
            var signedIn = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
            AssertEqual("synthetic-owner", (await signedIn.TryRestoreSessionAsync(default))?.Subject, "the new credential restores");
            new WindowsTokenVault(path).DeleteRefreshToken(key);
            var afterSignIn = new OAuthPkceClient(new ScmHttpClient(handler), new WindowsTokenVault(path), options);
            await afterSignIn.TryRestoreSessionAsync(default);
            AssertEqual(ScmSessionRestoreOutcome.NoStoredCredential, afterSignIn.LastSessionRestoreOutcome,
                "a successful restore clears the expired-session marker");
            Console.WriteLine("PASS a rejected credential asks to sign in again after restart; the marker holds no secrets and clears on sign-in");
        }
        finally { System.IO.Directory.Delete(root, recursive: true); }
    }
}
