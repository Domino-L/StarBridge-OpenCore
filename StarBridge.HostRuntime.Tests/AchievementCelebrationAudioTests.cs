using StarBridge.HostRuntime.Notifications;
using System.Security.Cryptography;
using System.Text.Json;

internal static class AchievementCelebrationAudioTests
{
    private sealed class Output : INotificationAudioOutput
    {
        internal byte[]? Wave;
        public bool TryPlay(byte[] wave) { Wave = wave; return true; }
        public void Stop() => Wave = null;
        public void Dispose() => Stop();
    }
    internal static void Run()
    {
        FadeEnvelope();
        var root = Path.Combine(Path.GetTempPath(), "sb-achievement-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var wave = NotificationAudioTests.Wave(16);
            File.WriteAllBytes(Path.Combine(root, "achievement.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1, assets = new[] {
                new { assetId = "achievement-test", cueId = "achievement.unlock", fileName = "achievement.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(wave)) }
            }}));
            var settings = new NotificationAudioSettingsStore(root);
            var output = new Output();
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
                canNotify: () => false, canPlaySocial: () => false);
            Require(!audio.TryPlayAchievement(() => true), "Explicitly muted sound remains muted");
            settings.Save(0, true, .5, doNotDisturb: true);
            Require(audio.TryPlayAchievement(() => true), "Achievement ignores DND and ordinary-message environment suppression");
            Require(output.Wave!.SequenceEqual(NotificationWaveGain.Apply(wave, .5, 160)), "Original mother track receives one global gain with achievement-only short fade-in");
            Require(!audio.TryPlayAchievement(() => true), "Single achievement sound track cannot overlap itself");
            audio.StopAchievement();
            Require(output.Wave is null && !audio.TryPlayAchievement(() => false), "Expired account cannot play and cancellation stops its sound");
            settings.Save(1, true, 0, doNotDisturb: true);
            Require(!audio.TryPlayAchievement(() => true), "Zero volume still mutes achievement sound");
            settings.Save(2, true, .5);
            File.WriteAllBytes(Path.Combine(root, "achievement.wav"), [1, 2, 3]);
            Require(!audio.TryPlayAchievement(() => true), "Corrupt achievement audio cannot bypass verified asset integrity");
        }
        finally { Directory.Delete(root, true); }
    }
    internal static void FadeEnvelope()
    {
        foreach (var bits in new[] { 16, 24 })
        {
            const int rate = 48000, channels = 2, frames = 9600;
            using var stream = new MemoryStream();
            using (var writer = new BinaryWriter(stream, System.Text.Encoding.UTF8, leaveOpen: true))
            {
                var block = channels * bits / 8;
                writer.Write("RIFF"u8); writer.Write(36 + frames * block); writer.Write("WAVEfmt "u8);
                writer.Write(16); writer.Write((ushort)1); writer.Write((ushort)channels); writer.Write(rate);
                writer.Write(rate * block); writer.Write((ushort)block); writer.Write((ushort)bits);
                writer.Write("data"u8); writer.Write(frames * block);
                for (var frame = 0; frame < frames; frame++) for (var channel = 0; channel < channels; channel++)
                    if (bits == 16) writer.Write((short)16000); else writer.Write(new byte[] { 0, 0, 64 });
            }
            var original = stream.ToArray(); var before = (byte[])original.Clone();
            var plain = NotificationWaveGain.Apply(original, .7);
            var faded = NotificationWaveGain.Apply(original, .7, 160);
            var bytes = bits / 8; var fadeEnd = 44 + (rate * 160 / 1000) * channels * bytes;
            Require(faded.AsSpan(44, channels * bytes).ToArray().All(b => b == 0), "Fade starts at silence on both channels");
            Require(faded.AsSpan(44 + 3840 * channels * bytes, bytes).SequenceEqual(faded.AsSpan(44 + 3840 * channels * bytes + bytes, bytes)),
                "Fade uses the same frame envelope for left and right channels");
            Require(!faded.AsSpan(44 + 3840 * channels * bytes, bytes).SequenceEqual(plain.AsSpan(44 + 3840 * channels * bytes, bytes)),
                "Mid-fade samples are attenuated");
            Require(faded.AsSpan(fadeEnd).SequenceEqual(plain.AsSpan(fadeEnd)), "Everything after 160ms is exactly the original one-gain playback");
            Require(faded.Length == original.Length && faded.AsSpan(0, 44).SequenceEqual(original.AsSpan(0, 44)) && original.SequenceEqual(before),
                "Fade preserves source, WAV metadata, duration and timing");
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
