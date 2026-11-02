using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

internal static partial class OfficialFleetReadTests
{
    internal static async Task ProfileReads()
    {
        await ProfileBackgroundImages();
        foreach (var (status, state) in new[] {
            (HttpStatusCode.RequestTimeout, "transientFailure"), (HttpStatusCode.TooManyRequests, "transientFailure"),
            (HttpStatusCode.ServiceUnavailable, "transientFailure"), ((HttpStatusCode)599, "transientFailure"),
            (HttpStatusCode.Forbidden, "forbidden"), (HttpStatusCode.Unauthorized, "forbidden"),
            (HttpStatusCode.BadRequest, "unavailable"), ((HttpStatusCode)799, "unavailable") })
        {
            using var handler = new Handler();
            handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(status) {
                Content = new StringContent("{}") }) : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            CheckProfile(await Read(dispatcher, host, false, "profile-status"), state);
        }
        foreach (var (error, state) in new (Exception, string)[] {
            (new HttpRequestException(), "transientFailure"), (new IOException(), "transientFailure"),
            (new OperationCanceledException(), "transientFailure"), (new TimeoutException(), "transientFailure"),
            (new FormatException(), "invalid"), (new JsonException(), "invalid"),
            (new InvalidDataException(), "invalid"), (new InvalidOperationException(), "invalid"),
            (new System.Text.RegularExpressions.RegexMatchTimeoutException("synthetic-html", "expression", TimeSpan.FromMilliseconds(1)), "invalid"),
            (new Exception("private-optional-profile-detail"), "unavailable") })
        {
            using var handler = new Handler();
            handler.Failure = (request, _) => IsProfile(request) ? throw error : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var response = await Read(dispatcher, host, false, "profile-exception");
            CheckProfile(response, state);
            Require(!JsonSerializer.Serialize(response, BridgeProtocol.JsonOptions).Contains("private-optional-profile-detail"), "Exception text must not reach the optional field contract");
        }
        foreach (var body in new[] { "{", "{\"code\":0,\"data\":{\"id\":8,\"sid\":\"OTHER\"}}", new string('x', 1024 * 1024 + 1) })
        {
            using var handler = new Handler();
            handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) }) : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            CheckProfile(await Read(dispatcher, host, false, "profile-invalid-body"), "invalid");
        }
        using (var handler = new Handler())
        using (var host = Host(handler))
        using (var dispatcher = new AccountBridgeDispatcher(host))
        {
            var success = await Read(dispatcher, host, false, "profile-success");
            CheckProfile(success, "available");
            var profileTime = success.Payload.GetProperty("profileRead").GetProperty("observedAtUtc").GetDateTimeOffset();
            Require(profileTime >= success.Payload.GetProperty("observedAtUtc").GetDateTimeOffset(), "Profile completion time is independent from earlier membership confirmation");
            handler.NoFleet = true;
            var absent = await Read(dispatcher, host, false, "no-fleet");
            Require(absent.Payload.GetProperty("state").GetString() == "notMember" &&
                (!absent.Payload.TryGetProperty("profileRead", out var metadata) || metadata.ValueKind == JsonValueKind.Null), "No membership must not carry a profile read");
        }
        using (var handler = new Handler())
        using (var host = Host(handler))
        using (var dispatcher = new AccountBridgeDispatcher(host))
        {
            var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
            var release = new TaskCompletionSource<HttpResponseMessage>(TaskCreationOptions.RunContinuationsAsynchronously);
            handler.Failure = (request, _) => {
                if (!IsProfile(request)) return null;
                started.TrySetResult();
                return release.Task;
            };
            var pending = Read(dispatcher, host, false, "profile-late-owner");
            await started.Task.WaitAsync(TimeSpan.FromSeconds(3));
            host.Dispose();
            release.SetResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{}") });
            var response = await pending;
            Require(response.Status == BridgeResponseStatuses.Error && response.Error?.Code == "account.reauthorization_required", "A retired owner cannot publish even the earlier valid membership");
        }
        using (var handler = new Handler())
        using (var host = Host(handler))
        using (var cancellation = new CancellationTokenSource())
        {
            handler.Failure = (request, _) => {
                if (!IsProfile(request)) return null;
                cancellation.Cancel();
                return Task.FromCanceled<HttpResponseMessage>(cancellation.Token);
            };
            try { await host.GetOfficialFleetAsync(host.CurrentContext!, cancellation.Token); }
            catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { return; }
            throw new InvalidOperationException("Caller cancellation became optional-field success");
        }
    }

    private static async Task ProfileBackgroundImages()
    {
        const string background = "https://example.invalid/background.jpg";
        const string banner = "https://example.invalid/banner.jpg";
        foreach (var (field, expected, state) in new (string, string?, string)[] {
            (",\"backgroundImage\":\"" + background + "\"", background, "available"),
            ("", null, "available"),
            (",\"backgroundImage\":null", null, "available"),
            (",\"backgroundImage\":\"http://example.invalid/background.jpg\"", null, "available"),
            (",\"backgroundImage\":\"https://viewer@example.invalid/background.jpg\"", null, "available"),
            (",\"backgroundImage\":\"https://\"", null, "available"),
            (",\"backgroundImage\":42", null, "invalid"),
            (",\"backgroundImage\":\"" + new string('x', 2049) + "\"", null, "invalid") })
        {
            var body = "{\"code\":0,\"data\":{\"id\":7,\"sid\":\"ASTER\",\"banner\":\"" + banner + "\"" + field + "}}";
            using var handler = new Handler();
            handler.Failure = (request, _) => IsProfile(request)
                ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(body) })
                : null;
            using var host = Host(handler);
            using var dispatcher = new AccountBridgeDispatcher(host);
            var response = await Read(dispatcher, host, false, "profile-background");
            CheckProfile(response, state);
            if (state != "available") continue;

            using var data = JsonDocument.Parse(body);
            var model = StarBridge.HostRuntime.OfficialFleet.OfficialFleetReadModel.Profile(
                data.RootElement.GetProperty("data"), "officialFleet:7", "ASTER");
            Require(model.BackgroundUrl == expected, "Background model preserves valid HTTPS or null");
            var profile = response.Payload.GetProperty("fleet").GetProperty("profile");
            Require(profile.GetProperty("bannerUrl").GetString() == banner, "Banner wire name remains camelCase");
            Require(!profile.TryGetProperty("BackgroundUrl", out _), "Background wire name must be camelCase");
            // BridgeProtocol omits null properties, just as it does for bannerUrl.
            if (expected is null)
                Require(!profile.TryGetProperty("backgroundUrl", out _), "Null background is omitted on the wire");
            else
                Require(profile.GetProperty("backgroundUrl").GetString() == expected,
                    "Bridge profile includes the original backgroundUrl");
        }
    }

    internal static async Task<string> ProfileReadWire()
    {
        using var handler = new Handler();
        using var host = Host(handler);
        using var dispatcher = new AccountBridgeDispatcher(host);
        var success = await Read(dispatcher, host, false, "profile-success");
        handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable) {Content = new StringContent("{}")}) : null;
        var transient = await Read(dispatcher, host, false, "profile-transient");
        handler.Failure = (request, _) => IsProfile(request) ? Task.FromResult(new HttpResponseMessage(HttpStatusCode.Forbidden) {Content = new StringContent("{}")}) : null;
        var forbidden = await Read(dispatcher, host, false, "profile-forbidden");
        handler.Failure = null;
        handler.BadProfile = true;
        var invalid = await Read(dispatcher, host, false, "profile-invalid");
        return JsonSerializer.Serialize(new {success, transient, forbidden, invalid}, BridgeProtocol.JsonOptions);
    }

    private static bool IsProfile(HttpRequestMessage request) => request.RequestUri!.AbsolutePath == "/app-api/member/organization/get";
    private static void CheckProfile(BridgeEnvelope response, string state)
    {
        Require(response.Status == BridgeResponseStatuses.Ok && response.Payload.GetProperty("state").GetString() == "member", "Optional profile failure must not erase verified membership");
        Require(response.Payload.TryGetProperty("profileRead", out var read) && read.GetProperty("state").GetString() == state, $"Missing or incorrect profileRead state: expected {state}");
        var hasProfile = response.Payload.GetProperty("fleet").TryGetProperty("profile", out var profile) && profile.ValueKind == JsonValueKind.Object;
        Require(hasProfile == (state == "available"), "Only a confirmed profile read can supply profile content");
        var hasTime = read.TryGetProperty("observedAtUtc", out var at) && at.ValueKind == JsonValueKind.String;
        Require(hasTime == (state == "available"), "A failed optional read must never fabricate a new content time");
    }
}
