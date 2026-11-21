namespace StarBridge.Desktop.Tests;

using StarBridge.HostRuntime.Notifications;
using System.Windows;
using System.Windows.Automation;

internal static class AnnouncementNotificationCardTests
{
    internal static void Run()
    {
        Exception? failure = null;
        var count = 0;
        var thread = new Thread(() => {
            try {
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                foreach (var preview in new[] { "sourceOnly", "fullContent", "hiddenDetails" })
                foreach (var summaryCount in new[] { 0, 1, 3, 99, 100 }) {
                    var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0, preview, "bottomRight", locale,
                        "dark", () => true, ReduceMotion: true, Community: new("Synthetic fleet", "NEVER-AUTHOR", "NEVER-BODY", false,
                            OrganizationNotificationSourceKind.OfficialFleet, Announcement: true, AnnouncementSummaryCount: summaryCount));
                    var card = new DesktopNotificationCard(notice, () => { }, () => { });
                    card.Measure(new Size(380, 170)); card.Arrange(new Rect(0, 0, 380, 170));
                    var text = AutomationProperties.GetName(card);
                    var hidden = preview == "hiddenDetails";
                    var number = summaryCount > 99 ? "99+" : summaryCount.ToString(System.Globalization.CultureInfo.InvariantCulture);
                    var expected = summaryCount == 0 ? (locale == "en-US" ? "New announcement." : "有新公告。")
                        : locale == "zh-CN" ? $"有 {number} 条新公告。"
                        : locale == "zh-TW" ? $"有 {number} 則新公告。"
                        : summaryCount == 1 ? "1 new announcement." : $"{number} new announcements.";
                    if (text.Contains("NEVER") || text.Contains("Synthetic fleet") == hidden ||
                        !hidden && !text.Contains(expected) || hidden && text.Contains(expected))
                        throw new Exception("Announcement card must contain only the permitted organization label and generic announcement copy.");
                    count++;
                }
            } catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure != null) throw failure;
        Console.WriteLine($"PASS announcement cards: {count} locale/preview combinations, 0 failed; no HWND");
    }
}
