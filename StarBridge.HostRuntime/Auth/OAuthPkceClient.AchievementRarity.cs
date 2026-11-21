using StarBridge.HostRuntime.Achievements;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(AchievementRarity Result, ScmOAuthSession ActiveSession)> ReadAchievementRarityAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        var result = await ReadAccountResourceAsync<AchievementRarity>(session,
            new Uri(options.AchievementsEndpoint.AbsoluteUri.TrimEnd('/') + "/rarity"),
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "achievements-rarity", token,
            maximumResponseBytes: 65536, sessionReady: sessionReady);
        result.Result.Validate(); return result;
    }
}
