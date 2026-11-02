using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;

internal static class OverlayEntitlementRefreshTests
{
    internal static async Task Verify()
    {
        var previousRoot = HostDataRoot.CurrentRoot;
        var isolatedRoot = Path.Combine(Path.GetTempPath(), "starbridge-entitlement-refresh-" + Guid.NewGuid().ToString("N"));
        HostDataRoot.UsePreparedRoot(isolatedRoot);
        try
        {
            foreach (var mode in new[] { "granted", "revoked", "expired", "missing", "mismatch", "unavailable", "cancelled", "denied" })
            {
                using var transport = new Transport(mode);
                var endpoint = new Uri("https://example.invalid/");
                var options = new ScmOAuthOptions("synthetic-authority", endpoint, endpoint, endpoint,
                    "synthetic-client", "synthetic-resource", "openid profile.read", "/callback");
                var vault = new Vault();
                var oauth = new OAuthPkceClient(new ScmHttpClient(transport), vault, options);
                var initial = await oauth.TryRestoreSessionAsync(default) ?? throw new Exception("Missing synthetic session");
                Check(transport.BootstrapReads == 0, "Cold restoration must not duplicate the Host bootstrap");
                var bootstrap = await oauth.LoadBootstrapAsync(initial, default);
                Check(bootstrap.ActiveSession.ActiveOverlayEntitlements.Contains("overlay.skin.night-shadow"), "Initial permanent qualification");
                Check(bootstrap.ActiveSession.ActiveOverlayEntitlements.Contains("overlay.skin.verdict"), "Initial temporary qualification");
                using var cancellation = new CancellationTokenSource();
                transport.CancelRefresh = mode == "cancelled" ? cancellation.Cancel : null;
                try
                {
                    var active = await oauth.RefreshIdentityAsync(bootstrap.ActiveSession, cancellation.Token);
                    Check(mode is not ("mismatch" or "unavailable" or "cancelled" or "denied"), "Failed authoritative refresh must not publish success");
                    Check(active.Subject == bootstrap.ActiveSession.Subject && active.AuthorityId == bootstrap.ActiveSession.AuthorityId,
                        "Refreshed session must remain the same owner");
                    Check(active.ActiveOverlayEntitlements.Contains("overlay.skin.night-shadow") == (mode is "granted" or "expired"),
                        "Permanent qualification must follow fresh authority, not an empty token response or stale cached grant");
                    Check(active.ActiveOverlayEntitlements.Contains("overlay.skin.verdict") == (mode == "granted"),
                        "Temporary qualification must retain its actual expiry");
                    Check(transport.TokenRefreshes >= 3 && transport.BootstrapReads == 2, "Rotation must re-read bootstrap exactly once");
                }
                catch (InvalidOperationException) when (mode == "mismatch") { }
                catch (ScmApiUnavailableException) when (mode == "unavailable") { }
                catch (OperationCanceledException) when (mode == "cancelled" && cancellation.IsCancellationRequested) { }
                catch (ScmRefreshTemporarilyUnavailableException) when (mode == "denied") { }
                Check(vault.Deletes == 0,
                    "Resource qualification denial cannot delete the refresh credential");
                if (mode == "unavailable")
                {
                    transport.Recovered = true;
                    var recovered = await oauth.RefreshIdentityAsync(bootstrap.ActiveSession, default);
                    Check(recovered.ActiveOverlayEntitlements.Contains("overlay.skin.night-shadow"),
                        "A transient qualification failure must be recoverable from the original account authority");
                }
                Console.WriteLine("PASS token refresh qualification " + mode);
            }
        }
        finally
        {
            HostDataRoot.UsePreparedRoot(previousRoot);
            if (Directory.Exists(isolatedRoot)) Directory.Delete(isolatedRoot, recursive: true);
        }
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new Exception(message);
    }

    private sealed class Vault : ITokenVault
    {
        private string token = "synthetic-refresh";
        internal int Deletes;
        public void SaveRefreshToken(string accountKey, string refreshToken) => token = refreshToken;
        public string? LoadRefreshToken(string accountKey) => token;
        public string? LoadActiveAccountKey() => "synthetic-authority:synthetic-subject";
        public void DeleteRefreshToken(string accountKey) => Deletes++;
    }

    private sealed class Transport(string mode) : HttpMessageHandler
    {
        internal int TokenRefreshes, BootstrapReads;
        internal Action? CancelRefresh;
        internal bool Recovered;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            token.ThrowIfCancellationRequested();
            if (request.RequestUri?.Host != "example.invalid") throw new Exception("Unexpected non-synthetic request");
            object body;
            if (request.RequestUri.AbsolutePath == "/open-api/oauth2/token")
                body = new { access_token = "synthetic-access-" + (++TokenRefreshes), refresh_token = "synthetic-next",
                    // Exercise near-expiry rotation, then issue the normal
                    // long-lived token so nested resource reads do not rotate again.
                    token_type = "Bearer", expires_in = TokenRefreshes < 3 ? 30 : 3600 };
            else if (request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/me")
                body = new { subject = "synthetic-subject", displayName = "Synthetic Pilot", capabilities = new[] { "profile.read" } };
            else if (request.RequestUri.AbsolutePath == "/app-api/starbridge/v1/bootstrap")
            {
                var refreshing = ++BootstrapReads > 1;
                if (refreshing && mode == "unavailable" && !Recovered)
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
                if (refreshing && mode == "denied")
                    return Task.FromResult(new HttpResponseMessage(HttpStatusCode.Unauthorized));
                if (refreshing && CancelRefresh is { } cancel)
                {
                    cancel();
                    token.ThrowIfCancellationRequested();
                }
                var payload = new Dictionary<string, object?>
                {
                    ["profile"] = new { subject = "synthetic-subject", displayName = "Synthetic Pilot", gameIdentityVerified = false },
                    ["identityLink"] = new { linked = true, legacyAccountId = "synthetic-original" },
                    ["fleets"] = Array.Empty<object>(), ["primaryFleet"] = null,
                    ["unreadNotifications"] = 0, ["blacklistVersion"] = 1,
                    ["resourceVersions"] = new Dictionary<string, long>(), ["serverTime"] = DateTimeOffset.UtcNow,
                    ["capabilities"] = new[] { "profile.read" }
                };
                if (!refreshing || mode != "missing")
                    payload["overlayEntitlements"] = new
                    {
                        status = "ready", accountId = refreshing && mode == "mismatch" ? "synthetic-other" : "synthetic-original",
                        entitlements = refreshing && mode == "revoked" ? Array.Empty<string>() : new[] { "overlay.skin.night-shadow" },
                        temporaryEntitlements = refreshing && mode == "revoked" ? Array.Empty<object>() : new object[] {
                            new { entitlement = "overlay.skin.verdict", expiresAt = refreshing && mode == "expired"
                                ? DateTimeOffset.UtcNow.AddSeconds(-1) : DateTimeOffset.UtcNow.AddHours(1) } },
                        observedAt = DateTimeOffset.UtcNow
                    };
                body = payload;
            }
            else throw new Exception("Unexpected synthetic endpoint");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            {
                Content = new StringContent(JsonSerializer.Serialize(body), Encoding.UTF8, "application/json")
            });
        }
    }
}
