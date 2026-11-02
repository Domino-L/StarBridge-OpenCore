using System.Net;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task UnauthorizedIdentityProjectsReauthorization()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = options.AuthorityId + ":synthetic-identity-denied";
        var memory = new MemoryTokenVault();
        memory.SaveRefreshToken(accountKey, "synthetic-original");
        var handler = new ScriptedHandler(request => request.RequestUri == options.TokenEndpoint
            ? JsonResponse(HttpStatusCode.OK,
                "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}")
            : JsonResponse(HttpStatusCode.Unauthorized, "{\"message\":\"Synthetic identity denied\"}"));
        using (var runtime = CreateAccountRuntime(settings, options, memory, handler))
        {
            var response = (await ReadCurrent(runtime, "synthetic-identity-401")).Response;
            AssertEqual("ok", response.Status, "identity 401 is a bounded account state");
            AssertEqual("credentialTemporarilyUnavailable", response.Payload.GetProperty("state").GetString(),
                "identity resource 401 cannot reject refresh credential");
            AssertEqual<BridgeAccountContext?>(null, response.AccountContext, "identity 401 cannot expose an authenticated context");
            AssertEqual("synthetic-rotated", memory.LoadRefreshToken(accountKey), "identity 401 retains the actual rotated credential");
        }

        var root = System.IO.Path.Combine(System.IO.Path.GetTempPath(), "StarBridge-cold-401-writer-" + Guid.NewGuid().ToString("N"));
        System.IO.Directory.CreateDirectory(root);
        System.IO.FileStream? held = null;
        try
        {
            var path = System.IO.Path.Combine(root, "vault.json");
            var vault = new WindowsTokenVault(path);
            vault.SaveRefreshToken(accountKey, "synthetic-original");
            byte[]? rotatedBytes = null;
            var busy = true;
            var windowsHandler = new ScriptedHandler(request =>
            {
                if (request.RequestUri == options.TokenEndpoint)
                    return JsonResponse(HttpStatusCode.OK,
                        "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-rotated\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                if (busy)
                {
                    rotatedBytes = System.IO.File.ReadAllBytes(path);
                    held = new(path + ".lock", System.IO.FileMode.Open, System.IO.FileAccess.ReadWrite, System.IO.FileShare.None);
                }
                return JsonResponse(HttpStatusCode.Unauthorized, "{\"message\":\"Synthetic identity denied\"}");
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(windowsHandler), vault, options);
            var retired = new List<(string Authority, string Subject)>();
            oauth.StoredCredentialRejected += (authority, subject) => retired.Add((authority, subject));
            var temporary = false;
            try { await oauth.TryRestoreSessionAsync(default); }
            catch (ScmRefreshTemporarilyUnavailableException) { temporary = true; }
            AssertEqual(true, temporary, "identity denial stays temporary without attempting deletion");
            AssertEqual(true, rotatedBytes is not null && rotatedBytes.SequenceEqual(System.IO.File.ReadAllBytes(path)),
                "failed rejection changed the committed rotated credential");
            AssertEqual(0, retired.Count, "unverified current credential version must not retire a proof");
            AssertEqual(true, oauth.ReadOfflineDisplayOwner() is not null,
                "retained exact credential may supply outage display");
            AssertEqual(true, held is not null, "synthetic writer lease was not acquired");
            held?.Dispose(); held = null; busy = false;
            try { await oauth.TryRestoreSessionAsync(default); throw new InvalidOperationException("Expected temporary identity denial"); }
            catch (ScmRefreshTemporarilyUnavailableException) { }
            AssertEqual(ScmSessionRestoreOutcome.CredentialTemporarilyUnavailable, oauth.LastSessionRestoreOutcome, "retry temporary state");
            AssertEqual("synthetic-rotated", vault.LoadRefreshToken(accountKey), "retry must retain the selected credential");
            AssertEqual(0, retired.Count, "identity denial cannot retire original proof");
        }
        finally
        {
            held?.Dispose();
            System.IO.Directory.Delete(root, recursive: true);
        }
        Console.WriteLine("PASS cold identity 401 and busy writer preserve rotated credentials and remain retryable");
    }
}
