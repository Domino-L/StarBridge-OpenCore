using StarBridge.HostRuntime.Achievements;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private ScmAchievementUnlockRuntime? _scmAchievementUnlocks;
    private ScmAchievementUnlockStore? _scmAchievementUnlockStore;
    private readonly HashSet<(long Generation, string Receipt)> _scmPublishedReceipts = [];
    private void ConfirmOfflineScmAchievements(StarBridge.NativeBridge.BridgeAccountContext owner, ScmAchievementCatalog catalog, Func<bool> current)
    {
        try { _scmAchievementUnlockStore?.ConfirmOffline(owner, catalog, () => !_disposed && current()); }
        catch (Exception failure) when (failure is IOException or UnauthorizedAccessException or System.Text.Json.JsonException or OperationCanceledException) { }
    }
    private void PublishScmAchievementEarned(long generation, ScmAchievementItem item, string receipt)
    {
        var at = (item.UnlockedAtUtc ?? DateTimeOffset.UtcNow).ToUniversalTime();
        _achievementCelebration?.ScmEarned(generation, item.Id, at, item.Name.Replace('\n', ' ').Replace('\t', ' '), ScmAchievementPresentation.Artwork(item), receipt);
        if (_scmPublishedReceipts.Add((generation, receipt)))
            _dispatcher.PublishDomainEvent("achievements.earned", generation,
                new { schemaVersion = 1, achievementId = item.Id, earnedAt = at, receiptId = receipt });
    }
}
