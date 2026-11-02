namespace StarBridge.HostRuntime.Auth;

public sealed record ScmOAuthOptions(
    string AuthorityId,
    Uri WebBaseUri,
    Uri AuthorizationServerBaseUri,
    Uri ResourceServerBaseUri,
    string ClientId,
    string Resource,
    string Scope,
    string CallbackPath,
    Uri? WebSocketServerBaseUri = null)
{
    public static ScmOAuthOptions CreateDefault() => Create(ScmEnvironmentSettings.Load());

    internal static ScmOAuthOptions Create(
        ScmEnvironmentSettings settings,
        ScmRegionRoute? route = null) => new(
        settings.AuthorityId,
        settings.WebBaseUri,
        route?.ApiBaseUri ?? settings.ApiBaseUri,
        route?.ResourceBaseUri ?? settings.ResourceBaseUri,
        "starbridge-desktop",
        "starbridge-api",
        "openid profile.read profile.write game_identity.read game_identity.verify organizations.read presence.write fleet_broadcast.read fleet_broadcast.write trade.read trade.write checklist.read checklist.write blocklist.read blocklist.write offline_access",
        "/oauth/callback",
        route?.EffectiveWebSocketBaseUri ?? settings.EffectiveWebSocketBaseUri);

    public Uri AuthorizeEndpoint => new(WebBaseUri, "oauth/authorize");
    public Uri TokenEndpoint => new(AuthorizationServerBaseUri, "open-api/oauth2/token");
    public Uri RevokeEndpoint => new(AuthorizationServerBaseUri, "open-api/oauth2/revoke");
    public Uri MeEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/me");
    public Uri BootstrapEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/bootstrap");
    public Uri ProfileEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/profile");
    public Uri PersonalProfileEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/personal-profile");
    public Uri HandlePrivacyEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/handle-privacy");
    public Uri AchievementsEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/achievements");
    public Uri ScmAchievementsEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/achievements/scm");
    public Uri TimeZoneDirectoryEndpoint => new(AuthorizationServerBaseUri, "app-api/member/timezone/list");
    public Uri WebSocketTicketEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/ws-ticket");
    public Uri PresenceStatusEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/presence/status");
    public Uri FleetBroadcastEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/fleet-broadcasts");
    public Uri DeviceRegisterEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/device/register");
    public Uri DeviceStatusEndpoint => new(ResourceServerBaseUri, "app-api/starbridge/v1/device/status");
    public Uri WebSocketEndpoint
    {
        get
        {
            var baseUri = WebSocketServerBaseUri ?? ResourceServerBaseUri;
            var builder = new UriBuilder(baseUri)
            {
                Scheme = baseUri.Scheme is "https" or "wss" ? "wss" : "ws",
                Path = "/infra/ws/starbridge",
                Query = string.Empty
            };
            return builder.Uri;
        }
    }

}
