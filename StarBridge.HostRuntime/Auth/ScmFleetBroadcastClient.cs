using System.Net.Http;
using System.Net.Http.Json;

namespace StarBridge.HostRuntime.Auth;

internal sealed class ScmFleetBroadcastClient(
    ScmHttpClient httpClient,
    OAuthPkceClient oauthClient,
    ScmOAuthOptions options)
{
    internal Task<(ScmFleetBroadcastScope Result, ScmOAuthSession ActiveSession)> ResolveOrganizationScopeAsync(
        ScmOAuthSession session,
        string legacyFleetCode,
        CancellationToken cancellationToken) =>
        SendAsync<ScmFleetBroadcastScope>(
            session,
            HttpMethod.Get,
            new Uri(options.FleetBroadcastEndpoint,
                $"fleet-broadcasts/organization-scope?legacyFleetCode={Uri.EscapeDataString(legacyFleetCode)}"),
            null,
            "舰队广播范围",
            cancellationToken);

    internal Task<(ScmFleetBroadcastFeed Result, ScmOAuthSession ActiveSession)> LoadFeedAsync(
        ScmOAuthSession session,
        ScmFleetBroadcastScope scope,
        long afterVersion,
        CancellationToken cancellationToken) =>
        SendAsync<ScmFleetBroadcastFeed>(
            session,
            HttpMethod.Get,
            new Uri(options.FleetBroadcastEndpoint,
                $"fleet-broadcasts?scopeType={Uri.EscapeDataString(scope.ScopeType)}" +
                $"&scopeId={scope.ScopeId}&afterVersion={Math.Max(0, afterVersion)}"),
            null,
            "舰队广播同步",
            cancellationToken);

    internal Task<(ScmFleetBroadcastMutation Result, ScmOAuthSession ActiveSession)> PublishAsync(
        ScmOAuthSession session,
        ScmFleetBroadcastPublishRequest request,
        CancellationToken cancellationToken) =>
        SendAsync<ScmFleetBroadcastMutation>(
            session,
            HttpMethod.Post,
            options.FleetBroadcastEndpoint,
            request,
            "舰队广播发送",
            cancellationToken);

    private Task<(T Result, ScmOAuthSession ActiveSession)> SendAsync<T>(
        ScmOAuthSession session,
        HttpMethod method,
        Uri endpoint,
        object? body,
        string operation,
        CancellationToken cancellationToken) =>
        oauthClient.SendResourceRequestAsync(
            session,
            async (activeSession, token) =>
            {
                using var request = new HttpRequestMessage(method, endpoint);
                if (body is not null)
                {
                    request.Content = JsonContent.Create(body);
                }

                using var response = await httpClient.SendAsync(request, activeSession.AccessToken, token);
                return await httpClient.ReadJsonAsync<T>(response, operation, token);
            },
            cancellationToken);
}

internal sealed record ScmFleetBroadcastScope(string ScopeType, long ScopeId);

internal sealed record ScmFleetBroadcastAppearance(
    string AccentColor,
    string BackgroundColor,
    string TextColor,
    double DurationSeconds,
    int RepeatCount,
    double FontScale);

internal sealed record ScmFleetBroadcastAuthor(
    string LegacyAccountId,
    string? Callsign,
    string? GameName,
    string? RoleTitle);

internal sealed record ScmFleetBroadcast(
    string Id,
    ScmFleetBroadcastScope Scope,
    string Message,
    ScmFleetBroadcastAuthor Author,
    ScmFleetBroadcastAppearance Appearance,
    long ResourceVersion,
    DateTimeOffset CreatedAt,
    DateTimeOffset ExpiresAt);

internal sealed record ScmFleetBroadcastFeed(
    string ScopeType,
    long ScopeId,
    ScmFleetBroadcast[] Broadcasts,
    bool CanPublish,
    long ResourceVersion,
    DateTimeOffset ServerTime);

internal sealed record ScmFleetBroadcastPublishRequest(
    string ScopeType,
    long ScopeId,
    string Message,
    ScmFleetBroadcastAppearance Appearance,
    string ClientRequestId);

internal sealed record ScmFleetBroadcastMutation(
    string Status,
    ScmFleetBroadcast? Broadcast,
    string? ErrorCode,
    long RetryAfterSeconds);
