using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class PolishRsiRefreshTests
{
    internal static async Task Run()
    {
        foreach (var (body, state, minutes) in new (string, string, long?)[] {
            ("{\"success\":true,\"fromCache\":false}", "requested", null),
            ("{\"success\":true,\"fromCache\":true}", "cached", null),
            ("{\"success\":true,\"fromCache\":\"true\"}", "unavailable", null),
            ("{\"success\":false,\"remainingMinutes\":17}", "rateLimited", 17),
            ("{\"success\":false}", "globalBusy", null),
            ("{\"success\":false,\"message\":\"请先完成账户验证\"}", "verificationRequired", null),
            ("{\"success\":false,\"message\":\"您的RSI账户状态异常（可能已改名），请重新进行账户验证\"}", "verificationRequired", null),
            ("{\"success\":false,\"message\":\"private-upstream-text\"}", "unavailable", null),
            ("{\"success\":false,\"remainingMinutes\":-1}", "unavailable", null),
            ("{\"success\":false,\"remainingMinutes\":\"17\"}", "unavailable", null),
            ("{}", "unavailable", null)
        }) {
            using var json = JsonDocument.Parse("{\"code\":0,\"data\":" + body + "}");
            var result = OAuthPkceClient.ProjectRsiRefresh(json.RootElement);
            Check(result.State == state && result.RemainingMinutes == minutes, "Sanitized outcome " + state);
            Check(!JsonSerializer.Serialize(result).Contains("private-upstream-text"), "Raw messages stay out of Bridge");
        }
        foreach (var status in new[] { HttpStatusCode.OK, HttpStatusCode.Unauthorized,
            HttpStatusCode.TooManyRequests, HttpStatusCode.ServiceUnavailable }) {
            using var handler = new Handler(status);
            var options = new ScmOAuthOptions("fixture", new("https://auth.invalid/"),
                new("https://resource.invalid/"), new("https://relay.invalid/"), "fixture-client", "fixture-api", "profile.read", "/callback");
            var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options);
            var session = new ScmOAuthSession("fixture", "synthetic-owner", "Fixture", "synthetic-access",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            var outcome = await client.RefreshRsiDataAsync(session, () => true, default);
            Check(handler.Calls == 1, "Every click issues exactly one POST, including 401 and service failure");
            Check(outcome.Result.State == (status == HttpStatusCode.OK ? "requested" :
                status == HttpStatusCode.Unauthorized ? "signInRequired" :
                status == HttpStatusCode.TooManyRequests ? "globalBusy" : "unavailable"), "HTTP mapping");
            await client.RefreshRsiDataAsync(session, () => false, default).ContinueWith(t => {
                Check(t.IsCanceled || t.IsFaulted, "Retired identity fails closed");
            });
            Check(handler.Calls == 1, "Retired identity never sends");
        }
        using (var handler = new Handler(HttpStatusCode.OK)) {
            var options = new ScmOAuthOptions("fixture", new("https://auth.invalid/"),
                new("https://resource.invalid/"), new("https://relay.invalid/"), "fixture-client", "fixture-api", "profile.read", "/callback");
            var session = new ScmOAuthSession("fixture", "synthetic-owner", "Fixture", "synthetic-access",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            using var host = new ScmAccountBridgeHost(new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options),
                new ScmProfileCacheStore(Path.Combine(Path.GetTempPath(), "polish-rsi-cache")), "fixture", () => null,
                initialSession: session, initialGeneration: 1);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var owner = host.CurrentContext!;
            var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request("account.refreshRsiData", "refresh", 1,
                new { schemaVersion = 1 }, owner));
            Check(result.Response.Status == "ok" && result.Response.Payload.GetProperty("state").GetString() == "requested",
                "Actual Bridge dispatcher routes the command to the authenticated owner");
            var invalid = await dispatcher.DispatchAsync(BridgeEnvelope.Request("account.refreshRsiData", "bad", 1,
                new { schemaVersion = 1, userId = 42 }, owner));
            Check(invalid.Response.Status == "error" && handler.Calls == 1,
                "The caller cannot select a different SCM member or send an unrecognized payload");
        }
        Console.WriteLine("PASS CX-POLISH-B RSI refresh: 11 projections, 4 single-send/status cases, identity fences and 2 Bridge cases");
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    private sealed class Handler(HttpStatusCode status) : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Check(request.Method == HttpMethod.Post && request.RequestUri!.AbsolutePath ==
                "/app-api/member/user/refresh-rsi-data", "Resource route and POST");
            return Task.FromResult(new HttpResponseMessage(status) {
                Content = new StringContent("{\"code\":0,\"data\":{\"success\":true,\"fromCache\":false}}") });
        }
    }
    private sealed class Vault : ITokenVault
    {
        public void SaveRefreshToken(string a, string b) => throw new Exception("Unexpected vault write");
        public string? LoadRefreshToken(string a) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string a) => throw new Exception("Unexpected vault delete");
    }
}
