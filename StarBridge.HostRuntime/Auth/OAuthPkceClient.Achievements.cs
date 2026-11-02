using System.Net.Http.Json;
using StarBridge.HostRuntime.Achievements;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal Task<(bool Result, ScmOAuthSession ActiveSession)> TriggerScmAchievementsAsync(ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null) =>
        SendResourceRequestAsync(session, async (active, ct) => {
            if (!active.Capabilities.Contains("profile.read", StringComparer.Ordinal))
                throw new Account.AccountBridgeHostException("scmAchievements.not_allowed");
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(options.ResourceServerBaseUri, "app-api/member/user/get"));
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var envelope = await ReadMarketplaceEnvelopeAsync(response, "scm-achievements-trigger", ct);
            if (!envelope.TryGetProperty("code", out var code) || code.GetInt32() != 0)
                throw new ScmApiProtocolException("SCM achievement trigger rejected.");
            return true;
        }, token, sessionReady);
    internal async Task<(ScmAchievementCatalog Result, ScmOAuthSession ActiveSession)> ReadScmAchievementsAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        var result = await ReadAccountResourceAsync<ScmAchievementCatalog>(session, options.ScmAchievementsEndpoint,
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "scm-achievements-read", token, maximumResponseBytes: 1500000, sessionReady: sessionReady);
        result.Result.Validate(); return result;
    }
    internal async Task<(AchievementSnapshot Result, ScmOAuthSession ActiveSession)> ReadAchievementsAsync(
        ScmOAuthSession session, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        var result = await ReadAccountResourceAsync<AchievementSnapshot>(session, options.AchievementsEndpoint,
            session.CorrelationId ?? Guid.NewGuid().ToString("N"), "achievements-read", token, sessionReady: sessionReady);
        result.Result.Validate(); return result;
    }
    internal async Task<(AchievementReceipt Result, ScmOAuthSession ActiveSession)> ObserveFirstEntryAsync(
        ScmOAuthSession session, FirstEntryObservation observation, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        if (!observation.IsValid) throw new ArgumentException("Invalid game entry evidence.");
        // This endpoint is idempotent under (authenticated issuer, subject, achievement id).
        return await SendResourceRequestAsync(session, async (active, ct) => {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.AchievementsEndpoint.AbsoluteUri + "/observations/first-entry"))
            { Content = JsonContent.Create(observation) };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var receipt = await scmHttpClient.ReadJsonAsync<AchievementReceipt>(response, "Game entry observation", ct);
            new AchievementSnapshot(receipt.SchemaVersion, receipt.EarnedAt).Validate();
            return receipt;
        }, token, sessionReady);
    }
    internal async Task<(CityAchievementReceipt Result, ScmOAuthSession ActiveSession)> ObserveCityAsync(
        ScmOAuthSession session, CityObservation observation, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        if (!observation.IsValid) throw new ArgumentException("Invalid city evidence.");
        // Keep parser names in the durable outbox; only the Java wire contract uses these values.
        var evidence = observation.Evidence switch {
            "RequestLocationInventory" => "inventory",
            "PLAYER_LOCATION" => "explicit",
            _ => throw new ArgumentException("Invalid city evidence.")
        };
        return await SendResourceRequestAsync(session, async (active, ct) => {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.AchievementsEndpoint.AbsoluteUri.TrimEnd('/') + "/observations/city"))
            { Content = JsonContent.Create(new { observation.SchemaVersion, observation.HandleHash, observation.City, evidence }) };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var receipt = await scmHttpClient.ReadJsonAsync<CityAchievementReceipt>(response, "City arrival observation", ct);
            receipt.Validate(); return receipt;
        }, token, sessionReady);
    }
    internal async Task<(HangarAchievementReceipt Result, ScmOAuthSession ActiveSession)> ObserveHangarAchievementsAsync(
        ScmOAuthSession session, HangarAchievementObservation observation, CancellationToken token, Action<ScmOAuthSession>? sessionReady = null)
    {
        if (!observation.IsValid) throw new ArgumentException("Invalid hangar evidence.");
        return await SendResourceRequestAsync(session, async (active, ct) => {
            using var request = new HttpRequestMessage(HttpMethod.Post, new Uri(options.AchievementsEndpoint.AbsoluteUri + "/observations/hangar"))
            { Content = JsonContent.Create(observation) };
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, ct);
            var receipt = await scmHttpClient.ReadJsonAsync<HangarAchievementReceipt>(response, "Hangar milestone observation", ct);
            receipt.Validate(); return receipt;
        }, token, sessionReady);
    }
}
