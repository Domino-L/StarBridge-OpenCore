namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Button = System.Windows.Controls.Button;
using Image = System.Windows.Controls.Image;
using Brush = System.Windows.Media.Brush;

/// <summary>Direction A projection. This same element is rendered by the native window and offline QA.</summary>
internal sealed class DesktopNotificationCard : Border
{
    private readonly Border _hover;
    private readonly bool _reduceMotion;
    private readonly TextBlock _hoverHint;
    private readonly string _idleHint, _pausedHint;

    internal DesktopNotificationCard(DesktopNotification notice, Action open, Action dismiss)
    {
        var light = notice.Appearance == "light";
        _reduceMotion = notice.ReduceMotion;
        var en = !notice.Locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var tw = notice.Locale is "zh-TW" or "zh-Hant";
        string Local(string cn, string traditional, string english) => en ? english : tw ? traditional : cn;
        var primary = Paint(light ? "#17242C" : "#E7EEF2");
        var secondary = Paint(light ? "#4A5B64" : "#93A4AE");
        var accent = Paint(light ? "#1768A3" : "#4CB2F5");
        var tone = notice.Test ? accent : Paint(light ? "#8A5700" : "#F5B544");
        var hidden = notice.Preview == "hiddenDetails";
        var title = notice.Test ? Local("测试提醒", "測試提醒", "Test notification")
            : hidden ? Local("你有新的提醒", "你有新的提醒", "You have a new notification")
            : Local("房间有新的待处理事项", "房間有新的待處理事項", "New room requests");
        var body = notice.Test ? Local("这是本机桌面提醒，不会产生未读或房间操作。", "這是本機桌面提醒，不會產生未讀或房間操作。", "This desktop test creates no unread items or room actions.")
            : hidden ? Local("打开应用查看。", "開啟應用程式查看。", "Open the app to view it.")
            : notice.Preview == "fullContent" ? Local($"新邀请 {notice.Invitations} · 新加入申请 {notice.Applications}", $"新邀請 {notice.Invitations} · 新加入申請 {notice.Applications}", $"Invitations: {notice.Invitations} · Join requests: {notice.Applications}")
            : Local("有新的房间邀请或加入申请。", "有新的房間邀請或加入申請。", "New room invitations or join requests.");
        if (notice.DirectMessage is { } direct && !hidden) {
            title = string.IsNullOrWhiteSpace(direct.Callsign)
                ? Local("收到新私信", "收到新私訊", "New direct message") : direct.Callsign;
            body = notice.Preview == "fullContent" ? direct.Text
                : Local("发来一条私信。", "傳來一則私訊。", "Sent you a direct message.");
            if (direct.Conversations > 1)
                body = Local($"{direct.Conversations} 个会话有新私信。", $"{direct.Conversations} 個對話有新私訊。", $"New messages in {direct.Conversations} conversations.");
        }
        if (notice.Community is {} community && !hidden) {
            title = community.Name;
            body = community.Management ? Local("有新的加入申请待处理。", "有新的加入申請待處理。", "New join requests need your review.")
                : notice.Preview == "fullContent" ? (string.IsNullOrWhiteSpace(community.Callsign) ? "" : community.Callsign + ": ") + community.Text
                : Local("有新的组织聊天消息。", "有新的組織聊天訊息。", "New organization chat message.");
        }
        if (notice.Activity is { } activity) {
            tone = Paint(activity.Kind switch {
                "Online" => light ? "#1768A3" : "#4CB2F5",
                "StartedGame" => light ? "#197844" : "#42CF7C",
                _ => light ? "#566670" : "#91A5B5"
            });
            title = notice.Test ? Local("测试玩家", "測試玩家", "Test player") :
                string.IsNullOrWhiteSpace(activity.Callsign) ? activity.GameId : activity.Callsign;
            var change = activity.Kind switch {
                "Online" => Local("已上线", "已上線", "is online"),
                "Offline" => Local("已离线", "已離線", "is offline"),
                "StartedGame" => Local("开始游戏", "開始遊戲", "started playing"),
                _ => Local("结束游戏", "結束遊戲", "stopped playing")
            };
            body = (string.IsNullOrWhiteSpace(activity.GameId) ? "" : "@" + activity.GameId + " · ") + change;
        }
        Width = 380; Height = 170;
        Background = Paint(light ? "#F5F8FA" : "#101A21");
        BorderBrush = Paint(light ? "#BAC9D1" : "#47606E"); BorderThickness = new(1); CornerRadius = new(9);
        SnapsToDevicePixels = true;
        var grid = new Grid { ClipToBounds = true };
        _hover = new Border { Background = Paint(light ? "#E9F0F5" : "#192A35"),
            BorderBrush = Paint(light ? "#7596AD" : "#7394A7"), BorderThickness = new(1),
            CornerRadius = new(8), IsHitTestVisible = false, Opacity = 0 };
        grid.Children.Add(_hover);
        grid.Children.Add(new Border { Width = 3, Background = tone, HorizontalAlignment = HorizontalAlignment.Left, Margin = new(0,9,0,9) });
        var content = new Grid { Margin = new(17, 10, 12, 10) };
        content.RowDefinitions.Add(new() { Height = new(28) });
        content.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
        content.RowDefinitions.Add(new() { Height = new(30) });
        var header = new DockPanel();
        var close = MakeButton("×", secondary, dismiss, light, close: true); close.Width = 28;
        close.Name = "DismissNotification";
        close.ToolTip = Local("收起提醒，不标为已读", "收起提醒，不標為已讀", "Dismiss without marking as read");
        AutomationProperties.SetName(close, close.ToolTip.ToString()); DockPanel.SetDock(close, Dock.Right); header.Children.Add(close);
        var brand = new Image { Width = 24, Height = 24, Margin = new(0,0,7,0), Stretch = Stretch.Uniform };
        // The 1254px brand master needs area filtering at notification size; default
        // low-quality sampling drops thin rays and turns the star into isolated pixels.
        RenderOptions.SetBitmapScalingMode(brand, BitmapScalingMode.HighQuality);
        var assemblyName = Uri.EscapeDataString(typeof(DesktopNotificationCard).Assembly.GetName().Name!);
        brand.Source = new BitmapImage(new Uri($"pack://application:,,,/{assemblyName};component/Assets/Brand/notification_mark_{(light ? "light" : "dark")}.png"));
        header.Children.Add(brand);
        header.Children.Add(Text("StarBridge", primary, 13, true));
        header.Children.Add(Text("  ·  " + (notice.Activity != null ? Local("玩家动态", "玩家動態", "Player activity") : notice.Test ? Local("当前设备", "目前裝置", "This device") : hidden ? Local("通知", "通知", "Notification") : notice.DirectMessage != null ? Local("私信", "私訊", "Direct messages") : notice.Community is {} group ? (group.Management ? Local("管理待办", "管理待辦", "Management tasks") : Local("组织聊天", "組織聊天", "Organization chat")) : Local("房间", "房間", "Rooms")), secondary, 12));
        content.Children.Add(header);
        var text = new StackPanel { Margin = new(0,9,0,0) };
        text.Children.Add(Text(title, primary, 15, true));
        var detail = Text(body, secondary, 13); detail.TextWrapping = TextWrapping.Wrap; detail.LineHeight = 19;
        detail.LineStackingStrategy = LineStackingStrategy.BlockLineHeight; detail.MaxHeight = 38; detail.Margin = new(0,5,0,0);
        text.Children.Add(detail);
        var identity = new DockPanel { LastChildFill = true };
        if (notice.Activity is { } player) {
            var avatar = new Border { Width = 42, Height = 42, Margin = new(0,9,11,0),
                Background = Paint(light ? "#E0EAF0" : "#233743"), CornerRadius = new(6),
                VerticalAlignment = VerticalAlignment.Top, ClipToBounds = true };
            var bitmap = PlayerAvatar(player.AvatarImageData);
            avatar.Child = bitmap is null
                ? new TextBlock { Text = title.Length == 0 ? "?" : System.Globalization.StringInfo.GetNextTextElement(title),
                    Foreground = primary, FontSize = 18, HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center }
                : new Image { Source = bitmap, Stretch = Stretch.UniformToFill };
            DockPanel.SetDock(avatar, Dock.Left); identity.Children.Add(avatar);
        }
        identity.Children.Add(text); Grid.SetRow(identity,1); content.Children.Add(identity);
        var footer = new DockPanel();
        var action = MakeButton(notice.Activated == null || hidden ? Local("打开应用 →", "開啟應用程式 →", "Open app →")
            : notice.DirectMessage != null ? Local("查看私信 →", "查看私訊 →", "View direct messages →")
            : notice.Community != null ? Local("查看组织 →", "查看組織 →", "View organizations →")
            : Local("查看房间提醒 →", "查看房間提醒 →", "View room reminders →"), accent, open, light);
        DockPanel.SetDock(action, Dock.Right); footer.Children.Add(action);
        _idleHint = Local("悬停暂停收起", "游標停留時暫停收起", "Hover to keep open");
        _pausedHint = Local("已暂停自动收起", "已暫停自動收起", "Auto-dismiss paused");
        _hoverHint = Text(_idleHint, secondary, 11);
        footer.Children.Add(_hoverHint);
        Grid.SetRow(footer, 2); content.Children.Add(footer);
        grid.Children.Add(content); Child = grid;
        AutomationProperties.SetName(this, $"StarBridge. {title}. {body}");
        Cursor = System.Windows.Input.Cursors.Hand;
        MouseEnter += (_, _) => SetHovered(true);
        MouseLeave += (_, _) => SetHovered(false);
        MouseLeftButtonUp += (_, e) => { if (!e.Handled) { open(); e.Handled = true; } };
    }

    internal void SetHovered(bool hovered) {
        _hoverHint.Text = hovered ? _pausedHint : _idleHint;
        DesktopNotificationMotion.Fade(_hover, hovered ? 1 : 0, 100, DesktopNotificationMotion.Enabled(_reduceMotion));
    }

    internal static BitmapSource? PlayerAvatar(string? data)
    {
        if (data is null || data.Length > 350000) return null;
        var comma = data.IndexOf(',');
        if (comma < 0 || data[..comma] is not ("data:image/png;base64" or "data:image/jpeg;base64" or "data:image/webp;base64")) return null;
        try {
            using var bytes = new System.IO.MemoryStream(Convert.FromBase64String(data[(comma + 1)..]));
            var image = new BitmapImage(); image.BeginInit(); image.CacheOption = BitmapCacheOption.OnLoad;
            image.DecodePixelWidth = 84; image.StreamSource = bytes; image.EndInit(); image.Freeze(); return image;
        } catch { return null; }
    }

    private static Brush Paint(string value) => new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(value));
    private static TextBlock Text(string value, Brush brush, double size, bool emphasis = false) => new() {
        Text = value, Foreground = brush, FontSize = size, FontFamily = new("Segoe UI, Microsoft YaHei UI"),
        FontWeight = emphasis ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis
    };
    private static Button MakeButton(string text, Brush color, Action action, bool light, bool close = false)
    {
        var button = new Button { Content = text, Foreground = color, Background = Brushes.Transparent,
            BorderThickness = new(0), Padding = new(7,3,7,3), FontSize = 12, Focusable = false,
            Cursor = System.Windows.Input.Cursors.Hand };
        // Own the template completely: Windows' default button chrome paints a pale-blue hover.
        var border = new FrameworkElementFactory(typeof(Border));
        border.SetValue(Border.CornerRadiusProperty, new CornerRadius(5));
        border.SetValue(Border.BackgroundProperty, new TemplateBindingExtension(Control.BackgroundProperty));
        border.SetValue(Border.PaddingProperty, new TemplateBindingExtension(Control.PaddingProperty));
        var content = new FrameworkElementFactory(typeof(ContentPresenter));
        content.SetValue(ContentPresenter.HorizontalAlignmentProperty, HorizontalAlignment.Center);
        content.SetValue(ContentPresenter.VerticalAlignmentProperty, VerticalAlignment.Center);
        border.AppendChild(content);
        var template = new ControlTemplate(typeof(Button)) { VisualTree = border };
        var hover = new Trigger { Property = UIElement.IsMouseOverProperty, Value = true };
        hover.Setters.Add(new Setter(Control.BackgroundProperty, Paint(close ? (light ? "#F6E0E0" : "#351A1C") : (light ? "#DDEAF2" : "#173348"))));
        hover.Setters.Add(new Setter(Control.ForegroundProperty, close ? Paint(light ? "#B62F43" : "#F26D75") : color));
        template.Triggers.Add(hover);
        var pressed = new Trigger { Property = System.Windows.Controls.Primitives.ButtonBase.IsPressedProperty, Value = true };
        pressed.Setters.Add(new Setter(Control.BackgroundProperty, Paint(close ? (light ? "#EFC5CA" : "#51272D") : (light ? "#C6DFEF" : "#244B64"))));
        template.Triggers.Add(pressed);
        button.Template = template;
        button.Click += (_, e) => { e.Handled = true; action(); };
        return button;
    }
}
