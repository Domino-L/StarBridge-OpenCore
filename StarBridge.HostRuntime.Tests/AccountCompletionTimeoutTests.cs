using StarBridge.HostRuntime.Auth;
using System.Net;
using System.Text;

internal static class AccountCompletionTimeoutTests
{
    private static readonly ScmOAuthOptions Options = new(
        "synthetic", new Uri("https://web.example.invalid/"),
        new Uri("https://auth.example.invalid/"), new Uri("https://resource.example.invalid/"),
        "synthetic-client", "starbridge-api", "openid profile.read", "/oauth/callback");

    internal static async Task SlowCompletionCanFinish()
    {
        await Task.WhenAll(new[] { "token", "identity", "register", "status" }.Select(Run));

        static async Task Run(string slowStep)
        {
            var calls = new Dictionary<string, int>();
            var handler = new SyntheticHandler(async (request, cancellation) =>
            {
                var step = request.RequestUri == Options.TokenEndpoint ? "token"
                    : request.RequestUri == Options.MeEndpoint ? "identity"
                    : request.RequestUri == Options.DeviceRegisterEndpoint ? "register"
                    : request.RequestUri == Options.DeviceStatusEndpoint ? "status"
                    : throw new InvalidOperationException("Unexpected completion endpoint.");
                calls[step] = calls.GetValueOrDefault(step) + 1;
                if (step == slowStep) await Task.Delay(TimeSpan.FromSeconds(16), cancellation);
                return Json(step switch
                {
                    "token" => "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}",
                    "identity" => "{\"subject\":\"owner\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}",
                    _ => "{\"trusted\":true}"
                });
            });
            var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new MemoryVault(), Options);
            try
            {
                if (slowStep is "token" or "identity")
                {
                    var restored = await oauth.TryRestoreSessionAsync(CancellationToken.None);
                    Equal("owner", restored?.Subject, slowStep + " lost a valid completion");
                }
                else
                {
                    var session = new ScmOAuthSession("synthetic", "owner", "Synthetic Pilot",
                        "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
                    var status = slowStep == "register"
                        ? await oauth.RegisterDesktopDeviceAsync(session, "synthetic-device", CancellationToken.None)
                        : await oauth.GetDesktopDeviceStatusAsync(session, "synthetic-device", CancellationToken.None);
                    Equal(true, status.Trusted, slowStep + " was not confirmed");
                }
            }
            catch (OperationCanceledException)
            {
                throw new InvalidOperationException(slowStep + " discarded a valid 16-second response.");
            }
            Equal(1, calls[slowStep], slowStep + " was automatically repeated");
        }
    }

    internal static async Task CancellationAndHttpDeadlineStillStop()
    {
        var calls = 0;
        var handler = new SyntheticHandler(async (_, cancellation) =>
        {
            Interlocked.Increment(ref calls);
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellation);
            throw new InvalidOperationException("Unreachable response.");
        });
        var http = new ScmHttpClient(handler);
        using (var request = new HttpRequestMessage(HttpMethod.Get, Options.MeEndpoint))
        {
            try
            {
                await http.SendAsync(request, requestTimeout: TimeSpan.FromMilliseconds(30));
                throw new InvalidOperationException("HTTP deadline was ignored.");
            }
            catch (OperationCanceledException) { }
        }
        var oauth = new OAuthPkceClient(http, new MemoryVault(), Options);
        var session = new ScmOAuthSession("synthetic", "owner", "Synthetic Pilot",
            "synthetic-access", DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        using var cancel = new CancellationTokenSource(TimeSpan.FromMilliseconds(30));
        try
        {
            await oauth.RegisterDesktopDeviceAsync(session, "synthetic-device", cancel.Token);
            throw new InvalidOperationException("Caller cancellation was ignored.");
        }
        catch (OperationCanceledException) { }
        Equal(2, calls, "Cancellation replayed a request");
    }

    private static HttpResponseMessage Json(string json) => new(HttpStatusCode.OK)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private static void Equal<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual)) throw new InvalidOperationException(message);
    }

    private sealed class SyntheticHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            => send(request, cancellationToken);
    }

    private sealed class MemoryVault : ITokenVault
    {
        private string? _refresh = "synthetic-refresh";
        public string? LoadActiveAccountKey() => _refresh is null ? null : "synthetic:owner";
        public string? LoadRefreshToken(string accountKey) => _refresh;
        public void SaveRefreshToken(string accountKey, string refreshToken) => _refresh = refreshToken;
        public void DeleteRefreshToken(string accountKey) => _refresh = null;
    }
}
