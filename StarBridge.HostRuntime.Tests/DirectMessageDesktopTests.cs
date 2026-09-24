using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class DirectMessageDesktopTests
{
    private sealed class Sink : IDesktopNotificationSink {
        internal List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification value, CancellationToken token) {
            Notices.Add(value); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "direct-notice-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try {
            var sink = new Sink(); var background = true; long generation = 1, sequence = 0;
            using var owner = new NotificationSettingsBridgeDispatcher(root, () => generation, () => background,
                desktop: sink, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, payload));
            var time = DateTimeOffset.UtcNow;
            async Task Save(int revision, bool direct, string preview = "sourceOnly") {
                var result = await owner.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1, expectedRevision = revision, inAppEnabled = true, windowsEnabled = true,
                        directMessageWindowsEnabled = direct, position = "bottomRight", preview }));
                Check(result.Response.Status == "ok", "Preference write succeeds.");
            }
            async Task Read(int second, long message) {
                var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1 }, new BridgeAccountContext("fixture", "fixture", "fixture"));
                await owner.ObserveAsync(request, BridgeEnvelope.Response(request, new {
                    schemaVersion = 1, serverTime = time.AddSeconds(second), conversations = new[] {
                        new { conversationKey = new string('a', 64), latestSequence = message, unreadCount = 1,
                            lastMessageIncoming = true, lastMessageAt = time.AddSeconds(second), callsign = "Fixture", preview = "Private fixture text" }
                    }
                }), default);
            }
            await Save(0, false); await Read(0, 1); await Read(1, 2);
            Check(sink.Notices.Count == 0, "Disabled messages are consumed quietly.");
            await Save(1, true); await Read(2, 2);
            Check(sink.Notices.Count == 0, "Enabling never replays muted messages.");
            await Read(3, 3);
            Check(sink.Notices.Count == 1 && sink.Notices[0].DirectMessage is { Callsign: "Fixture", Text: "" }, "Source-only redacts message before native delivery.");
            var notice = sink.Notices[0]; notice.Activated!();
            async Task<string?> Consume() {
                var result = (await owner.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1, activationId = notice.Id.ToString("N") }))).Response;
                Check(result.Status == "ok", "Activation acknowledgement is valid.");
                return result.Payload.TryGetProperty("destination", out var value) ? value.GetString() : null;
            }
            Check(await Consume() == "directMessages" && await Consume() == null, "Activation is scoped and one-use.");
            background = false; await Read(4, 4); background = true; await Read(5, 4);
            Check(sink.Notices.Count == 1, "Foreground messages do not replay later.");
            await Save(2, true, "hiddenDetails"); await Read(6, 5);
            Check(!notice.IsCurrent() && sink.Notices.Last().DirectMessage is { Callsign: "", Text: "" }, "Saving invalidates old notices and hidden mode contains no private text.");
            owner.Reset(); generation++; await Read(7, 6);
            Check(sink.Notices.Count == 2 && !sink.Notices.Last().IsCurrent(), "New generation starts quiet and retires old cards.");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
