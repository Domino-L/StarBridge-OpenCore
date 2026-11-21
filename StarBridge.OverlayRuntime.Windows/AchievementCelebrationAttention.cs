namespace StarBridge.OverlayRuntime.Windows;

// Build 105 (user 11-21): "成就庆祝的预期是用户可以明显的看到". An unlocked
// desktop is not enough when nobody is at it: after this long without keyboard
// or mouse input the card waits (paused, not dropped, not counted as shown)
// and plays once input returns. Input inside the game counts as input. When
// Windows cannot report input, the card also waits (R1 P3).
internal static class AchievementCelebrationAttention
{
    internal static readonly TimeSpan IdleHold = TimeSpan.FromMinutes(5);
    internal static bool Present(uint? idleMilliseconds) =>
        idleMilliseconds is { } idle && idle < IdleHold.TotalMilliseconds;
}
