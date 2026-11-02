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
        public void Submit(AchievementCelebration notice)
        {
            if (!notice.TryAcceptReceipt()) return;
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
            using var runtime = new AccountBridgeRuntime(host, achievementDataRoot: root, backgroundTime: clock);
            var sink = new Sink(); runtime.ConfigureAchievementCelebration(sink);
            runtime.EventReady += frame => { if (frame.Name == "achievements.earned") throw new IOException("Synthetic event subscriber failure"); };
            var events = new System.Collections.Concurrent.ConcurrentQueue<BridgeEnvelope>(); runtime.EventReady += events.Enqueue;
            await CelebrationTestClock.Until(() => clock.Waiting(TimeSpan.FromSeconds(3)));
            ScmAchievementItem Item(int id, DateTimeOffset? at) => new($"scm-{id}", "星际圣诞", null, null, null, null, "RARE", "HOLIDAY", true, at, null, null, id);
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null)]);
            var baseline = await runtime.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read", "baseline", 1, new { schemaVersion = 1 }, probe.Owner));
            if (baseline.Response.Status != "ok" || !sink.Notices.IsEmpty || probe.Triggers != 1) throw new Exception("Composed startup must trigger once and seed old page without celebrating");
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null), Item(2, DateTimeOffset.UtcNow)]);
            clock.Advance(TimeSpan.FromSeconds(3));
            await CelebrationTestClock.Until(() => sink.Notices.Count == 1 && events.Any(e => e.Name == "achievements.earned"));
            if (!sink.Notices.TryPeek(out var notice) || notice.AchievementId != "scm-2" || notice.DisplayName != "星际圣诞" ||
                notice.LocalImagePath != "Assets/Achievements/scm-holiday-christmas-512.webp") throw new Exception("Background reread must enter actual native sink and domain event with SCM display data");
            sink.ThrowOnce = "scm-3";
            probe.Catalog = new(1, DateTimeOffset.UtcNow, [Item(1, null), Item(2, null), Item(3, null), Item(4, null), Item(5, null)]);
            async Task Refresh(string id) => _ = await runtime.DispatchAsync(BridgeEnvelope.Request("scmAchievements.read", id, 1, new { schemaVersion = 1 }, probe.Owner));
            await Refresh("failed-sink"); await Refresh("retry-sink"); await Refresh("deduplicated");
            if (sink.Notices.Count != 4 || events.Count(e => e.Name == "achievements.earned") != 4 || sink.Notices.Any(n => n.Receipt is null))
                throw new Exception("R4 composed sink/event failures must preserve siblings and retry with idempotent receipts");
            Console.WriteLine("PASS R4 ComposedThrowingSinkAndSubscriber: remaining cards, retry, native/event receipts");
            probe.Switch();
            if (notice.IsCurrent() || sink.Clears == 0) throw new Exception("Actual account event must invalidate the old card and queue");
            await CelebrationTestClock.Until(() => Volatile.Read(ref probe.Triggers) == 2);
            Console.WriteLine("PASS CX-ACHCEL composition: 1 group, 0 failed (startup, page baseline, delayed sink/event, account invalidation)");
        }
        finally { if (Directory.Exists(root)) Directory.Delete(root, true); }
    }
}
