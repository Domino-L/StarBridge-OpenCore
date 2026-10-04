using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class SocialNotificationAudioTests
{
    private sealed class Clock : TimeProvider {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
    }
    private sealed class Output : INotificationAudioOutput {
        internal int Plays;
        public bool TryPlay(byte[] bytes) { Plays++; return true; }
        public void Stop() { }
        public void Dispose() { }
    }
    private sealed class Domain : IBridgeRequestDispatcher {
        internal object Value = new { };
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default) =>
            ValueTask.FromResult(new BridgeDispatchBatch(BridgeEnvelope.Response(request, Value), []));
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-social-audio-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var endpoint = AudioEndpointSnapshot.Fingerprint("synthetic-device");
            if (endpoint.Length != 16 || endpoint != AudioEndpointSnapshot.Fingerprint("synthetic-device") ||
                endpoint == AudioEndpointSnapshot.Fingerprint("other-device"))
                throw new Exception("Endpoint fingerprints must distinguish changes without raw device IDs.");
            var traceRequest = BridgeEnvelope.Request("directMessages.read", "private-correlation", 1);
            var trace = NotificationDeliveryJournal.TraceFor(traceRequest);
            if (trace != NotificationDeliveryJournal.TraceFor(traceRequest) ||
                trace == NotificationDeliveryJournal.TraceFor(traceRequest with { }))
                throw new Exception("One read must share an opaque trace; separate reads must not collide.");
            var journalProbe = new NotificationDeliveryJournal(root);
            journalProbe.Record(NotificationDeliveryChannel.Audio, NotificationDeliveryStage.NativeAccepted,
                trace, "private transport", "private error");
            journalProbe.Record(NotificationDeliveryChannel.Desktop, NotificationDeliveryStage.NativeAccepted,
                trace, "wpfCard", "queued");
            var probeText = File.ReadAllText(Path.Combine(root, "notification-delivery-diagnostics.log"));
            if (probeText.Split("trace=" + trace).Length != 3 || probeText.Contains("private", StringComparison.OrdinalIgnoreCase) ||
                !probeText.Contains("transport=unknown result=unknown") || !probeText.Contains("transport=wpfCard result=queued"))
                throw new Exception("Diagnostics must correlate channels and redact arbitrary native strings.");
            var wave = NotificationAudioTests.Wave();
            File.WriteAllBytes(Path.Combine(root, "soft.wav"), wave);
            File.WriteAllText(Path.Combine(root, "cue-catalog.v1.json"), NotificationAudioTests.Manifest(wave));
            new NotificationAudioSettingsStore(root).Save(0, true, .5);
            var output = new Output(); var domain = new Domain(); var clock = new Clock(); var allowed = true; var socialAllowed = true;
            using var audio = new NotificationAudioBridgeDispatcher(root, NotificationAudioCatalog.Load(root), output, () => 1,
                () => allowed, clock, canPlaySocial: () => socialAllowed);
            using var composite = new CompositeBridgeDispatcher(domain, domain, domain, audio: audio);
            var start = DateTimeOffset.UtcNow;
            async Task Read(int second, int sequence) {
                clock.Seconds = second;
                domain.Value = new { schemaVersion = 1, serverTime = start.AddSeconds(second), conversations = new[] {
                    new { conversationKey = new string('a', 64), latestSequence = sequence,
                        unreadCount = 1, lastMessageIncoming = true, lastMessageAt = start.AddSeconds(second) }
                }};
                var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1 }, new BridgeAccountContext("fixture", "fixture", "fixture"));
                await composite.DispatchAsync(request);
            }
            await Read(0, 1);
            if (output.Plays != 0) throw new Exception("Initial history must remain silent.");
            await Read(1, 2);
            if (output.Plays != 1) throw new Exception("Fresh private message must reach enabled audio through the real composite dispatcher.");
            await Read(2, 2);
            if (output.Plays != 1) throw new Exception("Repeated read must not replay audio.");
            await Read(3, 3);
            if (output.Plays != 2) throw new Exception("Separate social messages must not inherit the ten-second room cooldown.");
            async Task Friend(int second, char key) {
                clock.Seconds = second;
                domain.Value = new { schemaVersion = 1, updatedAt = start.AddSeconds(second), items = new[] {
                    new { eventKey = new string(key, 64), actionTarget = "friend_requests", createdAt = start.AddSeconds(second), read = false, isAvailable = true }
                }};
                await composite.DispatchAsync(BridgeEnvelope.Request("notificationInbox.read", Guid.NewGuid().ToString("N"), 1,
                    new { schemaVersion = 1 }, new BridgeAccountContext("fixture", "fixture", "fixture")));
            }
            await Friend(4, 'a'); await Friend(5, 'b');
            if (output.Plays != 3) throw new Exception("Fresh friend request must reach the sound output.");
            var store = new NotificationAudioSettingsStore(root);
            store.Save(store.Read().Revision, false, .5);
            await Read(7, 4); await Friend(8, 'c');
            if (output.Plays != 3) throw new Exception("Disabled sound must remain quiet for all social sources.");
            store.Save(store.Read().Revision, true, .5);
            await Read(9, 4); await Friend(10, 'c');
            if (output.Plays != 3) throw new Exception("Enabling sound must not replay consumed messages.");
            allowed = false; socialAllowed = false;
            await Read(11, 5);
            if (output.Plays != 3) throw new Exception("Environment suppression must prevent automatic sound.");
            socialAllowed = true;
            await Read(12, 6);
            await Friend(13, 'd');
            if (output.Plays != 5)
                throw new Exception("Fullscreen visual suppression must not mute enabled private and friend audio.");
            var journal = File.ReadAllText(Path.Combine(root, "notification-delivery-diagnostics.log"));
            if (!journal.Contains("trace=") || !journal.Contains("transport=unknown") || !journal.Contains("result=acceptedUnverified"))
                throw new Exception("Automatic audio must retain a private trace and truthful output result.");
            foreach (var stage in new[] { "NoFreshEvent", "FreshEvent", "ChannelDisabled", "EnvironmentSuppressed", "NativeAccepted" })
                if (!journal.Contains("Audio " + stage)) throw new Exception("Missing audio diagnostic stage: " + stage);
            if (journal.Contains("fixture", StringComparison.OrdinalIgnoreCase) || journal.Contains(new string('a', 64)))
                throw new Exception("Audio diagnostics must not contain account or conversation identifiers.");
        } finally { Directory.Delete(root, true); }
    }
}
