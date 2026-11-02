namespace StarBridge.HostRuntime.Achievements;

// Process-local presentation coordination, reported by the playback owner.
// Remains occupied across inter-card gaps, locked desktops and silent playback.
public sealed class AchievementCelebrationActivity
{
    public static AchievementCelebrationActivity Shared { get; } = new();
    private int _active;
    public bool IsActive => Volatile.Read(ref _active) != 0;
    public event Action<bool>? Changed;
    public void Report(bool active)
    {
        if (Interlocked.Exchange(ref _active, active ? 1 : 0) == (active ? 1 : 0)) return;
        if (Changed is not { } callbacks) return;
        foreach (Action<bool> callback in callbacks.GetInvocationList())
            try { callback(active); } catch { /* A reminder sink cannot shorten a celebration. */ }
    }
}
