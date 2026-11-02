namespace StarBridge.Core.Achievements;

/// <summary>Live, current-account server evidence is required; a remembered identity or process alone is insufficient.</summary>
public static class FirstEntryAchievementPolicy
{
    public const string Id = "first-entry";
    public static bool CanUnlock(bool currentAccount, bool liveIdentityMatched, string? channel, string? serverState) =>
        currentAccount && liveIdentityMatched && channel is { Length: >= 2 and <= 32 } &&
        channel.All(c => c is >= 'A' and <= 'Z' or >= '0' and <= '9' or '_' or '-') &&
        serverState == "connected";
}
