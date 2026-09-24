using System.Net;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.Core.Profiles;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class LegacyPasswordLoginClient
{
    internal async Task<bool> PublishGameplayStatisticsAsync(string bearer,
        PersonalProfileGameplayStatisticsUpdateRequestContract update, CancellationToken token)
    {
        // Never send Flutter snapshots through the unversioned WPF compatibility path.
        if (update.ExpectedGameplayRevision is null or < 0 ||
            update.HistoryImportOperationId is { } historyOperation &&
                (!Guid.TryParseExact(historyOperation, "N", out _) || update.HistoryImportedAt is null) ||
            update.ResetOperationId is not null && !Guid.TryParseExact(update.ResetOperationId, "N", out _) ||
            update.PlayTimeSeconds < 0 || update.HistoricalPlayTimeSeconds < 0 ||
            update.HistoricalPlayTimeSeconds > update.PlayTimeSeconds ||
            update.DownedCount != 0 || update.DeathCount != 0 || update.HistoricalSessionCount < 0 ||
            update.HistoricalIncompleteSessionCount < 0 || update.HistoricalIncompleteSessionCount > update.HistoricalSessionCount ||
            update.HistoricalPlayTimeSeconds > 0 && update.HistoryImportedAt is null)
            throw new ArgumentException("Invalid versioned gameplay statistics.");
        token.ThrowIfCancellationRequested();
        using var request = new HttpRequestMessage(HttpMethod.Put,
            new Uri(_baseUri, "api/profile/me/gameplay-statistics"));
        request.Headers.Authorization = new("Bearer", bearer);
        request.Headers.CacheControl = new() { NoCache = true, NoStore = true };
        request.Content = JsonContent.Create(update);
        // One write only. The caller reconciles uncertain outcomes by reading authority,
        // not by refreshing a token and replaying an obsolete snapshot.
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token);
        if (response.StatusCode == HttpStatusCode.Conflict) return false;
        response.EnsureSuccessStatusCode();
        using var json = await LegacyPasswordRecoveryClient.ReadBoundedJsonAsync(response.Content, token, 262144);
        var root = json.RootElement;
        Profiles.LocalPersonalProfileStore.RejectDuplicates(root);
        if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
            root.GetProperty("isGameplayStatisticsPublic").GetBoolean() != update.IsPublic)
            throw new JsonException("Invalid gameplay statistics acknowledgement.");
        var stats = root.GetProperty("gameplayStatistics");
        if (stats.GetProperty("playTimeSeconds").GetInt64() != update.PlayTimeSeconds ||
            stats.GetProperty("downedCount").GetInt32() != update.DownedCount ||
            stats.GetProperty("deathCount").GetInt32() != update.DeathCount ||
            stats.GetProperty("historicalPlayTimeSeconds").GetInt64() != update.HistoricalPlayTimeSeconds ||
            stats.GetProperty("historicalSessionCount").GetInt32() != update.HistoricalSessionCount ||
            stats.GetProperty("historicalIncompleteSessionCount").GetInt32() != update.HistoricalIncompleteSessionCount ||
            stats.GetProperty("historyImportedAt").Deserialize<DateTimeOffset?>() != update.HistoryImportedAt)
            throw new JsonException("Mismatched gameplay statistics acknowledgement.");
        token.ThrowIfCancellationRequested();
        return true;
    }
}
