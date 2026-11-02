using System.IO;
using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Notifications;
using StarBridge.OverlayRuntime.Windows;

internal static class CelebrationAudioOwnershipTests
{
    private sealed class Clock : TimeProvider
    {
        internal long Now;
        public override long TimestampFrequency => TimeSpan.TicksPerSecond;
        public override long GetTimestamp() => Now;
    }
    private sealed class Output : INotificationAudioOutput
    {
        internal int Plays;
        internal bool FailStop;
        public bool TryPlay(byte[] wave) { Plays++; return true; }
        public void Stop() { if (FailStop) throw new InvalidOperationException("Synthetic output stop failure"); }
        public void Dispose() { }
    }
    private sealed class Surface : IAchievementCelebrationSurface
    {
        public double LifetimeMilliseconds => 100;
        public bool IsVisible { get; private set; }
        public void Show() => IsVisible = true;
        public void Hide() => IsVisible = false;
        public void Advance(double elapsed, int remaining) { }
        public void UpdatePosition() { }
        public void Dispose() => IsVisible = false;
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
    internal static void Run()
    {
        foreach (var scenario in new[] { "clear", "account-invalidated", "dispose" }) Run(scenario);
    }
    private static void Run(string scenario)
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-audio-owner-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var wave = new byte[48];
            using (var stream = new MemoryStream(wave))
            using (var writer = new BinaryWriter(stream))
            {
                writer.Write("RIFF"u8); writer.Write(40); writer.Write("WAVEfmt "u8); writer.Write(16);
                writer.Write((short)1); writer.Write((short)1); writer.Write(48000); writer.Write(96000);
                writer.Write((short)2); writer.Write((short)16); writer.Write("data"u8); writer.Write(4); writer.Write(0);
            }
            File.WriteAllBytes(Path.Combine(root, "cue.wav"), wave);
            File.WriteAllBytes(Path.Combine(root, "rally.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1,
                assets = new[] { "achievement.unlock", "notify.rally" }.Select((cue, i) => new {
                    assetId = "cue" + i, cueId = cue, fileName = i == 0 ? "cue.wav" : "rally.wav", tier = "approved", priority = 320,
                    sha256 = Convert.ToHexString(SHA256.HashData(wave)) }) }));
            new NotificationAudioSettingsStore(root).Save(0, true, 1);
            var activity = new AchievementCelebrationActivity(); var output = new Output(); var clock = new Clock();
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output,
                () => 1, () => true, clock, canPlaySocial: () => true, celebration: activity);
            var current = true;
            AchievementCelebration Notice(string receipt) => new("scm-1", DateTimeOffset.UtcNow, 1, () => current,
                DisplayName: "Synthetic", Receipt: receipt);
            AchievementCelebrationPlayback Playback() => new(_ => new Surface(), () => true,
                audio.TryPlayAchievement, audio.StopAchievement, activity);
            using var playback = Playback();
            playback.Submit(Notice("first")); playback.Advance(0);
            Check(output.Plays == 1 && activity.IsActive, "Real dispatcher starts the first soundtrack.");
            output.FailStop = true;
            if (scenario == "clear") playback.Clear();
            else if (scenario == "account-invalidated") { current = false; playback.Advance(0); }
            else playback.Dispose();
            Check(!activity.IsActive, "Exceptional cleanup releases presentation activity: " + scenario);
            output.FailStop = false;
            clock.Now += TimeSpan.FromSeconds(2).Ticks;
            Check(audio.TryPlayRally(() => true) && output.Plays == 2, "Ordinary sound resumes after " + scenario);
            current = true;
            using var next = Playback(); next.Submit(Notice("next")); next.Advance(0);
            Check(output.Plays == 3 && next.HasActive, "R3 DispatcherStopFailure: next valid celebration regains its audio track after " + scenario);
            Console.WriteLine("PASS R3 DispatcherStopFailure: " + scenario);
        }
        finally { Directory.Delete(root, true); }
    }
}
