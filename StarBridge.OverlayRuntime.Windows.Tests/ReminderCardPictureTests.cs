using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// 0.7.3 announcement and grouped activity cards rendered off screen (no window). Pictures are written when STARBRIDGE_CARD_PICTURES names a folder.
/// </summary>
internal static class ReminderCardPictureTests
{
    internal static void Run()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                DesktopNotification Card() => new(Guid.NewGuid(), false, 0, 0, "fullContent", "bottomRight", "zh-CN", "dark", () => true);
                var announcement = Card() with { Community = new("示例组织", "", "", false, OrganizationNotificationSourceKind.Community, true, 1), ShowDuringQuiet = true };
                var folder = Environment.GetEnvironmentVariable("STARBRIDGE_CARD_PICTURES");
                foreach (var (name, card) in new[] { ("announcement", announcement) })
                {
                    var element = new DesktopNotificationCard(card, () => { }, () => { });
                    element.Measure(new Size(element.Width, element.Height));
                    element.Arrange(new Rect(0, 0, element.Width, element.Height));
                    element.UpdateLayout();
                    if (folder is null) continue;
                    var bitmap = new RenderTargetBitmap((int)(element.Width * 2), (int)(element.Height * 2), 192, 192, PixelFormats.Pbgra32);
                    bitmap.Render(element);
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    Directory.CreateDirectory(folder);
                    using var file = File.Create(Path.Combine(folder, name + "-card.png"));
                    encoder.Save(file);
                }
                // 0.7.3 (user 11-06: "合成一张"): several members coming online share one card.
                PlayerActivityNotificationContent Group(string kind, string[] names, int online) =>
                    new PlayerActivityNotificationContent("", "", kind, "", null, null, ["friends", "organization:示例组织"])
                    { GroupNames = names, OnlineNow = online, Tracked = 12 };
                foreach (var (name, activity, title, change) in new[] {
                    ("members-online", Group("Online", ["星海一号", "Bravo", "Charlie"], 5), "3 位成员上线 · 在线 5/12", "星海一号、Bravo、Charlie"),
                    ("members-offline", Group("Offline", ["Alpha", "Bravo", "Charlie", "Delta"], 2), "4 位成员下线 · 在线 2/12", "Alpha、Bravo、Charlie 等") })
                {
                    var element = new PlayerActivityNotificationCard(Card() with { Activity = activity });
                    element.Measure(new Size(element.Width, element.Height));
                    element.Arrange(new Rect(0, 0, element.Width, element.Height));
                    element.UpdateLayout();
                    var shownTitle = ((System.Windows.Controls.TextBlock)LogicalTreeHelper.FindLogicalNode(element, "PlayerName")).Text;
                    var shownChange = ((System.Windows.Controls.TextBlock)LogicalTreeHelper.FindLogicalNode(element, "PlayerChange")).Text;
                    if (shownTitle != title || shownChange != change) throw new Exception($"grouped card text: {shownTitle} / {shownChange}");
                    if (folder is null) continue;
                    var bitmap = new RenderTargetBitmap((int)(element.Width * 2), (int)(element.Height * 2), 192, 192, PixelFormats.Pbgra32);
                    bitmap.Render(element);
                    var encoder = new PngBitmapEncoder();
                    encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file = File.Create(Path.Combine(folder, name + "-card.png"));
                    encoder.Save(file);
                }
            }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) System.Runtime.ExceptionServices.ExceptionDispatchInfo.Capture(failure).Throw();
        Console.WriteLine("PASS reminder cards: announcement and grouped member cards render off screen");
    }
}
