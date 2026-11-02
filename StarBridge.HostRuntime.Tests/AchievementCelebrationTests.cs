using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class AchievementCelebrationTests
{
    private sealed class Sink : IAchievementCelebrationSink
    {
        internal readonly List<AchievementCelebration> Notices = [];
        internal int Clears;
        public void Submit(AchievementCelebration notice) => Notices.Add(notice);
        public void Clear() => Clears++;
    }
    internal static void Run()
    {
        var account = new BridgeAccountContext("test", "scm", "synthetic-celebration");
        (BridgeAccountContext? Context, long Generation) current = (account, 1);
        var at = DateTimeOffset.Parse("2026-09-04T12:00:30Z");
        using var delivery = new AchievementCelebrationDelivery(() => current);
        var sink = new Sink();
        delivery.FirstEntryEarned(1, at); // A grant can arrive before Windows composition completes.
        delivery.Configure(sink);
        Require(sink.Notices.Count == 1, "Newly earned achievement reaches the independent production presentation sink");
        var first = sink.Notices[0];
        Require(first.IsCurrent() && first.AchievementId == "first-entry" && first.EarnedAt == at,
            "The grant timestamp is retained without manufacturing an award");
        delivery.FirstEntryEarned(1, at);
        Require(sink.Notices.Count == 1, "Duplicate cloud receipts do not replay a celebration");
        current = (account with { Subject = "other" }, 2);
        delivery.Invalidate(2);
        Require(!first.IsCurrent() && sink.Clears == 1, "Account change clears queued and visible old-account content");
        delivery.FirstEntryEarned(1, at);
        Require(sink.Notices.Count == 1, "A late old-generation callback cannot present to another account");
        delivery.FirstEntryEarned(2, at);
        Require(sink.Notices.Count == 2, "Another account has its own presentation receipt");
        current = (null, 3);
        delivery.Invalidate(3);
        delivery.FirstEntryEarned(3, at);
        Require(sink.Notices.Count == 2 && !sink.Notices[1].IsCurrent(), "Signed-out accounts cannot celebrate");
        delivery.Dispose();
        current = (account, 4);
        delivery.FirstEntryEarned(4, at);
        Require(sink.Notices.Count == 2, "Disposed producer cannot deliver");
        SeriesDelivery();
        ScmDelivery();
    }
    private static void ScmDelivery()
    {
        var owner = new BridgeAccountContext("test", "scm", "synthetic-scm-celebration");
        using var delivery = new AchievementCelebrationDelivery(() => (owner, 1));
        var sink = new Sink(); delivery.Configure(sink);
        var at = DateTimeOffset.UtcNow;
        delivery.ScmEarned(1, "scm-1", at, "星际圣诞", "Assets/Achievements/scm-holiday-christmas-512.webp");
        delivery.ScmEarned(1, "scm-1", at, "星际圣诞", null);
        delivery.SeriesEarned(1, "scm-2", 1, at);
        delivery.ScmEarned(1, "unknown", at, "Synthetic", null);
        delivery.ScmEarned(1, "scm-3", at, "", null);
        Require(sink.Notices.Count == 1 && sink.Notices[0].CanPresent && sink.Notices[0].DisplayName == "星际圣诞" &&
            sink.Notices[0].LocalImagePath!.EndsWith("christmas-512.webp"), "Only validated SCM display notices join the existing trusted sink");
    }
    private static void SeriesDelivery()
    {
        var owner = new BridgeAccountContext("test", "scm", "synthetic-series-celebration");
        (BridgeAccountContext? Context, long Generation) current = (owner, 1);
        var at = DateTimeOffset.UnixEpoch.AddDays(1);
        using var delivery = new AchievementCelebrationDelivery(() => current);
        foreach (var id in StarBridge.Core.Achievements.HangarAchievementPolicy.Ids)
            delivery.SeriesEarned(1, id, 5, at);
        var sink = new Sink();
        delivery.Configure(sink);
        Require(sink.Notices.Count == 3 && sink.Notices.All(n => n.Rank == 5 && n.IsCurrent()),
            "Three simultaneous grants survive startup and keep distinct series identities");
        delivery.SeriesEarned(1, "hangar-home", 5, at);
        delivery.SeriesEarned(1, "hangar-home", 0, at);
        delivery.SeriesEarned(1, "hangar-home", 6, at);
        delivery.SeriesEarned(1, "unknown", 1, at);
        Require(sink.Notices.Count == 3, "Repeated receipts and invalid ranks cannot produce extra cards");
        current = (null, 2);
        delivery.Invalidate(2);
        Require(sink.Notices.All(n => !n.IsCurrent()) && sink.Clears == 1,
            "All queued series expire with their owning account");
    }
    private static void Require(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}
