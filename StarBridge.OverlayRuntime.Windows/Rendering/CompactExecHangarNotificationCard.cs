namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;

/// <summary>Activity-sized, click-through hangar projection; timing remains in the shared panel.</summary>
internal sealed class CompactExecHangarNotificationCard : Border
{
    internal CompactExecHangarNotificationCard(DesktopNotification notice)
    {
        var hangar = notice.ExecHangar ?? throw new ArgumentException("Hangar content required.");
        var light = notice.Appearance == "light";
        Brush Paint(string value) => new SolidColorBrush((Color)ColorConverter.ConvertFromString(value));
        var primary = Paint(light ? "#17242C" : "#E7EEF2");
        var secondary = Paint(light ? "#4A5B64" : "#93A4AE");
        var accent = Paint(hangar.LeaveWarning || !hangar.Opening
            ? light ? "#B62F43" : "#F26D75" : light ? "#13734F" : "#3ED59A");
        Width = 344; Height = 88; CornerRadius = new(6);
        Background = Paint(light ? "#F5F8FA" : "#101A21");
        BorderBrush = Paint(light ? "#BAC9D1" : "#47606E"); BorderThickness = new(1);
        IsHitTestVisible = false; Focusable = false; SnapsToDevicePixels = true;
        var frame = new Grid();
        frame.Children.Add(new NotificationBrandWatermark(light));
        frame.Children.Add(new Border { Width = 3, Background = accent,
            HorizontalAlignment = HorizontalAlignment.Left, Margin = new(0,6,0,6), CornerRadius = new(1.5) });
        UIElement content;
        if (notice.Preview == "hiddenDetails") {
            var text = notice.Locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "你有新的提醒" : "You have a new notification";
            content = new TextBlock { Text = "StarBridge · " + text, Foreground = primary, FontSize = 13,
                TextTrimming = TextTrimming.CharacterEllipsis, VerticalAlignment = VerticalAlignment.Center };
            AutomationProperties.SetName(this, text);
        } else {
            content = new ExecHangarNotificationPanel(hangar, notice.Locale, light, primary, secondary,
                accent, notice.IsCurrent, () => { }, compact: true) { VerticalAlignment = VerticalAlignment.Center };
        }
        var body = new Grid { Margin = new(12,8,12,8) }; body.Children.Add(content);
        frame.Children.Add(body); Child = frame;
    }
}
