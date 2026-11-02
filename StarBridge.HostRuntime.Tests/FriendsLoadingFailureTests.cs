using System.Net;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Friends;

internal static class FriendsLoadingFailureTests
{
    internal static async Task Run()
    {
        foreach (var scm in new[] { false, true })
        foreach (var (status, code, retryable) in new[] {
            (HttpStatusCode.Forbidden, "friends.forbidden", false),
            (HttpStatusCode.Redirect, "friends.read_unavailable", false),
            ((HttpStatusCode)799, "friends.read_unavailable", false),
            (HttpStatusCode.ServiceUnavailable, "friends.read_transient", true),
            (HttpStatusCode.TooManyRequests, "friends.read_transient", true) })
        {
            using var transport = new Handler((_, _) => Task.FromResult(new HttpResponseMessage(status)
                { Content = new StringContent("{}") }));
            using var reader = new FriendsReader(new("https://relay.example.invalid/"), transport);
            var oauth = new OAuthPkceClient(new ScmHttpClient(transport), new Vault(), ScmOAuthOptions.CreateDefault());
            try
            {
                if (scm) await oauth.SearchParticipantsAsync(new("synthetic", "owner", "Synthetic", "test-token",
                    DateTimeOffset.MaxValue, ["profile.read"]), "test", default);
                else await reader.ReadAsync("test-token", null, default);
                throw new InvalidOperationException("An unsuccessful response was accepted");
            }
            catch (AccountBridgeHostException error)
            {
                if (error.Code != code || error.Retryable != retryable)
                    throw new InvalidOperationException($"{scm}/{(int)status}: expected {code}/{retryable}, got {error.Code}/{error.Retryable}");
            }
        }
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> reply) : HttpMessageHandler
    { protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => reply(request, token); }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No token write permitted");
        public void DeleteRefreshToken(string key) => throw new InvalidOperationException("No token deletion permitted");
    }
}
