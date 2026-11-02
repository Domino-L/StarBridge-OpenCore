using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Notifications;
using StarBridge.Desktop;

internal static class CelebrationDesktopDeferralTests
{
    internal static void Run()
    {
        var now = DateTimeOffset.UtcNow; var current = true;
        var activity = new AchievementCelebrationActivity();
        var pending = new Queue<DesktopNotification>();
        DesktopNotification Notice() => new(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight", "zh-CN", "dark", () => current);
        var trade = Notice() with { Trade = new("Synthetic trade", "Synthetic body") };
        var direct = Notice() with { DirectMessage = new("Synthetic", "Synthetic message", 1) };
        activity.Report(true);
        Require(DesktopCelebrationDeferral.Enqueue(pending, trade, now) && DesktopCelebrationDeferral.Enqueue(pending, direct, now), "Trade/private cards wait in native bounded queue");
        Require(!DesktopCelebrationDeferral.CanDrain(activity, 0, true), "Native drain cannot show even its first card while playback owns the corner");
        for (var i = 2; i < DesktopCelebrationDeferral.MaximumPending; i++)
            Require(DesktopCelebrationDeferral.Enqueue(pending, Notice() with { PresentUntil = now.AddSeconds(1) }, now), "Queue admits up to its limit");
        Require(!DesktopCelebrationDeferral.Enqueue(pending, Notice(), now), "Desktop pending limit is enforced");
        now = now.AddSeconds(20); DesktopCelebrationDeferral.Prune(pending, now);
        Require(pending.Count == 2 && activity.IsActive, "Expired reminders are removed while celebration remains protected");
        activity.Report(false);
        Require(DesktopCelebrationDeferral.CanDrain(activity, 0, true) && !DesktopCelebrationDeferral.CanDrain(activity, 1, true), "Deferred native drain displays one whole card at a time");
        Require(pending.Dequeue() == trade && pending.Dequeue() == direct, "Deferred trade/private cards retain receipt order");
        DesktopCelebrationDeferral.Enqueue(pending, Notice(), now); current = false;
        DesktopCelebrationDeferral.Prune(pending, now);
        Require(pending.Count == 0, "Changed-account notifications never reappear after celebration");
        Console.WriteLine("PASS CX-ACHCEL desktop: 1 group, 0 failed (trade/private FIFO, limit, expiry and account invalidation)");
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
