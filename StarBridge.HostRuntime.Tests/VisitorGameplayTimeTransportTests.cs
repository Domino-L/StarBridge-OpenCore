using System.Net;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Presence;

internal static class VisitorGameplayTimeTransportTests
{
    private static readonly ScmOAuthOptions Options = new("test", new Uri("https://web.example.invalid/"),
        new Uri("https://auth.example.invalid/"), new Uri("https://resource.example.invalid/"),
        "test-client", "starbridge-api", "openid profile.write", "/callback");
    private const string Path = "/app-api/starbridge/v1/personal-profile/gameplay-time";

    internal static async Task Run()
    {
        var replies = new Queue<HttpResponseMessage>(
        [
            Response(HttpStatusCode.OK, """{"schemaVersion":1,"updatedAt":"2026-01-01T00:00:00Z"}"""),
            Response(HttpStatusCode.OK, """{"schemaVersion":1,"updatedAt":"2026-01-01T00:00:00Z"}"""),
            Response(HttpStatusCode.NotFound, "{}"),
            Response(HttpStatusCode.BadRequest, """{"schemaVersion":1,"error":"gameplay_time.invalid","field":"sourceRevision","value":"ignored"}"""),
            Response(HttpStatusCode.BadRequest, """{"schemaVersion":1,"error":"gameplay_time.invalid","field":"unexpected user-supplied text"}"""),
            Response(HttpStatusCode.Conflict, """{"schemaVersion":1,"error":"gameplay_time.stale_revision","sourceRevision":8}"""),
            RateLimited(),
            Response(HttpStatusCode.ServiceUnavailable, "{}"),
        ]);
        var requests = new List<JsonElement>();
        using var handler = new Handler(async (request, token) =>
        {
            Check(request.Method == HttpMethod.Put && request.RequestUri == new Uri(Options.ResourceServerBaseUri, Path) &&
                request.Content?.Headers.ContentType?.MediaType == "application/json", "only the HK resource PUT is used");
            using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
            requests.Add(body.RootElement.Clone());
            if (replies.Count == 0) throw new HttpRequestException("synthetic network failure");
            return replies.Dequeue();
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), Options);
        var session = Session(["profile.write"]);
        var adopted = 0;
        async Task<VisitorGameplayTimeResult> Write(long seconds, long? revision)
        {
            var (result, active) = await oauth.WriteVisitorGameplayTimeAsync(session, new(seconds, revision), default,
                ready => { Check(ready == session, "only the bound owner can send"); adopted++; });
            Check(active == session, "return the active session to the Host");
            return result;
        }

        Check((await Write(3600, 7)).Outcome == VisitorGameplayTimeOutcome.Ok, "200 classified");
        Check((await Write(1200, null)).Outcome == VisitorGameplayTimeOutcome.Ok, "200 accepts unversioned local value");
        Check(requests[0].EnumerateObject().Select(p => p.Name).SequenceEqual(["schemaVersion", "playTimeSeconds", "sourceRevision"]) &&
            requests[0].GetProperty("schemaVersion").GetInt32() == 1 && requests[0].GetProperty("playTimeSeconds").GetInt64() == 3600 &&
            requests[0].GetProperty("sourceRevision").GetInt64() == 7, "versioned request has exactly the three contract keys and values");
        Check(requests[1].EnumerateObject().Select(p => p.Name).SequenceEqual(["schemaVersion", "playTimeSeconds"]) &&
            requests[1].GetProperty("schemaVersion").GetInt32() == 1 && requests[1].GetProperty("playTimeSeconds").GetInt64() == 1200,
            "unversioned request omits the key");
        Check((await Write(0, 8)).Outcome == VisitorGameplayTimeOutcome.Unavailable, "404 classified");
        Check(await Write(1, 8) is { Outcome: VisitorGameplayTimeOutcome.Invalid, Field: "sourceRevision" }, "400 returns only field");
        Check(await Write(2, 8) is { Outcome: VisitorGameplayTimeOutcome.Invalid, Field: null }, "untrusted 400 field is discarded");
        Check(await Write(3, 7) is { Outcome: VisitorGameplayTimeOutcome.StaleRevision, StoredRevision: 8 }, "409 reads the stored revision");
        Check(await Write(4, 8) is { Outcome: VisitorGameplayTimeOutcome.TemporaryFailure, RetryAfter: { TotalSeconds: 120 } },
            "429 reads Retry-After seconds");
        Check((await Write(5, 8)).Outcome == VisitorGameplayTimeOutcome.TemporaryFailure, "5xx classified");
        try { _ = await Write(6, 8); throw new InvalidOperationException("Expected network failure."); }
        catch (HttpRequestException) { }
        foreach (var (seconds, revision) in new (long, long?)[] { (-1, null), (1_000_000_001, null), (0, -1), (0, 9_007_199_254_740_992) })
        {
            try { _ = await Write(seconds, revision); throw new InvalidOperationException("Expected local range check."); }
            catch (ArgumentOutOfRangeException) { }
        }
        Check(adopted == 9 && requests.Count == 9, "out-of-range values never hit the transport");

        var limited = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), Options);
        try
        {
            _ = await limited.WriteVisitorGameplayTimeAsync(Session(["profile.read"]), new(1, null), default);
            throw new InvalidOperationException("Expected missing profile.write to be rejected.");
        }
        catch (ScmApiForbiddenException) { }
        Check(requests.Count == 9, "scope check prevents requests");

        foreach (var status in new[] { HttpStatusCode.Unauthorized, HttpStatusCode.Forbidden })
            await AuthorizationRejected(status);
    }

    private static async Task AuthorizationRejected(HttpStatusCode status)
    {
        var writes = 0;
        var refreshes = 0;
        var invalidated = 0;
        using var handler = new Handler((request, _) =>
        {
            if (request.RequestUri == Options.TokenEndpoint)
            {
                refreshes++;
                return Task.FromResult(Response(HttpStatusCode.BadRequest, """{"error":"invalid_grant"}"""));
            }
            Check(request.RequestUri?.AbsolutePath == Path && request.Method == HttpMethod.Put, "unexpected auth transport request");
            writes++;
            return Task.FromResult(Response(status, "{}"));
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new Vault("test-refresh"), Options);
        oauth.SessionInvalidated += (_, _) => invalidated++;
        try
        {
            _ = await oauth.WriteVisitorGameplayTimeAsync(Session(["profile.write"]), new(1, null), default);
            throw new InvalidOperationException("Expected resource authorization rejection.");
        }
        catch (ScmApiAuthenticationException) { }
        Check(writes == 1 && refreshes == 1 && invalidated == 1, "401/403 reuse the guarded login invalidation flow");
    }

    private static ScmOAuthSession Session(string[] capabilities) =>
        new(Options.AuthorityId, "test-subject", "Test Pilot", "test-access", DateTimeOffset.UtcNow.AddHours(1), capabilities);

    private static HttpResponseMessage RateLimited()
    {
        var response = Response(HttpStatusCode.TooManyRequests, "{}");
        response.Headers.RetryAfter = new RetryConditionHeaderValue(TimeSpan.FromSeconds(120));
        return response;
    }

    private static HttpResponseMessage Response(HttpStatusCode status, string data) =>
        new(status) { Content = new StringContent(data, Encoding.UTF8, "application/json") };

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException("Visitor gameplay time transport: " + message);
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken) =>
            send(request, cancellationToken);
    }

    private sealed class Vault(string? refresh = null) : ITokenVault
    {
        public string? LoadActiveAccountKey() => refresh is null ? null : Options.AuthorityId + ":test-subject";
        public string? LoadRefreshToken(string accountKey) => refresh;
        public void SaveRefreshToken(string accountKey, string refreshToken) => refresh = refreshToken;
        public void DeleteRefreshToken(string accountKey) => refresh = null;
    }
}
