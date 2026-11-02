using System.Net;
using System.Net.Http.Json;
using StarBridge.NativeBridge;

internal static partial class AccountPreferenceActionTests
{
    internal static async Task StagedCacheIsLocalAndScoped()
    {
        using var f = new Fixture();
        var stamp = DateTimeOffset.UtcNow.AddHours(-1);
        f.Cache.Save(f.Route, f.Handler.Profile, stamp);
        var result = await f.Send("profile.readDisplayCache", new { schemaVersion = 1 });
        Equal("ok", result.Response.Status, "local display cache route");
        Equal("cache", result.Response.Payload.GetProperty("source").GetString(), "display source");
        Equal(stamp, result.Response.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset(), "original observation time");
        Equal(false, result.Response.Payload.GetProperty("profile").TryGetProperty("email", out var email) && email.ValueKind != System.Text.Json.JsonValueKind.Null, "cached email excluded");
        Equal(0, f.Handler.Requests, "cached display must not start HTTP or refresh credentials");
        Equal(false, result.Response.Payload.GetProperty("preferencesPolicy").GetProperty("availableActions").EnumerateArray().Any(v => v.GetString() == "profile.patchPreferences"), "cache cannot enable preference writes");
        var bad = await f.Send("profile.readDisplayCache", new { schemaVersion = 1, force = true });
        Equal("error", bad.Response.Status, "unknown cache-read options rejected");
        var stale = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request("profile.readDisplayCache", Guid.NewGuid().ToString("N"), 6, new { schemaVersion = 1 }, f.Context));
        Equal("error", stale.Response.Status, "old generation cannot read cached display");
        f.Cache.Clear(f.Route);
        var empty = await f.Send("profile.readDisplayCache", new { schemaVersion = 1 });
        Equal("ok", empty.Response.Status, "cache miss is an explicit empty display, not a network request");
        Equal(false, empty.Response.Payload.TryGetProperty("profile", out var data) && data.ValueKind != System.Text.Json.JsonValueKind.Null, "cache miss has no invented data");
        Equal(0, f.Handler.Requests, "all local cache reads stay local");
    }

    internal static async Task StagedLiveDoesNotReadDirectory()
    {
        using var f = new Fixture();
        f.Handler.DirectoryReply = (_, _) => throw new InvalidOperationException("Directory must not start during display-data read");
        var result = await f.Send("profile.getDisplayData", new { schemaVersion = 1 });
        Equal("ok", result.Response.Status, "fresh display must not await auxiliary directory");
        Equal("live", result.Response.Payload.GetProperty("source").GetString(), "fresh source");
        Equal(1, f.Handler.Requests, "only actual profile endpoint requested");
        Equal(0, result.Response.Payload.GetProperty("preferencesPolicy").GetProperty("timeZones").GetArrayLength(), "no invented directory");
        Equal(false, result.Response.Payload.GetProperty("preferencesPolicy").GetProperty("availableActions").EnumerateArray().Any(v => v.GetString() == "profile.patchPreferences"), "directory still required for editing");
        Equal(f.Handler.Profile.DisplayName, f.Cache.Load(f.Route)?.DisplayName, "fresh display is durable before auxiliary IO");
    }

    internal static async Task StagedDirectoryIsIndependentAndRetired()
    {
        using var f = new Fixture();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var reply = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Handler.DirectoryReply = async (request, _) => {
            Equal(null, request.Headers.Authorization, "public time-zone directory carries no bearer");
            entered.TrySetResult();
            return await reply.Task;
        };
        var read = f.Send("profile.getTimeZoneDirectory", new { schemaVersion = 1 }).AsTask();
        try {
            await Task.WhenAny(read, entered.Task).WaitAsync(TimeSpan.FromSeconds(3));
            Equal(false, read.IsCompleted, "directory actually started and is held");
            await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
            var current = await f.Dispatcher.DispatchAsync(BridgeEnvelope.Request("account.getCurrent", Guid.NewGuid().ToString("N"), 7, new { schemaVersion = 1 })).AsTask().WaitAsync(TimeSpan.FromSeconds(3));
            Equal("ok", current.Response.Status, "held public directory cannot occupy private account queue");
            Equal("ok", (await f.Send("account.logout", new { schemaVersion = 1 })).Response.Status, "logout remains independent of public directory");
        } finally {
            reply.TrySetResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = JsonContent.Create(new { code = 0, data = new[] { new { value = "UTC", label = "UTC", offset = "UTC+00:00" } } }) });
        }
        Equal("error", (await read).Response.Status, "retired directory cannot return old-owner success");
    }

    internal static async Task<string> StagedProfileWire()
    {
        using var f = new Fixture();
        async Task<BridgeEnvelope> Read(string name) => (await f.Send(name, new { schemaVersion = 1 })).Response;
        var current = await Read("account.getCurrent");
        var empty = await Read("profile.readDisplayCache");
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow.AddHours(-1));
        var cached = await Read("profile.readDisplayCache");
        var live = await Read("profile.getDisplayData");
        var cachedAfterLive = await Read("profile.readDisplayCache");
        var directory = await Read("profile.getTimeZoneDirectory");
        var identity = await Read("gameIdentity.getPolicy");
        f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) { Content = new StringContent("{}") });
        var forbidden = await Read("profile.getDisplayData");
        var retired = await Read("profile.readDisplayCache");
        f.Handler.ReadReply = null;
        var saved = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        var cachedAfterSaved = await Read("profile.readDisplayCache");
        var cleared = await Read("profile.clearLocalCache");
        return System.Text.Json.JsonSerializer.Serialize(new { current, empty, cached, live, cachedAfterLive,
            directory, identity, forbidden, retired, saved, cachedAfterSaved, cleared }, BridgeProtocol.JsonOptions);
    }

    internal static async Task StagedDirectoryFailuresStayIndependent()
    {
        foreach (var (create, retryable, code) in new (Func<Exception>, bool, string)[] {
            (() => new HttpRequestException("synthetic", null, HttpStatusCode.Unauthorized), false, "profile.directory_unavailable"),
            (() => new HttpRequestException("synthetic", null, HttpStatusCode.Forbidden), false, "profile.directory_unavailable"),
            (() => new HttpRequestException("synthetic", null, HttpStatusCode.ServiceUnavailable), true, "profile.directory_unavailable"),
            (() => new OperationCanceledException("synthetic internal deadline"), true, "profile.directory_unavailable"),
            (() => new StarBridge.HostRuntime.Auth.ScmApiProtocolException("synthetic invalid directory"), false, "profile.directory_unavailable"),
            (() => new System.Text.Json.JsonException("synthetic invalid JSON"), false, "profile.directory_unavailable"),
            (() => new InvalidOperationException("synthetic internal failure"), false, "bridge.host_error") }) {
            using var f = new Fixture();
            f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow.AddMinutes(-1));
            f.Handler.DirectoryReply = (request, _) => {
                Equal(null, request.Headers.Authorization, "public auxiliary never carries bearer");
                return Task.FromException<HttpResponseMessage>(create());
            };
            var result = (await f.Send("profile.getTimeZoneDirectory", new { schemaVersion = 1 })).Response;
            Equal(code, result.Error?.Code, "independent directory error");
            Equal(retryable, result.Error?.Retryable, "only known transient directory errors retry");
            Equal(f.Context, f.Host.CurrentContext, "public directory failure cannot retire private account");
            Equal(f.Handler.Profile.DisplayName, f.Cache.Load(f.Route)?.DisplayName, "directory failure cannot remove private cached display");
            Equal(0, f.Handler.ReadTokens.Count, "public failure does not replay a private profile read");
        }
    }

    internal static async Task StagedConfirmedMemorySurvivesSuppressedDisk()
    {
        using var f = new Fixture();
        f.Cache.Save(f.Route, f.Handler.Profile, DateTimeOffset.UtcNow.AddHours(-1));
        var path = Directory.GetFiles(Path.Combine(f.Root.FullName, "scm-profile-cache"), "*.json").Single();
        using (File.Open(path, FileMode.Open, FileAccess.Read, FileShare.Read)) {
            f.Handler.ReadReply = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) { Content = new StringContent("{}") });
            Equal("profile.read_forbidden", (await f.Send("profile.getDisplayData", new { schemaVersion = 1 })).Response.Error?.Code, "hard denial retires display even if disk cannot be deleted");
            f.Handler.ReadReply = (_, _) => Task.FromResult(JsonRead(f.Handler.Profile with { DisplayName = "New confirmed data" }));
            var live = (await f.Send("profile.getDisplayData", new { schemaVersion = 1 })).Response;
            Equal("live", live.Payload.GetProperty("source").GetString(), "fresh data survives disk-write failure");
            var cached = (await f.Send("profile.readDisplayCache", new { schemaVersion = 1 })).Response;
            Equal("cache", cached.Payload.GetProperty("source").GetString(), "suppressed old disk cannot suppress newer confirmed memory");
            Equal("New confirmed data", cached.Payload.GetProperty("profile").GetProperty("displayName").GetString(), "only new confirmed display is retained");
            Equal(live.Payload.GetProperty("observedAtUtc").GetDateTimeOffset(), cached.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset(), "memory read preserves actual confirmed observation time");
        }
        Equal("Synthetic pilot", f.Cache.Load(f.Route)?.DisplayName, "test genuinely retained the older disk file");
    }

    internal static async Task StagedConfirmedWriteObservationIsShared()
    {
        using var f = new Fixture();
        var saved = (await f.Send("profile.patchPreferences", new { schemaVersion = 1, patch = new { locale = "en-US" } })).Response;
        Equal("ok", saved.Status, "confirmed preference write");
        var observed = saved.Payload.GetProperty("observedAtUtc").GetDateTimeOffset();
        Equal(observed, f.Cache.Load(f.Route)?.CachedAtUtc, "saved response and disk describe the same confirmed observation");
        var cached = (await f.Send("profile.readDisplayCache", new { schemaVersion = 1 })).Response;
        Equal(observed, cached.Payload.GetProperty("cachedAtUtc").GetDateTimeOffset(), "subsequent local view retains saved observation, not time of reopening");
    }

    internal static async Task StagedReadCancellationOwnsCallbackExit()
    {
        await using var reads = new StarBridge.HostRuntime.Lifecycle.BridgeReadCancellation(default);
        var request = BridgeEnvelope.Request("profile.getDisplayData", "callback-owner", 7, new { schemaVersion = 1 }, new("integration", "synthetic", "owner"));
        Equal(true, reads.Register(request), "read registered");
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        using var release = new ManualResetEventSlim();
        using var registration = reads.TokenFor(request).Register(() => { entered.TrySetResult(); release.Wait(); });
        Equal(true, reads.Cancel(BridgeEnvelope.Request("bridge.cancel", "cancel-callback", 7, new { targetCorrelationId = "callback-owner" })), "cancel is requested without blocking reader on callback");
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(3));
        var completion = reads.CompleteAsync(request).AsTask();
        try { Equal(false, completion.IsCompleted, "read ownership is retained through actual callback exit"); }
        finally { release.Set(); }
        await completion.WaitAsync(TimeSpan.FromSeconds(3));
    }
}
