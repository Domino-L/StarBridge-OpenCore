using System.Net;
using System.Text;
using StarBridge.HostRuntime.Auth;

internal static class ProfileWriteSessionTests
{
    internal static async Task Run()
    {
        var options = new ScmOAuthOptions("fixture", new("https://example.invalid/"),
            new("https://example.invalid/"), new("https://example.invalid/"),
            "starbridge-desktop", "starbridge-api", "openid profile.read profile.write offline_access", "/callback");
        var session = new ScmOAuthSession("fixture", "synthetic-owner", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "profile.write"]);
        var calls = 0;
        var vault = new Vault();
        var http = new Handler(_ => { calls++; throw new InvalidOperationException("Unexpected HTTP for active session"); });
        var client = new OAuthPkceClient(new ScmHttpClient(http), vault, options);
        for (var i = 0; i < 3; i++)
            Check(ReferenceEquals(session, await client.AuthorizeProfileWriteAsync(session, default)), "Repeated writes must reuse login");
        Check(calls == 0 && vault.Saves == 0, "Active writes must not exchange or persist temporary grants");
        await Reject<ScmApiAuthenticationException>(() => client.AuthorizeProfileWriteAsync(
            session with { Capabilities = ["profile.read"] }, default));
        await Reject<OperationCanceledException>(() => client.AuthorizeProfileWriteAsync(session, new CancellationToken(true)));

        // Expired login uses the existing refresh path, including after client reconstruction.
        foreach (var granted in new[] { true, false })
        {
            var refreshes = 0;
            var refreshingVault = new Vault();
            refreshingVault.SaveRefreshToken("fixture:synthetic-owner", "synthetic-refresh");
            var refreshing = new OAuthPkceClient(new ScmHttpClient(new Handler(request =>
            {
                if (request.RequestUri == options.TokenEndpoint)
                {
                    refreshes++;
                    return Json("{\"access_token\":\"synthetic-renewed\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
                }
                return Json("{\"subject\":\"synthetic-owner\",\"displayName\":\"Synthetic\",\"capabilities\":[\"profile.read\"" +
                    (granted ? ",\"profile.write\"" : "") + "]}");
            })), refreshingVault, options);
            var expired = session with { ExpiresAt = DateTimeOffset.UtcNow.AddMinutes(-1) };
            if (granted)
            {
                var renewed = await refreshing.AuthorizeProfileWriteAsync(expired, default);
                Check(renewed.AccessToken == "synthetic-renewed", "Write must use renewed token");
                Check(ReferenceEquals(renewed, await refreshing.AuthorizeProfileWriteAsync(expired, default)), "Next write must reuse renewed session");
                await Reject<ScmApiAuthenticationException>(() => refreshing.AuthorizeProfileWriteAsync(
                    expired with { Subject = "other-owner" }, default));
                await Reject<ScmApiAuthenticationException>(() => refreshing.AuthorizeProfileWriteAsync(
                    expired with { AuthorityId = "other-authority" }, default));
            }
            else
                await Reject<ScmApiAuthenticationException>(() => refreshing.AuthorizeProfileWriteAsync(expired, default));
            Check(refreshes == 1, "Refresh must not loop or request a browser grant");
        }
        Console.WriteLine("PASS profile write daily session: reuse, missing grant, cancellation, refresh, revoked grant, owner and authority isolation");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Reject<T>(Func<Task<ScmOAuthSession>> action) where T : Exception
    {
        try { await action(); } catch (T) { return; }
        throw new InvalidOperationException("Expected " + typeof(T).Name);
    }
    private static HttpResponseMessage Json(string text) => new(HttpStatusCode.OK)
        { Content = new StringContent(text, Encoding.UTF8, "application/json") };
    private sealed class Handler(Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { token.ThrowIfCancellationRequested(); return Task.FromResult(respond(request)); }
    }
    private sealed class Vault : ITokenVault
    {
        private string? key;
        private string? value;
        internal int Saves;
        public void SaveRefreshToken(string accountKey, string refreshToken) { key = accountKey; value = refreshToken; Saves++; }
        public string? LoadActiveAccountKey() => key;
        public string? LoadRefreshToken(string accountKey) => accountKey == key ? value : null;
        public void DeleteRefreshToken(string accountKey) { if (key == accountKey) { key = null; value = null; } }
    }
}
