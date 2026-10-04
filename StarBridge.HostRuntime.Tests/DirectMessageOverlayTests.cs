using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

internal static class DirectMessageOverlayTests
{
    private sealed class Sink : IInformationOverlayReminderSink
    {
        internal readonly List<InformationOverlayReminder> Notices = [];
        internal bool Accepted = true, Throw;
        public ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken token)
        { Notices.Add(reminder); if (Throw) throw new OperationCanceledException(); return ValueTask.FromResult(Accepted); }
        public void ClearReminder() { }
    }
    private sealed class Desktop : IDesktopNotificationSink
    {
        internal int Count;
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Count++; return ValueTask.FromResult(true); }
        public void Clear() { }
        public void Dispose() { }
    }
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "overlay-direct-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var sink = new Sink(); var desktop = new Desktop(); long generation = 1;
            using var owner = new NotificationSettingsBridgeDispatcher(root, () => generation, () => true, overlay: sink, desktop: desktop);
            var account = new BridgeAccountContext("fixture", "fixture", "fixture");
            long revision = 0;
            async Task Save(bool overlayEnabled, string preview = "sourceOnly")
            {
                var result = await owner.DispatchAsync(BridgeEnvelope.Request("notificationSettings.save", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1, expectedRevision = revision, inAppEnabled = true, windowsEnabled = true,
                        directMessageWindowsEnabled = true, overlayEnabled, position = "bottomRight", preview }));
                Check(result.Response.Status == "ok", "Notification preferences save."); revision++;
            }
            var time = DateTimeOffset.UtcNow;
            async Task Read(int second, long sequence)
            {
                var request = BridgeEnvelope.Request("directMessages.read", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1 }, account);
                await owner.ObserveAsync(request, BridgeEnvelope.Response(request, new
                {
                    schemaVersion = 1, serverTime = time.AddSeconds(second), conversations = new[] {
                        new { conversationKey = new string('a', 64), latestSequence = sequence, unreadCount = 1,
                            lastMessageIncoming = true, lastMessageAt = time.AddSeconds(second), callsign = "Fixture", preview = "Private fixture" }
                    }
                }), default);
            }
            await Read(0, 1);
            Check(sink.Notices.Count == 0, "Initial private-message directory is a quiet baseline.");
            await Read(1, 2);
            Check(sink.Notices.Count == 1, "Fresh private message must reach enabled information overlay even with desktop channel disabled.");
            Check(sink.Notices[0].DirectMessage is { Callsign: "Fixture", Text: "" }, "Source-only content is redacted before crossing renderer seam.");
            await Read(2, 2);
            Check(sink.Notices.Count == 1, "Repeated snapshot does not replay.");
            await Save(false); await Read(3, 3);
            Check(sink.Notices.Count == 1 && desktop.Count == 1, "Overlay off retains separately enabled desktop delivery.");
            await Save(true); await Read(4, 3);
            Check(sink.Notices.Count == 1, "Enabling overlay does not replay consumed messages.");
            await Read(5, 4);
            Check(sink.Notices.Count == 2 && desktop.Count == 1, "Accepted overlay suppresses a duplicate desktop card.");
            await Save(true, "hiddenDetails"); await Read(6, 5);
            Check(sink.Notices.Last().DirectMessage is { Callsign: "", Text: "" }, "Hidden details removes sender and preview at Host boundary.");
            await Save(true, "fullContent"); await Read(7, 6);
            Check(sink.Notices.Last().DirectMessage is { Callsign: "Fixture", Text: "Private fixture" }, "Full content retains authorized preview for renderer's additional gate.");
            var policies = new NotificationPolicyStore(root);
            policies.Save(account, 0, Guid.NewGuid().ToString("N"), [new("directMessages", NotificationSourceMode.DoNotDisturb)], () => true);
            Check(!sink.Notices.Last().IsCurrent(), "Muting retires an active private reminder.");
            var before = sink.Notices.Count;
            await Read(8, 7); Check(sink.Notices.Count == before, "Muted source never reaches overlay.");
            policies.Save(account, 1, Guid.NewGuid().ToString("N"), [], () => true);
            await Read(9, 7); Check(sink.Notices.Count == before, "Unmuting does not replay.");
            sink.Accepted = false; await Read(10, 8);
            Check(desktop.Count == 2, "Explicit renderer rejection permits existing desktop fallback.");
            sink.Throw = true; await Read(11, 9);
            Check(desktop.Count == 2, "Uncertain overlay delivery cannot duplicate on desktop.");
            sink.Throw = false; sink.Accepted = true;
            before = sink.Notices.Count; await Read(60, 10);
            Check(sink.Notices.Count == before, "Reconnect gap establishes a quiet baseline.");
            await Read(61, 11); var active = sink.Notices.Last();
            owner.Reset(); generation++; await Read(62, 12);
            Check(!active.IsCurrent() && sink.Notices.Last() == active, "Account generation change retires content and restarts baseline.");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
