using System.Windows;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop.Tests;

internal static class OverlayAnnouncementReplayTests
{
    internal static void RunAll()
    {
        var settings = OverlayDisplaySettings.Default with { ShowNotice = true };
        var context = new OverlaySceneContext(OverlayScenePreference.Auto, OverlaySceneKind.Community,
            "Fixture", false, ChatChannelId: "organization:fixture");
        var announcement = new OverlayCommandState("Fixture notice", "Original body", null, null, null, null);
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default,
            "en", true, announcement, PlayerPresenceKind.AppOnline, "", context);
        try
        {
            Check(model.FleetNotice == "Original body", "initial announcement is shown");
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                announcement with { NoticeTitle = "", NoticeText = "" }, PlayerPresenceKind.AppOnline, "", context);
            Check(model.NotificationVisibility != Visibility.Visible, "expired communication contents are removed");
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                announcement, PlayerPresenceKind.AppOnline, "", context);
            Check(model.NotificationVisibility != Visibility.Visible,
                "The same announcement must not pop again when an empty communication snapshot recovers in the same open window.");
            model.ClearAuthorizedContent(preserveDeviceLocalEvents: true, preserveAnnouncementReceipt: true);
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", false,
                announcement with { NoticeTitle = "Unavailable", NoticeText = "Organization information unavailable" },
                PlayerPresenceKind.AppOnline, "", context with { IsFallback = true, ChatChannelId = null });
            Check(model.NotificationVisibility != Visibility.Visible, "an unavailable snapshot is not a communication announcement");
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                announcement, PlayerPresenceKind.AppOnline, "", context);
            Check(model.NotificationVisibility != Visibility.Visible, "source recovery clears private content but retains only the dedup receipt");
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                announcement with { NoticeText = "New body" }, PlayerPresenceKind.AppOnline, "", context);
            Check(model.FleetNotice == "New body" && model.NotificationVisibility == Visibility.Visible, "a genuinely changed announcement is not suppressed");
            model.ClearAuthorizedContent();
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                announcement, PlayerPresenceKind.AppOnline, "", context);
            Check(model.FleetNotice == "Original body" && model.NotificationVisibility == Visibility.Visible,
                "a new open lifetime may show the announcement again");
        }
        finally { model.ClearAuthorizedContent(); }
        Console.WriteLine("PASS same-window organization announcement does not replay after an empty snapshot");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
