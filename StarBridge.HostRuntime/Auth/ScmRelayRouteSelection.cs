namespace StarBridge.HostRuntime.Auth;

internal static class ScmRelayRouteSelection
{
    internal static string Resolve(
        ScmEnvironmentSettings settings,
        string? persistedRelayBaseUrl)
    {
        ArgumentNullException.ThrowIfNull(settings);

        var environmentRelayBaseUrl = settings.RelayBaseUri.AbsoluteUri.TrimEnd('/');
        if (settings.IsDevelopment || string.IsNullOrWhiteSpace(persistedRelayBaseUrl))
        {
            return environmentRelayBaseUrl;
        }

        return persistedRelayBaseUrl.Trim().TrimEnd('/');
    }
}
