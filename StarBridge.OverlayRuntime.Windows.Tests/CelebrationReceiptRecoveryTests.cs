using System.IO;
using StarBridge.HostRuntime.Achievements;
using StarBridge.NativeBridge;
using StarBridge.OverlayRuntime.Windows;

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
        internal AchievementCelebration? LastNotice;
        private readonly AchievementCelebrationPlayback _playback;
        internal Sink() => _playback = new(_ => { Presented++; return new Surface(); }, () => true, _ => true, () => { });
        public void Submit(AchievementCelebration notice)
        {
            LastNotice = notice;
            // Same synchronous acceptance / STA admission split as Native,
            // with a headless surface instead of creating a visible window.
            if (!notice.TryAcceptReceipt()) return;
            _playback.SubmitAccepted(notice); _playback.Advance(0);
        }
        public void Clear() => _playback.Clear();
        public void Dispose() => _playback.Dispose();
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static void Run() => RunAsync().GetAwaiter().GetResult();
    private static async Task RunAsync()
    {
        foreach (var failure in new[] { "callback-after-accept", "confirmation-save", "exit-before-confirmation" })
        {
            var root = Path.Combine(Path.GetTempPath(), "sb-receipt-recovery-" + Guid.NewGuid().ToString("N"));
            var account = new BridgeAccountContext("fixture", "scm", "synthetic-receipt-owner");
            (BridgeAccountContext? Context, long Generation) owner = (account, 1);
            var item = new ScmAchievementItem("scm-1", "Synthetic", null, null, null, null, "RARE", "HOLIDAY", true,
                DateTimeOffset.UtcNow, null, null, 1);
            ScmAchievementCatalog Catalog(params ScmAchievementItem[] items) => new(1, DateTimeOffset.UtcNow, items);
            FileStream? blockConfirmation = null;
            try
            {
                using (var sink = new Sink())
                using (var delivery = new AchievementCelebrationDelivery(() => owner, root))
                using (var runtime = new ScmAchievementUnlockRuntime(root, () => owner, (_, _) => Task.CompletedTask,
                    (_, _) => Task.FromResult(Catalog()), (generation, earned, receipt) => {
                        delivery.ScmEarned(generation, earned.Id, earned.UnlockedAtUtc!.Value, earned.Name, null, receipt);
                        if (failure == "callback-after-accept") throw new IOException("Synthetic callback after sink accepted");
                        if (failure == "confirmation-save")
                        {
                            // Acceptance is durable; the producer's separate acknowledgement
                            // may read the state but cannot replace it until this handle exits.
                            var state = Directory.GetFiles(Path.Combine(root, "scm-achievement-unlocks-v1"), "*.json").Single();
                            blockConfirmation = new FileStream(state, FileMode.Open, FileAccess.Read, FileShare.Read);
                        }
                        if (failure == "exit-before-confirmation") owner = (null, 2);
                    }))
                {
                    delivery.Configure(sink);
                    await runtime.ObserveAsync(account, 1, Catalog());
                    try { await runtime.ObserveAsync(account, 1, Catalog(item)); }
                    catch (IOException) when (failure == "confirmation-save") { }
                    finally { blockConfirmation?.Dispose(); }
                    Check(sink.Presented == 1, "Initial receipt reaches the real playback once.");
                    using var lease = new ScmAchievementUnlockStore(root).Open(account);
                    var accepted = lease.Read();
                    Check(accepted.Pending?.Length == 1 && accepted.Accepted?.Single() == accepted.OwnerHash + ":" + item.Id,
                        "Fault injection must retain both producer Pending and durable receiver acceptance: " + failure);
                    // The producer can retry the identical object after an interrupted
                    // Configure, as well as reconstruct a new notice from Pending.
                    if (failure != "exit-before-confirmation")
                    {
                        lease.Dispose(); sink.Clear(); sink.Submit(sink.LastNotice!);
                        Check(sink.Presented == 1, "R4 SameNoticeAfterClear must recheck durable acceptance.");
                    }
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
                Check(rebuiltSink.Presented == 0, "R4 RebuiltReceiptOwner must not celebrate accepted pending again: " + failure);
                owner = (account with { Subject = "synthetic-other" }, 4); rebuiltDelivery.Invalidate(4);
                owner = (account, 5); rebuiltDelivery.Invalidate(5);
                // Recreate an unconfirmed producer receipt to exercise account return,
                // independent of the successful retry's removal of Pending.
                using (var lease = new ScmAchievementUnlockStore(root).Open(account))
                {
                    var state = lease.Read();
                    lease.Save(state with { Pending = [new(state.OwnerHash + ":" + item.Id, item)] }, () => true);
                }
                await rebuiltRuntime.ObserveAsync(account, 5, Catalog(item));
                Check(rebuiltSink.Presented == 0, "R4 AccountRoundTrip cannot clear durable acceptance: " + failure);
                using (var lease = new ScmAchievementUnlockStore(root).Open(account))
                    Check(lease.Read().Pending?.Length == 0, "A durable duplicate is acknowledged without another card.");
                await rebuiltRuntime.RetireAsync();
                Console.WriteLine("PASS R4 RebuiltReceiptOwner / AccountRoundTrip: " + failure);
            }
            finally { blockConfirmation?.Dispose(); if (Directory.Exists(root)) Directory.Delete(root, true); }
        }
    }
}
