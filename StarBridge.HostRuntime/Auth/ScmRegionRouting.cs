using System.IO;
using System.Net.Http;
using System.Net.Http.Json;
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
    TimeSpan RegionCacheDuration)
{
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
            !isDevelopment);
        var regionApi = ReadOptionalSecureUri("STARBRIDGE_SCM_REGION_API_URL", isDevelopment) ??
            (isDevelopment ? null : new Uri("https://scms.flowcld.com/app-api/region"));
        var webBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_WEB_BASE_URL",
            isDevelopment ? "http://127.0.0.1:3000/" : "https://scm.flowcld.com/",
            isDevelopment);
        var apiBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_API_BASE_URL",
            isDevelopment ? "http://127.0.0.1:18080/" : "https://flowcld.xyz/",
            isDevelopment);
        var resourceBase = ReadRuntimeUri(
            "STARBRIDGE_SCM_RESOURCE_BASE_URL",
            isDevelopment ? "http://127.0.0.1:18081/" : "https://flowcld.xyz/",
            isDevelopment);
        var relayBase = ReadRuntimeUri(
            "STARBRIDGE_RELAY_BASE_URL",
            isDevelopment ? "http://127.0.0.1:5058/" : "https://api.scstarbridge.com/",
            isDevelopment);
        var trustedHosts = Read(
                "STARBRIDGE_SCM_TRUSTED_REGION_HOSTS",
                isDevelopment
                    ? string.Empty
                    : "origin.flowcld.top,flowcld.xyz,scms.flowcld.com,scmk.flowcld.com")
            .Split(',', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries)
            .Select(host => host.ToLowerInvariant())
            .ToHashSet(StringComparer.OrdinalIgnoreCase);
        trustedHosts.Add(apiBase.Host);
        trustedHosts.Add(resourceBase.Host);

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
            TimeSpan.FromSeconds(ReadPositiveInt("STARBRIDGE_SCM_REGION_CACHE_SECONDS", 86400)));
    }

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
}

internal sealed record ScmRegionRoute(
    Uri ApiBaseUri,
    Uri ResourceBaseUri,
    string Source,
    DateTimeOffset ResolvedAt);

internal sealed class ScmRegionRouter(HttpClient httpClient, string cachePath)
{
    internal async Task<ScmRegionRoute> ResolveAsync(
        ScmEnvironmentSettings settings,
        CancellationToken cancellationToken)
    {
        if (!settings.RegionDiscoveryEnabled || settings.IsDevelopment || settings.RegionApiUri is null)
        {
            return CreateFallback(settings, "environment");
        }

        var cached = TryLoadCache(settings);
        if (cached is not null)
        {
            return cached;
        }

        try
        {
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(cancellationToken);
            timeout.CancelAfter(settings.RegionRequestTimeout);
            using var response = await httpClient.GetAsync(settings.RegionApiUri, timeout.Token);
            response.EnsureSuccessStatusCode();
            var payload = await response.Content.ReadFromJsonAsync<ScmRegionResponse>(timeout.Token)
                ?? throw new JsonException("地域识别 API 返回了空响应。");
            var route = CreateDiscoveredRoute(payload, settings);
            SaveCache(route);
            return route;
        }
        catch (Exception exception) when (
            exception is HttpRequestException or TaskCanceledException or JsonException or InvalidOperationException)
        {
            return CreateFallback(settings, "fallback");
        }
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
            if (cache is null || DateTimeOffset.UtcNow - cache.ResolvedAt > settings.RegionCacheDuration)
            {
                return null;
            }

            var apiBaseUri = new Uri(cache.ApiBaseUri);
            var resourceBaseUri = new Uri(cache.ResourceBaseUri);
            if (!IsTrustedCachedUri(apiBaseUri, settings) ||
                !IsTrustedCachedUri(resourceBaseUri, settings))
            {
                return null;
            }

            return new ScmRegionRoute(
                apiBaseUri,
                resourceBaseUri,
                "cache",
                cache.ResolvedAt);
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException or JsonException or UriFormatException)
        {
            return null;
        }
    }

    private static bool IsTrustedCachedUri(Uri uri, ScmEnvironmentSettings settings) =>
        uri.Scheme.Equals(Uri.UriSchemeHttps, StringComparison.OrdinalIgnoreCase) &&
        settings.TrustedRegionHosts.Contains(uri.Host);

    private static ScmRegionRoute CreateDiscoveredRoute(
        ScmRegionResponse payload,
        ScmEnvironmentSettings settings)
    {
        var host = (payload.ApiHost ?? string.Empty).Trim().ToLowerInvariant();
        if (string.IsNullOrWhiteSpace(host) ||
            host.Contains('/') ||
            host.Contains(':') ||
            !settings.TrustedRegionHosts.Contains(host))
        {
            throw new InvalidOperationException("地域识别 API 返回了未受信任的 SCM Host。");
        }

        var baseUri = new Uri($"https://{host}/", UriKind.Absolute);
        return new ScmRegionRoute(baseUri, baseUri, "region-api", DateTimeOffset.UtcNow);
    }

    private static ScmRegionRoute CreateFallback(ScmEnvironmentSettings settings, string source) =>
        new(settings.ApiBaseUri, settings.ResourceBaseUri, source, DateTimeOffset.UtcNow);

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
                    route.ResolvedAt)));
        }
        catch (Exception exception) when (exception is IOException or UnauthorizedAccessException)
        {
            // A cache write failure must not block SCM login.
        }
    }

    private sealed record ScmRegionResponse(
        [property: JsonPropertyName("apiHost")] string? ApiHost);

    private sealed record ScmRegionCache(
        string ApiBaseUri,
        string ResourceBaseUri,
        DateTimeOffset ResolvedAt);
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
