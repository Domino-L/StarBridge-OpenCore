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
        Check(NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings with { ShowNotice = false }, true, true), "Direct messages never use the top notice slot, so its switch does not gate them.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings, false, true), "Game foreground is required.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder, settings, true, false), "Never opens a closed overlay.");
        Check(!NativeInformationOverlayRuntime.CanPresentReminder(reminder with { IsCurrent = () => false }, settings, true, true), "Stale content must not render.");
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        {
            var plain = NativeInformationOverlayRuntime.DirectMessageBarrageCopy(reminder, language, false);
            Check(plain.Title == "\u2709 Fixture sender" && !plain.Detail.Contains("Private fixture"), "Overlay preview switch redacts content; the sender stays.");
            Check(NativeInformationOverlayRuntime.DirectMessageBarrageCopy(reminder, language, true).Detail == "Private fixture", "Both full-content switches permit preview.");
            Check(!NativeInformationOverlayRuntime.DirectMessageBarrageCopy(reminder with { Preview = "sourceOnly" }, language, true).Detail.Contains("Private fixture"), "Source-only privacy overrides preview switch.");
            var hidden = NativeInformationOverlayRuntime.DirectMessageBarrageCopy(reminder with { Preview = "hiddenDetails" }, language, true);
            Check(hidden.Title == "\u2709 StarBridge" && !hidden.Detail.Contains("Fixture"), "Hidden details reveal neither sender nor text.");
            var several = NativeInformationOverlayRuntime.DirectMessageBarrageCopy(reminder with { DirectMessage = new("", "", 3) }, language, true);
            Check(several.Detail.Contains('3') && !several.Title.Contains("Fixture"), "Several conversations show a count, no sender.");
        }
        RevocationOwnership();
        foreach (var (unread, mark) in new (InformationOverlayDirectUnread?, string?)[] {
            (null, null), (new(0, "Vega"), null), (new(1, "Vega"), "\u2709 Vega"), (new(1, " "), "\u2709 1"), (new(3, ""), "\u2709 3"),
            (new(2, "Vega"), "\u2709 2"), (new(1, "ABCDEFGHIJKLMNOPQ"), "\u2709 ABCDEFGHIJKLM\u2026") })
        {
            Check(NativeInformationOverlayRuntime.DirectUnreadMark(unread) == mark, $"Unread mark for {unread}: {mark}");
        }
    }
    // A room reminder arriving after a direct message (Clear -> Direct -> Room on the
    // control thread) must not hide the message line from preview revocation.
    internal static void RevocationOwnership()
    {
        const System.Reflection.BindingFlags all = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        var type = typeof(NativeInformationOverlayRuntime);
        foreach (var settings in new[] {
            InformationOverlayDefaults.DefaultSettings with { CommunicationMessagePreview = false },
            InformationOverlayDefaults.DefaultSettings with { CommunicationFriendEvents = false } })
        {
            using var runtime = new NativeInformationOverlayRuntime();
            type.GetField("_workspace", all)!.SetValue(runtime, new InformationOverlayRuntimeWorkspace(1, settings, [], "Alt+O", false,
                StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty, "en"));
            var room = new InformationOverlayReminder(Guid.NewGuid(), 1, 0, "fullContent", () => true);
            var message = new InformationOverlayReminder(Guid.NewGuid(), 0, 0, "fullContent", () => true)
                { DirectMessage = new("Fixture sender", "Private fixture", 1) };
            type.GetField("_activeDirectMessage", all)!.SetValue(runtime, message);
            type.GetField("_activeDirectMessageIncludesPreview", all)!.SetValue(runtime, true);
            type.GetField("_activeReminder", all)!.SetValue(runtime, room);
            type.GetMethod("RevokeReminderPreview", all)!.Invoke(runtime, []);
            Check(type.GetField("_activeDirectMessage", all)!.GetValue(runtime) is null, "The message line is revoked despite a later room reminder.");
            Check(ReferenceEquals(type.GetField("_activeReminder", all)!.GetValue(runtime), room), "The room reminder keeps the slot.");
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
