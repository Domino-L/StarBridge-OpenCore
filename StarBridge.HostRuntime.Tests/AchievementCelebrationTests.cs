using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class AchievementCelebrationTests
{
    private sealed class Sink : IAchievementCelebrationSink
    {
        internal readonly List<AchievementCelebration> Notices = [];
        internal int Clears;
        public void Submit(AchievementCelebration notice)
        {
            if (notice.TryAcceptReceipt()) Notices.Add(notice);
        }
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
        ReceiptRarityParity().GetAwaiter().GetResult();
    }

    private static async Task ReceiptRarityParity()
    {
        var parent = Path.Combine(Path.GetTempPath(), "sb-rarity-parity-" + Guid.NewGuid().ToString("N"));
        var owner = new BridgeAccountContext("fixture", "scm", "synthetic-rarity-parity");
        var at = DateTimeOffset.UnixEpoch.AddDays(1);
        try
        {
            async Task<byte[]> Present(string root, string? tier)
            {
                var store = new ScmAchievementUnlockStore(root);
                ScmAchievementUnlockStore.PendingUnlock[] pending;
                using (var lease = store.Open(owner))
                {
                    var empty = lease.Read();
                    pending = Enumerable.Range(1, 3).Select(i =>
                    {
                        var item = new ScmAchievementItem($"scm-{i}", $"Fixture {i}", null, null, null, null,
                            "EPIC", "HOLIDAY", true, at, null, null, i);
                        return new ScmAchievementUnlockStore.PendingUnlock(empty.OwnerHash + ":" + item.Id,
                            ScmAchievementUnlockStore.ForCard(item, at));
                    }).ToArray();
                    lease.Save(empty with { Pending = pending, Confirmed = pending.Select(p => p.Item.Id).ToArray(), Baseline = true }, () => true);
                }
                var persisted = Directory.GetFiles(root, "*.json", SearchOption.AllDirectories).Single();
                var before = File.ReadAllBytes(persisted);
                var sink = new Sink();
                using var delivery = new AchievementCelebrationDelivery(() => (owner, 1), root);
                delivery.Configure(sink);
                var single = pending[0];
                delivery.ScmEarned(1, single.Item.Id, at, single.Item.Name, null, single.Receipt, tier);
                delivery.ScmEarned(1, single.Item.Id, at, single.Item.Name, null, single.Receipt, "RARE");
                delivery.ScmSummary(1, pending.Select(p => p.Receipt).ToArray(), at);
                delivery.ScmSummary(1, pending.Select(p => p.Receipt).ToArray(), at);
                Require(sink.Notices.Count == 2 && sink.Notices.All(n => n.CanPresent && n.TryAcceptReceipt()),
                    "Exactly one single and one deduplicated summary reach the sink with or without rarity");
                var (card, summary) = (sink.Notices[0], sink.Notices[1]);
                Require(card.RarityTier == tier && card.RarityBasisPoints is null && summary.SummaryCount == 2 &&
                    summary.RarityTier is null && summary.RarityBasisPoints is null, "Only the individual notice carries its optional rarity");
                Require(File.ReadAllBytes(persisted).SequenceEqual(before), "Admission must leave the durable queue byte-for-byte unchanged");
                card.MarkPresented();
                await CelebrationTestClock.Until(() => ScmAchievementUnlockTests.Pending(root, owner).Length == 2);
                Require(!card.TryAcceptReceipt() && summary.TryAcceptReceipt(), "Only the fully presented single is acknowledged");
                summary.MarkPresented();
                await CelebrationTestClock.Until(() => ScmAchievementUnlockTests.Pending(root, owner).Length == 0);
                Require(!summary.TryAcceptReceipt(), "Presenting a summary acknowledges its remaining member receipts");
                return File.ReadAllBytes(persisted);
            }

            var omitted = await Present(Path.Combine(parent, "omitted"), null);
            var supplied = await Present(Path.Combine(parent, "supplied"), "EPIC");
            Require(omitted.SequenceEqual(supplied), "Acknowledged SCM storage is byte-for-byte identical with and without notice rarity");
            Console.WriteLine("PASS SCM receipt rarity parity: admission, deduplication, summary, acknowledgement and durable state");
        }
        finally { if (Directory.Exists(parent)) Directory.Delete(parent, true); }
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
        // Build 105: one summary card stands for unlocks past the single-card cap.
        delivery.ScmSummary(1, ["r-4", "r-5", "r-6"], at);
        delivery.ScmSummary(1, ["r-4", "r-5", "r-6"], at);
        delivery.ScmEarned(1, "scm-5", at, "星际圣诞", null, "r-5");
        delivery.ScmEarned(1, "scm-9", at, "星际圣诞", null, "r-9");
        delivery.ScmSummary(1, ["r-4", "r-5", "r-6", "r-8", "r-9"], at);
        delivery.ScmSummary(1, ["r-4", "r-6"], at);
        Require(sink.Notices.Count == 4 && sink.Notices[1].AchievementId == "scm-summary" && sink.Notices[1].SummaryCount == 3 &&
            sink.Notices[1].CanPresent && sink.Notices[2].AchievementId == "scm-9" &&
            sink.Notices[3].SummaryCount == 1 && sink.Notices[3].Receipt == "r-8",
            "R1 P2: a receipt queued once (single or inside a summary) is never queued again; a later summary stands only for the rest");
        delivery.Invalidate(2);
        Require(!new AchievementCelebration("scm-summary", at, 1, () => true).CanPresent, "An empty summary is never presented");
        var presented = 0;
        new AchievementCelebration("scm-1", at, 1, () => true, DisplayName: "星际圣诞") { Presented = () => presented++ }.MarkPresented();
        new AchievementCelebration("scm-1", at, 1, () => true, DisplayName: "星际圣诞") { Presented = () => throw new IOException() }.MarkPresented();
        Require(presented == 1, "MarkPresented reports once and never throws into the receiver");
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
