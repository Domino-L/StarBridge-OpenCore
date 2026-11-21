using System.Globalization;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Overlay;

internal static class ContinuousPlayCardTests
{
    internal static async Task Run()
    {
        Text();
        Compatibility();
        // The trade rule decides: whatever the ordinary social rule says (do-not-disturb, quiet time, any full screen,
        // an unusual notification mode), the card shows while the trade rule is clear (user 11-14: "免打扰时也照常弹").
        foreach (var ordinary in new[] { "", "do-not-disturb", "shell-suppressed-6", "foreground-fullscreen", "shell-suppressed-3",
            "shell-suppressed-7", "notification-mode-unsupported" })
            await Delivery(ordinary, "", true, true);
        // Locked or switched desktop, presentation mode, an inactive desktop or an unknown shell state block it, even
        // during do-not-disturb.
        foreach (var trade in new[] { "shell-suppressed-1", "shell-suppressed-4", "secure-or-inactive-desktop",
            "input-desktop-unavailable", "shell-state-unavailable", "system-state-unavailable" })
            await Delivery("do-not-disturb", trade, true, false);
        // NativeHost injects the system rule alone: StarBridge in front or an unknown game state (the trade rule's local
        // gate) does not hold it back, a locked desktop still does (review CX-CPLAY-CARD-073-R1).
        await Delivery("do-not-disturb", "main-window-active-or-unknown", true, true, continuous: "");
        await Delivery("do-not-disturb", "game-active-or-unknown", true, true, continuous: "");
        await Delivery("", "", true, false, continuous: "shell-suppressed-1");
        await Delivery("", "", false, false);
    }

    private static void Text()
    {
        foreach (var (minutes, expected) in new[] { (60, "1"), (90, "1.5"), (105, "2"), (119, "2"), (120, "2"), (600, "10") })
        {
            var value = new ContinuousPlayNotificationContent(TimeSpan.FromMinutes(minutes));
            Check(value.Number == expected, "nearest half hour, ties upward");
            Check(value.Unit("en") == (minutes == 60 ? "hour" : "hours"), "English plural");
            Check(value.Unit("zh-CN") == "小时" && value.Unit("zh-TW") == "小時", "localized unit");
        }
        var content = new ContinuousPlayNotificationContent(TimeSpan.FromHours(2));
        var local = new DateTimeOffset(2026, 11, 14, 22, 10, 0, TimeZoneInfo.Local.GetUtcOffset(new DateTime(2026, 11, 14, 22, 10, 0)));
        var previous = CultureInfo.CurrentCulture;
        try
        {
            CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo("en-US");
            Check(content.Now("en", local.ToUniversalTime()) == "Now 22:10", "local 24 hour time");
            Check(content.Now("zh-CN", local) == "现在 22:10" && content.Now("zh-TW", local) == "現在 22:10", "localized now");
            Check(content.Label("en") == "Continuous play" && content.Label("zh-CN") == "连续游玩" && content.Label("zh-TW") == "連續遊玩", "labels");
        }
        finally { CultureInfo.CurrentCulture = previous; }
    }

    private static async Task Delivery(string ordinary, string quietIgnoring, bool enabled, bool expected, string? continuous = null)
    {
        var root = Path.Combine(Path.GetTempPath(), "sb-cplay-card-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            new ContinuousPlayStore(root).SaveSettings(new(enabled));
            new NotificationCardPreferencesStore(root).Save(new(ShowDuringQuiet: false, QuietSummary: true));
            // No migration: WindowsEnabled defaults to false, while this local reminder is independent.
            var sink = new Sink();
            using var dispatcher = new NotificationSettingsBridgeDispatcher(root, () => 1, desktop: sink,
                desktopSuppressionReason: () => ordinary, tradeSuppressionReason: () => quietIgnoring,
                continuousPlaySuppressionReason: continuous is null ? null : () => continuous);
            Check(!dispatcher.InspectLocalSetup().WindowsEnabled, "Windows master off fixture");
            var shown = await dispatcher.TryPresentReminderCardAsync(new(TimeSpan.FromHours(2)), () => true, CancellationToken.None);
            Check(shown == expected && sink.Cards.Count == (expected ? 1 : 0), "delivery: " + ordinary);
            Check(dispatcher.QuietSummaryCount == 0, "continuous play never enters quiet summary");
            if (expected)
            {
                var card = sink.Cards.Single();
                Check(card.ContinuousPlay != null && card.Reminder == null && !card.IsSocial && !card.BackgroundOnly, "dedicated passive content");
                new ContinuousPlayStore(root).SaveSettings(new(false));
                Check(!await card.CanPresentAsync(CancellationToken.None), "disable before deferred presentation");
            }
        }
        finally { Directory.Delete(root, true); }
    }

    private static void Compatibility()
    {
        foreach (var enabled in new[] { false, true })
        {
            var original = OverlayDisplaySettings.Default with {
                EventNotificationTypes = OverlayEventNotificationTypes.ShipChange | (enabled ? OverlayEventNotificationTypes.LocalPlayReminder : OverlayEventNotificationTypes.None),
                EventNotificationDurations = OverlayEventNotificationDurationOverrides.InheritAll.Set(OverlayEventNotificationTypes.LocalPlayReminder, 17.5) };
            var wire = System.Text.Json.JsonSerializer.SerializeToElement(OverlayWorkspaceWireProjection.Settings(original));
            var fromWire = OverlayWorkspaceWireProjection.ParseSettings(wire);
            Check(fromWire.EventNotificationTypes == original.EventNotificationTypes &&
                fromWire.EventNotificationDurations.LocalPlayReminder == 17.5, "Host wire roundtrip preserves hidden values");
            var csv = original.Serialize();
            var parsed = OverlayDisplaySettings.Parse(csv);
            Check(parsed.EventNotificationTypes == original.EventNotificationTypes && parsed.EventNotificationDurations.LocalPlayReminder == 17.5, "CSV roundtrip");
            // The old reader's established slots remain 34 (flags), 38 (durations), inner slot 10.
            var written = parsed.Serialize().Split(',');
            Check((int.Parse(written[34], CultureInfo.InvariantCulture) & 1024) == (enabled ? 1024 : 0) &&
                double.Parse(written[38].Split(';')[10], CultureInfo.InvariantCulture) == 17.5, "0.7.2.1 positional contract");
            var root = Path.Combine(Path.GetTempPath(), "sb-cplay-compat-" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(root);
            try
            {
                File.WriteAllText(Path.Combine(root, "overlay.settings"), csv);
                var store = new OverlayWorkspaceStore(root, enableSourcePresets: true);
                var state = store.Load();
                state = store.Apply(new(state.Revision, OverlayWorkspaceMutationKind.SaveActive,
                    Settings: state.Settings with { ShowChat = !state.Settings.ShowChat }, Layout: state.Layout,
                    RenderMode: state.RenderMode, Hotkey: state.Hotkey));
                var reopened = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
                Check(reopened.Settings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder) == enabled &&
                    reopened.Settings.EventNotificationDurations.LocalPlayReminder == 17.5, "preset save retains retired values");
                // 0.7.3 may rewrite the global overlay.settings compatibility copy on save (known since m94); what 0.7.2.1 reads
                // back from it must still be the user's flag and duration.
                var legacy = OverlayDisplaySettings.Parse(File.ReadAllText(Path.Combine(root, "overlay.settings")));
                Check(legacy.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder) == enabled &&
                    legacy.EventNotificationDurations.LocalPlayReminder == 17.5, "0.7.2.1 reads the user's retired values back from overlay.settings");
                // Reset rebuilds the preset from its defaults; the retired flag and duration stay the user's (review CX-CPLAY-CARD-073-R1).
                var reset = store.Apply(new(reopened.Revision, OverlayWorkspaceMutationKind.ResetPreset, PresetId: reopened.ActivePresetId));
                var afterReset = new OverlayWorkspaceStore(root, enableSourcePresets: true).Load();
                Check(reset.Settings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder) == enabled &&
                    afterReset.Settings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder) == enabled &&
                    afterReset.Settings.EventNotificationDurations.LocalPlayReminder == 17.5 &&
                    // the fixture kept ShipChange alone; a real reset brings the other default types back
                    (afterReset.Settings.EventNotificationTypes & ~OverlayEventNotificationTypes.LocalPlayReminder) != OverlayEventNotificationTypes.ShipChange,
                    "preset reset keeps the retired values, other event types return to the defaults");
                var legacyAfterReset = OverlayDisplaySettings.Parse(File.ReadAllText(Path.Combine(root, "overlay.settings")));
                Check(legacyAfterReset.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder) == enabled &&
                    legacyAfterReset.EventNotificationDurations.LocalPlayReminder == 17.5, "after a reset 0.7.2.1 still reads the user's retired values");
            }
            finally { Directory.Delete(root, true); }
        }
    }
    private sealed class Sink : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Cards = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) { Cards.Add(notice); return new(true); }
        public void Clear() { }
        public void Dispose() { }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
