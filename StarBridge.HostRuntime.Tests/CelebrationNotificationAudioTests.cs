using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Achievements;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class CelebrationNotificationAudioTests
{
    private sealed class Output : INotificationAudioOutput
    {
        internal readonly List<byte[]> Played = [];
        internal int Stops;
        public bool TryPlay(byte[] wave) { Played.Add(wave); return true; }
        public void Stop() => Stops++;
        public void Dispose() { }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-celebration-deferred-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var soft = NotificationAudioTests.Wave(16); var rally = NotificationAudioTests.Wave(24);
            Array.Resize(ref rally, 44 + 48000 * 3 * 3); // Three-second PCM, to catch queued-cue truncation.
            System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(rally.AsSpan(4), rally.Length - 8);
            System.Buffers.Binary.BinaryPrimitives.WriteInt32LittleEndian(rally.AsSpan(40), rally.Length - 44);
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), soft); File.WriteAllBytes(Path.Combine(root, "rally.wav"), rally);
            File.WriteAllBytes(Path.Combine(root, "achievement.wav"), soft);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), JsonSerializer.Serialize(new { schemaVersion = 1, assets = new[] {
                new { assetId = "soft", cueId = "notify.soft", fileName = "soft.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(soft)) },
                new { assetId = "achievement", cueId = "achievement.unlock", fileName = "achievement.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(soft)) },
                new { assetId = "rally", cueId = "notify.rally", fileName = "rally.wav", tier = "approved", priority = 320, sha256 = Convert.ToHexString(SHA256.HashData(rally)) }
            }}));
            var settings = new NotificationAudioSettingsStore(root); settings.Save(0, true, 1);
            var clock = new CelebrationTestClock(); var activity = new AchievementCelebrationActivity();
            var output = new Output(); var generation = 1L; var current = true;
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => generation,
                () => true, clock, canPlaySocial: () => true, celebration: activity);
            var owner = new BridgeAccountContext("fixture", "scm", "synthetic-notification-owner");
            void Direct(int sequence)
            {
                var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 }, owner);
                var response = BridgeEnvelope.Response(request, new { schemaVersion = 1, serverTime = clock.GetUtcNow(), conversations = new[] {
                    new { conversationKey = new string('a', 64), latestSequence = sequence, unreadCount = 1,
                        lastMessageIncoming = true, lastMessageAt = clock.GetUtcNow() }
                }});
                audio.ObserveRoomRead(request, response, default);
            }
            Direct(1); activity.Report(true);
            Check(audio.TryPlayAchievement(() => true), "Achievement soundtrack starts under occupied presentation");
            clock.Advance(TimeSpan.FromSeconds(1));
            Direct(2);
            Check(!audio.TryPlayRally(() => current), "Rally sound defers while its independent banner can present");
            var preview = BridgeEnvelope.Request("notificationAudio.preview", "preview", 1, new { schemaVersion = 1, cueId = "notify.soft" });
            Check((await audio.DispatchAsync(preview)).Response.Payload.GetProperty("status").GetString() == "queued", "Other previews also wait");
            clock.Advance(TimeSpan.FromSeconds(20)); audio.DrainDeferred();
            Check(output.Played.Count == 1 && output.Stops == 0, "Neither messages nor rally cut the full celebration after 1.65 seconds");
            audio.StopAchievement(); activity.Report(false); audio.DrainDeferred();
            Check(output.Played.Count == 2 && output.Played[1].SequenceEqual(soft), "Private sound starts only after final card ends");
            audio.DrainDeferred(); Check(output.Played.Count == 2, "Queued sounds do not overwrite each other");
            clock.Advance(TimeSpan.FromSeconds(1)); audio.DrainDeferred();
            Check(output.Played.Count == 3 && output.Played[2].SequenceEqual(rally), "Rally follows prior audio in receipt order");
            clock.Advance(TimeSpan.FromSeconds(1)); audio.DrainDeferred();
            Check(output.Played.Count == 3, "Next cue waits for the actual three-second WAV duration");
            clock.Advance(TimeSpan.FromSeconds(2)); audio.DrainDeferred();
            Check(output.Played.Count == 4 && output.Played[3].SequenceEqual(soft), "Preview is the final serial cue");
            activity.Report(true); audio.TryPlayRally(() => current); current = false;
            activity.Report(false); audio.DrainDeferred(); Check(output.Played.Count == 4, "Expired rally is rechecked at playback");
            current = true; activity.Report(true); audio.TryPlayRally(() => current); generation++;
            activity.Report(false); audio.DrainDeferred(); Check(output.Played.Count == 4, "Account generation discards queued old audio");
            activity.Report(true); audio.TryPlayRally(() => current); settings.Save(1, false, 1);
            activity.Report(false); audio.DrainDeferred(); Check(output.Played.Count == 4, "Mute is rechecked at deferred delivery");
            activity.Report(true); audio.TryPlayRally(() => current); settings.Save(2, true, 1);
            activity.Report(false); audio.DrainDeferred(); Check(output.Played.Count == 4, "Events muted on arrival cannot replay after unmute");
            activity.Report(true); audio.TryPlayRally(() => current);
            settings.Save(3, false, 1); settings.Save(4, true, 1);
            activity.Report(false); audio.DrainDeferred();
            Check(output.Played.Count == 4, "R5 CloseRestoreBeforeDequeue: restoring audio cannot revive suppressed queued cues");
            var policies = new NotificationPolicyStore(root);
            activity.Report(true); Direct(3);
            policies.Save(owner, 0, Guid.NewGuid().ToString("N"), [new("directMessages", NotificationSourceMode.DoNotDisturb)], () => true);
            policies.Save(owner, 1, Guid.NewGuid().ToString("N"), [], () => true);
            activity.Report(false); audio.DrainDeferred();
            Check(output.Played.Count == 4, "R5 SourceDndRestoreBeforeDequeue: restored source cannot revive its old queued cue");
            activity.Report(true);
            Check(audio.TryPlayAchievement(() => true), "R6 soundtrack starts before injected policy failure");
            var stopsBeforeFault = output.Stops;
            var policyFile = Directory.GetFiles(Path.Combine(root, "notification-policies-v1"), "*.json").Single();
            File.WriteAllText(policyFile, "{");
            Direct(4);
            Check(output.Stops == stopsBeforeFault, "R6 PolicyReadFailureDuringCelebration must not stop the achievement soundtrack");
            audio.StopAchievement(); activity.Report(false);
            Console.WriteLine("PASS CX-ACHCEL audio: 1 group, 0 failed (private/rally/preview FIFO, full dwell, expiry/account/mute)");
        }
        finally { Directory.Delete(root, true); }
    }
}
