using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.Net;
using System.Text;

internal static class AccountSessionRestoreTests
{
    internal static async Task RestoreCallerCancellationRemainsCancelled()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "synthetic-cancel-refresh");
        using var cancellation = new CancellationTokenSource();
        var handler = new ScriptedHandler(_ =>
        {
            cancellation.Cancel();
            cancellation.Token.ThrowIfCancellationRequested();
            throw new InvalidOperationException("Cancellation was not observed.");
        });
        using var account = CreateAccountRuntime(settings, options, vault, handler);
        var result = await account.DispatchAsync(BridgeEnvelope.Request(
            "account.getCurrent", "restore-caller-cancel", account.Generation,
            new { schemaVersion = 1 }), cancellation.Token);
        AssertEqual(BridgeResponseStatuses.Cancelled, result.Response.Status,
            "explicit caller cancellation was treated as a network timeout");
        AssertEqual("synthetic-cancel-refresh", vault.LoadRefreshToken(accountKey),
            "caller cancellation removed the credential");
    }

    internal static async Task RestoreTimeoutIsRecoverable()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "synthetic-timeout-refresh");
        var timedOut = true;
        var handler = new ScriptedHandler(request =>
        {
            if (timedOut) throw new TaskCanceledException("Synthetic HTTP deadline elapsed.");
            return request.RequestUri == options.TokenEndpoint
                ? JsonResponse(HttpStatusCode.OK,
                    "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}")
                : JsonResponse(HttpStatusCode.OK,
                    "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}");
        });
        using var account = CreateAccountRuntime(settings, options, vault, handler);
        var before = account.Generation;
        var result = await ReadCurrent(account, "restore-deadline");
        AssertEqual(BridgeResponseStatuses.Ok, result.Response.Status,
            "network deadline was presented as a user cancellation");
        AssertEqual("credentialTemporarilyUnavailable",
            result.Response.Payload.GetProperty("state").GetString(), "timeout state");
        AssertEqual<BridgeAccountContext?>(null, result.Response.AccountContext, "timeout context");
        AssertEqual(before, account.Generation, "timeout changed generation");
        AssertEqual(0, result.Events.Count, "timeout published an account change");
        AssertEqual("synthetic-timeout-refresh", vault.LoadRefreshToken(accountKey),
            "timeout removed the saved credential");
        timedOut = false;
        var recovered = await ReadCurrent(account, "restore-deadline-retry");
        AssertEqual("signedIn", recovered.Response.Payload.GetProperty("state").GetString(),
            "retry did not recover the existing account");
    }

    internal static async Task PersonalProfileOutagePreservesAccount()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "synthetic-refresh");
        var refreshRequests = 0;
        var handler = new ScriptedHandler(request =>
        {
            if (request.RequestUri == options.TokenEndpoint)
            {
                refreshRequests++;
                return JsonResponse(HttpStatusCode.OK,
                    "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
            }
            if (request.RequestUri == options.MeEndpoint)
            {
                return JsonResponse(HttpStatusCode.OK,
                    "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic Pilot\",\"capabilities\":[\"profile.read\"]}");
            }
            AssertEqual(options.PersonalProfileEndpoint, request.RequestUri,
                "outage touched an unexpected endpoint");
            return JsonResponse(HttpStatusCode.ServiceUnavailable, "{}");
        });
        using var account = new AccountBridgeRuntime(new ScmAccountBridgeHost(
            new OAuthPkceClient(new ScmHttpClient(handler), vault, options),
            new ScmProfileCacheStore(System.IO.Path.Combine(System.IO.Path.GetTempPath(),
                "StarBridge-profile-recovery-" + Guid.NewGuid().ToString("N"))),
            settings.EnvironmentName, () => null));
        var current = await ReadCurrent(account, "outage-initial");
        var generation = account.Generation;
        var result = await account.DispatchAsync(BridgeEnvelope.Request(
            "personalProfile.getSelf", "outage-read", generation,
            new { schemaVersion = 1 }, current.Response.AccountContext));
        AssertEqual("personal_profile.read_unavailable", result.Response.Error?.Code,
            "503 must remain a local profile failure");
        AssertEqual(1, refreshRequests, "503 triggered an unnecessary credential refresh");
        AssertEqual(generation, account.Generation, "503 changed account generation");
        AssertEqual(0, result.Events.Count, "503 invalidated account state");
        AssertEqual("synthetic-next", vault.LoadRefreshToken(accountKey),
            "503 removed the saved credential");
        var after = await ReadCurrent(account, "outage-after");
        AssertEqual("signedIn", after.Response.Payload.GetProperty("state").GetString(),
            "503 signed out the user");
    }

    internal static async Task RejectedCredentialProjectsReauthorization()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "refresh-rejected");
        var handler = new ScriptedHandler(_ => JsonResponse(
            HttpStatusCode.BadRequest,
            "{\"error\":\"invalid_grant\"}"));
        using var account = CreateAccountRuntime(settings, options, vault, handler);

        var first = await ReadCurrent(account, "reauthorization-invalid-grant");

        AssertEqual(BridgeResponseStatuses.Ok, first.Response.Status, "invalid grant response status");
        AssertEqual(
            "reauthorizationRequired",
            first.Response.Payload.GetProperty("state").GetString(),
            "invalid grant account state");
        AssertEqual<BridgeAccountContext?>(null, first.Response.AccountContext,
            "invalid grant account context");
        AssertEqual<string?>(null, vault.LoadRefreshToken(accountKey),
            "invalid grant retained refresh credential");
        AssertEqual<string?>(null, vault.LoadActiveAccountKey(),
            "invalid grant retained active account key");

        var requestCount = handler.RequestCount;
        var second = await ReadCurrent(account, "reauthorization-no-restore-retry");
        AssertEqual(
            "reauthorizationRequired",
            second.Response.Payload.GetProperty("state").GetString(),
            "reauthorization state changed without a new login");
        AssertEqual(requestCount, handler.RequestCount,
            "reauthorization state retried a deleted credential");
    }

    internal static async Task IdentityMismatchProjectsReauthorization()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "refresh-subject-1");
        var handler = new ScriptedHandler(request =>
            request.RequestUri == options.TokenEndpoint
                ? JsonResponse(
                    HttpStatusCode.OK,
                    "{\"access_token\":\"access-new\",\"refresh_token\":\"refresh-new\",\"token_type\":\"Bearer\",\"expires_in\":3600}")
                : JsonResponse(
                    HttpStatusCode.OK,
                    "{\"subject\":\"subject-2\",\"displayName\":\"Another Pilot\",\"capabilities\":[\"profile.read\"]}"));
        using var account = CreateAccountRuntime(settings, options, vault, handler);

        var result = await ReadCurrent(account, "reauthorization-identity-mismatch");

        AssertEqual(BridgeResponseStatuses.Ok, result.Response.Status,
            "identity mismatch response status");
        AssertEqual(
            "reauthorizationRequired",
            result.Response.Payload.GetProperty("state").GetString(),
            "identity mismatch account state");
        AssertEqual<BridgeAccountContext?>(null, result.Response.AccountContext,
            "identity mismatch account context");
        AssertEqual<string?>(null, vault.LoadRefreshToken(accountKey),
            "identity mismatch retained rotated credential");
        AssertEqual<string?>(null, vault.LoadActiveAccountKey(),
            "identity mismatch retained active account key");
    }

    internal static async Task RuntimeInvalidationProjectsReauthorization()
    {
        var settings = CreateEnvironmentSettings();
        var options = ScmOAuthOptions.Create(settings);
        var accountKey = $"{options.AuthorityId}:subject-1";
        var vault = new MemoryTokenVault();
        vault.SaveRefreshToken(accountKey, "refresh-runtime");
        var handler = new ScriptedHandler(request =>
        {
            if (request.RequestUri == options.TokenEndpoint)
            {
                return JsonResponse(
                    HttpStatusCode.OK,
                    "{\"access_token\":\"access-runtime\",\"refresh_token\":\"refresh-runtime-next\",\"token_type\":\"Bearer\",\"expires_in\":3600}");
            }

            if (request.RequestUri?.AbsolutePath == options.MeEndpoint.AbsolutePath)
            {
                return JsonResponse(
                    HttpStatusCode.OK,
                    "{\"subject\":\"subject-1\",\"displayName\":\"SCM Pilot\",\"capabilities\":[\"profile.read\"]}");
            }

            AssertEqual(options.ProfileEndpoint.AbsolutePath, request.RequestUri?.AbsolutePath,
                "runtime invalidation used an unexpected resource endpoint");
            return JsonResponse(HttpStatusCode.Unauthorized, "{}");
        });
        using var account = CreateAccountRuntime(settings, options, vault, handler);
        var signedIn = await ReadCurrent(account, "runtime-invalidation-signed-in");
        var context = signedIn.Response.AccountContext ??
            throw new InvalidOperationException("restored account context was missing");
        var signedInGeneration = account.Generation;

        var profile = await account.DispatchAsync(
            BridgeEnvelope.Request(
                "profile.getSelf",
                "runtime-invalidation-profile",
                signedInGeneration,
                new { schemaVersion = 1 },
                context));

        AssertEqual(BridgeResponseStatuses.Error, profile.Response.Status,
            "runtime invalidation response status");
        AssertEqual(
            "account.reauthorization_required",
            profile.Response.Error?.Code,
            "runtime invalidation stable error");
        AssertEqual(signedInGeneration + 1, account.Generation,
            "runtime invalidation generation");
        AssertEqual(1, profile.Events.Count,
            "runtime invalidation event count");
        AssertEqual("account.changed", profile.Events[0].Name,
            "runtime invalidation event name");
        AssertEqual(account.Generation, profile.Events[0].SessionGeneration,
            "runtime invalidation event generation");
        AssertEqual<string?>(null, vault.LoadRefreshToken(accountKey),
            "runtime invalidation retained refresh credential");

        var current = await ReadCurrent(account, "runtime-invalidation-current");
        AssertEqual(
            "reauthorizationRequired",
            current.Response.Payload.GetProperty("state").GetString(),
            "runtime invalidation current state");
        AssertEqual<BridgeAccountContext?>(null, current.Response.AccountContext,
            "runtime invalidation current context");
    }

    private static AccountBridgeRuntime CreateAccountRuntime(
        ScmEnvironmentSettings settings,
        ScmOAuthOptions options,
        MemoryTokenVault vault,
        HttpMessageHandler handler)
    {
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        return new AccountBridgeRuntime(
            new ScmAccountBridgeHost(
                oauth,
                new ScmProfileCacheStore(),
                settings.EnvironmentName,
                () => null));
    }

    private static ValueTask<BridgeDispatchBatch> ReadCurrent(
        AccountBridgeRuntime account,
        string correlationId) => account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.getCurrent",
            correlationId,
            account.Generation,
            new { schemaVersion = 1 }));

    private static ScmEnvironmentSettings CreateEnvironmentSettings() => new(
        "development",
        AccountAccessEnabled: true,
        RegionDiscoveryEnabled: false,
        RegionApiUri: null,
        WebBaseUri: new Uri("http://127.0.0.1:3000/"),
        ApiBaseUri: new Uri("http://127.0.0.1:18080/"),
        ResourceBaseUri: new Uri("http://127.0.0.1:18081/"),
        RelayBaseUri: new Uri("http://127.0.0.1:5058/"),
        TrustedRegionHosts: new HashSet<string>(StringComparer.OrdinalIgnoreCase)
        {
            "127.0.0.1"
        },
        RegionRequestTimeout: TimeSpan.FromSeconds(1),
        RegionCacheDuration: TimeSpan.FromHours(1));

    private static HttpResponseMessage JsonResponse(HttpStatusCode status, string json) => new(status)
    {
        Content = new StringContent(json, Encoding.UTF8, "application/json")
    };

    private static void AssertEqual<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException($"{message}: expected {expected}, got {actual}");
        }
    }

    private sealed class ScriptedHandler(
        Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
    {
        internal int RequestCount { get; private set; }

        protected override Task<HttpResponseMessage> SendAsync(
            HttpRequestMessage request,
            CancellationToken cancellationToken)
        {
            cancellationToken.ThrowIfCancellationRequested();
            RequestCount++;
            return Task.FromResult(respond(request));
        }
    }

    private sealed class MemoryTokenVault : ITokenVault
    {
        private readonly Dictionary<string, string> _tokens = new(StringComparer.Ordinal);
        private string? _activeAccountKey;

        public void SaveRefreshToken(string accountKey, string refreshToken)
        {
            _tokens[accountKey] = refreshToken;
            _activeAccountKey = accountKey;
        }

        public string? LoadRefreshToken(string accountKey) =>
            _tokens.TryGetValue(accountKey, out var refreshToken) ? refreshToken : null;

        public string? LoadActiveAccountKey() => _activeAccountKey;

        public void DeleteRefreshToken(string accountKey)
        {
            _tokens.Remove(accountKey);
            if (string.Equals(_activeAccountKey, accountKey, StringComparison.Ordinal))
            {
                _activeAccountKey = null;
            }
        }
    }

    private sealed class CompatibilityCoordinator : IAccountCompatibilityCoordinator
    {
        public Task<AccountBridgeCompatibilityProjection> ReadAsync(
            ScmOAuthSession session,
            CancellationToken cancellationToken) => throw Unexpected();

        public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(
            ScmOAuthSession session,
            LegacyIdentityLinkPasswordCredential? credential,
            CancellationToken cancellationToken) => throw Unexpected();

        public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
            ScmOAuthSession session,
            CancellationToken cancellationToken) => throw Unexpected();

        private static InvalidOperationException Unexpected() =>
            new("Compatibility operations are outside account restore tests.");
    }
}
