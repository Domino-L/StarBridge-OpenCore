namespace StarBridge.HostRuntime.Auth;

internal static class ScmRegionDiagnostics
{
    internal static void WriteRoute(ScmRegionRoute route, Action<string>? sink = null)
    {
        var detail = $"source={route.Source} apiHost={route.ApiBaseUri.Host} resourceHost={route.ResourceBaseUri.Host} wsHost={route.EffectiveWebSocketBaseUri.Host}";
        if (route.Source is "region-api" or "cache" or "fallback-preflight")
            detail += $" isCN={route.IsCN?.ToString().ToLowerInvariant() ?? "unknown"}";
        Write(detail, sink);
    }

    internal static void Write(string detail, Action<string>? sink = null)
    {
        if (sink is not null) sink(detail);
        else ScmAuthDiagnostics.Write("region-routing", "region-routing", "observation", detail);
    }
}
