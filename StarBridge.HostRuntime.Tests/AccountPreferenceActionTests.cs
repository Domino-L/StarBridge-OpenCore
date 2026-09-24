using StarBridge.Core.Identity;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;
using System.Net;
using System.Net.Http.Json;

internal static class AccountPreferenceActionTests
{
    internal static async Task SaveConfirmsWithoutReplacingLogin()
    {
        using var f = new Fixture();
        var result = await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } });
        Equal("ok", result.Response.Status, "preference save");
        Equal("en-US", result.Response.Payload.GetProperty("profile").GetProperty("locale").GetString(), "confirmed locale");
        Equal(1, f.Authorization.Calls, "one explicit authorization");
        Equal("{\"locale\":\"en-US\"}", f.Handler.PatchBody, "only changed field reaches SCM");
        Equal("read-token", f.Handler.ReadTokens.Single(), "confirmation uses normal login, not the temporary write grant");
        await f.Send("profile.getSelf", new { schemaVersion = 1 });
        Equal(true, f.Handler.ReadTokens.All(x => x == "read-token"), "subsequent reads retain normal login");
        Equal("refresh-kept", f.Vault.LoadRefreshToken("synthetic:owner"), "login credential preserved");
        Equal(7L, f.Runtime.Generation, "no account transition");
        var actions = result.Response.Payload.GetProperty("preferencesPolicy").GetProperty("availableActions");
        Equal(2, actions.GetArrayLength(), "advertise only the two enabled profile actions");
        var cached = f.Cache.Load(f.Route)!;
        Equal("en-US", cached.Locale, "confirmed data cached");
        var json = File.ReadAllText(Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache")).Single());
        Equal(false, json.Contains("owner@example.invalid"), "email not cached");
        Equal(false, json.Contains("-token"), "tokens not cached");
    }

    internal static async Task AuthorizationFailuresDoNotWrite()
    {
        foreach (var kind in new[] { "denied", "cancelled", "timeout", "wrong-subject", "missing-scope" })
        {
            using var f = new Fixture();
            f.Authorization.Kind = kind;
            var result = await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } });
            var expected = kind switch {
                "cancelled" => "cancelled",
                "timeout" => "account.login_timeout",
                "wrong-subject" => "account.reauthorization_required",
                _ => "profile.write_forbidden"
            };
            Equal(expected, result.Response.Status == "cancelled" ? "cancelled" : result.Response.Error?.Code, kind);
            Equal(0, f.Handler.Patches, kind + " must not write");
            Equal("refresh-kept", f.Vault.LoadRefreshToken("synthetic:owner"), "retain existing login");
            Equal(7L, f.Runtime.Generation, "retain account generation");
        }
    }

    internal static async Task BadRequestsNeverAuthorize()
    {
        using var f = new Fixture();
        foreach (var payload in new object[] {
            new { schemaVersion = 1, patch = new { } },
            new { schemaVersion = 1, patch = new { locale = "en-US", displayName = "not-allowed" } },
            new { schemaVersion = 1, patch = new { locale = 9 } },
            new { schemaVersion = 1, patch = new { locale = "unsupported" } },
            new { schemaVersion = 2, patch = new { locale = "en-US" } }
        })
        {
            var result = await f.Send("profile.patchPreferences", payload);
            Equal("error", result.Response.Status, "invalid patch rejected");
        }
        foreach (var name in new[] { "profile.patchPreferences", "profile.clearLocalCache" })
        {
            var payload = new { schemaVersion = 1, patch = new { locale = "en-US" } };
            var stale = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 6, payload, f.Context));
            Equal(BridgeErrorCodes.StaleGeneration, stale.Response.Error?.Code, "stale generation rejected");
            var wrong = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 7, payload,
                new BridgeAccountContext("integration", "synthetic", "other")));
            Equal("error", wrong.Response.Status, "another account rejected");
            var missing = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 7, payload));
            Equal("error", missing.Response.Status, "missing context rejected");
        }
        Equal(0, f.Authorization.Calls, "no browser authorization for invalid requests");
        Equal(0, f.Handler.Patches, "no external write");
    }

    internal static async Task SaveFailureKeepsCacheAndCanRetry()
    {
        using var f = new Fixture();
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow);
        f.Handler.FailPatch = true;
        var failed = await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } });
        Equal("profile.write_conflict", failed.Response.Error?.Code, "save failure");
        Equal(true, failed.Response.Error?.Retryable, "retry offered");
        Equal("zh-CN", f.Cache.Load(f.Route)?.Locale, "failure keeps previous cache");
        f.Handler.FailPatch = false;
        var retried = await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } });
        Equal("ok", retried.Response.Status, "retry succeeds");
        Equal("en-US", f.Cache.Load(f.Route)?.Locale, "confirmed retry updates cache");
    }

    internal static async Task ClearIsLocalAndIsolated()
    {
        using var f = new Fixture();
        var other = AccountRouteIdentity.Create("integration", "synthetic", "other", null);
        var otherEnvironment = AccountRouteIdentity.Create("another-environment", "synthetic", "owner", null);
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow);
        f.Cache.Save(other, f.Handler.Profile with { Subject = "other" }, DateTimeOffset.UtcNow);
        f.Cache.Save(otherEnvironment, f.Handler.Profile, DateTimeOffset.UtcNow);
        var settingsFile = Path.Combine(f.Root.FullName, "unrelated-settings.json");
        File.WriteAllText(settingsFile, "{}");
        var result = await f.Send("profile.clearLocalCache", new { schemaVersion = 1 });
        Equal("ok", result.Response.Status, "clear");
        Equal(true, result.Response.Payload.GetProperty("cleared").GetBoolean(), "deleted existing cache");
        Equal<ScmCachedProfileContract?>(null, f.Cache.Load(f.Route), "only current route cleared");
        Equal(true, f.Cache.Load(other) != null && f.Cache.Load(otherEnvironment) != null, "other routes untouched");
        Equal("{}", File.ReadAllText(settingsFile), "other local data untouched");
        Equal("refresh-kept", f.Vault.LoadRefreshToken("synthetic:owner"), "credentials untouched");
        Equal(0, f.Handler.Requests, "no server needed for local clear");
        var again = await f.Send("profile.clearLocalCache", new { schemaVersion = 1 });
        Equal(false, again.Response.Payload.GetProperty("cleared").GetBoolean(), "already absent is idempotent");
    }

    internal static async Task ClearFailureIsNotReportedAsSuccess()
    {
        using var f = new Fixture();
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow);
        var file = Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache")).Single();
        using (File.Open(file, FileMode.Open, FileAccess.Read, FileShare.None))
        {
            var result = await f.Send("profile.clearLocalCache", new { schemaVersion = 1 });
            Equal("error", result.Response.Status, "locked cache must not report success");
            Equal("profile.cache_clear_unavailable", result.Response.Error?.Code, "clear failure");
            Equal(true, result.Response.Error?.Retryable, "clear is retryable");
        }
        var retry = await f.Send("profile.clearLocalCache", new { schemaVersion = 1 });
        Equal(true, retry.Response.Payload.GetProperty("cleared").GetBoolean(), "unlocked cache can be cleared");
    }

    internal static async Task UnconfirmedSaveNeverReplacesCache()
    {
        using var f = new Fixture();
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow);
        f.Handler.FailRead = true;
        var result = await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } });
        Equal("error", result.Response.Status, "readback failure is not success");
        Equal("zh-CN", f.Cache.Load(f.Route)?.Locale, "unconfirmed result never replaces cache");
        f.Handler.FailRead = false;
        var recovered = await f.Send("profile.getSelf", new { schemaVersion = 1 });
        Equal("en-US", recovered.Response.Payload.GetProperty("profile").GetProperty("locale").GetString(),
            "refresh reconciles a server write whose response was lost");
        Equal(1, f.Handler.Patches, "recovery does not repeat the write");
        Equal("read-token", f.Handler.ReadTokens.Last(), "recovery retains normal login");
    }

    internal static async Task BrowserDeclineKeepsCallbackStateProtection()
    {
        foreach (var state in new[] { "expected-state", "wrong-state" })
        {
            await using var listener = LoopbackCallbackListener.Start("/callback");
            using var deadline = new CancellationTokenSource(TimeSpan.FromSeconds(5));
            var waiting = listener.WaitForCallbackAsync("expected-state", deadline.Token);
            using var client = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
            var uri = new UriBuilder(listener.RedirectUri) { Query = $"state={state}&error=access_denied" }.Uri;
            using var response = await client.GetAsync(uri, deadline.Token);
            Exception? failure = null;
            try { await waiting; } catch (InvalidOperationException error) { failure = error; }
            Equal(true, failure != null, "declined callback cannot authorize");
            Equal(state == "expected-state", failure is OAuthAuthorizationDeniedException,
                "only a matching callback is treated as the user's cancellation");
        }
    }

    private static void Equal<T>(T expected, T actual, string message)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{message}: expected {expected}, got {actual}");
    }

    private sealed class Fixture : IDisposable
    {
        internal DirectoryInfo Root { get; } = Directory.CreateTempSubdirectory("starbridge-preference-test-");
        internal MemoryVault Vault { get; } = new();
        internal Handler Handler { get; } = new();
        internal Authorization Authorization { get; } = new();
        internal ScmProfileCacheStore Cache { get; }
        internal AccountBridgeRuntime Runtime { get; }
        internal CompositeBridgeDispatcher Dispatcher { get; }
        internal BridgeAccountContext Context { get; } = new("integration", "synthetic", "owner");
        internal AccountRouteIdentity Route { get; } = AccountRouteIdentity.Create("integration", "synthetic", "owner", null);

        internal Fixture()
        {
            HostDataRoot.UsePreparedRoot(Root.FullName);
            Vault.SaveRefreshToken("synthetic:owner", "refresh-kept");
            var uri = new Uri("http://127.0.0.1:9/");
            var options = new ScmOAuthOptions("synthetic", uri, uri, uri, "synthetic", "synthetic", "openid profile.read", "/callback");
            var oauth = new OAuthPkceClient(new ScmHttpClient(Handler), Vault, options);
            Cache = new ScmProfileCacheStore(Root.FullName);
            var session = new ScmOAuthSession("synthetic", "owner", "Synthetic pilot", "read-token",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
            Runtime = new AccountBridgeRuntime(new ScmAccountBridgeHost(
                oauth, Cache, "integration", () => null, session, 7, Authorization));
            Dispatcher = new CompositeBridgeDispatcher(new HostBridgeDispatcher("test"), Runtime,
                new HostBridgeDispatcher("unused-settings"));
        }

        internal ValueTask<BridgeDispatchBatch> Send(string name, object payload) =>
            Dispatcher.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), Runtime.Generation, payload, Context));

        public void Dispose()
        {
            Dispatcher.Dispose();
            var temporaryRoot = Path.GetFullPath(Path.GetTempPath()).TrimEnd(Path.DirectorySeparatorChar) + Path.DirectorySeparatorChar;
            if (!Root.FullName.StartsWith(temporaryRoot, StringComparison.OrdinalIgnoreCase) ||
                !Root.Name.StartsWith("starbridge-preference-test-", StringComparison.Ordinal))
                throw new InvalidOperationException("Unsafe test cleanup path.");
            Root.Delete(recursive: true);
        }
    }

    private sealed class Authorization : IProfileWriteAuthorizationClient
    {
        internal string Kind { get; set; } = "granted";
        internal int Calls { get; private set; }
        public Task<ScmOAuthSession> AuthorizeProfileWriteAsync(ScmOAuthSession session,
            CancellationToken cancellationToken, Action<string>? reportProgress = null)
        {
            Calls++;
            return Kind switch {
                "denied" => Task.FromException<ScmOAuthSession>(new ScmApiForbiddenException("synthetic denial")),
                "cancelled" => Task.FromException<ScmOAuthSession>(new OAuthAuthorizationDeniedException()),
                "timeout" => Task.FromException<ScmOAuthSession>(new TimeoutException()),
                _ => Task.FromResult(session with {
                    Subject = Kind == "wrong-subject" ? "other" : session.Subject,
                    AccessToken = "write-token", Capabilities = Kind == "missing-scope" ? [] : ["profile.write"]
                })
            };
        }
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal int Requests { get; private set; }
        internal int Patches { get; private set; }
        internal bool FailPatch { get; set; }
        internal bool FailRead { get; set; }
        internal string? PatchBody { get; private set; }
        internal List<string?> ReadTokens { get; } = [];
        internal ScmSelfProfileContract Profile { get; private set; } =
            new("owner", "Synthetic pilot", null, "owner@example.invalid", "zh-CN", "UTC");

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Requests++;
            if (request.RequestUri?.AbsolutePath == "/app-api/member/timezone/list")
                return Json(new { code = 0, data = new[] { new { value = "UTC", label = "UTC", offset = "UTC+00:00" } } });
            if (request.RequestUri?.AbsolutePath != "/app-api/starbridge/v1/profile")
                throw new InvalidOperationException("Unexpected synthetic endpoint");
            if (request.Method == HttpMethod.Patch)
            {
                Patches++;
                Equal("write-token", request.Headers.Authorization?.Parameter, "scoped bearer used for write");
                PatchBody = await request.Content!.ReadAsStringAsync(cancellationToken);
                if (FailPatch) return new HttpResponseMessage(HttpStatusCode.Conflict) { Content = JsonContent.Create(new { }) };
                Profile = Profile with { Locale = "en-US" };
            }
            else
            {
                ReadTokens.Add(request.Headers.Authorization?.Parameter);
                if (FailRead) return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
            }
            return Json(Profile);
        }
        private static HttpResponseMessage Json(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
    }

    private sealed class MemoryVault : ITokenVault
    {
        private string? _key;
        private string? _value;
        public void SaveRefreshToken(string accountKey, string refreshToken) { _key = accountKey; _value = refreshToken; }
        public string? LoadRefreshToken(string accountKey) => accountKey == _key ? _value : null;
        public string? LoadActiveAccountKey() => _key;
        public void DeleteRefreshToken(string accountKey) { if (_key == accountKey) { _key = null; _value = null; } }
    }
}
