using System.IO;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;
using StarBridge.OverlayRuntime.Windows;

// Build 105 (user 11-21): "成就庆祝的预期是用户可以明显的看到，不要在加载的时候就
// 已经获取然后不弹庆祝了". An SCM unlock is acknowledged only after its card has
// completed the visible dwell; a card handed over but never seen comes back once.
internal static class CelebrationReceiptRecoveryTests
{
    private sealed class Surface : IAchievementCelebrationSurface
    {
        public double LifetimeMilliseconds => 50;
        public bool IsVisible { get; private set; }
        public void Show() => IsVisible = true;
        public void Hide() => IsVisible = false;
        public void Advance(double elapsed, int remaining) { }
        public void UpdatePosition() { }
        public void Dispose() => IsVisible = false;
    }
    private sealed class Sink : IAchievementCelebrationSink, IDisposable
    {
        internal int Presented;
        private readonly AchievementCelebrationPlayback _playback;
        internal Sink() => _playback = new(_ => { Presented++; return new Surface(); }, () => true, _ => true, () => { });
        public void Submit(AchievementCelebration notice)
        {
            // Same synchronous admission / STA split as Native, with a headless
            // surface instead of creating a visible window.
            if (!notice.TryAcceptReceipt()) return;
            _playback.SubmitAccepted(notice); _playback.Advance(0);
        }
        // Lets the current card finish its dwell (50 ms here).
        internal void FinishDwell() => _playback.Advance(60);
        public void Clear() => _playback.Clear();
        public void Dispose() => _playback.Dispose();
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static void Run() => RunAsync().GetAwaiter().GetResult();
    private static int Pending(string root, BridgeAccountContext account)
    {
        using var lease = new ScmAchievementUnlockStore(root).Open(account);
        return ScmAchievementUnlockStore.Unshown(lease.Read()).Length;
    }
    private static async Task Until(Func<bool> check)
    {
        var timeout = System.Diagnostics.Stopwatch.StartNew();
        while (!check()) { if (timeout.Elapsed > TimeSpan.FromSeconds(5)) throw new Exception("Acknowledgement did not arrive"); await Task.Delay(5); }
    }
    // Paused time (locked desktop, nobody at it) is not visible dwell (R1 P3).
    private static void PausedDwell()
    {
        var allowed = true; var presented = 0;
        using var playback = new AchievementCelebrationPlayback(_ => new Surface(), () => allowed, _ => true, () => { });
        playback.Submit(new AchievementCelebration("scm-1", DateTimeOffset.UtcNow, 1, () => true, DisplayName: "Synthetic") { Presented = () => presented++ });
        playback.Advance(0);
        allowed = false; playback.Advance(60); playback.Advance(60);
        Check(presented == 0, "A paused card is not counted as shown");
        allowed = true; playback.Advance(0);
        Check(presented == 0, "Resuming restarts the entrance rather than finishing the dwell");
        playback.Advance(60);
        Check(presented == 1, "The card counts as shown once its dwell completes while visible");
        Console.WriteLine("PASS R1 PausedDwell: no MarkPresented while held, once after a visible dwell");
    }
    private static async Task RunAsync()
    {
        PausedDwell();
        foreach (var scenario in new[] { "exit-before-dwell", "account-switch-before-dwell", "shown" })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-receipt-recovery-" + Guid.NewGuid().ToString("N"));
            var account = new BridgeAccountContext("fixture", "scm", "synthetic-receipt-owner");
            (BridgeAccountContext? Context, long Generation) owner = (account, 1);
            var item = new ScmAchievementItem("scm-1", "Synthetic", null, null, null, null, "RARE", "HOLIDAY", true,
                DateTimeOffset.UtcNow, null, null, 1);
            ScmAchievementCatalog Catalog(params ScmAchievementItem[] items) => new(1, DateTimeOffset.UtcNow, items);
            try
            {
                using (var sink = new Sink())
                using (var delivery = new AchievementCelebrationDelivery(() => owner, root))
                using (var runtime = new ScmAchievementUnlockRuntime(root, () => owner, (_, _) => Task.CompletedTask,
                    (_, _) => Task.FromResult(Catalog()), (generation, earned, receipt) =>
                        delivery.ScmEarned(generation, earned.Id, earned.UnlockedAtUtc!.Value, earned.Name, null, receipt)))
                {
                    delivery.Configure(sink);
                    await runtime.ObserveAsync(account, 1, Catalog());
                    await runtime.ObserveAsync(account, 1, Catalog(item));
                    Check(sink.Presented == 1, "The new unlock reaches the real playback once: " + scenario);
                    await Task.Delay(50);
                    Check(Pending(root, account) == 1, "Starting to show a card does not acknowledge it: " + scenario);
                    await runtime.ObserveAsync(account, 1, Catalog(item));
                    Check(sink.Presented == 1, "A card already handed over is not admitted twice in one process: " + scenario);
                    if (scenario == "shown")
                    {
                        sink.FinishDwell();
                        await Until(() => Pending(root, account) == 0);
                    }
                    if (scenario == "account-switch-before-dwell")
                    {
                        owner = (account with { Subject = "synthetic-other" }, 2); delivery.Invalidate(2);
                        await Task.Delay(50);
                        Check(Pending(root, account) == 1, "Clearing the queue on an account switch does not count as shown");
                    }
                    await runtime.RetireAsync();
                }
                // Every receiving object is new. Only production files survive.
                owner = (account, 3);
                using var rebuiltSink = new Sink();
                using var rebuiltDelivery = new AchievementCelebrationDelivery(() => owner, root);
                rebuiltDelivery.Configure(rebuiltSink);
                using var rebuiltRuntime = new ScmAchievementUnlockRuntime(root, () => owner, (_, _) => Task.CompletedTask,
                    (_, _) => Task.FromResult(Catalog()), (generation, earned, receipt) =>
                        rebuiltDelivery.ScmEarned(generation, earned.Id, earned.UnlockedAtUtc!.Value, earned.Name, null, receipt));
                await rebuiltRuntime.ObserveAsync(account, 3, Catalog(item));
                var expected = scenario == "shown" ? 0 : 1;
                Check(rebuiltSink.Presented == expected, "R4 RebuiltReceiptOwner: a never-shown card plays again, a shown one never: " + scenario);
                if (expected == 1) { rebuiltSink.FinishDwell(); await Until(() => Pending(root, account) == 0); }
                owner = (account with { Subject = "synthetic-other" }, 4); rebuiltDelivery.Invalidate(4);
                owner = (account, 5); rebuiltDelivery.Invalidate(5);
                await rebuiltRuntime.ObserveAsync(account, 5, Catalog(item));
                Check(rebuiltSink.Presented == expected, "R4 AccountRoundTrip: a shown card does not return: " + scenario);
                // A store from an older build marked admission as Accepted; such a
                // receipt is treated as shown rather than celebrated twice.
                using (var lease = new ScmAchievementUnlockStore(root).Open(account))
                {
                    var state = lease.Read();
                    var receipt = state.OwnerHash + ":" + item.Id;
                    lease.Save(state with { Pending = [new(receipt, item)], Accepted = [receipt] }, () => true);
                }
                await rebuiltRuntime.ObserveAsync(account, 5, Catalog(item));
                Check(rebuiltSink.Presented == expected && Pending(root, account) == 0, "A legacy accepted receipt is not shown again");
                await rebuiltRuntime.RetireAsync();
                Console.WriteLine("PASS R4 RebuiltReceiptOwner / AccountRoundTrip: " + scenario);
            }
            finally
            {
                for (var attempt = 0; Directory.Exists(root); attempt++)
                {
                    try { Directory.Delete(root, true); }
                    catch (IOException) when (attempt < 40) { Thread.Sleep(50); }
                }
            }
        }
    }
}
