using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class NotificationAudioTests
{
    private sealed class Output : INotificationAudioOutput {
        internal int Plays, Stops; internal byte[]? Last;
        public bool TryPlay(byte[] wave) { Plays++; Last = wave; return true; }
        public void Stop() => Stops++;
        public void Dispose() => Stop();
    }
    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
    internal static byte[] Wave(int bits = 24) {
        using var memory = new MemoryStream(); using var writer = new BinaryWriter(memory);
        writer.Write(Encoding.ASCII.GetBytes("RIFF")); writer.Write(36 + bits / 8 * 2); writer.Write(Encoding.ASCII.GetBytes("WAVEfmt "));
        writer.Write(16); writer.Write((short)1); writer.Write((short)1); writer.Write(48000); writer.Write(48000 * bits / 8);
        writer.Write((short)(bits / 8)); writer.Write((short)bits); writer.Write(Encoding.ASCII.GetBytes("data")); writer.Write(bits / 8 * 2);
        if (bits == 24) writer.Write(new byte[] { 0, 0, 64, 0, 0, 192 });
        else { writer.Write((short)16384); writer.Write((short)-16384); }
        return memory.ToArray();
    }
    internal static string Manifest(byte[] wave) => JsonSerializer.Serialize(new { schemaVersion = 1, assets = new[] {
        new { assetId = "approved", cueId = "notify.soft", fileName = "soft.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(wave)) },
        new { assetId = "fallback", cueId = "notify.soft", fileName = "fallback.wav", tier = "fallback", priority = 120, sha256 = Convert.ToHexString(SHA256.HashData(wave)) },
    }});
    private static byte[] ExtendedWave(int bits) {
        using var memory = new MemoryStream(); using var writer = new BinaryWriter(memory);
        writer.Write("RIFF"u8); writer.Write(0); writer.Write("WAVEfmt "u8);
        writer.Write(40); writer.Write((ushort)0xfffe); writer.Write((ushort)2);
        writer.Write(48000); writer.Write(48000 * 2 * bits / 8);
        writer.Write((ushort)(2 * bits / 8)); writer.Write((ushort)bits);
        writer.Write((ushort)22); writer.Write((ushort)bits); writer.Write(3);
        writer.Write(new Guid("00000001-0000-0010-8000-00aa00389b71").ToByteArray());
        writer.Write("LIST"u8); writer.Write(26); writer.Write(new byte[26]);
        writer.Write("data"u8); writer.Write(2 * bits / 8); writer.Write(Wave(bits).AsSpan(44));
        var result = memory.ToArray();
        System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(result.AsSpan(4), result.Length - 8);
        return result;
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-audio-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            foreach (var bits in new[] { 16, 24 }) {
                var extended = ExtendedWave(bits);
                var half = NotificationWaveGain.Apply(extended, .5);
                Check(half.AsSpan(102).SequenceEqual(NotificationWaveGain.Apply(Wave(bits), .5).AsSpan(44)), "Extensible PCM gain matches classic PCM");
                Check(half.AsSpan(0, 102).SequenceEqual(extended.AsSpan(0, 102)) && extended.SequenceEqual(ExtendedWave(bits)), "Preserve metadata and source bytes");
                Check(NotificationWaveGain.Apply(extended, 0).Skip(102).All(v => v == 0), "Extensible PCM mute");
                Check(NotificationWaveGain.Apply(extended, 1).SequenceEqual(extended), "Extensible PCM unity gain");
                foreach (var position in new[] { 36, 38, 44 }) {
                    var malformed = (byte[])extended.Clone(); malformed[position] = 0;
                    try { NotificationWaveGain.Apply(malformed, .5); throw new Exception("Accepted invalid extensible format"); }
                    catch (InvalidDataException) { }
                }
            }
            // Optional product-bundle gate: real assets, isolated preferences, silent output.
            if (Environment.GetEnvironmentVariable("STARBRIDGE_TEST_AUDIO_BUNDLE") is { Length: > 0 } bundle) {
                var bundleOutput = new Output();
                using var bundleDispatcher = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(bundle), bundleOutput, () => 3);
                new NotificationAudioSettingsStore(root).Save(0, true, .5);
                foreach (var cue in NotificationAudioCueIds.All) {
                    var response = (await bundleDispatcher.DispatchAsync(BridgeEnvelope.Request("notificationAudio.preview", Guid.NewGuid().ToString("N"), 3, new { schemaVersion = 1, cueId = cue }))).Response;
                    Check(response.Status == "ok" && response.Payload.GetProperty("played").GetBoolean(), $"Bundled preview {cue}: {response.Error?.Code}");
                }
                if (Environment.GetEnvironmentVariable("STARBRIDGE_TEST_AUDIO_DEVICE") == "1") {
                    using var device = new WindowsWaveAudioOutput();
                    Check(device.TryPlay(NotificationWaveGain.Apply(bundleOutput.Last!, 0)), "Windows accepts verified extensible PCM (silent device probe)");
                }
                File.Delete(Path.Combine(root, "notification-audio.v1.json"));
            }
            var wave = Wave();
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), wave); File.WriteAllBytes(Path.Combine(root, "fallback.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), Manifest(wave));
            var catalog = NotificationAudioCatalog.Load(root);
            Check(catalog.Resolve("notify.soft")!.Tier == NotificationAudioAssetTier.Approved, "Approved priority");
            foreach (var bits in new[] { 16, 24 }) {
                var original = Wave(bits); var half = NotificationWaveGain.Apply(original, .5); var zero = NotificationWaveGain.Apply(original, 0);
                Check(zero.Skip(44).All(v => v == 0) && original.SequenceEqual(Wave(bits)), "Zero gain and immutable original");
                Check(half[bits == 24 ? 46 : 45] == 32, "Independent PCM gain");
                Check(NotificationWaveGain.Apply(original, 1).SequenceEqual(original), "Unity gain preserves PCM");
            }
            var output = new Output();
            using var dispatcher = new NotificationAudioBridgeDispatcher(root, catalog, output, () => 3);
            async Task<BridgeEnvelope> Call(string name, object payload, long generation = 3, BridgeAccountContext? owner = null) =>
                (await dispatcher.DispatchAsync(BridgeEnvelope.Request("notificationAudio." + name, Guid.NewGuid().ToString("N"), generation, payload, owner))).Response;
            foreach (var name in NotificationAudioBridgeDispatcher.AdvertisedCapabilities)
                Check(!BridgeRequestPolicy.RequiresAccountContext(name), "Device audio requires no account");
            var read = await Call("read", new { schemaVersion = 1 });
            Check(read.Status == "ok" && !read.Payload.GetProperty("enabled").GetBoolean() && read.Payload.GetProperty("previewAvailable").GetBoolean(), "Safe default and real assets");
            var muted = await Call("preview", new { schemaVersion = 1, cueId = "notify.soft" });
            Check(muted.Payload.GetProperty("status").GetString() == "muted" && output.Plays == 0, "Muted never plays");
            var saved = await Call("save", new { schemaVersion = 1, expectedRevision = 0, enabled = true, volume = .5 });
            Check(saved.Status == "ok" && new NotificationAudioSettingsStore(root).Read().Volume == .5, "Persisted gain");
            var conflict = await Call("save", new { schemaVersion = 1, expectedRevision = 0, enabled = false, volume = .1 });
            Check(conflict.Error?.Code == "notificationAudio.write_conflict" && new NotificationAudioSettingsStore(root).Read().Enabled, "Conflict cannot overwrite");
            var played = await Call("preview", new { schemaVersion = 1, cueId = "notify.soft" });
            Check(played.Payload.GetProperty("played").GetBoolean() && output.Plays == 1 && output.Last![46] == 32, "Verified bytes with persisted gain");
            var stale = await Call("preview", new { schemaVersion = 1, cueId = "notify.soft" }, 2);
            Check(stale.Status == "error" && output.Plays == 1, "Stale request never plays");
            var invalid = await Call("preview", new { schemaVersion = 1, cueId = "notify.soft", filePath = "not-allowed.wav" });
            Check(invalid.Status == "error" && output.Plays == 1, "No caller supplied path");
            await Call("save", new { schemaVersion = 1, expectedRevision = 1, enabled = true, volume = 0 });
            await Call("preview", new { schemaVersion = 1, cueId = "notify.soft" });
            Check(output.Plays == 1 && output.Stops >= 2, "Zero volume also mutes; changing settings stops old playback");
            await Call("save", new { schemaVersion = 1, expectedRevision = 2, enabled = true, volume = .5 });
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), [1, 2, 3]);
            var broken = await Call("preview", new { schemaVersion = 1, cueId = "notify.soft" });
            Check(broken.Error?.Code == "notificationAudio.integrity_failed" && output.Plays == 1, "Present corrupt approved asset refuses fallback");
            File.WriteAllText(Path.Combine(root, "notification-audio.v1.json"), "{}");
            var damaged = await Call("save", new { schemaVersion = 1, expectedRevision = 3, enabled = true, volume = .2 });
            Check(damaged.Status == "error" && File.ReadAllText(Path.Combine(root, "notification-audio.v1.json")) == "{}", "Corrupt preferences are not overwritten");
            var stopped = await Call("stop", new { schemaVersion = 1 });
            Check(stopped.Payload.GetProperty("status").GetString() == "stopped", "Stop works even with damaged preferences");
        } finally { Directory.Delete(root, true); }
    }
}
