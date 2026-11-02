using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class AccountPreferenceActionTests
{
    internal static async Task ReadCacheFailureMatrix()
    {
        var failures = new List<string>();
        foreach (var (name, status, expected, transient) in new[] {
            ("403", HttpStatusCode.Forbidden, "profile.read_forbidden", false),
            ("404", HttpStatusCode.NotFound, "profile.read_unavailable", false),
            ("redirect", HttpStatusCode.Redirect, "profile.read_unavailable", false),
            ("799", (HttpStatusCode)799, "profile.read_unavailable", false),
            ("408", HttpStatusCode.RequestTimeout, "profile.read_transient", true),
            ("429", HttpStatusCode.TooManyRequests, "profile.read_transient", true),
            ("500", HttpStatusCode.InternalServerError, "profile.read_transient", true),
            ("503", HttpStatusCode.ServiceUnavailable, "profile.read_transient", true),
            ("599", (HttpStatusCode)599, "profile.read_transient", true) }) {
            await CheckReadFailure(name, _ => Task.FromResult(new HttpResponseMessage(status) { Content = new StringContent("{}") }), expected, transient, failures);
        }
        await CheckReadFailure("transport", _ => throw new HttpRequestException("synthetic transport"), "profile.read_transient", true, failures);
        await CheckReadFailure("stream", _ => throw new IOException("synthetic stream"), "profile.read_transient", true, failures);
        await CheckReadFailure("internal deadline", _ => throw new OperationCanceledException("synthetic internal deadline"), "profile.read_transient", true, failures);
        await CheckReadFailure("bad json", _ => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{bad") }), "profile.data_invalid", false, failures);
        await CheckReadFailure("wrong subject", f => Task.FromResult(JsonRead(f.Handler.Profile with { Subject = "other" })), "profile.data_invalid", false, failures);
        await CheckReadFailure("empty subject", f => Task.FromResult(JsonRead(f.Handler.Profile with { Subject = "" })), "profile.data_invalid", false, failures);
        await CheckReadFailure("unknown internal", _ => throw new InvalidOperationException("synthetic private error"), BridgeErrorCodes.HostError, false, failures);
        // 401 already retires OAuth credentials. Verify that actual Runtime
        // lifecycle instead of assuming that its broad catch returns the cache.
        using (var f = new Fixture()) {
            await SeedReadCache(f);
            f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Unauthorized) { Content = new StringContent("{}") });
            var response = await f.Send("profile.getSelf", new { schemaVersion = 1 });
            if (response.Response.Status == "ok" || f.Host.CurrentContext is not null || f.Runtime.Generation == 7)
                failures.Add("401 must retire the actual owner and cannot return a cached success");
        }
        foreach(var cacheState in new[] { "missing", "valid", "corrupt", "other environment" }) {
            using var f = new Fixture();
            if(cacheState is "corrupt" or "valid") {
                // Seed persistent data without a live in-memory snapshot.
                f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow);
                if(cacheState == "corrupt")
                    File.WriteAllText(Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache"), "*.json").Single(), "{broken");
            } else if(cacheState == "other environment") {
                f.Cache.Save(AccountRouteIdentity.Create("other-environment", "synthetic", "owner", null), f.Handler.Profile, DateTimeOffset.UtcNow);
            }
            f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") });
            var response = await f.Send("profile.getSelf", new { schemaVersion = 1 });
            if(cacheState == "valid") {
                if(response.Response.Status != "ok" || response.Response.Payload.GetProperty("source").GetString() != "cache") failures.Add("valid disk-only cache must remain a display fallback");
            } else if(response.Response.Status != "error" || response.Response.Error?.Code != "profile.read_transient" || response.Response.Error?.Retryable != true)
                failures.Add(cacheState + " cache must not become an available profile");
        }
        if(failures.Count != 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
    }

    private static async Task CheckReadFailure(string name, Func<Fixture, Task<HttpResponseMessage>> reply,
        string code, bool transient, List<string> failures)
    {
        foreach(var cached in new[] { true, false }) {
            using var f = new Fixture();
            if(cached) await SeedReadCache(f);
            var before = f.Cache.Load(f.Route);
            f.Handler.ReadReply = (_, _) => reply(f);
            var response = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
            if(cached && transient) {
                if(response.Status != "ok" || response.Payload.GetProperty("source").GetString() != "cache")
                    failures.Add(name + ": known transient read did not retain the display cache");
            } else if(response.Status != "error" || response.Error?.Code != code || response.Error?.Retryable != transient) {
                failures.Add($"{name}/{cached}: expected {code}/{transient}, got {response.Status}/{response.Error?.Code}/{response.Error?.Retryable}");
            }
            var after = f.Cache.Load(f.Route);
            if(transient && after?.CachedAtUtc != before?.CachedAtUtc) failures.Add(name + ": failure advanced successful cache time");
            if(!transient && after is not null) failures.Add(name + ": hard failure did not retire the old display cache");
            if(f.Runtime.Generation != 7 || f.Vault.LoadRefreshToken("synthetic:owner") != "refresh-kept") failures.Add(name + ": non-401 failure changed account authority");
            if(f.Handler.Patches != 0 || f.Handler.ReadTokens.Count != (cached ? 2 : 1)) failures.Add(name + ": read was replayed or wrote remote state");
        }
    }

    internal static async Task ReadCacheHardDenial()
    {
        // Failure to delete a locked cache cannot make the next temporary
        // failure revive content rejected by an earlier hard read.
        using(var f = new Fixture()) {
            await SeedReadCache(f);
            var cacheFile = Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache"), "*.json").Single();
            using(File.Open(cacheFile, FileMode.Open, FileAccess.Read, FileShare.Read)) {
                f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) {Content = new StringContent("{}")});
                Equal("profile.read_forbidden", (await f.Send("profile.getSelf", new {schemaVersion = 1})).Response.Error?.Code, "denial remains explicit if cache cannot be deleted");
                f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {Content = new StringContent("{}")});
                Equal("profile.read_transient", (await f.Send("profile.getSelf", new {schemaVersion = 1})).Response.Error?.Code, "next transient failure cannot revive rejected content");
            }
            f.Handler.ReadReply = (_, _) => Task.FromResult(JsonRead(f.Handler.Profile with {Locale = "en-US"}));
            Equal("live", (await f.Send("profile.getSelf", new {schemaVersion = 1})).Response.Payload.GetProperty("source").GetString(), "fresh read restores display continuity");
            f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {Content = new StringContent("{}")});
            var recoveredCache = (await f.Send("profile.getSelf", new {schemaVersion = 1})).Response;
            Equal("cache", recoveredCache.Payload.GetProperty("source").GetString(), "only confirmed persistence enables cache again");
            Equal("en-US", recoveredCache.Payload.GetProperty("profile").GetProperty("locale").GetString(), "retained content belongs to the new successful read");
        }
    }

    internal static async Task ReadCacheWriteFailure()
    {
        using var f = new Fixture();
        await SeedReadCache(f);
        var cacheFile = Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache"), "*.json").Single();
        f.Handler.ReadReply = (_, _) => Task.FromResult(JsonRead(f.Handler.Profile with { Locale = "en-US" }));
        using (File.Open(cacheFile, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            var response = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
            Equal("ok", response.Status, "cache write failure must not discard successful remote content");
            Equal("live", response.Payload.GetProperty("source").GetString(), "new response is live");
            Equal("en-US", response.Payload.GetProperty("profile").GetProperty("locale").GetString(), "display uses newly loaded content");
        }
        Equal("zh-CN", f.Cache.Load(f.Route)?.Locale, "failed persistence did not claim to save fresh content");
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") });
        var retained = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
        Equal("en-US", retained.Payload.GetProperty("profile").GetProperty("locale").GetString(), "next transient failure retains the newest confirmed read, not older disk content");
    }

    internal static async Task ReadCacheLifecycle()
    {
        using(var f = new Fixture()) {
            await SeedReadCache(f);
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.ReadReply = async (_, token) => { entered.TrySetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token); throw new Exception("unreachable"); };
            using var cancelled = new CancellationTokenSource();
            var pending = f.Runtime.DispatchAsync(BridgeEnvelope.Request("profile.getSelf", "caller-cancelled", 7, new { schemaVersion = 1 }, f.Context), cancelled.Token).AsTask();
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            cancelled.Cancel();
            Equal("cancelled", (await pending).Response.Status, "caller cancellation must not return cached success");
            Equal(7L, f.Runtime.Generation, "cancellation is not logout");
        }
        using(var f = new Fixture()) {
            await SeedReadCache(f);
            var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
            f.Handler.ReadReply = (_, _) => { entered.TrySetResult(); return release.Task; };
            var pending = f.Host.GetProfileAsync(f.Context, default);
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            await f.Host.LogoutAsync(f.Context, default);
            release.TrySetResult(JsonRead(f.Handler.Profile));
            try { await pending; } catch(AccountBridgeHostException) { }
            Equal<BridgeAccountContext?>(null, f.Host.CurrentContext, "late read must not reinstall a retired login");
        }
    }

    internal static async Task ReadCacheMutations()
    {
        using var f = new Fixture();
        await SeedReadCache(f);
        var saved = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        Equal("ok", saved.Status, "explicit preference write is confirmed normally");
        f.Handler.FailRead = true;
        var retained = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
        Equal("en-US", retained.Payload.GetProperty("profile").GetProperty("locale").GetString(), "fallback must not resurrect the snapshot from before the confirmed write");
        await f.Send("profile.clearLocalCache", new { schemaVersion = 1 });
        var cleared = (await f.Send("profile.getSelf", new { schemaVersion = 1 })).Response;
        Equal("profile.read_transient", cleared.Error?.Code, "explicit clear must retire memory and disk display snapshots");
        Equal(7L, f.Runtime.Generation, "local display cache changes do not transition the account");
    }

    private static async Task SeedReadCache(Fixture f)
    {
        var response = await f.Send("profile.getSelf", new { schemaVersion = 1 });
        Equal("ok", response.Response.Status, "synthetic remote read seeds display cache");
    }
    internal static async Task<string> ReadCacheWire()
    {
        using var f = new Fixture();
        async Task<BridgeEnvelope> Invoke(string name) => (await f.Send(name, new { schemaVersion = 1 })).Response;
        var current = await Invoke("account.getCurrent");
        var identity = await Invoke("gameIdentity.getPolicy");
        var live = await Invoke("profile.getSelf");
        f.Handler.FailRead = true;
        var cached = await Invoke("profile.getSelf");
        f.Handler.FailRead = false;
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) { Content = new StringContent("{}") });
        var forbidden = await Invoke("profile.getSelf");
        f.Handler.ReadReply = (_, _) => Task.FromResult(JsonRead(f.Handler.Profile with { Subject = "other" }));
        var invalid = await Invoke("profile.getSelf");
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.NotFound) { Content = new StringContent("{}") });
        var unavailable = await Invoke("profile.getSelf");
        f.Handler.ReadReply = (_, _) => throw new InvalidOperationException("synthetic private internal error");
        var internalError = await Invoke("profile.getSelf");
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) { Content = new StringContent("{}") });
        var transientWithoutCache = await Invoke("profile.getSelf");
        f.Handler.ReadReply = null;
        var saved = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        var cleared = (await f.Send("profile.clearLocalCache", new { schemaVersion = 1 })).Response;
        return JsonSerializer.Serialize(new { current, identity, live, cached, forbidden, invalid, unavailable, internalError, transientWithoutCache, saved, cleared }, BridgeProtocol.JsonOptions);
    }
    private static HttpResponseMessage JsonRead(object value) => new(HttpStatusCode.OK) { Content = JsonContent.Create(value) };
}
