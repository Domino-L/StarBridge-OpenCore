using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;

internal static class ScmAchievementReviewTests
{
    private static readonly BridgeAccountContext Owner = new("fixture", "scm", "synthetic-review-owner");
    private static ScmAchievementItem Item(int id, DateTimeOffset? at = null) =>
        new($"scm-{id}", "星际圣诞", null, null, null, null, "RARE", "HOLIDAY", true, at, null, null, id);
    private static ScmAchievementCatalog Catalog(params ScmAchievementItem[] items) => new(1, DateTimeOffset.UtcNow, items);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static async Task Run(string parent)
    {
        var root = Path.Combine(parent, "review");
        await ClockRollback(root);
        await DeliveryRetry(root);
        await InvalidationDuringDelivery(root);
        await CancellationReentry(root);
    }
    private static async Task ClockRollback(string root)
    {
        foreach (var scenario in new[] { "before-start", "untrusted-no-rollback", "during-run", "trusted-mismatch", "consistent-trusted" })
        {
            var clock = new CelebrationTestClock(); var realStart = clock.GetUtcNow();
            if (scenario == "before-start") clock.ShiftWall(TimeSpan.FromMinutes(-55));
            var delivered = 0;
            using var runtime = new ScmAchievementUnlockRuntime(Path.Combine(root, scenario), () => (Owner, 1),
                (_, _) => Task.CompletedTask, (_, _) => Task.FromResult(Catalog()), (_, _, _) => delivered++, clock,
                scenario is "before-start" or "untrusted-no-rollback" ? null : realStart);
            if (scenario == "during-run") clock.ShiftWall(TimeSpan.FromMinutes(-55));
            if (scenario == "trusted-mismatch") clock.ShiftWall(TimeSpan.FromMinutes(5));
            var at = scenario == "before-start" ? realStart.AddHours(-1) : realStart.AddMinutes(-9);
            await runtime.ObserveAsync(Owner, 1, Catalog(Item(1, at)));
            Check(delivered == (scenario == "consistent-trusted" ? 1 : 0), "R2 ClockRollback: " + scenario);
            await runtime.ObserveAsync(Owner, 1, Catalog(Item(1, realStart)));
            Check(delivered == (scenario == "consistent-trusted" ? 1 : 0), "Clock recovery cannot replay an observed ID");
            await runtime.RetireAsync();
        }
        Console.WriteLine("PASS R2 ClockRollback: before-start, runtime drift, trusted mismatch, consistent trusted anchor");
    }
    private static async Task DeliveryRetry(string root)
    {
        var attempts = new List<string>(); var displays = new List<string>();
        var path = Path.Combine(root, "retry");
        using (var delivery = new AchievementCelebrationDelivery(() => (Owner, 1), path))
        using (var runtime = new ScmAchievementUnlockRuntime(path, () => (Owner, 1), (_, _) => Task.CompletedTask,
            (_, _) => Task.FromResult(Catalog()), (generation, item, receipt) => {
                attempts.Add(item.Id);
                delivery.ScmEarned(generation, item.Id, item.UnlockedAtUtc!.Value, item.Name, null, receipt);
                if (item.Id == "scm-1") throw new IOException("Synthetic throw after acceptance");
            }))
        {
            delivery.Configure(new AcceptingSink(displays));
            await runtime.ObserveAsync(Owner, 1, Catalog());
            await runtime.ObserveAsync(Owner, 1, Catalog(Item(3), Item(1), Item(2)));
            Check(attempts.SequenceEqual(new[] { "scm-1", "scm-2", "scm-3" }), "R4 ThrowingCallbackContinuesSiblings: all cards receive their turn");
            using var lease = new ScmAchievementUnlockStore(path).Open(Owner);
            var state = lease.Read();
            Check(state.Confirmed.Length == 3 && state.Pending?.Single().Item.Id == "scm-1", "Only the unacknowledged receipt remains pending");
        }
        using var restartedDelivery = new AchievementCelebrationDelivery(() => (Owner, 2), path);
        restartedDelivery.Configure(new AcceptingSink(displays));
        using var restarted = new ScmAchievementUnlockRuntime(path, () => (Owner, 2), (_, _) => Task.CompletedTask,
            (_, _) => Task.FromResult(Catalog()), (generation, item, receipt) => {
                attempts.Add(item.Id);
                restartedDelivery.ScmEarned(generation, item.Id, item.UnlockedAtUtc!.Value, item.Name, null, receipt);
            });
        await restarted.ObserveAsync(Owner, 2, Catalog(Item(1), Item(2), Item(3)));
        await restarted.ObserveAsync(Owner, 2, Catalog(Item(1), Item(2), Item(3)));
        Check(attempts.SequenceEqual(new[] { "scm-1", "scm-2", "scm-3", "scm-1" }) && displays.Count == 3,
            "Stable receipt retries across restart without duplicating accepted cards");
        await restarted.RetireAsync();
        Console.WriteLine("PASS R4 ThrowingCallbackContinuesSiblings: durable pending, retry, idempotent receipt");
    }
    private sealed class AcceptingSink(List<string> displays) : IAchievementCelebrationSink
    {
        public void Submit(AchievementCelebration notice)
        { if (notice.TryAcceptReceipt()) displays.Add(notice.AchievementId); }
        public void Clear() { }
    }
    private static async Task InvalidationDuringDelivery(string root)
    {
        (BridgeAccountContext? Context, long Generation) owner = (Owner, 1);
        using var entered = new ManualResetEventSlim(); using var release = new ManualResetEventSlim(); var delivered = 0;
        using var runtime = new ScmAchievementUnlockRuntime(Path.Combine(root, "blocked"), () => owner, (_, _) => Task.CompletedTask,
            (_, _) => Task.FromResult(Catalog()), (_, _, _) => { Interlocked.Increment(ref delivered); entered.Set(); release.Wait(); });
        await runtime.ObserveAsync(Owner, 1, Catalog());
        var observation = runtime.ObserveAsync(Owner, 1, Catalog(Item(1), Item(2)));
        Check(entered.Wait(TimeSpan.FromSeconds(5)), "Delivery must enter the real coordinator callback");
        Task? retirement = null;
        try
        {
            owner = (null, 2);
            await Task.Run(() => runtime.Invalidate(2)).WaitAsync(TimeSpan.FromSeconds(2));
            retirement = runtime.RetireAsync();
            Check(!retirement.IsCompleted, "R7 Retirement waits for physical delivery after invalidation returns promptly");
        }
        finally { release.Set(); }
        await observation; await retirement!;
        Check(delivered == 1, "Late callback cannot deliver the old account's remaining cards");
        Console.WriteLine("PASS R7 InvalidationDuringDelivery: short state lock, retirement drain, stale siblings rejected");
    }
    private static async Task CancellationReentry(string root)
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var reentered = false;
        ScmAchievementUnlockRuntime? runtime = null;
        runtime = new(Path.Combine(root, "cancel"), () => (Owner, 1), async (_, token) => {
            using var registration = token.Register(() => Task.Run(() => { runtime!.Wake(); reentered = true; }).Wait(TimeSpan.FromSeconds(2)));
            entered.SetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, token);
        }, (_, _) => Task.FromResult(Catalog()), (_, _, _) => { });
        runtime.Wake(); await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        await runtime.RetireAsync().WaitAsync(TimeSpan.FromSeconds(5));
        Check(reentered, "R7 CancellationReentry: cancellation callback can reenter the short state lock from another thread");
        runtime.Dispose();
        Console.WriteLine("PASS R7 CancellationReentry: cancellation outside lock, CTS disposed after drain");
    }
}
