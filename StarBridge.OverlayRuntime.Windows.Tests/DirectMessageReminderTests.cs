using StarBridge.HostRuntime.Overlay;
namespace StarBridge.Desktop.Tests;

internal static class DirectMessageReminderTests
{
    internal static void RunAll()
    {
        var reminder = new InformationOverlayReminder(Guid.NewGuid(), 0, 0, "fullContent", () => true)
        { DirectMessage = new("Fixture sender", "Private fixture", 1) };
        var settings = StarBridge.Core.Overlay.OverlayDisplaySettings.Default;
        Check(NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings, true, true), "Enabled visible game overlay accepts direct messages.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings with { CommunicationFriendEvents = false }, true, true), "Visible overlay alone does not enable friend events.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings with { ShowNotice = false }, true, true), "Communication module must be enabled.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings, false, true), "Game foreground is required.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings, true, false), "Never opens a closed overlay.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder with { IsCurrent = () => false }, settings, true, true), "Stale content must not render.");
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        {
            var plain = NativeInformationOverlayRuntime.DirectMessageReminderCopy(reminder, language, false);
            Check(plain.Detail.Contains("Fixture sender") && !plain.Detail.Contains("Private fixture"), "Overlay preview switch redacts content.");
            Check(NativeInformationOverlayRuntime.DirectMessageReminderCopy(reminder, language, true).Detail.Contains("Private fixture"), "Both full-content switches permit preview.");
            Check(!NativeInformationOverlayRuntime.DirectMessageReminderCopy(reminder with { Preview = "sourceOnly" }, language, true).Detail.Contains("Private fixture"), "Source-only privacy overrides preview switch.");
            var hidden = NativeInformationOverlayRuntime.DirectMessageReminderCopy(reminder with { Preview = "hiddenDetails" }, language, true);
            Check(hidden.Title == "StarBridge" && !hidden.Detail.Contains("Fixture"), "Hidden details reveal neither sender nor text.");
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
