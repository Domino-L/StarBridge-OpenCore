using System.Reflection;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal interface ICelebrationFixtureHost : IAccountBridgeHost, IAchievementRemote { }
internal static class ScmAchievementCompositionTests
{
    private sealed class Sink : IAchievementCelebrationSink
    {
        internal readonly System.Collections.Concurrent.ConcurrentQueue<AchievementCelebration> Notices = new();
        internal int Clears;
        internal string? ThrowOnce;
        private readonly HashSet<string> _admitted = new(StringComparer.Ordinal);
        public void Submit(AchievementCelebration notice)
        {
            // Native's queue admits a receipt once per process (build 105: nothing is
            // written at admission; the card is acknowledged after its dwell).
            if (!notice.TryAcceptReceipt() || notice.Receipt is { } receipt && !_admitted.Add(receipt)) return;
            Notices.Enqueue(notice);
            if (notice.AchievementId == ThrowOnce) { ThrowOnce = null; throw new IOException("Synthetic sink failure after acceptance"); }
        }
        public void Clear() => Interlocked.Increment(ref Clears);
    }
    public class Probe : DispatchProxy
    {
        internal BridgeAccountContext Owner = new("fixture", "scm", "synthetic-composed-unlocks");
        internal long Generation = 1;
        internal int Triggers;
        internal ScmAchievementCatalog Catalog = new(1, DateTimeOffset.UtcNow, []);
        internal AchievementRarity? Rarity;
        private Action<long>? _changed;
        internal void Switch() { Owner = Owner with { Subject = "synthetic-other" }; Generation++; _changed?.Invoke(Generation); }
        protected override object? Invoke(MethodInfo? method, object?[]? args)
        {
            switch (method!.Name)
            {
                case "get_Generation": return Generation;
                case "get_CurrentContext": case "get_GameplayTimeContext": return Owner;
                case "get_HangarIdentity": return null;
                case "get_SupportsConcurrentReads": return false;
                case "add_AccountChanged": _changed += (Action<long>)args![0]!; return null;
                case "remove_AccountChanged": _changed -= (Action<long>)args![0]!; return null;
                case "TriggerScmAchievementsAsync": Interlocked.Increment(ref Triggers); return Task.CompletedTask;
                case "ReadScmAchievementsAsync": return Task.FromResult(Catalog);
                case "ReadAchievementsAsync": return Task.FromResult(new AchievementSnapshot(1, []));
                case "ReadRarityAsync": return Task.FromResult(Rarity);
                default: throw new NotSupportedException(method.Name);
            }
        }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-scm-composition-" + Guid.NewGuid().ToString("N"));
        var clock = new CelebrationTestClock();
        try
        {
            var host = DispatchProxy.Create<ICelebrationFixtureHost, Probe>(); var probe = (Probe)(object)host;
            // SCM `name` differs from the shown `title` (build 104: 资深玩家 vs 中登).
            ScmAchievementItem Item(int id, DateTimeOffset? at) => new($"scm-{id}", "圣诞节成就", "✨ 星际圣诞 ✨", null, null, null, "RARE", "HOLIDAY", true, at, null, null, id);
            // Already unlocked before this account's first sync (build 105: the
            // startup read before the trigger is that first, silent sync).
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null)]);
            using var runtime = new AccountBridgeRuntime(host, achievementDataRoot: root, backgroundTime: clock);
            var sink = new Sink(); runtime.ConfigureAchievementCelebration(sink);
            runtime.EventReady += frame => { if (frame.Name == "achievements.earned") throw new IOException("Synthetic event subscriber failure"); };
            var events = new System.Collections.Concurrent.ConcurrentQueue<BridgeEnvelope>(); runtime.EventReady += events.Enqueue;
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
            var baseline = await runtime.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read", "baseline", 1, new { schemaVersion = 1 }, probe.Owner));
            if (baseline.Response.Status != "ok" || !sink.Notices.IsEmpty || probe.Triggers != 1) throw new Exception("Composed startup must trigger once and seed old page without celebrating");
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null), Item(2, DateTimeOffset.UtcNow)]);
            clock.Advance(TimeSpan.FromSeconds(3));
            await CelebrationTestClock.Until(() => sink.Notices.Count == 1 && events.Any(e => e.Name == "achievements.earned"));
            if (!sink.Notices.TryPeek(out var notice) || notice.AchievementId != "scm-2" || notice.DisplayName != "星际圣诞" ||
                notice.LocalImagePath != "Assets/Achievements/scm-holiday-christmas-512.webp" ||
                notice.RarityTier != "RARE" || notice.RarityBasisPoints is not null)
                throw new Exception("Background reread must carry the stored SCM rarity and artwork to the native sink");
            sink.ThrowOnce = "scm-3";
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null), Item(2, null), Item(3, null), Item(4, null), Item(5, null)]);
            async Task Refresh(string id) => _ = await runtime.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read", id, 1, new { schemaVersion = 1 }, probe.Owner));
            await Refresh("failed-sink"); await Refresh("retry-sink"); await Refresh("deduplicated");
            if (sink.Notices.Count != 4 || events.Count(e => e.Name == "achievements.earned") != 4 || sink.Notices.Any(n => n.Receipt is null))
                throw new Exception("R4 composed sink/event failures must preserve siblings and retry with idempotent receipts");
            Console.WriteLine("PASS R4 ComposedThrowingSinkAndSubscriber: remaining cards, retry, native/event receipts");
            await VerifyAppRarity(runtime, probe, sink);
            probe.Switch();
            if (notice.IsCurrent() || sink.Clears == 0) throw new Exception("Actual account event must invalidate the old card and queue");
            await CelebrationTestClock.Until(() => Volatile.Read(ref probe.Triggers) == 2);
            Console.WriteLine("PASS CX-ACHCEL composition: 1 group, 0 failed (startup, page baseline, delayed sink/event, account invalidation)");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static async Task VerifyAppRarity(AccountBridgeRuntime runtime, Probe probe, Sink sink)
    {
        const BindingFlags flags = BindingFlags.Instance | BindingFlags.NonPublic;
        var at = DateTimeOffset.UtcNow;
        probe.Rarity = new(1, 30, 500, at,
            new() { ["first-entry"] = 120, ["hangar-home-3"] = 4, ["journey-lorville"] = 3000 },
            new() { ["first-entry"] = "rare", ["hangar-home-3"] = "veryRare" });
        var achievements = (AchievementRuntime)typeof(AccountBridgeRuntime).GetField("_achievements", flags)!.GetValue(runtime)!;
        await achievements.RefreshRarityAsync((probe.Owner, probe.Generation));
        _ = typeof(AccountBridgeRuntime).GetMethod("PublishFirstEntryEarned", flags)!.Invoke(runtime, [probe.Generation, at]);
        var series = typeof(AccountBridgeRuntime).GetMethod("PublishSeriesEarned", flags)!;
        foreach (var (id, rank) in new[] { ("hangar-home", 3), ("hangar-home", 4), ("journey-lorville", 0) })
            _ = series.Invoke(runtime, [probe.Generation, id, rank, at]);
        var rarity = sink.Notices.Where(n => n.Receipt is null).Select(n => (n.AchievementId, n.Rank, n.RarityTier, n.RarityBasisPoints));
        (string Id, int Rank, string? Tier, int? BasisPoints)[] expected =
        [
            ("first-entry", 0, "rare", 120),
            ("hangar-home", 3, "veryRare", 4),
            ("hangar-home", 4, null, null),
            ("journey-lorville", 0, null, 3000)
        ];
        if (!rarity.SequenceEqual(expected)) throw new Exception("Actual host callbacks must attach the owner-scoped cached tier and ratio by id and rank");
        Console.WriteLine("PASS composed app rarity: first entry, ranked hangar key, missing tier/ratio and percentage-only journey");
    }
}
