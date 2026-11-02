using System.Net.Http;

namespace StarBridge.HostRuntime.Auth;

/// <summary>
/// Resolves one stable SCM account environment into the regional endpoints and
/// environment-scoped local storage used by the headless Host.
/// </summary>
internal sealed record ScmRuntimeConfiguration(
    string EnvironmentId,
    bool AccountAccessEnabled,
    ScmOAuthOptions OAuthOptions,
    Uri LegacyRelayBaseUri,
    string TokenVaultPath,
    string LegacyMigrationCredentialPath,
    string RegionCachePath,
    string RouteSource)
{
    internal ScmRouteState? RouteState { get; init; }
    internal static HttpClientHandler CreateRegionHttpHandler() => new()
    {
        AllowAutoRedirect = false,
        UseCookies = false,
    };

    internal static async Task<ScmRuntimeConfiguration> ResolveDefaultAsync(
        string dataRoot,
        CancellationToken cancellationToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(dataRoot);
        _ = StarBridgeDotEnv.Load();
        var settings = ScmEnvironmentSettings.Load();
        var regionCachePath = Path.Combine(dataRoot, settings.RegionCacheFileName);
        using var regionHttpClient = new HttpClient(CreateRegionHttpHandler());
        var router = new ScmRegionRouter(regionHttpClient, regionCachePath);
        return await ResolveAsync(
                settings,
                dataRoot,
                router.ResolveAsync,
                cancellationToken)
            .ConfigureAwait(false);
    }

    internal static async Task<ScmRuntimeConfiguration> ResolveAsync(
        ScmEnvironmentSettings settings,
        string dataRoot,
        Func<ScmEnvironmentSettings, CancellationToken, Task<ScmRegionRoute>> resolveRoute,
        CancellationToken cancellationToken,
        Action<string>? diagnostic = null)
    {
        ArgumentNullException.ThrowIfNull(settings);
        ArgumentException.ThrowIfNullOrWhiteSpace(dataRoot);
        ArgumentNullException.ThrowIfNull(resolveRoute);
        var state = new ScmRouteState(Path.Combine(dataRoot, "scm-route-state.json"));
        var fallback = state.StartupFallback(settings.AccountAccessEnabled && !settings.IsDevelopment &&
            !settings.HasExplicitRouteOverride);
        var route = settings.AccountAccessEnabled && fallback is null
            ? await resolveRoute(settings, cancellationToken).ConfigureAwait(false)
            : new ScmRegionRoute(
                settings.ApiBaseUri,
                settings.ResourceBaseUri,
                settings.AccountAccessEnabled ? fallback! : "environment-locked",
                DateTimeOffset.UtcNow,
                settings.EffectiveWebSocketBaseUri);
        state.SetActive(route);
        ScmRegionDiagnostics.WriteRoute(route, diagnostic);
        return new ScmRuntimeConfiguration(
            settings.EnvironmentName,
            settings.AccountAccessEnabled,
            ScmOAuthOptions.Create(settings, route),
            settings.RelayBaseUri,
            Path.Combine(dataRoot, settings.TokenVaultFileName),
            Path.Combine(dataRoot, settings.LegacyMigrationCredentialFileName),
            Path.Combine(dataRoot, settings.RegionCacheFileName),
            route.Source) { RouteState = state };
    }
}
