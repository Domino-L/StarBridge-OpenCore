using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Support;

internal static class ScmWebsiteRoutingTests
{
    private static void Equal<T>(T expected, T actual)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"Expected {expected}; got {actual}");
    }

    internal static Task Verify()
    {
        var settings = new ScmEnvironmentSettings("production", true, true, null,
            new("https://scm.flowcld.com/"), new("https://scmk.flowcld.com/"),
            new("https://scmk.flowcld.com/"), new("https://relay.example.invalid/"),
            new HashSet<string>(), TimeSpan.FromSeconds(1), TimeSpan.FromDays(1));
        ScmRegionRoute Route(string source, bool domestic) => new(
            domestic ? new("https://flowcld.xyz/") : settings.ApiBaseUri,
            domestic ? new("https://flowcld.xyz/") : settings.ResourceBaseUri,
            source, DateTimeOffset.UnixEpoch);
        var overseas = ScmOAuthOptions.Create(settings, Route("overseas", false));
        try
        {
            foreach (var (source, domestic) in new[]
            {
                ("region-api", true), ("cache", true), ("overseas", false),
                ("fallback", false), ("fallback-preflight", false),
                ("fallback-login", false), ("user-overseas", false),
                ("environment-locked", false),
            })
            {
                var route = Route(source, domestic);
                var host = domestic ? "flowcld.xyz" : "scm.flowcld.com";
                var options = ScmOAuthOptions.Create(settings, route);
                Equal($"https://{host}/oauth/authorize", options.AuthorizeEndpoint.AbsoluteUri);
                Equal(overseas.AuthorityId, options.AuthorityId);
                Equal("/oauth/callback", options.CallbackPath);
                Equal(new Uri(route.ApiBaseUri, "open-api/oauth2/token"), options.TokenEndpoint);
                Equal(new Uri(route.ApiBaseUri, "open-api/oauth2/revoke"), options.RevokeEndpoint);
                ScmWebsiteRouting.SetActive(route);
                // All browser entry points share the published root.
                Equal($"https://{host}/", HelpSupportBridgeDispatcher.ScmWebsiteRoot.AbsoluteUri);
                using var blueprint = JsonDocument.Parse("""{"kind":"blueprints","id":42}""");
                Equal($"https://{host}/search/blueprint?blueprintId=42",
                    AccountBridgeRuntime.CatalogWebsite(blueprint.RootElement).AbsoluteUri);
                using var mission = JsonDocument.Parse("""{"kind":"missions","title":"A & B"}""");
                Equal($"https://{host}/search/missions?keyword=A%20%26%20B",
                    AccountBridgeRuntime.CatalogWebsite(mission.RootElement).AbsoluteUri);
                Equal($"https://{host}/message?userId=42", ScmWebsiteRouting.Chat(42).AbsoluteUri);
            }
            var domesticRoute = Route("region-api", true);
            foreach (var explicitRoot in new[] { "https://custom.example.invalid/site/", "https://scm.flowcld.com/" })
            {
                var explicitSettings = settings with
                {
                    WebBaseUri = new(explicitRoot), HasExplicitWebBaseOverride = true
                };
                Equal(explicitRoot + "oauth/authorize",
                    ScmOAuthOptions.Create(explicitSettings, domesticRoute).AuthorizeEndpoint.AbsoluteUri);
            }
            var development = settings with { EnvironmentName = "development", WebBaseUri = new("http://127.0.0.1:3000/") };
            Equal("http://127.0.0.1:3000/oauth/authorize",
                ScmOAuthOptions.Create(development, domesticRoute).AuthorizeEndpoint.AbsoluteUri);
            Equal(overseas.AuthorizeEndpoint, ScmOAuthOptions.Create(settings).AuthorizeEndpoint);
            // Account access off (environment-locked) keeps the original page even with a domestic API host.
            var locked = settings with { AccountAccessEnabled = false };
            Equal("https://scm.flowcld.com/oauth/authorize",
                ScmOAuthOptions.Create(locked, Route("environment-locked", true)).AuthorizeEndpoint.AbsoluteUri);
            ScmWebsiteRouting.SetActive(null);
            Equal("https://scm.flowcld.com/", HelpSupportBridgeDispatcher.ScmWebsiteRoot.AbsoluteUri);
        }
        finally { ScmWebsiteRouting.SetActive(null); }
        return Task.CompletedTask;
    }
}