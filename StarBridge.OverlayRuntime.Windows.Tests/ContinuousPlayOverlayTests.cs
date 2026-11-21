using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Notifications;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop.Tests;

internal static class ContinuousPlayOverlayTests
{
    internal static void RunAll()
    {
        var model = new OverlayViewModel(new([]), OverlayDisplaySettings.Default,
            OverlayRosterSelectionSettings.Default, "zh", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
        model.EventNotifications.Clear();
        try
        {
            var notice = new ContinuousPlayNotice(TimeSpan.FromHours(2), () => true);
            Check(!NativeInformationOverlayRuntime.DispatchContinuousPlayAsync(notice,
                (_, _, _) => Task.FromResult(false), CancellationToken.None).AsTask().GetAwaiter().GetResult(), "card rejected");
            Check(!NativeInformationOverlayRuntime.DispatchContinuousPlayAsync(notice, null,
                CancellationToken.None).AsTask().GetAwaiter().GetResult(), "missing card sink");
            // Even an old caller or preview cannot put this retired type in either event box.
            model.QueueGameEventNotification(OverlayEventNotificationTypes.LocalPlayReminder, "fixture", "fixture", false, true);
            Check(model.EventNotifications.Count == 0 && model.PendingEventNotificationCount == 0, "no event fallback");
            var called = false;
            Check(!NativeInformationOverlayRuntime.DispatchContinuousPlayAsync(notice with { IsCurrent = () => false },
                (_, _, _) => { called = true; return Task.FromResult(true); }, CancellationToken.None).AsTask().GetAwaiter().GetResult()
                && !called, "stale notice rejected");
            Check(NativeInformationOverlayRuntime.DispatchContinuousPlayAsync(notice,
                (content, current, _) => Task.FromResult(content.Duration == notice.Duration && current()),
                CancellationToken.None).AsTask().GetAwaiter().GetResult(), "card dispatch preserves duration and validity");
        }
        finally { model.ClearAuthorizedContent(); }
        Exception? failure = null;
        var thread = new Thread(() => { try { Pictures(); } catch (Exception error) { failure = error; } });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure != null) throw failure;
        Console.WriteLine("PASS continuous play: no event fallback, stale gate, 18 offscreen cards");
    }

    private static void Pictures()
    {
        foreach (var locale in new[] { "zh-CN", "zh-TW", "en" })
        foreach (var theme in new[] { "dark", "light" })
        foreach (var hours in new[] { 1.5, 2, 10 })
        {
            var content = new ContinuousPlayNotificationContent(TimeSpan.FromHours(hours));
            var notice = new DesktopNotification(Guid.NewGuid(), false, 0, 0,
                "fullContent", "bottomRight", locale, theme, () => true) { ContinuousPlay = content };
            Check(NativeDesktopNotificationRuntime.IsPassive(notice) &&
                NativeDesktopNotificationRuntime.DisplayLifetime(notice) == TimeSpan.FromSeconds(8), "eight seconds, passive hover/click behavior");
            var card = new ContinuousPlayNotificationCard(notice);
            card.Measure(new Size(220, 56)); card.Arrange(new Rect(0, 0, 220, 56)); card.UpdateLayout();
            Check(card.ActualWidth == 220 && card.ActualHeight == 56 && !card.IsHitTestVisible && !card.Focusable, "passive size");
            var left = (FrameworkElement)LogicalTreeHelper.FindLogicalNode(card, "PlayDurationBox");
            var right = (FrameworkElement)LogicalTreeHelper.FindLogicalNode(card, "PlayLabels");
            Rect Bounds(FrameworkElement child) => child.TransformToAncestor(card).TransformBounds(new Rect(child.RenderSize));
            var a = Bounds(left); var b = Bounds(right);
            Check(a.Right + 7 <= b.Left && a.Left >= 1 && b.Right <= 219 &&
                a.Top >= 1 && b.Top >= 1 && a.Bottom <= 55 && b.Bottom <= 55, "text blocks do not overlap or leave card");
            foreach (var block in ((System.Windows.Controls.StackPanel)right).Children.OfType<System.Windows.Controls.TextBlock>())
                Check(block.DesiredSize.Width <= right.ActualWidth + 0.1, "right text not clipped");
            // User 11-14 ("logo位置不正，参考其他的"): the activity card's rule scaled to 54 px inside the border: a whole mark,
            // right-aligned and vertically centred, size and inset in the same proportion as 60 and 12 in 86.
            var frame = (System.Windows.Controls.Grid)card.Child;
            var mark = frame.Children.OfType<NotificationBrandWatermark>().SingleOrDefault();
            var textLayer = frame.Children.IndexOf((UIElement)VisualTreeHelper.GetParent(left));
            Check(mark is not null && frame.Children.IndexOf(mark) < textLayer, "brand mark behind the text");
            var m = Bounds(mark!);
            var scale = 54 / NotificationBrandWatermark.ReferenceInnerHeight;
            Check(Math.Abs(m.Width - Math.Round(NotificationBrandWatermark.ReferenceSize * scale)) < 0.5 && Math.Abs(m.Height - m.Width) < 0.5,
                "brand mark size scaled like the activity card's (60 in 86)");
            Check(Math.Abs((m.Top + m.Bottom) / 2 - 28) < 0.75 && m.Top >= 1 && m.Bottom <= 55,
                "brand mark vertically centred and whole, like the activity card's");
            Check(Math.Abs((219 - m.Right) - NotificationBrandWatermark.ReferenceInset * scale) < 0.75 && m.Right <= 219,
                "brand mark right inset scaled like the activity card's (12 in 86)");
            // 乙 (user 11-14): neither text block reaches the mark, in every language and duration (10 hours is the longest).
            Check(a.Right + 4 <= m.Left && b.Right + 4 <= m.Left, $"text keeps clear of the brand mark ({locale}, {theme}, {hours} h)");
            var bitmap = new RenderTargetBitmap(220, 56, 96, 96, PixelFormats.Pbgra32); bitmap.Render(card);
            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(Path.Combine(AppContext.BaseDirectory,
                $"continuous-play-{locale}-{theme}-{content.Number}.png"));
            encoder.Save(file);
        }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
