using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.Net;
using System.Net.Http.Json;

internal static class ResourceReadTimeoutTests
{
    private static readonly ScmOAuthOptions Options = new(
        "synthetic", new Uri("https://web.example.invalid/"),
        new Uri("https://auth.example.invalid/"), new Uri("https://resource.example.invalid/"),
        "synthetic-client", "starbridge-api", "openid profile.read", "/oauth/callback");

    internal static Task SlowReadsReachTheirCallers() => Task.WhenAll(
        SlowPersonalProfile(), SlowAccountRead(bootstrap: true), SlowAccountRead(bootstrap: false));

    private static async Task SlowPersonalProfile()
    {
        using var fixture = new Fixture(async (_, cancellation) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(16), cancellation);
            return Json(Document());
        });
        var current = await fixture.Current();
        var result = await fixture.Read(current.Response.AccountContext!);
        Equal(BridgeResponseStatuses.Ok, result.Response.Status,
            "A valid 16-second personal profile must reach the page");
        Equal("Synthetic Pilot", result.Response.Payload.GetProperty("profile")
            .GetProperty("identity").GetProperty("callSign").GetString(), "Profile payload");
        Equal(1, fixture.ReadCalls, "Slow read was replayed");
        Equal(1, fixture.RefreshCalls, "Slow read refreshed credentials");
    }

    private static async Task SlowAccountRead(bool bootstrap)
    {
        var endpoint = bootstrap ? Options.BootstrapEndpoint : Options.ProfileEndpoint;
        var calls = 0;
        var oauth = new OAuthPkceClient(new ScmHttpClient(new Handler(async (request, cancellation) =>
        {
            Equal(endpoint.AbsolutePath, request.RequestUri?.AbsolutePath, "Unexpected read endpoint");
            calls++;
            await Task.Delay(TimeSpan.FromSeconds(16), cancellation);
            return bootstrap
                ? Json<object>(new { profile = new { subject = "owner" }, capabilities = new[] { "profile.read" } })
                : Json<object>(new { subject = "owner", displayName = "Synthetic Pilot" });
        })), new MemoryVault(), Options);
        var session = new ScmOAuthSession("synthetic", "owner", "Synthetic Pilot", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        try
        {
            var subject = bootstrap
                ? (await oauth.LoadBootstrapAsync(session, CancellationToken.None)).Snapshot.Profile.Subject
                : (await oauth.LoadProfileAsync(session, CancellationToken.None)).Profile.Subject;
            Equal("owner", subject, "Read subject");
        }
        catch (OperationCanceledException)
        {
            throw new InvalidOperationException((bootstrap ? "Bootstrap" : "Account profile") +
                " discarded a valid 16-second response.");
        }
        Equal(1, calls, "Slow read was replayed");
    }

    internal static async Task TimeoutIsRetryableWithoutLosingAccount()
    {
        var timedOut = true;
        using var fixture = new Fixture((_, _) => timedOut
            ? Task.FromException<HttpResponseMessage>(new TaskCanceledException("Synthetic HTTP deadline."))
            : Task.FromResult(Json(Document())));
        var current = await fixture.Current();
        var generation = fixture.Runtime.Generation;
        var failure = await fixture.Read(current.Response.AccountContext!);
        Equal(BridgeResponseStatuses.Error, failure.Response.Status, "HTTP deadline is not user cancellation");
        Equal("personal_profile.read_unavailable", failure.Response.Error?.Code, "Local retryable read failure");
        Equal(true, failure.Response.Error?.Retryable, "Timeout must allow retry");
        Equal(generation, fixture.Runtime.Generation, "Timeout changed account generation");
        Equal(0, failure.Events.Count, "Timeout published account invalidation");
        Equal("synthetic-next", fixture.Vault.LoadRefreshToken("synthetic:owner"), "Timeout deleted credentials");
        timedOut = false;
        var recovered = await fixture.Read(current.Response.AccountContext!);
        Equal(BridgeResponseStatuses.Ok, recovered.Response.Status, "Explicit retry did not recover");
        Equal(2, fixture.ReadCalls, "Unexpected automatic retry");
        Equal(1, fixture.RefreshCalls, "Read timeout refreshed credentials");
        Equal("signedIn", (await fixture.Current()).Response.Payload.GetProperty("state").GetString(),
            "Read timeout signed out the account");
    }

    internal static async Task CallerCancellationStillStopsRead()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var fixture = new Fixture(async (_, cancellation) =>
        {
            entered.TrySetResult();
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellation);
            throw new InvalidOperationException("Unreachable response.");
        });
        var current = await fixture.Current();
        using var cancellation = new CancellationTokenSource();
        var pending = fixture.Read(current.Response.AccountContext!, cancellation.Token).AsTask();
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(2));
        cancellation.Cancel();
        Equal(BridgeResponseStatuses.Cancelled, (await pending).Response.Status, "Caller cancellation ignored");
        Equal(1, fixture.ReadCalls, "Cancelled read replayed");
        Equal(1, fixture.RefreshCalls, "Cancellation refreshed credentials");
    }

    internal static Task FiniteBudgetsAndQueueKeepTheirBoundaries() => Task.WhenAll(
        ReadDeadlineEnds(), WriteDeadlineIsUnchanged(), QueuedReadsKeepContext());

    private static async Task ReadDeadlineEnds()
    {
        using var fixture = new Fixture(async (_, cancellation) =>
        {
            await Task.Delay(Timeout.InfiniteTimeSpan, cancellation);
            throw new InvalidOperationException("Unreachable response.");
        });
        var current = await fixture.Current();
        var result = await fixture.Read(current.Response.AccountContext!).AsTask().WaitAsync(TimeSpan.FromSeconds(55));
        Equal("personal_profile.read_unavailable", result.Response.Error?.Code, "Read deadline did not end as retryable");
        Equal(true, result.Response.Error?.Retryable, "Read deadline lost retry action");
        Equal(1, fixture.ReadCalls, "Deadline automatically replayed a read");
        Equal(1, fixture.RefreshCalls, "Deadline refreshed credentials");
    }

    private static async Task WriteDeadlineIsUnchanged()
    {
        var calls = 0;
        var oauth = new OAuthPkceClient(new ScmHttpClient(new Handler(async (request, cancellation) =>
        {
            Equal(HttpMethod.Patch, request.Method, "Unexpected write method");
            calls++;
            await Task.Delay(TimeSpan.FromSeconds(16), cancellation);
            return Json(Document());
        })), new MemoryVault(), Options);
        try
        {
            await oauth.UpdatePersonalProfileAsync(new ScmOAuthSession("synthetic", "owner", "Synthetic Pilot",
                "synthetic-write-grant", DateTimeOffset.UtcNow.AddHours(1), ["profile.write"]),
                new PersonalProfilePresentationUpdateContract(4, "public", "Synthetic Pilot", 0, "default", "", []),
                CancellationToken.None);
            throw new InvalidOperationException("Read policy widened the existing write deadline.");
        }
        catch (OperationCanceledException) { }
        Equal(1, calls, "Write deadline replayed a mutation");
    }

    private static async Task QueuedReadsKeepContext()
    {
        using var fixture = new Fixture(async (_, cancellation) =>
        {
            await Task.Delay(TimeSpan.FromSeconds(16), cancellation);
            return Json(Document());
        });
        var current = await fixture.Current();
        var generation = fixture.Runtime.Generation;
        var first = fixture.Read(current.Response.AccountContext!).AsTask();
        var second = fixture.Read(current.Response.AccountContext!).AsTask();
        var results = await Task.WhenAll(first, second).WaitAsync(TimeSpan.FromSeconds(55));
        foreach (var result in results)
        {
            Equal(BridgeResponseStatuses.Ok, result.Response.Status, "Queued read lost the profile");
            Equal(generation, result.Response.SessionGeneration, "Queued read changed generation");
        }
        Equal(2, fixture.ReadCalls, "Queue lost or replayed a read");
        Equal(1, fixture.RefreshCalls, "Queue needlessly refreshed credentials");
    }

    private static PersonalProfileDocumentContract Document() => new(
        PersonalProfileContractPolicy.CurrentSchemaVersion, "synthetic-profile", true, 4,
        DateTimeOffset.UtcNow, new PersonalProfileIdentityContract("Synthetic Pilot", "Synthetic-Pilot"),
        PersonalProfileContentContract.Empty, null, new PersonalProfileHangarContract([]),
        new PersonalProfileGameplayStatisticsContract(3600, 0, 0, DateTimeOffset.UtcNow), true);

    private static HttpResponseMessage Json<T>(T payload) => new(HttpStatusCode.OK)
    {
        Content = JsonContent.Create(payload)
    };

    private static void Equal<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{message}: expected {expected}, got {actual}");
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly MemoryVault Vault = new();
        internal readonly AccountBridgeRuntime Runtime;
        internal int ReadCalls;
        internal int RefreshCalls;

        internal Fixture(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> read)
        {
            var http = new ScmHttpClient(new Handler((request, cancellation) =>
            {
                if (request.RequestUri == Options.TokenEndpoint)
                {
                    RefreshCalls++;
                    return Task.FromResult(Json(new { access_token = "synthetic-access", refresh_token = "synthetic-next",
                        token_type = "Bearer", expires_in = 3600 }));
                }
                if (request.RequestUri == Options.MeEndpoint)
                    return Task.FromResult(Json(new { subject = "owner", displayName = "Synthetic Pilot",
                        capabilities = new[] { "profile.read" } }));
                Equal(Options.PersonalProfileEndpoint, request.RequestUri, "Unexpected runtime endpoint");
                Equal(HttpMethod.Get, request.Method, "Read made a write request");
                ReadCalls++;
                return read(request, cancellation);
            }));
            Runtime = new AccountBridgeRuntime(new ScmAccountBridgeHost(
                new OAuthPkceClient(http, Vault, Options),
                new ScmProfileCacheStore(Path.Combine(Path.GetTempPath(), "StarBridge-read-test-" + Guid.NewGuid().ToString("N"))),
                "synthetic", () => null));
        }

        internal ValueTask<BridgeDispatchBatch> Current() => Runtime.DispatchAsync(BridgeEnvelope.Request(
            "account.getCurrent", "synthetic-current", Runtime.Generation, new { schemaVersion = 1 }));
        internal ValueTask<BridgeDispatchBatch> Read(BridgeAccountContext context, CancellationToken cancellation = default) =>
            Runtime.DispatchAsync(BridgeEnvelope.Request("personalProfile.getSelf", "synthetic-read", Runtime.Generation,
                new { schemaVersion = 1 }, context), cancellation);
        public void Dispose() => Runtime.Dispose();
    }

    private sealed class Handler(Func<HttpRequestMessage, CancellationToken, Task<HttpResponseMessage>> send) : HttpMessageHandler
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
