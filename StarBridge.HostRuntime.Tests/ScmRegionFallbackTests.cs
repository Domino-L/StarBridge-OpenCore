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
            Check(!settings.HasExplicitWebBaseOverride, "default web root is not explicit");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_WEB_BASE_URL", "https://scm.flowcld.com/");
            var explicitWeb = ScmEnvironmentSettings.Load();
            Check(explicitWeb.HasExplicitWebBaseOverride, "explicit default-valued web root remains explicit");
            Check(!explicitWeb.HasExplicitRouteOverride, "web override does not change API routing");
            var domesticWebRoute = new ScmRegionRoute(new Uri("https://flowcld.xyz/"),
                new Uri("https://flowcld.xyz/"), "region-api", DateTimeOffset.UnixEpoch);
            Check(ScmOAuthOptions.Create(explicitWeb, domesticWebRoute).AuthorizeEndpoint ==
                new Uri("https://scm.flowcld.com/oauth/authorize"), "explicit web root wins");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_WEB_BASE_URL", null);
            Check(settings.RegionFallbackApiUri == new Uri("https://flowcld.xyz/app-api/region"), "production secondary default");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_REGION_FALLBACK_API_URL", "https://secondary.example.invalid/app-api/region");
            Check(ScmEnvironmentSettings.Load().RegionFallbackApiUri == new Uri("https://secondary.example.invalid/app-api/region/"),
                "explicit secondary overrides built-in default using existing URI normalization");
            Environment.SetEnvironmentVariable("STARBRIDGE_SCM_REGION_FALLBACK_API_URL", null);
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
                var failed = scenario is "forbidden" or "transport" or "invalid-json" or "timeout" or "redirect";
                var expectedCalls = failed ? 2 : 1;
                Check(handler.Calls == expectedCalls && File.Exists(path), "classifiers run in order without overseas preflight");
                var again = await new ScmRegionRouter(http, path, lines.Add, NeverWs).ResolveAsync(
                    settings with { RegionRequestTimeout = TimeSpan.FromMilliseconds(scenario == "timeout" ? 30 : 5000) }, default);
                EqualEndpoints(baseline, again, scenario + " cached");
                Check(handler.Calls == expectedCalls, "overseas start-up sends no further classification request while cached");
                using (var saved = JsonDocument.Parse(File.ReadAllText(path))) {
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
            Check(development.RegionFallbackApiUri is null, "development has no secondary default");
            Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "local");
            Check(ScmEnvironmentSettings.Load().RegionFallbackApiUri is null, "local has no secondary default");
            Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", null);
            await Domestic(settings, baseline, root);
            await SecondaryClassification(settings, baseline, root);
            await RetainedDomestic(settings, baseline, root);
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

    private static async Task SecondaryClassification(ScmEnvironmentSettings settings, ScmRegionRoute baseline, string root)
    {
        var now = DateTimeOffset.Parse("2026-11-13T12:00:00Z");
        foreach (var cn in new[] { false, true })
        foreach (var primary in new[] { "ok", "transport", "timeout", "forbidden", "redirect", "invalid-json" })
        {
            var path = Path.Combine(root, $"secondary-{primary}-{cn}");
            using var fixture = new Fixture(primary, isCN: cn, secondaryScenario: "ok");
            using var http = new HttpClient(fixture);
            var probes = 0;
            Task<ScmWebSocketProbeResult> Probe(Uri _, CancellationToken __)
            {
                probes++;
                return Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(101));
            }
            var route = await new ScmRegionRouter(http, path, _ => { }, Probe, () => now).ResolveAsync(
                settings with { RegionRequestTimeout = TimeSpan.FromMilliseconds(primary == "timeout" ? 30 : 5000) }, default);
            var classifiers = fixture.Endpoints.Where(uri => uri?.AbsolutePath == "/app-api/region").ToArray();
            Check(classifiers.SequenceEqual(primary == "ok"
                ? new[] { settings.RegionApiUri }
                : new[] { settings.RegionApiUri, settings.RegionFallbackApiUri }), "exact primary/secondary order, stop at first success");
            Check(fixture.Calls == classifiers.Length + (cn ? 1 : 0) && probes == (cn ? 1 : 0),
                "only domestic results run both preflight probes");
            using var cache = JsonDocument.Parse(File.ReadAllText(path));
            Check(cache.RootElement.GetProperty("IsCN").GetBoolean() == cn &&
                cache.RootElement.GetProperty("ResolvedAt").GetDateTimeOffset() == now, "successful classification cached at current time");
            if (cn)
            {
                Check(route.Source == "region-api" && route.IsCN == true &&
                    route.ApiBaseUri == new Uri("https://flowcld.xyz/") && route.ResourceBaseUri == route.ApiBaseUri &&
                    route.EffectiveWebSocketBaseUri == new Uri("https://ws.flowcld.xyz/"), "secondary domestic fixed endpoints");
                Check(cache.RootElement.GetProperty("ConfirmedAt").GetDateTimeOffset() == now, "real domestic confirmation timestamp");
            }
            else
            {
                EqualEndpoints(baseline, route, "secondary overseas");
                Check(cache.RootElement.GetProperty("ConfirmedAt").ValueKind == JsonValueKind.Null, "overseas is not domestic confirmation");
            }
        }
        using var duplicate = new Fixture("transport");
        using var duplicateHttp = new HttpClient(duplicate);
        await new ScmRegionRouter(duplicateHttp, Path.Combine(root, "duplicate"), _ => { }, NeverWs)
            .ResolveAsync(settings with { RegionFallbackApiUri = settings.RegionApiUri }, default);
        Check(duplicate.Calls == 1, "identical classifier URIs attempted only once even on failure");

        // A real classifier result takes precedence over an eligible stale domestic cache.
        foreach (var cn in new[] { false, true })
        {
            var path = Path.Combine(root, "reclassified-" + cn);
            WriteExpiredCache(path, now.AddDays(-2), now.AddDays(-10));
            using var fixture = new Fixture("transport", isCN: cn, secondaryScenario: "ok");
            using var http = new HttpClient(fixture);
            var lines = new List<string>();
            var route = await new ScmRegionRouter(http, path, lines.Add,
                (_, _) => Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(101)), () => now).ResolveAsync(settings, default);
            using var cache = JsonDocument.Parse(File.ReadAllText(path));
            Check(cache.RootElement.GetProperty("IsCN").GetBoolean() == cn &&
                cache.RootElement.GetProperty("ResolvedAt").GetDateTimeOffset() == now &&
                !lines.Any(line => line.Contains("retained=")), "successful secondary replaces stale classification");
            if (cn)
                Check(route.Source == "region-api" && cache.RootElement.GetProperty("ConfirmedAt").GetDateTimeOffset() == now,
                    "new domestic confirmation resets the horizon");
            else
                EqualEndpoints(baseline, route, "overseas confirmation supersedes stale domestic cache");
        }
    }

    private static async Task RetainedDomestic(ScmEnvironmentSettings settings, ScmRegionRoute baseline, string root)
    {
        var now = DateTimeOffset.Parse("2026-11-13T12:00:00Z");
        foreach (var legacy in new[] { false, true })
        foreach (var preflight in new[] { "ok", "http-failure", "ws-failure" })
        {
            var path = Path.Combine(root, $"retained-{legacy}-{preflight}");
            var resolved = now.AddDays(-2);
            var confirmed = legacy ? resolved : now.AddDays(-10);
            WriteExpiredCache(path, resolved, legacy ? null : confirmed);
            using var fixture = new Fixture("transport", preflight == "http-failure" ? "503" : "ok");
            using var http = new HttpClient(fixture);
            var lines = new List<string>();
            var probes = 0;
            Task<ScmWebSocketProbeResult> Probe(Uri uri, CancellationToken token)
            {
                Check(uri == new Uri("wss://ws.flowcld.xyz/infra/ws/chat") && token.CanBeCanceled, "retained WS probe bounded");
                probes++;
                return Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(preflight == "ws-failure" ? 503 : 101));
            }
            var router = new ScmRegionRouter(http, path, lines.Add, Probe, () => now);
            var route = await router.ResolveAsync(settings, default);
            Check(fixture.Endpoints.SequenceEqual(new[] { settings.RegionApiUri, settings.RegionFallbackApiUri,
                new Uri("https://flowcld.xyz/app-api/member/timezone/list") }), "retention follows both classifier failures and HTTP preflight");
            Check(probes == (preflight == "http-failure" ? 0 : 1), "HTTP preflight precedes retained WS probe");
            if (preflight == "ok")
                Check(route.Source == "cache" && route.IsCN == true && route.ApiBaseUri == new Uri("https://flowcld.xyz/") &&
                    route.ResourceBaseUri == route.ApiBaseUri && route.EffectiveWebSocketBaseUri == new Uri("https://ws.flowcld.xyz/"),
                    "retained cache selects all domestic endpoints");
            else
            {
                EqualEndpoints(baseline, route, "retained preflight failure");
                Check(route.Source == "fallback-preflight" && route.IsCN == true, "preflight fallback is for this run only");
            }
            AssertRetainedCache(path, settings, now, confirmed);
            Check(lines.Contains("failure=all-classifiers retained=domestic") &&
                lines.All(line => !line.Contains("flowcld") && !line.Contains("https:") && !line.Contains("Synthetic")),
                "retention diagnostic contains only categories");
            AssertPrivateFieldsAbsent(lines);

            // A fresh router models another launch inside the retry hour: no classification, both preflights again.
            var before = File.ReadAllBytes(path);
            using var healthy = new Fixture("transport");
            using var healthyHttp = new HttpClient(healthy);
            var recovered = await new ScmRegionRouter(healthyHttp, path, _ => { },
                (_, _) => Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(101)), () => now.AddMinutes(30))
                .ResolveAsync(settings, default);
            Check(recovered.Source == "cache" && healthy.Calls == 1 &&
                healthy.Endpoints.Single()?.AbsolutePath == "/app-api/member/timezone/list" &&
                before.SequenceEqual(File.ReadAllBytes(path)), "next launch uses unchanged domestic cache after transient preflight failure");
        }

        foreach (var kind in new[] { "too-old", "legacy-too-old", "overseas", "missing", "wrong-api", "wrong-resource",
            "wrong-ws", "untrusted", "schema", "broken", "future-resolved", "future-confirmed", "unreadable" })
        {
            var path = Path.Combine(root, "rejected-" + kind);
            var current = kind == "untrusted" ? settings with
            { TrustedRegionHosts = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "scmk.flowcld.com" } } : settings;
            if (kind != "missing")
                WriteExpiredCache(path, kind == "future-resolved" ? now.AddMinutes(1) :
                    kind == "legacy-too-old" ? now.AddDays(-31) : now.AddDays(-2),
                    kind == "legacy-too-old" ? null : kind == "too-old" ? now.AddDays(-31) :
                    kind == "future-confirmed" ? now.AddMinutes(1) : now.AddDays(-3),
                    kind != "overseas", kind == "schema" ? 3 : 4,
                    kind == "wrong-api" ? "https://scmk.flowcld.com/" : "https://flowcld.xyz/",
                    kind == "wrong-resource" ? "https://flowcld.xyz/not-root" : "https://flowcld.xyz/",
                    kind == "wrong-ws" ? "https://flowcld.xyz/" : "https://ws.flowcld.xyz/");
            if (kind == "broken") File.WriteAllText(path, "{broken");
            var original = kind == "unreadable" ? File.ReadAllBytes(path) : null;
            using var fixture = new Fixture("transport");
            using var http = new HttpClient(fixture);
            var lines = new List<string>();
            using (var held = kind == "unreadable" ? new FileStream(path, FileMode.Open, FileAccess.ReadWrite, FileShare.None) : null)
            {
                var route = await new ScmRegionRouter(http, path, lines.Add, NeverWs, () => now).ResolveAsync(current, default);
                EqualEndpoints(baseline, route, kind);
                Check(route.Source == "fallback" && fixture.Calls == 2 && !lines.Any(line => line.Contains("retained=")),
                    "invalid retention candidate uses existing fallback: " + kind);
            }
            if (kind == "unreadable")
                Check(original!.SequenceEqual(File.ReadAllBytes(path)), "unreadable cache write failure remains nonfatal and unchanged");
            else
            {
                using var cache = JsonDocument.Parse(File.ReadAllText(path));
                Check(!cache.RootElement.GetProperty("IsCN").GetBoolean() &&
                    cache.RootElement.GetProperty("ResolvedAt").GetDateTimeOffset() + settings.RegionCacheDuration == now.AddHours(1),
                    "invalid candidate writes overseas for one hour: " + kind);
            }
        }

        // Caller cancellation during the retained preflight must not move the retry time.
        var cancelRetainedPath = Path.Combine(root, "retained-cancel");
        WriteExpiredCache(cancelRetainedPath, now.AddDays(-2), now.AddDays(-5));
        var cancelRetainedBefore = File.ReadAllBytes(cancelRetainedPath);
        using (var cancelRetained = new CancellationTokenSource())
        using (var cancelRetainedFixture = new Fixture("transport"))
        using (var cancelRetainedHttp = new HttpClient(cancelRetainedFixture))
        {
            try
            {
                await new ScmRegionRouter(cancelRetainedHttp, cancelRetainedPath, _ => { },
                    async (_, token) =>
                    {
                        cancelRetained.Cancel();
                        await Task.Delay(Timeout.Infinite, token);
                        return ScmWebSocketProbeResult.FromHttpStatus(101);
                    }, () => now).ResolveAsync(settings, cancelRetained.Token);
                throw new Exception("Retained preflight cancellation was lost");
            }
            catch (OperationCanceledException) when (cancelRetained.IsCancellationRequested) { }
        }
        Check(cancelRetainedBefore.SequenceEqual(File.ReadAllBytes(cancelRetainedPath)),
            "cancelled retained preflight leaves the domestic cache unchanged");

        // Advance only the injected clock: no rewriting fixtures between retries can mask a timestamp extension bug.
        var repeatedPath = Path.Combine(root, "repeated");
        var originalConfirmation = now.AddDays(-2);
        WriteExpiredCache(repeatedPath, originalConfirmation); // Old schema-4 cache without ConfirmedAt.
        var clock = now;
        using var repeated = new Fixture("transport");
        using var repeatedHttp = new HttpClient(repeated);
        var repeatedRouter = new ScmRegionRouter(repeatedHttp, repeatedPath, _ => { },
            (_, _) => Task.FromResult(ScmWebSocketProbeResult.FromHttpStatus(101)), () => clock);
        foreach (var age in new[] { TimeSpan.FromDays(2), TimeSpan.FromDays(3), TimeSpan.FromDays(29), TimeSpan.FromDays(30) })
        {
            clock = originalConfirmation + age;
            var route = await repeatedRouter.ResolveAsync(settings, default);
            Check(route.Source == "cache" && route.IsCN == true, "repeat failures retain through the 30-day boundary");
            AssertRetainedCache(repeatedPath, settings, clock, originalConfirmation);
        }
        Check(repeated.Calls == 12, "each expired retry makes two classifications and one HTTP preflight");
        clock = originalConfirmation.AddDays(30).AddHours(1).AddTicks(1);
        var expiredRoute = await repeatedRouter.ResolveAsync(settings, default);
        EqualEndpoints(baseline, expiredRoute, "past 30 days");
        Check(expiredRoute.Source == "fallback" && repeated.Calls == 14 &&
            ScmRegionRouter.ReadCachedClassification(repeatedPath, clock) == false, "confirmation horizon cannot be extended by repeated failures");
    }

    private static void WriteExpiredCache(string path, DateTimeOffset resolvedAt, DateTimeOffset? confirmedAt = null,
        bool isCN = true, int schema = 4, string api = "https://flowcld.xyz/", string resource = "https://flowcld.xyz/",
        string ws = "https://ws.flowcld.xyz/")
    {
        var cache = new Dictionary<string, object?>
        {
            ["ApiBaseUri"] = api, ["ResourceBaseUri"] = resource, ["WebSocketBaseUri"] = ws,
            ["ResolvedAt"] = resolvedAt, ["SchemaVersion"] = schema, ["IsCN"] = isCN
        };
        if (confirmedAt is not null) cache["ConfirmedAt"] = confirmedAt;
        File.WriteAllText(path, JsonSerializer.Serialize(cache));
    }

    private static void AssertRetainedCache(string path, ScmEnvironmentSettings settings, DateTimeOffset now, DateTimeOffset confirmed)
    {
        var text = File.ReadAllText(path);
        using var cache = JsonDocument.Parse(text);
        Check(cache.RootElement.GetProperty("SchemaVersion").GetInt32() == 4 && cache.RootElement.GetProperty("IsCN").GetBoolean(),
            "retention never writes overseas or changes schema");
        Check(cache.RootElement.GetProperty("ConfirmedAt").GetDateTimeOffset() == confirmed, "retention preserves true confirmation time");
        Check(cache.RootElement.GetProperty("ResolvedAt").GetDateTimeOffset() + settings.RegionCacheDuration == now.AddHours(1),
            "retained classification expires in exactly one hour");
        Check(ScmRegionRouter.ReadCachedClassification(path, now.AddMinutes(59)) == true &&
            ScmRegionRouter.ReadCachedClassification(path, now.AddHours(1).AddTicks(1)) is null,
            "unchanged mirror reader sees domestic only within retry hour");
        var oldReader = JsonSerializer.Deserialize<LegacyCache>(text);
        Check(oldReader is { SchemaVersion: 4, IsCN: true } &&
            oldReader.ApiBaseUri == "https://flowcld.xyz/" && oldReader.ResourceBaseUri == oldReader.ApiBaseUri &&
            oldReader.WebSocketBaseUri == "https://ws.flowcld.xyz/" && oldReader.ResolvedAt + settings.RegionCacheDuration == now.AddHours(1),
            "old cache record deserializes new optional unknown field without changing route or expiry");
    }

    // Exact pre-change cache shape and default System.Text.Json options used by the old client.
    private sealed record LegacyCache(string ApiBaseUri, string ResourceBaseUri, DateTimeOffset ResolvedAt,
        string? WebSocketBaseUri, int SchemaVersion, bool? IsCN = null);

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

    private sealed class Fixture(string scenario, string preflight = "ok", bool? isCN = false,
        string? secondaryScenario = null) : HttpMessageHandler
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
            var classification = request.RequestUri?.Host == "flowcld.xyz" ? secondaryScenario ?? scenario : scenario;
            if (classification == "transport") throw new HttpRequestException("Synthetic transport failure");
            if (classification == "timeout") await Task.Delay(Timeout.Infinite, token);
            var body = classification switch
            {
                "invalid-json" => "<html>synthetic denial</html>",
                "untrusted-host" => JsonSerializer.Serialize(new { apiHost = "not-trusted.example.invalid" }),
                "untrusted-ws" => JsonSerializer.Serialize(new { apiHost = "scmk.flowcld.com", wsHost = "untrusted.example.invalid" }),
                "domestic-no-ws" => JsonSerializer.Serialize(new { apiHost = "flowcld.xyz" }),
                _ => JsonSerializer.Serialize(new { country = "PrivateCountry", city = "PrivateCity", region = "PrivateRegion",
                    timezone = "PrivateTimezone", latitude = 31.234567, longitude = 121.765432, isCN = isCN,
                    apiHost = classification, wsHost = classification, cacheMaxAge = 86400, timestamp = 1792627200 }, new JsonSerializerOptions { DefaultIgnoreCondition = System.Text.Json.Serialization.JsonIgnoreCondition.WhenWritingNull })
            };
            var response = new HttpResponseMessage(classification == "forbidden" ? HttpStatusCode.Forbidden :
                classification == "redirect" ? HttpStatusCode.Found : HttpStatusCode.OK)
            { Content = new StringContent(body, Encoding.UTF8, "application/json") };
            if (classification == "forbidden") response.Headers.Add("cf-mitigated", "challenge");
            if (classification == "redirect") response.Headers.Location = new Uri("https://redirect.example.invalid/target");
            return response;
        }
    }
}
