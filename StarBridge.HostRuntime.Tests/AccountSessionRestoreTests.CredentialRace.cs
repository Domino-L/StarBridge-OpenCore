using System.Net;
using StarBridge.HostRuntime.Auth;

internal static partial class AccountSessionRestoreTests
{
    internal static async Task CredentialRace()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        var key = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(key, "synthetic-refresh");
        var refreshes = 0;
        var thirdIdentity = Signal();
        var releaseIdentity = Signal();
        using var handler = new RaceHandler(async (request, token) => {
            if (request.RequestUri == options.TokenEndpoint)
                return JsonResponse(HttpStatusCode.OK, "{\"access_token\":\"synthetic-access-" + (++refreshes) +
                    "\",\"refresh_token\":\"synthetic-next-" + refreshes + "\",\"expires_in\":3600}");
            if (refreshes == 3)
            {
                thirdIdentity.TrySetResult();
                await releaseIdentity.Task.WaitAsync(token);
            }
            return JsonResponse(HttpStatusCode.OK, "{\"subject\":\"subject-1\",\"capabilities\":[\"profile.read\"]}");
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var retryEntered = Signal();
        var releaseOld401 = Signal();
        var calls = 0;
        var first = oauth.SendResourceRequestAsync(initial, async (_, token) => {
            if (++calls == 1) throw new ScmApiAuthenticationException("Synthetic first 401");
            if (calls == 2)
            {
                retryEntered.TrySetResult();
                await releaseOld401.Task.WaitAsync(token);
                throw new ScmApiAuthenticationException("Synthetic delayed retry 401");
            }
            return true;
        }, default);
        await retryEntered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var secondCalls = 0;
        var second = oauth.SendResourceRequestAsync(initial, (_, _) => ++secondCalls == 1
            ? Task.FromException<bool>(new ScmApiAuthenticationException("Synthetic other resource 401"))
            : Task.FromResult(true), default);
        await thirdIdentity.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var background = oauth.TryRestoreSessionAsync(default);
        releaseIdentity.TrySetResult();
        await second.WaitAsync(TimeSpan.FromSeconds(5));
        await background.WaitAsync(TimeSpan.FromSeconds(5));
        releaseOld401.TrySetResult();
        Exception? failure = null;
        try { await first.WaitAsync(TimeSpan.FromSeconds(5)); }
        catch (Exception error) { failure = error; }
        Console.WriteLine($"CX-L07 race refreshes={refreshes} deletes={vault.Deletes} retained={vault.LoadActiveAccountKey() is not null}");
        AssertEqual(0, vault.Deletes, "old retry 401 must not delete a newer credential");
        AssertEqual<Exception?>(null, failure, "old retry must recover using current session");
        AssertEqual(3, refreshes, "late retry must reuse the background result");
        AssertEqual(key, vault.LoadActiveAccountKey(), "current credential remains selected");
    }

    private static TaskCompletionSource Signal() => new(TaskCreationOptions.RunContinuationsAsynchronously);

    private sealed class RaceHandler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send)
        : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) => send(request, token);
    }

    private sealed class RaceVault : ITokenVault
    {
        private readonly Dictionary<string, string> _tokens = new();
        private string? _active;
        internal int Deletes { get; private set; }
        public void SaveRefreshToken(string key, string value) { _tokens[key] = value; _active = key; }
        public string? LoadRefreshToken(string key) => _tokens.GetValueOrDefault(key);
        public string? LoadActiveAccountKey() => _active;
        public void DeleteRefreshToken(string key) { Deletes++; _tokens.Remove(key); if (_active == key) _active = null; }
    }
}
