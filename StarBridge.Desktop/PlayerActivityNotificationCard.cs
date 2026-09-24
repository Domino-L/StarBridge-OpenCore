namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;

/// <summary>Passive player activity only: no activation, dismiss action or unread state.</summary>
internal sealed class PlayerActivityNotificationCard : Border
{
    internal PlayerActivityNotificationCard(DesktopNotification notice)
    {
        var player = notice.Activity ?? throw new ArgumentException("Player activity required.");
        var en = !notice.Locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var tw = notice.Locale is "zh-TW" or "zh-Hant";
        string Local(string cn, string traditional, string english) => en ? english : tw ? traditional : cn;
        var light = notice.Appearance == "light";
        var foreground = Paint(light ? "#17242C" : "#E7EEF2");
        var secondary = Paint(light ? "#4A5B64" : "#93A4AE");
        var eventColor = Paint(EventColor(player.Kind, light));
        var title = notice.Test ? Local("测试玩家", "測試玩家", "Test player") :
            string.IsNullOrWhiteSpace(player.Callsign) ? player.GameId : player.Callsign;
        var change = player.Kind switch {
            "Online" => Local("已上线", "已上線", "Is online"),
            "Offline" => Local("已离线", "已離線", "Is offline"),
            "StartedGame" => Local("开始游玩 Star Citizen", "開始遊玩 Star Citizen", "Started playing Star Citizen"),
            _ => Local("结束游玩 Star Citizen", "結束遊玩 Star Citizen", "Stopped playing Star Citizen")
        };
        var labels = (player.Sources ?? []).Select(source => source switch {
            "friends" => Local("好友", "好友", "Friend"),
            "room" => Local("同房间", "同房間", "Same room"),
            _ when source.StartsWith("organization:", StringComparison.Ordinal) =>
                source[13..] + Local("成员", "成員", " member"),
            _ => ""
        }).Where(label => label.Length > 0).Distinct();
        Width = 344; Height = 88;
        Background = Paint(light ? "#F5F8FA" : "#101A21");
        BorderBrush = Paint(light ? "#BAC9D1" : "#47606E"); BorderThickness = new(1); CornerRadius = new(6);
        IsHitTestVisible = false; Focusable = false; SnapsToDevicePixels = true;
        var layout = new Grid { Margin = new(12, 10, 12, 10) };
        layout.ColumnDefinitions.Add(new() { Width = new(42) });
        layout.ColumnDefinitions.Add(new() { Width = new(12) });
        layout.ColumnDefinitions.Add(new() { Width = new(1, GridUnitType.Star) });
        var avatar = new Border { Width = 42, Height = 42, Background = Paint(light ? "#E0EAF0" : "#233743"), ClipToBounds = true };
        var image = DesktopNotificationCard.PlayerAvatar(player.AvatarImageData);
        avatar.Child = image is null ? new TextBlock { Text = title.Length == 0 ? "?" : System.Globalization.StringInfo.GetNextTextElement(title),
            Foreground = foreground, FontSize = 20, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
            : new System.Windows.Controls.Image { Source = image, Stretch = Stretch.UniformToFill };
        layout.Children.Add(avatar);
        var lines = new StackPanel { VerticalAlignment = VerticalAlignment.Center };
        TextBlock Line(string name, string text, double size, System.Windows.Media.Brush color) => new() {
            Name = name, Text = text, FontSize = size, Foreground = color, TextTrimming = TextTrimming.CharacterEllipsis,
            TextWrapping = TextWrapping.NoWrap, Margin = new(0, 1, 0, 1), FontFamily = new("Segoe UI, Microsoft YaHei UI")
        };
        var name = Line("PlayerName", title, 13, foreground); name.FontWeight = FontWeights.SemiBold;
        lines.Children.Add(name);
        lines.Children.Add(Line("PlayerChange", change, 12, eventColor));
        lines.Children.Add(Line("PlayerSources", string.Join(" · ", labels), 11, secondary));
        Grid.SetColumn(lines, 2); layout.Children.Add(lines);
        var frame = new Grid();
        frame.Children.Add(new Border { Name = "EventStripe", Width = 3, Background = eventColor,
            HorizontalAlignment = HorizontalAlignment.Left, Margin = new(0, 6, 0, 6), CornerRadius = new(1.5) });
        frame.Children.Add(layout); Child = frame;
    }
    // Match Flutter's Future Restraint semantic event tokens in both themes.
    internal static string EventColor(string kind, bool light) => kind switch {
        "Online" => light ? "#176AA3" : "#53B7FF",
        "StartedGame" => light ? "#13734F" : "#3ED59A",
        "StoppedGame" => light ? "#8A5700" : "#F5B544",
        _ => light ? "#66757D" : "#7A8790"
    };
    private static System.Windows.Media.Brush Paint(string value) => new SolidColorBrush(
        (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value));
}
