using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Auth;

internal sealed record ScmEnvironmentSettings(
    string EnvironmentName,
    bool AccountAccessEnabled,
    bool RegionDiscoveryEnabled,
    Uri? RegionApiUri,
    Uri WebBaseUri,
    Uri ApiBaseUri,
    Uri ResourceBaseUri,
    Uri RelayBaseUri,
    IReadOnlySet<string> TrustedRegionHosts,
    TimeSpan RegionRequestTimeout,
    TimeSpan RegionCacheDuration,
    Uri? RegionFallbackApiUri = null,
    Uri? WebSocketBaseUri = null,
    bool HasExplicitRouteOverride = false)
{
    internal Uri EffectiveWebSocketBaseUri => NormalizeWebSocketBase(WebSocketBaseUri ?? ResourceBaseUri);
    internal string AuthorityId => $"scm-{EnvironmentName}";

    internal string TokenVaultFileName => EnvironmentName.Equals(
        "production",
        StringComparison.Ordinal)
        ? "scm-token-vault.json"
        : $"scm-token-vault.{EnvironmentName}.json";

    internal string RegionCacheFileName => EnvironmentName.Equals(
        "production",
        StringComparison.Ordinal)
        ? "scm-region-cache.json"
        : $"scm-region-cache.{EnvironmentName}.json";

    internal string LegacyMigrationCredentialFileName => EnvironmentName.Equals(
        "production",
        StringComparison.Ordinal)
        ? "legacy-migration-credential.dat"
        : $"legacy-migration-credential.{EnvironmentName}.dat";

    internal bool IsDevelopment =>
        EnvironmentName.Equals("development", StringComparison.OrdinalIgnoreCase) ||
        EnvironmentName.Equals("local", StringComparison.OrdinalIgnoreCase);

    internal static ScmEnvironmentSettings Load()
    {
        var environmentName = NormalizeEnvironmentName(
            Read("STARBRIDGE_ENVIRONMENT", "production"));
        var isDevelopment =
            environmentName.Equals("development", StringComparison.OrdinalIgnoreCase) ||
            environmentName.Equals("local", StringComparison.OrdinalIgnoreCase);
        var accountAccessEnabled = isDevelopment || ReadBoolean(
            "STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED",
            true);
        var discoveryEnabled = ReadBoolean(
            "STARBRIDGE_SCM_REGION_DISCOVERY_ENABLED",
            // 0.7.2 enables automatic domestic routing with startup and login fallback.
            !isDevelopment);
        var regionApi = ReadOptionalSecureUri("STARBRIDGE_SCM_REGION_API_URL", isDevelopment) ??
            (isDevelopment ? null : new Uri("https://scms.flowcld.com/app-api/region"));
        var regionFallbackApi = ReadOptionalSecureUri("STARBRIDGE_SCM_REGION_FALLBACK_API_URL", isDevelopment);
        var webBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_WEB_BASE_URL",
            isDevelopment ? "http://127.0.0.1:3000/" : "https://scm.flowcld.com/",
            isDevelopment);
        // Trusted discovery/cache still selects the region. When discovery is unavailable,
        // default to the SCM backend rather than silently selecting the domestic proxy.
        var apiBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_API_BASE_URL",
            isDevelopment ? "http://127.0.0.1:18080/" : "https://scmk.flowcld.com/",
            isDevelopment);
        var resourceBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_RESOURCE_BASE_URL",
            isDevelopment ? "http://127.0.0.1:18081/" : "https://scmk.flowcld.com/",
            isDevelopment);
        var relayBase = ReadRuntimeUri(
            "STARBRIDGE_RELAY_BASE_URL",
            isDevelopment ? "http://127.0.0.1:5058/" : "https://api.scstarbridge.com/",
            isDevelopment);
        var webSocketBase = ValidateRuntimeUri(
            "STARBRIDGE_SCM_WS_BASE_URL",
            ParseWebSocketUri("STARBRIDGE_SCM_WS_BASE_URL", Read(
                "STARBRIDGE_SCM_WS_BASE_URL",
                resourceBase.AbsoluteUri)),
            isDevelopment);
        // Only a positive domestic classification can select the domestic endpoints.
        var trustedHosts = Read(
                "STARBRIDGE_SCM_TRUSTED_REGION_HOSTS",
                isDevelopment
                    ? string.Empty
                    : "scmk.flowcld.com,scms.flowcld.com,origin.flowcld.top,flowcld.xyz,ws.flowcld.xyz")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(host => host.ToLowerInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        trustedHosts.Add(apiBase.Host);
        trustedHosts.Add(resourceBase.Host);
        trustedHosts.Add(webSocketBase.Host);
        webSocketBase = NormalizeWebSocketBase(webSocketBase);

        return new ScmEnvironmentSettings(
            environmentName,
            accountAccessEnabled,
            discoveryEnabled,
            regionApi,
            webBase,
            apiBase,
            resourceBase,
            relayBase,
            trustedHosts,
            TimeSpan.FromMilliseconds(ReadPositiveInt("STARBRIDGE_SCM_REGION_TIMEOUT_MS", 5000)),
            TimeSpan.FromSeconds(ReadPositiveInt("STARBRIDGE_SCM_REGION_CACHE_SECONDS", 86400)),
            regionFallbackApi,
            webSocketBase,
            new[] { "STARBRIDGE_SCM_API_BASE_URL", "STARBRIDGE_SCM_RESOURCE_BASE_URL", "STARBRIDGE_SCM_WS_BASE_URL" }
                .Any(name => !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name))));
    }

    internal static Uri NormalizeWebSocketBase(Uri uri) =>
        uri.Host.Equals("flowcld.xyz", StringComparison.OrdinalIgnoreCase)
            ? new Uri("https://ws.flowcld.xyz/")
            : uri;

    private static string NormalizeEnvironmentName(string value) =>
        value.Trim().ToLowerInvariant() switch
        {
            "production" => "production",
            "development" => "development",
            "local" => "local",
            _ => throw new InvalidOperationException(
                "STARBRIDGE_ENVIRONMENT 仅支持 production、development 或 local。")
        };

    private static string Read(string name, string fallback) =>
        string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name))
            ? fallback
            : Environment.GetEnvironmentVariable(name)!.Trim();

    private static bool ReadBoolean(string name, bool fallback) =>
        bool.TryParse(Environment.GetEnvironmentVariable(name), out var value) ? value : fallback;

    private static int ReadPositiveInt(string name, int fallback) =>
        int.TryParse(Environment.GetEnvironmentVariable(name), out var value) && value > 0
            ? value
            : fallback;

    private static Uri? ReadOptionalSecureUri(string name, bool isDevelopment)
    {
        var value = Environment.GetEnvironmentVariable(name);
        return string.IsNullOrWhiteSpace(value) ? null : ValidateRuntimeUri(name, ParseSecureUri(name, value), isDevelopment);
    }

    private static Uri ReadRuntimeUri(string name, string fallback, bool isDevelopment) =>
        ValidateRuntimeUri(name, ParseSecureUri(name, Read(name, fallback)), isDevelopment);

    private static Uri ValidateRuntimeUri(string name, Uri uri, bool isDevelopment)
    {
        if (!isDevelopment && uri.IsLoopback)
        {
            throw new InvalidOperationException(
                $"{name} 在 production 中不能指向 loopback；请移除旧联调覆盖并使用正式 HTTPS 地址。");
        }

        return uri;
    }

    private static Uri ParseSecureUri(string name, string value)
    {
        if (!Uri.TryCreate(value.Trim().TrimEnd('/') + "/", UriKind.Absolute, out var uri))
        {
            throw new InvalidOperationException($"{name} 必须是有效的绝对地址。");
        }

        var isHttps = uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase);
        var isLoopbackHttp = uri.Scheme.Equals(Uri.UriSchemeHttp, StringComparison.OrdinalIgnoreCase) && uri.IsLoopback;
        if (!isHttps && !isLoopbackHttp)
        {
            throw new InvalidOperationException($"{name} 必须使用 HTTPS；本地测试仅允许 loopback HTTP。");
        }

        return uri;
    }

    private static Uri ParseWebSocketUri(string name, string value)
    {
        var normalized = value.Trim();
        if (normalized.StartsWith("wss://", StringComparison.OrdinalIgnoreCase))
        {
            normalized = "https://" + normalized[6..];
        }
        else if (normalized.StartsWith("ws://", StringComparison.OrdinalIgnoreCase))
        {
            normalized = "http://" + normalized[5..];
        }
        return ParseSecureUri(name, normalized);
    }
}

internal sealed record ScmRegionRoute(
    Uri ApiBaseUri,
    Uri ResourceBaseUri,
    string Source,
    DateTimeOffset ResolvedAt,
    Uri? WebSocketBaseUri = null,
    bool? IsCN = null)
{
    internal Uri EffectiveWebSocketBaseUri => ScmEnvironmentSettings.NormalizeWebSocketBase(WebSocketBaseUri ?? ResourceBaseUri);
}

internal sealed class ScmRegionRouter(HttpClient httpClient, string cachePath, Action<string>? diagnostic = null,
    Func<Uri, CancellationToken, Task<ScmWebSocketProbeResult>>? webSocketProbe = null)
{
    private const int CacheSchemaVersion = 4;
    internal async Task<ScmRegionRoute> ResolveAsync(
        ScmEnvironmentSettings settings,
        CancellationToken cancellationToken)
    {
        if (!settings.AccountAccessEnabled || !settings.RegionDiscoveryEnabled || settings.IsDevelopment ||
            settings.HasExplicitRouteOverride || settings.RegionApiUri is null)
        {
            return CreateFallback(settings, "environment");
        }

        var cached = TryLoadCache(settings);
        if (cached is not null)
        {
            return await PreflightAsync(cached, settings, cancellationToken);
        }

        foreach (var endpoint in new[] { settings.RegionApiUri, settings.RegionFallbackApiUri }
                     .OfType<Uri>().Distinct())
        {
            cancellationToken.ThrowIfCancellationRequested();
            try
            {
                using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
                timeout.CancelAfter(settings.RegionRequestTimeout);
                using var response = await httpClient.GetAsync(endpoint, timeout.Token);
                if (!response.IsSuccessStatusCode)
                {
                    ScmRegionDiagnostics.Write($"failure=http status={(int)response.StatusCode} cf-mitigated={response.Headers.Contains("cf-mitigated").ToString().ToLowerInvariant()}", diagnostic);
                    continue;
                }
                using var document = JsonDocument.Parse(await response.Content.ReadAsStringAsync(timeout.Token));
                var payload = ReadResponse(document.RootElement);
                var route = CreateDiscoveredRoute(payload, settings);
                if (route.IsCN == true) SaveCache(route);
                // Overseas users keep today's start-up: one classification per cache period, then no request.
                else SaveOverseas(settings, DateTimeOffset.UtcNow);
                var selected = await PreflightAsync(route, settings, cancellationToken);
                if (selected.Source == "fallback-preflight") return selected;
                return route with { WebSocketBaseUri = ScmEnvironmentSettings.NormalizeWebSocketBase(route.EffectiveWebSocketBaseUri) };
            }
            catch (Exception exception) when (!cancellationToken.IsCancellationRequested &&
                exception is HttpRequestException or TaskCanceledException or JsonException or InvalidOperationException)
            {
                var category = exception switch
                {
                    TaskCanceledException => "timeout",
                    JsonException => "invalid-json",
                    InvalidOperationException => "untrusted-host",
                    _ => "transport"
                };
                ScmRegionDiagnostics.Write($"failure={category}", diagnostic);
                // Try the configured secondary discovery endpoint before the environment fallback.
            }
        }
        // An unreachable classifier must not delay every start-up: remember the overseas fallback for an hour.
        SaveOverseas(settings, DateTimeOffset.UtcNow - settings.RegionCacheDuration + TimeSpan.FromHours(1));
        return CreateFallback(settings, "fallback");
    }

    private void SaveOverseas(ScmEnvironmentSettings settings, DateTimeOffset resolvedAt) =>
        SaveCache(new ScmRegionRoute(settings.ApiBaseUri, settings.ResourceBaseUri, "environment",
            resolvedAt, settings.EffectiveWebSocketBaseUri, false));

    private async Task<ScmRegionRoute> PreflightAsync(
        ScmRegionRoute route, ScmEnvironmentSettings settings, CancellationToken cancellationToken)
    {
        if (route.Source is not ("region-api" or "cache") || route.IsCN != true)
            return route;

        string? failure = null;
        using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
        timeout.CancelAfter(TimeSpan.FromSeconds(4));
        try
        {
            // This discovery client carries no account/session credentials.
            using var response = await httpClient.GetAsync(
                new Uri(route.ApiBaseUri, "app-api/member/timezone/list"), HttpCompletionOption.ResponseHeadersRead, timeout.Token);
            var status = (int)response.StatusCode;
            if (status != 200)
                failure = $"http status={status}";
            else
            {
                using var document = JsonDocument.Parse(
                    await response.Content.ReadAsStringAsync(timeout.Token));
                if (!IsTimeZoneDirectory(document.RootElement)) failure = "contract";
            }
        }
        catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
        {
            failure = "timeout";
        }
        catch (HttpRequestException)
        {
            failure = "transport";
        }
        catch (JsonException)
        {
            failure = "invalid-json";
        }
        // Any other preflight failure (e.g. an invalid charset) also falls back to overseas for this
        // run and keeps the domestic cache; start-up never fails on the preflight.
        catch (Exception) when (!cancellationToken.IsCancellationRequested)
        {
            failure = "transport";
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (failure is null)
        {
            using var wsTimeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            wsTimeout.CancelAfter(TimeSpan.FromSeconds(4));
            try
            {
                var result = await (webSocketProbe ?? ScmWebSocketProbe.ConnectAsync)(
                    new Uri("wss://ws.flowcld.xyz/infra/ws/chat"), wsTimeout.Token).WaitAsync(wsTimeout.Token);
                failure = result.Failure;
            }
            catch (OperationCanceledException) when (!cancellationToken.IsCancellationRequested)
            { failure = "ws-timeout"; }
            // Any other probe failure falls back to overseas; start-up never fails on the probe.
            catch (Exception) when (!cancellationToken.IsCancellationRequested)
            { failure = "ws-transport"; }
        }
        cancellationToken.ThrowIfCancellationRequested();
        if (failure is null) return route;
        ScmRegionDiagnostics.Write($"failure={failure}", diagnostic);
        // Keep the cached discovery result intact; fallback applies only to this process.
        return CreateFallback(settings, "fallback-preflight") with { IsCN = route.IsCN };
    }

    // Match the public timezone directory contract before selecting any account endpoints.
    private static bool IsTimeZoneDirectory(JsonElement root) =>
        root.ValueKind == JsonValueKind.Object &&
        root.TryGetProperty("code", out var code) && code.ValueKind == JsonValueKind.Number &&
        code.TryGetInt32(out var status) && status == 0 &&
        root.TryGetProperty("data", out var data) && data.ValueKind == JsonValueKind.Array &&
        data.EnumerateArray().Any(item =>
            item.ValueKind == JsonValueKind.Object &&
            item.TryGetProperty("value", out var value) && value.ValueKind == JsonValueKind.String &&
            !string.IsNullOrWhiteSpace(value.GetString()));

    private static ScmRegionResponse ReadResponse(JsonElement root)
    {
        if (root.ValueKind != JsonValueKind.Object)
        {
            throw new JsonException("地域识别 API 返回了无效响应。");
        }
        if (root.TryGetProperty("code", out var code))
        {
            if (!code.TryGetInt32(out var status) || status != 0 ||
                !root.TryGetProperty("data", out root) || root.ValueKind != JsonValueKind.Object)
            {
                throw new JsonException("地域识别 API 未返回成功的地域数据。");
            }
        }
        return root.Deserialize<ScmRegionResponse>()
            ?? throw new JsonException("地域识别 API 返回了空响应。");
    }

    private ScmRegionRoute? TryLoadCache(ScmEnvironmentSettings settings)
    {
        try
        {
            if (!File.Exists(cachePath))
            {
                return null;
            }

            var cache = JsonSerializer.Deserialize<ScmRegionCache>(File.ReadAllText(cachePath));
            if (cache is null ||
                cache.ResolvedAt > DateTimeOffset.UtcNow ||
                DateTimeOffset.UtcNow - cache.ResolvedAt > settings.RegionCacheDuration)
                return null;
            // Old overseas routes never become authoritative, even when they were trusted.
            if (cache.IsCN != true) return CreateFallback(settings, "environment");
            if (cache.SchemaVersion != CacheSchemaVersion ||
                string.IsNullOrWhiteSpace(cache.ApiBaseUri) ||
                string.IsNullOrWhiteSpace(cache.ResourceBaseUri) ||
                string.IsNullOrWhiteSpace(cache.WebSocketBaseUri))
            {
                return null;
            }

            var apiBaseUri = new Uri(cache.ApiBaseUri);
            var resourceBaseUri = new Uri(cache.ResourceBaseUri);
            var webSocketBaseUri = new Uri(cache.WebSocketBaseUri);
            if (!IsTrustedCachedUri(apiBaseUri, settings) ||
                !IsTrustedCachedUri(resourceBaseUri, settings) ||
                !IsTrustedCachedUri(webSocketBaseUri, settings))
            {
                return null;
            }

            if (apiBaseUri != new Uri("https://flowcld.xyz/") ||
                resourceBaseUri != apiBaseUri || webSocketBaseUri != new Uri("https://ws.flowcld.xyz/"))
                return null;
            return new ScmRegionRoute(
                apiBaseUri,
                resourceBaseUri,
                "cache",
                cache.ResolvedAt,
                ScmEnvironmentSettings.NormalizeWebSocketBase(webSocketBaseUri), cache.IsCN);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or UriFormatException)
        {
            return null;
        }
    }

    private static bool IsTrustedCachedUri(Uri uri, ScmEnvironmentSettings settings) =>
        uri.IsAbsoluteUri && uri.IsDefaultPort && string.IsNullOrEmpty(uri.UserInfo) &&
        uri.AbsolutePath == "/" && string.IsNullOrEmpty(uri.Query) && string.IsNullOrEmpty(uri.Fragment) &&
        uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
        settings.TrustedRegionHosts.Contains(uri.Host);

    private static ScmRegionRoute CreateDiscoveredRoute(
        ScmRegionResponse payload,
        ScmEnvironmentSettings settings)
    {
        if (payload.IsCN == true)
        {
            var domesticApi = new Uri("https://flowcld.xyz/");
            var domesticWs = new Uri("https://ws.flowcld.xyz/");
            if (!IsTrustedCachedUri(domesticApi, settings) || !IsTrustedCachedUri(domesticWs, settings))
                throw new InvalidOperationException("Domestic route hosts are not trusted.");
            return new ScmRegionRoute(domesticApi, domesticApi, "region-api",
                DateTimeOffset.UtcNow, domesticWs, payload.IsCN);
        }
        return CreateFallback(settings, "environment");
    }

    private static ScmRegionRoute CreateFallback(ScmEnvironmentSettings settings, string source) =>
        new(settings.ApiBaseUri, settings.ResourceBaseUri, source, DateTimeOffset.UtcNow,
            settings.EffectiveWebSocketBaseUri);

    private void SaveCache(ScmRegionRoute route)
    {
        try
        {
            var directory = Path.GetDirectoryName(cachePath);
            if (!string.IsNullOrWhiteSpace(directory))
            {
                Directory.CreateDirectory(directory);
            }

            File.WriteAllText(
                cachePath,
                JsonSerializer.Serialize(new ScmRegionCache(
                    route.ApiBaseUri.AbsoluteUri,
                    route.ResourceBaseUri.AbsoluteUri,
                    route.ResolvedAt,
                    // Persist only the fixed approved domestic endpoints.
                    (route.WebSocketBaseUri ?? route.ResourceBaseUri).AbsoluteUri,
                    CacheSchemaVersion, route.IsCN)));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A cache write failure must not block SCM login.
        }
    }

    private sealed record ScmRegionResponse(
        [property: JsonPropertyName("isCN")] bool? IsCN);

    private sealed record ScmRegionCache(
        string ApiBaseUri,
        string ResourceBaseUri,
        DateTimeOffset ResolvedAt,
        string? WebSocketBaseUri,
        int SchemaVersion,
        bool? IsCN = null);
}

internal static class StarBridgeDotEnv
{
    internal static string? Load()
    {
        var configured = Environment.GetEnvironmentVariable("STARBRIDGE_ENV_FILE");
        var candidates = new List<string?>
        {
            configured,
            Path.Combine(AppContext.BaseDirectory, ".env"),
            Path.Combine(Environment.CurrentDirectory, ".env")
        };
        var directory = new DirectoryInfo(AppContext.BaseDirectory);
        while (directory is not null)
        {
            candidates.Add(Path.Combine(directory.FullName, ".env"));
            directory = directory.Parent;
        }

        var path = candidates.FirstOrDefault(candidate =>
            !string.IsNullOrWhiteSpace(candidate) && File.Exists(candidate));
        if (path is null)
        {
            return null;
        }

        foreach (var rawLine in File.ReadLines(path))
        {
            var line = rawLine.Trim();
            if (line.Length == 0 || line.StartsWith('#'))
            {
                continue;
            }

            var separator = line.IndexOf('=');
            if (separator <= 0)
            {
                continue;
            }

            var name = line[..separator].Trim();
            if (!name.StartsWith("STARBRIDGE_", StringComparison.Ordinal) ||
                !string.IsNullOrWhiteSpace(Environment.GetEnvironmentVariable(name)))
            {
                continue;
            }

            var value = line[(separator + 1)..].Trim();
            if (value.Length >= 2 &&
                ((value[0] == '\'' && value[^1] == '\'') || (value[0] == '"' && value[^1] == '"')))
            {
                value = value[1..^1];
            }

            Environment.SetEnvironmentVariable(name, value);
        }

        return path!;
    }
}
