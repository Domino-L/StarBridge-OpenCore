using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;
using StarBridge.OverlayRuntime.Windows;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

// Explicit, local-only presentation probe. Uses the production STA, queue,
// HWND and verified audio output; never creates an account or grants an award.
internal static class AchievementCelebrationLiveProbe
{
    internal static async Task Run(string assetRoot, bool throughGrant = false)
    {
        var master = Path.Combine(Path.GetFullPath(assetRoot), "achievement.unlock.wav");
        Require(Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(master))) ==
            "738C9EBF57B2B714CE11A1F31B11FE6DAD91448E8FCC6CBD48C9742432D040D6", "Probe uses the approved original G3 master");
        var root = Path.Combine(Path.GetTempPath(), "sb-achievement-live-probe-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            File.WriteAllText(Path.Combine(root, "notification-audio.v1.json"), JsonSerializer.Serialize(new
            { schemaVersion = 1, revision = 0, enabled = true, volume = .7, doNotDisturb = true }));
            using var audio = NotificationAudioBridgeDispatcher.CreateDefault(root, assetRoot, () => 1,
                canNotify: () => false, canPlaySocial: () => false);
            var current = true;
            var played = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
            using var runtime = new NativeAchievementCelebrationRuntime(() => "zh-CN", () => false, () => false,
                owns => { var ok = audio.TryPlayAchievement(owns); played.TrySetResult(ok); return ok; }, audio.StopAchievement);
            var owner = new BridgeAccountContext("test", "scm", "synthetic-live-presentation");
            using var delivery = new AchievementCelebrationDelivery(() => (current ? owner : null, 1));
            delivery.Configure(runtime);
            using var cloud = new LocalGrantReceipt(root);
            var evidence = new FirstEntryEvidence(owner, 1,
                new FirstEntryObservation(1, FirstEntryObservation.HashHandle("Synthetic_Pilot"), "LIVE"));
            var earnedCallbacks = 0;
            using var achievements = new AchievementRuntime(new(root), cloud, () => (current ? owner : null, 1),
                () => evidence, _ => { }, startTimer: false,
                earned: (generation, at) => { earnedCallbacks++; delivery.FirstEntryEarned(generation, at); });
            Console.WriteLine("LOCAL PRESENTATION TEST: production native card + original G3 at 70%; no award, account, network or product preference changes.");
            await Task.Delay(3000);
            if (throughGrant)
            {
                await achievements.TickAsync(true);
                Require(cloud.Created && earnedCallbacks == 1, "Validated new-grant callback must reach production delivery despite a locked temporary outbox");
                cloud.ReleaseFile();
                await achievements.TickAsync(true);
                Require(earnedCallbacks == 1 && cloud.Observations == 1, "Local cleanup retry never duplicates grant or presentation");
            }
            else runtime.Submit(new AchievementCelebration("first-entry", DateTimeOffset.UtcNow, 1, () => current));
            var clock = Stopwatch.StartNew();
            var visible = false;
            var readable = false;
            while (clock.Elapsed < TimeSpan.FromSeconds(9))
            {
                var window = FindOwnCard();
                visible |= window != IntPtr.Zero;
                if (window != IntPtr.Zero && clock.ElapsedMilliseconds >= 1400 && GetWindowRect(window, out var bounds))
                    readable |= bounds.Right - bounds.Left >= 100 && bounds.Bottom - bounds.Top >= 40;
                if (visible && clock.ElapsedMilliseconds > 6500 && window == IntPtr.Zero) break;
                await Task.Delay(20);
            }
            current = false;
            Require(visible, "Full production runtime must create and show the native card after Submit");
            Require(readable, "Native card must remain visible during its readable hold");
            Require(played.Task.IsCompletedSuccessfully && played.Task.Result,
                "Native presentation must reach successful verified G3 playback despite ordinary DND guards");
            Require(FindOwnCard() == IntPtr.Zero, "Native runtime must dismiss its card after the presentation lifetime");
            Console.WriteLine("PASS full native presentation: Submit/STA/visible hold/dismiss + verified G3 playback, DND fixture, zero product writes");
            if (throughGrant) Console.WriteLine("PASS local grant-to-native chain: validated new receipt / blocked outbox cleanup / one delivery / one real card and G3");
        }
        finally { Directory.Delete(root, true); }
    }
    private sealed class LocalGrantReceipt(string root) : IAchievementRemote, IDisposable
    {
        private readonly Dictionary<string, DateTimeOffset> _saved = [];
        private FileStream? _blocker;
        internal bool Created => _saved.Count == 1;
        internal int Observations;
        public Task<AchievementSnapshot> ReadAchievementsAsync(BridgeAccountContext owner, long generation, CancellationToken token) =>
            Task.FromResult(new AchievementSnapshot(1, new(_saved)));
        public Task<AchievementReceipt> ObserveFirstEntryAsync(BridgeAccountContext owner, long generation, FirstEntryObservation observation, CancellationToken token)
        {
            Require(observation.IsValid, "Only finite local fixture evidence reaches the receipt provider");
            Observations++;
            var created = _saved.TryAdd("first-entry", DateTimeOffset.UtcNow);
            _blocker = new FileStream(Directory.GetFiles(Path.Combine(root, "achievements-pending-v1"), "*.json").Single(),
                FileMode.Open, FileAccess.ReadWrite, FileShare.None);
            return Task.FromResult(new AchievementReceipt(1, new(_saved), created));
        }
        internal void ReleaseFile() { _blocker?.Dispose(); _blocker = null; }
        public void Dispose() => ReleaseFile();
    }
    private static IntPtr FindOwnCard()
    {
        var found = IntPtr.Zero;
        EnumProc callback = (window, _) =>
        {
            GetWindowThreadProcessId(window, out var pid);
            if (pid == Environment.ProcessId && IsWindowVisible(window))
            {
                var title = new StringBuilder(128); GetWindowText(window, title, title.Capacity);
                if (title.ToString() == "StarBridge achievement") found = window;
            }
            return true;
        };
        EnumWindows(callback, IntPtr.Zero); GC.KeepAlive(callback); return found;
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private delegate bool EnumProc(IntPtr window, IntPtr arg);
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { internal int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern bool EnumWindows(EnumProc callback, IntPtr arg);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr window, out uint pid);
    [DllImport("user32.dll", CharSet = CharSet.Unicode)] private static extern int GetWindowText(IntPtr window, StringBuilder text, int length);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr window);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr window, out NativeRect rect);
}
