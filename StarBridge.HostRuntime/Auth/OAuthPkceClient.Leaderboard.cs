using System.Net.Http.Json;
using StarBridge.HostRuntime.Achievements;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private Uri LeaderboardEndpoint(string suffix = "") =>
        new(options.AchievementsEndpoint.AbsoluteUri.TrimEnd('/') + "/leaderboards/tsg-swift" + suffix);

    internal async Task<(TsgSwiftLeaderboard Result, ScmOAuthSession ActiveSession)> ReadLeaderboardAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        var result = await ReadAccountResourceAsync<TsgSwiftLeaderboard>(session, LeaderboardEndpoint(),
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "leaderboard-read", token,
            maximumResponseBytes: 65536, sessionReady: sessionReady);
        result.Result.Validate(); return result;
    }

    internal async Task<(LeaderboardConsent Result, ScmOAuthSession ActiveSession)> ReadLeaderboardConsentAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        var result = await ReadAccountResourceAsync<LeaderboardConsent>(session, LeaderboardEndpoint("/consent"),
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "leaderboard-consent", token,
            maximumResponseBytes: 4096, sessionReady: sessionReady);
        result.Result.Validate(); return result;
    }

    internal async Task<(LeaderboardConsent Result, ScmOAuthSession ActiveSession)> WriteLeaderboardConsentAsync(
        ScmOAuthSession session, bool optIn, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        using var budget = CancellationTokenSource.CreateLinkedTokenSource(token);
        budget.CancelAfter(TimeSpan.FromSeconds(8));
        var result = await SendResourceRequestWithRefreshAndSessionAsync(session, async (active, ct) =>
        {
            if (!active.Capabilities.Contains("profile.read", StringComparer.Ordinal) ||
                !active.Capabilities.Contains("profile.write", StringComparer.Ordinal))
                throw new ScmApiForbiddenException("Leaderboard consent requires profile.read and profile.write.");
            using var request = new HttpRequestMessage(HttpMethod.Put, LeaderboardEndpoint("/consent"))
                { Content = JsonContent.Create(new { optIn }) };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var consent = await scmHttpClient.ReadJsonAsync<LeaderboardConsent>(response, "leaderboard-consent", ct);
            consent.Validate();
            if (consent.OptedIn != optIn || consent.State == "undecided") throw new InvalidDataException("Consent was not confirmed.");
            return consent;
        }, budget.Token, sessionReady);
        return result;
    }
}
