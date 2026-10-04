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
                desktop: sink, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, payload),
                socialEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.social", g, ++sequence, payload),
                desktopSuppressionReason: () => background ? "" : "appForeground");
            var social = new List<BridgeEnvelope>();
            owner.EventReady += value => { if (value.Name == "notificationSettings.social") social.Add(value); };
            static bool Redacted(System.Text.Json.JsonElement payload, string name) =>
                !payload.TryGetProperty(name, out var value) || value.ValueKind == System.Text.Json.JsonValueKind.Null;
            var time = DateTimeOffset.UtcNow;
            string avatar = "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+jRZkAAAAASUVORK5CYII=";
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
                            lastMessageIncoming = true, lastMessageAt = time.AddSeconds(second), callsign = "Fixture", preview = "Private fixture text", avatarImageData = avatar }
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
            notice.ReportDiagnostic("contentRendered");
            notice.ReportDiagnostic("removed");
            (notice with { Diagnostic = _ => throw new Exception("synthetic") }).ReportDiagnostic("removed");
            Check(notice.DirectMessage!.AvatarImageData == avatar,
                "Source-only reminder carries the validated sender avatar without another fetch.");
            async Task<string?> Consume() {
                var result = (await owner.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation", Guid.NewGuid().ToString("N"), generation,
                    new { schemaVersion = 1, activationId = notice.Id.ToString("N") }))).Response;
                Check(result.Status == "ok", "Activation acknowledgement is valid.");
                return result.Payload.TryGetProperty("destination", out var value) ? value.GetString() : null;
            }
            Check(await Consume() == "directMessages" && await Consume() == null, "Activation is scoped and one-use.");
            background = false; await Read(4, 4); background = true; await Read(5, 4);
            Check(sink.Notices.Count == 1, "Foreground messages do not replay later.");
            Check(social.Count == 1 && social[0].Payload.GetProperty("senderName").GetString() == "Fixture" &&
                Redacted(social[0].Payload, "messagePreview"),
                "Source-only in-app reminder carries the sender but not private text.");
            await Save(2, true, "hiddenDetails"); await Read(6, 5);
            Check(!notice.IsCurrent() && sink.Notices.Last().DirectMessage is { Callsign: "", Text: "" }, "Saving invalidates old notices and hidden mode contains no private text.");
            Check(sink.Notices.Last().DirectMessage!.AvatarImageData is null,
                "Hidden details must redact the sender avatar too.");
            background = false; await Read(7, 6);
            Check(social.Count == 2 && Redacted(social[1].Payload, "senderName") &&
                Redacted(social[1].Payload, "messagePreview"),
                "Hidden in-app reminder carries neither sender nor text.");
            await Save(3, true, "fullContent"); await Read(8, 7);
            Check(social.Count == 3 && social[2].Payload.GetProperty("senderName").GetString() == "Fixture" &&
                social[2].Payload.GetProperty("messagePreview").GetString() == "Private fixture text",
                "Full in-app reminder carries the sender and one preview.");
            owner.Reset(); generation++; await Read(9, 8);
            Check(sink.Notices.Count == 2 && !sink.Notices.Last().IsCurrent(), "New generation starts quiet and retires old cards.");
            var journal = File.ReadAllText(Path.Combine(root, "notification-delivery-diagnostics.log"));
            Check(journal.Contains("trace=") && journal.Contains("result=unavailable"),
                "Desktop diagnostics preserve the sink result, not just accepted.");
            Check(journal.Contains("NativeLifecycle") && journal.Contains("result=contentRendered") && journal.Contains("result=removed"),
                "Lifecycle results must survive same-stage throttling and callback failure must not escape.");
            foreach (var stage in new[] { "NoFreshEvent", "FreshEvent", "ChannelDisabled", "EnvironmentSuppressed", "NativeAccepted" })
                Check(journal.Contains("Desktop " + stage), "Desktop diagnostics distinguish " + stage);
            Check(journal.Contains("Desktop EnvironmentSuppressed", StringComparison.Ordinal) &&
                journal.Contains("result=appForeground", StringComparison.Ordinal),
                "A consumed foreground message records the actual visual gate reason without sender data");
            Check(DesktopNotificationVisibility.LocalGateReason("", false, "notRunning") == "" &&
                DesktopNotificationVisibility.LocalGateReason("", true, "notRunning") == "appForeground" &&
                DesktopNotificationVisibility.LocalGateReason("", false, "running") == "" &&
                DesktopNotificationVisibility.LocalGateReason("", false, "unknown") == "gameActiveOrUnknown" &&
                DesktopNotificationVisibility.LocalGateReason("fullScreen", false, "notRunning") == "fullScreen",
                "Visual desktop gates classify only system, foreground and coarse game state without private content");
            // The authenticated directory accepts up to 512 KiB. Optional card
            // media must not silently apply the unrelated 96 KiB room default.
            var largeBytes = new byte[300 * 1024];
            Convert.FromBase64String(avatar[(avatar.IndexOf(',') + 1)..]).CopyTo(largeBytes, 0);
            avatar = "data:image/png;base64," + Convert.ToBase64String(largeBytes);
            await Save(4, true, "sourceOnly");
            background = true; await Read(10, 9);
            Check(sink.Notices.Last().DirectMessage!.AvatarImageData == avatar,
                "Card retains a valid directory avatar larger than the room thumbnail limit.");
            Check(!journal.Contains("Fixture", StringComparison.OrdinalIgnoreCase) && !journal.Contains("Private fixture text") &&
                !journal.Contains(new string('a', 64)), "Diagnostics never include identity, conversation key or message text.");
        } finally { Directory.Delete(root, true); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
