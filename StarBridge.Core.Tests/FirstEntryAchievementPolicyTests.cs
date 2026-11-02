using StarBridge.Core.Achievements;

namespace StarBridge.Core.Tests;

internal static class FirstEntryAchievementPolicyTests
{
    internal static void RunAll()
    {
        static void Require(bool value) { if (!value) throw new InvalidOperationException("First entry requires live matching account and server evidence."); }
        foreach (var channel in new[] { "LIVE", "PTU", "EPTU", "TECH-PREVIEW" }) Require(FirstEntryAchievementPolicy.CanUnlock(true, true, channel, "connected"));
        Require(!FirstEntryAchievementPolicy.CanUnlock(false, true, "LIVE", "connected"));
        Require(!FirstEntryAchievementPolicy.CanUnlock(true, false, "LIVE", "connected"));
        foreach (var state in new string?[] { null, "unknown", "notConnected", "frontend", "running" }) Require(!FirstEntryAchievementPolicy.CanUnlock(true, true, "LIVE", state));
        foreach (var channel in new string?[] { null, "unknown", "live", "invalid" }) Require(!FirstEntryAchievementPolicy.CanUnlock(true, true, channel, "connected"));
    }
}
