using System.Net;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;

internal static class ScmRegionFallbackTests
{
    internal static async Task Verify()
    {
        var names = new[] { "STARBRIDGE_ENVIRONMENT", "STARBRIDGE_SCM_REGION_DISCOVERY_ENABLED",
            "STARBRIDGE_SCM_REGION_API_URL", "STARBRIDGE_SCM_WEB_BASE_URL", "STARBRIDGE_SCM_API_BASE_URL",
            "STARBRIDGE_SCM_RESOURCE_BASE_URL", "STARBRIDGE_RELAY_BASE_URL", "STARBRIDGE_SCM_TRUSTED_REGION_HOSTS",
            "STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED", "STARBRIDGE_SCM_REGION_TIMEOUT_MS",
            "STARBRIDGE_SCM_REGION_CACHE_SECONDS", "STARBRIDGE_SCM_REGION_FALLBACK_API_URL", "STARBRIDGE_SCM_WS_BASE_URL" };
        var previous = names.ToDictionary(name => name, Environment.GetEnvironmentVariable);
        var root = Directory.CreateTempSubdirectory("sb-region-offline-").FullName;
        try
        {
            foreach (var name in names) Environment.SetEnvironmentVariable(name, null);
            var settings = ScmEnvironmentSettings.Load();
            Check(settings.RegionDiscoveryEnabled, "production discovery defaults on");
            using var transport = ScmRuntimeConfiguration.CreateRegionHttpHandler();
            Check(!transport.UseCookies && !transport.AllowAutoRedirect, "anonymous nonredirecting transport");
            using var noCalls = new Fixture("forbidden");
            using var disabledHttp = new HttpClient(noCalls);
            var baseline = await new ScmRegionRouter(disabledHttp, Path.Combine(root, "disabled"), webSocketProbe: NeverWs)
                .ResolveAsync(settings with { RegionDiscoveryEnabled = false }, default);
            Check(noCalls.Calls == 0, "explicit false sends no requests");
            Check(baseline.ApiBaseUri.AbsoluteUri == "https://scmk.flowcld.com/" &&
                baseline.ResourceBaseUri.AbsoluteUri == "https://scmk.flowcld.com/" &&
                baseline.EffectiveWebSocketBaseUri.AbsoluteUri == "https://scmk.flowcld.com/", "three original production defaults");
            foreach (var scenario in new[] { "origin.flowcld.top", "forbidden", "transport", "invalid-json", "timeout", "redirect", "untrusted-host", "untrusted-ws" })
            foreach (var cn in new bool?[] { false, null })
            {
                using var handler = new Fixture(scenario, isCN: cn);
                using var http = new HttpClient(handler);
                var path = Path.Combine(root, scenario + cn);
                var lines = new List<string>();
                var route = await new ScmRegionRouter(http, path, lines.Add, NeverWs).ResolveAsync(
                    settings with { RegionRequestTimeout = TimeSpan.FromMilliseconds(scenario == "timeout" ? 30 : 5000) }, default);
                EqualEndpoints(baseline, route, scenario);
                Check(handler.Calls == 1 && File.Exists(path), "overseas classification is remembered without a preflight");
                var again = await new ScmRegionRouter(http, path, lines.Add, NeverWs).ResolveAsync(
                    settings with { RegionRequestTimeout = TimeSpan.FromMilliseconds(scenario == "timeout" ? 30 : 5000) }, default);
                EqualEndpoints(baseline, again, scenario + " cached");
                Check(handler.Calls == 1, "overseas start-up sends no further classification request while cached");
                using (var saved = JsonDocument.Parse(File.ReadAllText(path))) {
                    var failed = scenario is "forbidden" or "transport" or "invalid-json" or "timeout" or "redirect";
                    var age = DateTimeOffset.UtcNow - saved.RootElement.GetProperty("ResolvedAt").GetDateTimeOffset();
                    Check(failed ? age > settings.RegionCacheDuration - TimeSpan.FromHours(1.1) : age < TimeSpan.FromMinutes(5),
                        "classifier failures are remembered for one hour, overseas results for the full period");
                }
                AssertPrivateFieldsAbsent(lines);
            }
            foreach (var schema in new[] { 2, 3, 4 })
            foreach (var cn in new bool?[] { false, null })
            {
                var path = Path.Combine(root, "old-overseas-" + schema + cn);
                WriteCache(path, "origin.flowcld.top", schema, cn);
                var before = File.ReadAllBytes(path);
                var route = await new ScmRegionRouter(disabledHttp, path, webSocketProbe: NeverWs).ResolveAsync(settings, default);
                EqualEndpoints(baseline, route, "old overseas cache");
                Check(noCalls.Calls == 0 && before.SequenceEqual(File.ReadAllBytes(path)), "old cache no requests or writes");
            }
            foreach (var kind in new[] { "disabled", "development", "explicit", "locked" })
            {
                var current = settings with
                {
                    RegionDiscoveryEnabled = kind != "disabled", EnvironmentName = kind == "development" ? "development" : "production",
                    HasExplicitRouteOverride = kind == "explicit", AccountAccessEnabled = kind != "locked"
                };
                var path = Path.Combine(root, kind);
                WriteDomesticCache(path);
                var before = File.ReadAllBytes(path);
                using (var held = new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None))
                {
                    var route = await new ScmRegionRouter(disabledHttp, path, webSocketProbe: NeverWs).ResolveAsync(current, default);
                    EqualEndpoints(baseline, route, kind);
                }
                Check(noCalls.Calls == 0 && before.SequenceEqual(File.ReadAllBytes(path)), kind + " bypasses cache and HTTP");
            }
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_API_BASE_URL", "https://api.example.invalid/");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_RESOURCE_BASE_URL", "https://resource.example.invalid/");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_WS_BASE_URL", "wss://ws.example.invalid/");
            var explicitSettings = ScmEnvironmentSettings.Load();
            var explicitRoute = await new ScmRegionRouter(disabledHttp, Path.Combine(root, "override"), webSocketProbe: NeverWs)
                .ResolveAsync(explicitSettings, default);
            Check(explicitRoute.ApiBaseUri == explicitSettings.ApiBaseUri && explicitRoute.ResourceBaseUri == explicitSettings.ResourceBaseUri &&
                explicitRoute.EffectiveWebSocketBaseUri == explicitSettings.EffectiveWebSocketBaseUri && noCalls.Calls == 0, "loaded explicit addresses win");
            foreach (var name in names) Environment.SetEnvironmentVariable(name, null);
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_REGION_DISCOVERY_ENABLED", "false");
            Check(!ScmEnvironmentSettings.Load().RegionDiscoveryEnabled, "explicit false respected");
            Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "development");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_REGION_DISCOVERY_ENABLED", null);
            var development = ScmEnvironmentSettings.Load();
            Check(!development.RegionDiscoveryEnabled && development.ApiBaseUri.IsLoopback, "development defaults unchanged");
            Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", null);
            await Domestic(settings, baseline, root);
            Console.WriteLine("PASS regional routing: overseas/default/cache, overrides, strict API contract, WS outcomes (offline fixtures)");
        }
        finally
        {
            foreach (var (name, value) in previous) Environment.SetEnvironmentVariable(name, value);
            Directory.Delete(root, true);
        }
    }

    private static async Task Domestic(ScmEnvironmentSettings settings, ScmRegionRoute baseline, string root)
    {
        foreach (var status in new[] { 101, 400, 401, 426 })
        {
            var wsCalls = 0;
            Task<ScmWebSocketProbeResult> Probe(Uri uri, CancellationToken token)
            {
                Check(uri.AbsoluteUri == "wss://ws.flowcld.xyz/infra/ws/chat" && token.CanBeCanceled, "exact bounded WS probe");
                wsCalls++;
                return Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(status));
            }
            using var fixture = new Fixture("origin.flowcld.top", isCN: true);
            using var http = new HttpClient(fixture);
            var path = Path.Combine(root, "domestic-" + status);
            var router = new ScmRegionRouter(http, path, webSocketProbe: Probe);
            var route = await router.ResolveAsync(settings, default);
            Check(route.Source == "region-api" && route.IsCN == true && route.ApiBaseUri.Host == "flowcld.xyz" &&
                route.ResourceBaseUri == route.ApiBaseUri && route.EffectiveWebSocketBaseUri.Host == "ws.flowcld.xyz", "domestic selected");
            var cached = await router.ResolveAsync(settings, default);
            Check(cached.Source == "cache" && wsCalls == 2 && fixture.Calls == 3, "cache repeats both probes");
            using var cache = JsonDocument.Parse(File.ReadAllText(path));
            Check(cache.RootElement.GetProperty("SchemaVersion").GetInt32() == 4, "domestic cache v4");
        }
        foreach (var source in new[] { "region-api", "cache" })
        foreach (var failure in new[] { "timeout", "503", "transport", "302", "no-response", "403", "404", "429", "unexpected" })
        {
            var path = Path.Combine(root, $"ws-{source}-{failure}");
            if (source == "cache") WriteDomesticCache(path);
            var before = File.Exists(path) ? File.ReadAllBytes(path) : null;
            using var fixture = new Fixture("origin.flowcld.top", isCN: true);
            using var http = new HttpClient(fixture);
            var lines = new List<string>();
            Task<ScmWebSocketProbeResult> Probe(Uri _, CancellationToken token) => failure switch
            {
                "timeout" => Task.FromException<ScmWebSocketProbeResult>(new TaskCanceledException()),
                "transport" or "no-response" => Task.FromException<ScmWebSocketProbeResult>(new HttpRequestException("Private failure")),
                "unexpected" => Task.FromException<ScmWebSocketProbeResult>(new NotSupportedException("Private failure")),
                _ => Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(int.Parse(failure)))
            };
            var router = new ScmRegionRouter(http, path, lines.Add, Probe);
            var config = await ScmRuntimeConfiguration.ResolveAsync(settings, Path.Combine(root, $"run-{source}-{failure}"),
                router.ResolveAsync, default, _ => { });
            Check(config.RouteSource == "fallback-preflight" && config.OAuthOptions.AuthorizationServerBaseUri == baseline.ApiBaseUri &&
                config.OAuthOptions.ResourceServerBaseUri == baseline.ResourceBaseUri &&
                config.OAuthOptions.WebSocketEndpoint.Host == baseline.EffectiveWebSocketBaseUri.Host, "WS failure defaults");
            Check(File.Exists(path) && (before is null || before.SequenceEqual(File.ReadAllBytes(path))), "failed WS preserves cache");
            Check(lines.Single() == "failure=" + (failure switch
            { "timeout" => "ws-timeout", "transport" or "no-response" or "unexpected" => "ws-transport", _ => "ws-http status=" + failure }), "WS failure category only");
            var calls = fixture.Calls;
            _ = config.RouteState!.SaveMode("overseas");
            _ = config.RouteState.SaveMode("auto");
            Check(config.RouteSource == "fallback-preflight" && fixture.Calls == calls, "runtime never switches back");
        }
        foreach (var outcome in new[] { "timeout", "502", "transport", "invalid-json", "302", "401", "403", "404", "429", "500", "201", "204",
            "empty-object", "null", "business-error", "empty-data", "missing-code", "string-code", "array-root", "object-data", "missing-data", "null-data", "invalid-items", "blank-value", "unexpected" })
        {
            using var fixture = new Fixture("origin.flowcld.top", outcome, true);
            using var http = new HttpClient(fixture);
            var route = await new ScmRegionRouter(http, Path.Combine(root, "api-" + outcome), _ => { }, NeverWs).ResolveAsync(settings, default);
            EqualEndpoints(baseline, route, "API " + outcome);
            Check(route.Source == "fallback-preflight", "API failure precedes WS");
        }
        using var cancellation = new CancellationTokenSource(TimeSpan.FromMilliseconds(100));
        using var cancelFixture = new Fixture("origin.flowcld.top", "timeout", true);
        using var cancelHttp = new HttpClient(cancelFixture);
        try
        {
            await new ScmRegionRouter(cancelHttp, Path.Combine(root, "cancel"), _ => { }, NeverWs).ResolveAsync(settings, cancellation.Token);
            throw new Exception("Caller cancellation was lost");
        }
        catch (OperationCanceledException) when (cancellation.IsCancellationRequested) { }
    }

    private static Task<ScmWebSocketProbeResult> NeverWs(Uri _, CancellationToken __) => throw new Exception("Unexpected WS probe");
    private static void EqualEndpoints(ScmRegionRoute expected, ScmRegionRoute actual, string label) => Check(
        expected.ApiBaseUri == actual.ApiBaseUri && expected.ResourceBaseUri == actual.ResourceBaseUri &&
        expected.EffectiveWebSocketBaseUri == actual.EffectiveWebSocketBaseUri, label + " matches all three default endpoints");
    private static void WriteDomesticCache(string path) => File.WriteAllText(path, JsonSerializer.Serialize(new
    {
        ApiBaseUri = "https://flowcld.xyz/", ResourceBaseUri = "https://flowcld.xyz/", WebSocketBaseUri = "https://ws.flowcld.xyz/",
        ResolvedAt = DateTimeOffset.UtcNow.AddMinutes(-5), SchemaVersion = 4, IsCN = true
    }));
    private static void WriteCache(string path, string host, int schema = 3, bool? isCN = null) => File.WriteAllText(path, JsonSerializer.Serialize(new
    {
        ApiBaseUri = $"https://{host}/", ResourceBaseUri = $"https://{host}/", WebSocketBaseUri = $"https://{host}/",
        ResolvedAt = DateTimeOffset.UtcNow.AddMinutes(-5), SchemaVersion = schema, IsCN = isCN
    }));

    private static void AssertPrivateFieldsAbsent(IEnumerable<string> lines)
    {
        var text = string.Join(" ", lines);
        foreach (var value in new[] { "PrivateCity", "PrivateCountry", "PrivateRegion", "PrivateTimezone", "31.234567", "121.765432" })
            Check(!text.Contains(value), "diagnostics omit location value " + value);
    }

    private static void Check(bool condition, string message)
    { if (!condition) throw new InvalidOperationException("Regional fallback: " + message); }

    private sealed class Fixture(string scenario, string preflight = "ok", bool? isCN = false) : HttpMessageHandler
    {
        internal int Calls;
        internal List<Uri?> Endpoints = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Calls++;
            Endpoints.Add(request.RequestUri);
            if (request.RequestUri?.AbsolutePath == "/app-api/member/timezone/list")
            {
                Check(request.Method == HttpMethod.Get && !request.Headers.Any(),
                    "preflight is one anonymous GET with no headers");
                if (preflight == "timeout") await Task.Delay(Timeout.Infinite, token);
                if (preflight == "transport") throw new HttpRequestException("PrivateCity 31.234567");
                // CX-T31R: e.g. an invalid charset surfaces as InvalidOperationException while decoding.
                if (preflight == "unexpected") throw new InvalidOperationException("PrivateCity 31.234567");
                var preflightBody = preflight switch
                {
                    "ok" => """{"code":0,"data":[{"value":"UTC"}]}""",
                    "mixed-valid" => """{"code":0,"data":[null,{},{"value":7},{"value":"UTC"}]}""",
                    "empty-object" => "{}",
                    "null" => "null",
                    "business-error" => """{"code":401}""",
                    "empty-data" => """{"code":0,"data":[]}""",
                    "missing-code" => """{"data":[{"value":"UTC"}]}""",
                    "string-code" => """{"code":"0","data":[{"value":"UTC"}]}""",
                    "array-root" => "[]",
                    "object-data" => """{"code":0,"data":{}}""",
                    "missing-data" => """{"code":0}""",
                    "null-data" => """{"code":0,"data":null}""",
                    "invalid-items" => """{"code":0,"data":[null,{},{"value":7}]}""",
                    "blank-value" => """{"code":0,"data":[{"value":""},{"value":" "}]}""",
                    _ => "PrivateCity 31.234567"
                };
                var reply = new HttpResponseMessage(int.TryParse(preflight, out var status)
                    ? (HttpStatusCode)status : HttpStatusCode.OK) { Content = new StringContent(preflightBody) };
                if (preflight == "302") reply.Headers.Location = new Uri("https://redirect.example.invalid/target");
                return reply;
            }
            Check(request.Method == HttpMethod.Get && request.Headers.Authorization is null &&
                request.RequestUri?.AbsolutePath == "/app-api/region", "discovery is anonymous and scoped");
            if (scenario == "transport") throw new HttpRequestException("Synthetic transport failure");
            if (scenario == "timeout") await Task.Delay(Timeout.Infinite, token);
            var body = scenario switch
            {
                "invalid-json" => "<html>synthetic denial</html>",
                "untrusted-host" => JsonSerializer.Serialize(new { apiHost = "not-trusted.example.invalid" }),
                "untrusted-ws" => JsonSerializer.Serialize(new { apiHost = "scmk.flowcld.com", wsHost = "untrusted.example.invalid" }),
                "domestic-no-ws" => JsonSerializer.Serialize(new { apiHost = "flowcld.xyz" }),
                _ => JsonSerializer.Serialize(new { country = "PrivateCountry", city = "PrivateCity", region = "PrivateRegion",
                    timezone = "PrivateTimezone", latitude = 31.234567, longitude = 121.765432, isCN = isCN,
                    apiHost = scenario, wsHost = scenario, cacheMaxAge = 86400, timestamp = 1792627200 }, new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull })
            };
            var response = new HttpResponseMessage(scenario == "forbidden" ? HttpStatusCode.Forbidden :
                scenario == "redirect" ? HttpStatusCode.Found : HttpStatusCode.OK)
            { Content = new StringContent(body, Encoding.UTF8, "application/json") };
            if (scenario == "forbidden") response.Headers.Add("cf-mitigated", "challenge");
            if (scenario == "redirect") response.Headers.Location = new Uri("https://redirect.example.invalid/target");
            return response;
        }
    }
}
