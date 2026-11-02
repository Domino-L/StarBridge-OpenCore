using System.Net;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static partial class AccountSessionRestoreTests
{
    private static async Task ReviewFixes()
    {
        await SwitchLogoutReview();
        var cases = new (string Name, Func<Task> Run)[] {
            ("fresh resource rejection preserves refresh", FreshResourceRejection),
            ("first waiter cancellation", () => IndependentRestoreCancellation(false, false)),
            ("all waiters cancellation", () => IndependentRestoreCancellation(true, false)),
            ("post-commit cancellation", () => IndependentRestoreCancellation(true, true)),
            ("cancelled failed flight permits retry", CancelledFlightFailureCanRetry),
            ("missing Windows stamp", MissingWindowsStamp),
            ("same subject explicit login", () => ExplicitLoginReplacesRetained("subject-1")),
            ("different subject explicit login", () => ExplicitLoginReplacesRetained("subject-2")),
            ("resume clear cannot readmit", ResumeClearCannotReadmit),
            ("writer conflict retains cache", WriterConflictRetainsCache)
        };
        var failures = new List<string>();
        foreach (var (name, run) in cases)
        {
            try { await run(); Console.WriteLine("PASS CX-L07b " + name); }
            catch (Exception error) { failures.Add(name); Console.WriteLine("FAIL CX-L07b " + name + ": " + error.Message); }
        }
        Console.WriteLine($"CX-L07b SUMMARY PASS {cases.Length - failures.Count}/{cases.Length} FAIL {failures.Count}");
        if (failures.Count != 0) throw new InvalidOperationException("CX-L07b failures: " + string.Join(", ", failures));
    }

    private const string ReviewToken = "{\"access_token\":\"synthetic-access\",\"refresh_token\":\"synthetic-next\",\"expires_in\":3600}";
    private static HttpResponseMessage ReviewIdentity(string subject = "subject-1") => JsonResponse(HttpStatusCode.OK,
        "{\"subject\":\"" + subject + "\",\"capabilities\":[\"profile.read\"],\"gameIdentity\":{\"status\":\"UNVERIFIED\",\"verified\":false}}");

    private static async Task FreshResourceRejection()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        var key = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(key, "synthetic-original");
        var refreshes = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.TokenEndpoint) { refreshes++; return JsonResponse(HttpStatusCode.OK, ReviewToken); }
            return ReviewIdentity();
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var initial = (await oauth.TryRestoreSessionAsync(default))!;
        var invalidations = 0;
        oauth.SessionInvalidated += (_, _) => invalidations++;
        var calls = 0;
        try
        {
            await oauth.SendResourceRequestAsync<bool>(initial, (_, _) => {
                calls++; throw new ScmApiAuthenticationException("Synthetic propagation delay");
            }, default);
            throw new InvalidOperationException("Expected temporary failure");
        }
        catch (ScmRefreshTemporarilyUnavailableException) { }
        AssertEqual(2, calls, "resource has exactly one bounded retry");
        AssertEqual(2, refreshes, "rejected access version refreshes once");
        AssertEqual(0, vault.Deletes, "resource 401 cannot retire refresh credential");
        AssertEqual(0, invalidations, "resource rejection cannot advance host generation");
        AssertEqual(key, vault.LoadActiveAccountKey(), "selection retained");
    }

    private static async Task IndependentRestoreCancellation(bool cancelAll, bool afterCommit)
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        var key = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(key, "synthetic-original");
        var entered = Signal(); var release = Signal();
        var refreshes = 0;
        using var handler = new RaceHandler(async (request, token) => {
            var isToken = request.RequestUri == options.TokenEndpoint;
            if (isToken) refreshes++;
            if (isToken != afterCommit) { entered.TrySetResult(); await release.Task.WaitAsync(token); }
            return isToken ? JsonResponse(HttpStatusCode.OK, ReviewToken) : ReviewIdentity();
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        using var firstCancel = new CancellationTokenSource();
        using var secondCancel = new CancellationTokenSource();
        var first = oauth.TryRestoreSessionAsync(firstCancel.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var second = oauth.TryRestoreSessionAsync(secondCancel.Token);
        firstCancel.Cancel();
        if (cancelAll) secondCancel.Cancel();
        try
        {
            await first.WaitAsync(TimeSpan.FromSeconds(5));
            throw new InvalidOperationException("First waiter must cancel independently");
        }
        catch (OperationCanceledException) { }
        if (cancelAll)
        {
            try { await second; throw new InvalidOperationException("Second waiter must cancel"); }
            catch (OperationCanceledException) { }
        }
        release.TrySetResult();
        var restored = cancelAll ? await oauth.TryRestoreSessionAsync(default) : await second.WaitAsync(TimeSpan.FromSeconds(5));
        AssertEqual(true, restored is not null, "independent flight remains available");
        AssertEqual(1, refreshes, "cancelled waiters cannot trigger extra rotation");
        AssertEqual("synthetic-next", vault.LoadRefreshToken(key), "committed credential retained");
        AssertEqual(0, vault.Deletes, "waiter cancellation never retires credential");
        AssertEqual(restored!.CredentialVersion, (await oauth.TryRestoreSessionAsync(default))!.CredentialVersion,
            "later independent retry uses installed result");
    }

    private static async Task MissingWindowsStamp()
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "l07b-missing-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, "vault.json");
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var key = options.AuthorityId + ":subject-1";
        var vault = new WindowsTokenVault(path);
        vault.SaveRefreshToken(key, "synthetic-old");
        var session = new ScmOAuthSession(options.AuthorityId, "subject-1", "Synthetic", "synthetic-access",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read"]);
        using var handler = new ScriptedHandler(_ => throw new InvalidOperationException("No transport expected"));
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        await oauth.SendResourceRequestAsync(session, (_, _) => Task.FromResult(true), default);
        var writer = new WindowsTokenVault(path);
        writer.SaveRefreshToken(key, "synthetic-new");
        try { await oauth.RevokeAsync(session, default); throw new InvalidOperationException("Missing stamp must fail temporarily"); }
        catch (ScmLocalCredentialRetirementException error) when (error.InnerException is ScmRefreshTemporarilyUnavailableException) { }
        AssertEqual("synthetic-new", writer.LoadRefreshToken(key), "unknown original stamp cannot delete other instance write");
        await oauth.ClearLocalCredentialAsync(session, default);
        AssertEqual("synthetic-new", writer.LoadRefreshToken(key), "realtime rejection cannot delete other instance write");
    }

    private static async Task CancelledFlightFailureCanRetry()
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-original");
        var entered = Signal(); var release = Signal(); var refreshes = 0;
        using var handler = new RaceHandler(async (request, token) => {
            if (request.RequestUri != options.TokenEndpoint) return ReviewIdentity();
            if (++refreshes == 1)
            {
                entered.TrySetResult(); await release.Task.WaitAsync(token);
                return JsonResponse(HttpStatusCode.ServiceUnavailable, "{}");
            }
            return JsonResponse(HttpStatusCode.OK, ReviewToken);
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        using var cancellation = new CancellationTokenSource();
        var first = oauth.TryRestoreSessionAsync(cancellation.Token);
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        cancellation.Cancel();
        try { await first; throw new InvalidOperationException("Waiter must cancel"); }
        catch (OperationCanceledException) { }
        var observer = oauth.TryRestoreSessionAsync(default);
        release.TrySetResult();
        try { await observer; throw new InvalidOperationException("Expected shared transient failure"); }
        catch (HttpRequestException) { }
        AssertEqual(true, await oauth.TryRestoreSessionAsync(default) is not null, "failed abandoned flight does not poison retry");
        AssertEqual(2, refreshes, "later independent failure retry rotates once");
        AssertEqual(0, vault.Deletes, "cancellation and failure retain refresh");
    }

    private static async Task ExplicitLoginReplacesRetained(string subject)
    {
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new RaceVault();
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-original");
        var available = false;
        using var handler = new ScriptedHandler(request => request.RequestUri == options.TokenEndpoint
            ? JsonResponse(HttpStatusCode.OK, ReviewToken)
            : available ? ReviewIdentity(subject) : throw new HttpRequestException("Synthetic identity outage"));
        Task? callback = null;
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options, authorizationBrowser: authorization => {
            var query = authorization.Query.TrimStart('?').Split('&').Select(value => value.Split('=', 2))
                .ToDictionary(value => Uri.UnescapeDataString(value[0]), value => Uri.UnescapeDataString(value[1]));
            var uri = new Uri(query["redirect_uri"] + "?code=synthetic-code&state=" + Uri.EscapeDataString(query["state"]));
            if (!uri.IsLoopback) throw new InvalidOperationException("Only local synthetic PKCE callback allowed");
            callback = LocalCallback(uri);
        });
        try { await oauth.TryRestoreSessionAsync(default); }
        catch (HttpRequestException) { }
        var retained = oauth.CurrentCredentialVersion;
        AssertEqual(true, retained.HasValue, "test must commit an unconfirmed rotation");
        available = true;
        var signedIn = await oauth.SignInAsync(default);
        await callback!;
        AssertEqual<Guid?>(signedIn.CredentialVersion, oauth.CurrentCredentialVersion, "successful login replaces retained version");
        AssertEqual(false, retained == signedIn.CredentialVersion, "new login has new lifecycle");
        await oauth.ClearLocalCredentialAsync(signedIn, default);
        AssertEqual<Guid?>(null, oauth.CurrentCredentialVersion, "new login resource clear retires memory lifecycle");
        AssertEqual("synthetic-next", vault.LoadRefreshToken(options.AuthorityId + ":" + subject), "realtime clear retains refresh");
    }

    private static async Task LocalCallback(Uri uri)
    {
        using var client = new HttpClient(new SocketsHttpHandler { UseProxy = false });
        using var response = await client.GetAsync(uri);
        response.EnsureSuccessStatusCode();
    }

    private static async Task ResumeClearCannotReadmit()
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "l07b-resume-" + Guid.NewGuid().ToString("N"));
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new WindowsTokenVault(Path.Combine(root, "vault.json"));
        vault.SaveRefreshToken(options.AuthorityId + ":subject-1", "synthetic-original");
        var refreshes = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.TokenEndpoint) { refreshes++; return JsonResponse(HttpStatusCode.OK, ReviewToken); }
            return ReviewIdentity();
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var result = await oauth.ResumeFirstUseSessionAsync(() => true, default);
        AssertEqual("observed", result.State, "native resume installs real session");
        await oauth.ClearLocalCredentialAsync(result.Session!, default);
        try { await oauth.SendResourceRequestAsync(result.Session!, (_, _) => Task.FromResult(true), default); }
        catch (ScmRefreshTemporarilyUnavailableException) { }
        AssertEqual<Guid?>(null, oauth.CurrentCredentialVersion, "late old resource cannot reinstall retired native resume");
        AssertEqual(1, refreshes, "late old call cannot refresh retired lifecycle");
    }

    private static async Task WriterConflictRetainsCache()
    {
        var root = Path.Combine(HostDataRoot.CurrentRoot, "l07b-writer-" + Guid.NewGuid().ToString("N"));
        var options = ScmOAuthOptions.Create(CreateEnvironmentSettings());
        var vault = new WindowsTokenVault(Path.Combine(root, "vault.json"));
        var writer = new WindowsTokenVault(Path.Combine(root, "vault.json"));
        var key = options.AuthorityId + ":subject-1";
        vault.SaveRefreshToken(key, "synthetic-original");
        var failing = false; var resources = 0;
        using var handler = new ScriptedHandler(request => {
            if (request.RequestUri == options.TokenEndpoint) return JsonResponse(HttpStatusCode.OK, ReviewToken);
            if (request.RequestUri?.AbsolutePath == options.MeEndpoint.AbsolutePath) return ReviewIdentity();
            if (request.RequestUri == options.TimeZoneDirectoryEndpoint) return JsonResponse(HttpStatusCode.OK,
                "{\"code\":0,\"data\":[{\"value\":\"UTC\",\"label\":\"UTC\",\"offset\":\"UTC+00:00\"}]}");
            if (!failing) return JsonResponse(HttpStatusCode.OK,
                "{\"subject\":\"subject-1\",\"displayName\":\"Synthetic\",\"locale\":\"zh-CN\",\"timeZone\":\"UTC\"}");
            if (++resources == 2) writer.SaveRefreshToken(key, "synthetic-third-writer");
            return JsonResponse(HttpStatusCode.Unauthorized, "{}");
        });
        var oauth = new OAuthPkceClient(new ScmHttpClient(handler), vault, options);
        var session = (await oauth.TryRestoreSessionAsync(default))!;
        var cache = new ScmProfileCacheStore(root);
        using var host = new ScmAccountBridgeHost(oauth, cache, "development", () => null, session, 7);
        using var runtime = new AccountBridgeRuntime(host);
        var context = host.CurrentContext!;
        var route = AccountRouteIdentity.Create("development", options.AuthorityId, "subject-1", null);
        var seeded = (await Read()).Response;
        AssertEqual("ok", seeded.Status, "cache seed response: " + seeded.Error?.Code);
        var stamp = cache.Load(route)?.CachedAtUtc;
        AssertEqual(true, stamp.HasValue, "test must seed real profile cache");
        failing = true;
        var result = (await Read()).Response;
        AssertEqual("ok", result.Status, "resource writer conflict keeps cached display");
        AssertEqual("cache", result.Payload.GetProperty("source").GetString(), "cache fallback on version conflict");
        AssertEqual(stamp, cache.Load(route)?.CachedAtUtc, "cached timestamp retained");
        AssertEqual(7L, runtime.Generation, "version conflict cannot change account generation");
        AssertEqual("synthetic-third-writer", writer.LoadRefreshToken(key), "new writer retained");
        // Exercise the still-deleting explicit path with an original, now stale stamp.
        // Read the actual installed V2; do not replace lifecycle state through reflection.
        var installed = (ScmOAuthSession)typeof(OAuthPkceClient).GetField("_currentSession",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(oauth)!;
        try { await oauth.RevokeAsync(installed, default); throw new InvalidOperationException("Version conflict expected"); }
        catch (ScmLocalCredentialRetirementException error) when (error.InnerException is ScmRefreshTemporarilyUnavailableException)
        {
            AssertEqual(true, AccountProfileReadFailures.Classify(error.InnerException!)?.Retryable, "exact stamp conflict is retryable");
        }
        AssertEqual(false, AccountProfileReadFailures.Classify(new InvalidDataException("Synthetic malformed data"))!.Retryable,
            "unrelated InvalidDataException stays permanent");
        ValueTask<BridgeDispatchBatch> Read() => runtime.DispatchAsync(BridgeEnvelope.Request("profile.getSelf",
            Guid.NewGuid().ToString("N"), runtime.Generation, new { schemaVersion = 1 }, context));
    }
}
