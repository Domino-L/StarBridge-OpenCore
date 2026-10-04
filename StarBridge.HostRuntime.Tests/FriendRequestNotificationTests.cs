using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class FriendRequestNotificationTests
{
    private sealed class Sink : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Notices.Add(notice); return ValueTask.FromResult(true); }
        public void Clear() { }
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-friend-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var sink = new Sink(); var background = false; long sequence = 0;
            using var dispatcher = new NotificationSettingsBridgeDispatcher(root, () => 1, () => background,
                desktop: sink, socialEvent: (g, p) => BridgeEnvelope.Event("notificationSettings.social", g, ++sequence, p),
                activationEvent: (g, p) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, p));
            var events = new List<BridgeEnvelope>(); dispatcher.EventReady += events.Add;
            await dispatcher.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", "settings", 1,
                new { schemaVersion = 1, expectedRevision = 0, inAppEnabled = true, windowsEnabled = true,
                    position = "bottomRight", preview = "hiddenDetails" }));
            var start = DateTimeOffset.UtcNow;
            async Task Read(int second, string key, bool read = false, long generation = 1) {
                var request = BridgeEnvelope.Request("notificationInbox.read", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1 }, new BridgeAccountContext("fixture", "fixture", "fixture"));
                await dispatcher.ObserveAsync(request, BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, updatedAt = start.AddSeconds(second), items = new[] {
                        new { eventKey = key.PadLeft(64, 'a'), actionTarget = "friend_requests", createdAt = start.AddSeconds(second), read,
                            isAvailable = true, title = "Private fixture", body = "Must not cross event boundary" }
                    }
                }), default);
            }
            await Read(0, "1");
            await Read(1, "2");
            if (events.Count != 1 || events[0].Payload.GetProperty("kind").GetString() != "friend" ||
                events[0].Payload.GetRawText().Contains("Private")) throw new Exception("Friend in-app notification missing or leaks details.");
            await Read(2, "2");
            if (events.Count != 1) throw new Exception("Friend notification replayed.");
            background = true;
            await Read(3, "3");
            if (sink.Notices.Count != 1 || sink.Notices[0].FriendRequests != 1) throw new Exception("Friend desktop notification missing.");
            sink.Notices[0].Activated!();
            var activation = await dispatcher.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", "consume", 1,
                new { schemaVersion = 1, activationId = sink.Notices[0].Id.ToString("N") }));
            if (activation.Response.Payload.GetProperty("destination").GetString() != "notificationInbox")
                throw new Exception("Friend notification must open the action inbox, not private chat requests.");
            await Read(4, "4", read: true);
            await Read(5, "5", generation: 0);
            if (sink.Notices.Count != 1) throw new Exception("Read or stale event notified.");
        } finally { Directory.Delete(root, true); }
    }
}
