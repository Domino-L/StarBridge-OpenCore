namespace StarBridge.Desktop;

using StarBridge.HostRuntime.Notifications;
using System.Globalization;
using System.Windows;
using System.Windows.Automation;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Shapes;
using Brush = System.Windows.Media.Brush;
using Image = System.Windows.Controls.Image;
using Path = System.Windows.Shapes.Path;
using Rectangle = System.Windows.Shapes.Rectangle;

/// <summary>SCM trade alert (user-approved 10-29): SCM crate, low-contrast SCM market stamp,
/// StarBridge star before the SCM wordmark. Content is already redacted by the Host.</summary>
internal sealed class TradeNotificationCard : Border
{
    private readonly Border _hover;
    private readonly bool _reduceMotion;
    private readonly TextBlock _hoverHint;
    private readonly string _idleHint, _pausedHint;

    internal TradeNotificationCard(DesktopNotification notice, Action open, Action dismiss)
    {
        var trade = notice.Trade ?? throw new ArgumentException("Trade content required.");
        var look = new TradeLook(notice);
        _reduceMotion = notice.ReduceMotion;
        Width = 380; Height = DesktopNotificationCard.PresentationHeight(notice);
        Background = look.Ground(0.46); BorderBrush = look.Edge; BorderThickness = new(1.5); CornerRadius = new(9);
        SnapsToDevicePixels = true;
        var grid = new Grid { ClipToBounds = true };
        _hover = new Border { Background = look.Paint(look.Light ? "#E9F0F5" : "#192A35"), CornerRadius = new(8),
            IsHitTestVisible = false, Opacity = 0 };
        grid.Children.Add(_hover);
        var stamp = new ScmMarketStamp(look.Scm, look.Light ? 0.09 : 0.10) { Name = "TradeStamp", Width = 150, Height = 150,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new(0, 16, -18, 0) };
        grid.Children.Add(stamp);
        grid.Children.Add(look.Box(96, 84, 24, new(0, 0, 0, 0), chatAvatar: 58));
        var content = new Grid { Margin = new(100, 10, 12, 10) };
        content.RowDefinitions.Add(new() { Height = new(28) });
        content.RowDefinitions.Add(new() { Height = new(1, GridUnitType.Star) });
        content.RowDefinitions.Add(new() { Height = new(30) });
        var header = new DockPanel();
        var close = DesktopNotificationCard.MakeButton("×", look.Secondary, dismiss, look.Light, close: true); close.Width = 28;
        close.Name = "DismissNotification";
        close.ToolTip = look.Local("收起提醒，不标为已读", "收起提醒，不標為已讀", "Dismiss without marking as read");
        AutomationProperties.SetName(close, close.ToolTip.ToString()); DockPanel.SetDock(close, Dock.Right); header.Children.Add(close);
        header.Children.Add(look.Brand(16, 40, 13));
        content.Children.Add(header);
        var body = new StackPanel { Margin = new(0, 6, 0, 0) };
        body.Children.Add(TradeLook.Text(look.Title, look.Primary, 15, true));
        if (look.Chat && !look.Hidden) body.Children.Add(look.Quote(13, 2));
        else {
            var detail = TradeLook.Text(look.Detail, look.Secondary, 13); detail.Margin = new(0, 3, 0, 0);
            body.Children.Add(detail);
            if (look.Step is {} step) body.Children.Add(look.Track(step));
        }
        Grid.SetRow(body, 1); content.Children.Add(body);
        var footer = new DockPanel();
        var action = DesktopNotificationCard.MakeButton(look.Action(notice.Activated is null), look.Scm, open, look.Light);
        DockPanel.SetDock(action, Dock.Right); footer.Children.Add(action);
        _idleHint = look.Local("悬停暂停收起", "游標停留時暫停收起", "Hover to keep open");
        _pausedHint = look.Local("已暂停自动收起", "已暫停自動收起", "Auto-dismiss paused");
        _hoverHint = TradeLook.Text(_idleHint, look.Secondary, 11);
        footer.Children.Add(_hoverHint);
        Grid.SetRow(footer, 2); content.Children.Add(footer);
        grid.Children.Add(content); Child = grid;
        AutomationProperties.SetName(this, look.Automation);
        Cursor = System.Windows.Input.Cursors.Hand;
        MouseEnter += (_, _) => SetHovered(true);
        MouseLeave += (_, _) => SetHovered(false);
        MouseLeftButtonUp += (_, e) => { if (!e.Handled) { open(); e.Handled = true; } };
        TradeLook.Press(stamp, -14, DesktopNotificationMotion.Enabled(notice.ReduceMotion));
    }

    internal void SetHovered(bool hovered) {
        _hoverHint.Text = hovered ? _pausedHint : _idleHint;
        DesktopNotificationMotion.Fade(_hover, hovered ? 1 : 0, 100, DesktopNotificationMotion.Enabled(_reduceMotion));
    }
}

/// <summary>In-game trade alert: activity-sized, click-through, no buttons.</summary>
internal sealed class CompactTradeNotificationCard : Border
{
    internal CompactTradeNotificationCard(DesktopNotification notice)
    {
        var look = new TradeLook(notice);
        Width = 344; Height = 88; CornerRadius = new(6);
        Background = look.Ground(0.5); BorderBrush = look.Edge; BorderThickness = new(1.5);
        IsHitTestVisible = false; Focusable = false; SnapsToDevicePixels = true;
        var grid = new Grid { ClipToBounds = true };
        var stamp = new ScmMarketStamp(look.Scm, look.Light ? 0.09 : 0.10) { Name = "TradeStamp", Width = 96, Height = 96,
            HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Top, Margin = new(0, -4, -6, 0) };
        grid.Children.Add(stamp);
        grid.Children.Add(look.Box(76, 62, 20, new(4, 0, 0, 0), chatAvatar: 50));
        var text = new StackPanel { Margin = new(84, 11, 12, 0) };
        text.Children.Add(look.Brand(12, 32, 11));
        var title = look.Chat && !look.Hidden
            ? look.Local("新的交易私信", "新的交易私訊", "New trade message") + (look.Peer.Length == 0 ? "" : " · " + look.Peer)
            : look.Title;
        var head = TradeLook.Text(title, look.Primary, 14, true); head.Margin = new(0, 4, 0, 0);
        text.Children.Add(head);
        var detail = TradeLook.Text(look.Chat && !look.Hidden ? look.ChatText : look.Detail, look.Secondary, 12);
        detail.Margin = new(0, 2, 0, 0);
        text.Children.Add(detail);
        grid.Children.Add(text); Child = grid;
        AutomationProperties.SetName(this, look.Automation);
        TradeLook.Press(stamp, -12, DesktopNotificationMotion.Enabled(notice.ReduceMotion));
    }
}

/// <summary>Shared colours, copy and pieces for both trade cards.</summary>
internal sealed class TradeLook
{
    internal readonly bool Light, Hidden, Chat;
    internal readonly Brush Primary, Secondary, Scm, Edge, Tone;
    internal readonly string Title, Detail, Peer, ChatText, Automation, Kind;
    internal readonly int? Step;
    private readonly string _locale;

    internal TradeLook(DesktopNotification notice)
    {
        var trade = notice.Trade!;
        _locale = notice.Locale;
        Light = notice.Appearance == "light";
        Hidden = notice.Preview == "hiddenDetails" || trade.Title.Length == 0;
        Kind = Hidden ? "" : trade.Kind;
        Chat = Kind == "message";
        Primary = Paint(Light ? "#17242C" : "#E7EEF2");
        Secondary = Paint(Light ? "#4A5B64" : "#93A4AE");
        Scm = Paint(Light ? "#C96A00" : "#FF9000");
        Edge = Paint(Light ? "#BFC96A00" : "#B3FF9000");
        Tone = Paint(Kind switch {
            "request" or "review" => Light ? "#8A5700" : "#FFB73D",
            "approved" or "shipped" or "receipt" => Light ? "#1768A3" : "#4CB2F5",
            "completed" => Light ? "#197844" : "#42CF7C",
            "cancelled" => Light ? "#B62F43" : "#F26D75",
            "message" => Light ? "#6A4FC4" : "#B497FF",
            _ => Light ? "#C96A00" : "#FF9000",
        });
        Step = Kind switch { "request" or "approved" => 1, "shipped" or "receipt" => 2, "completed" => 3, "cancelled" => 0, _ => null };
        Peer = Hidden ? "" : trade.Peer;
        ChatText = trade.Text.Length > 0 ? trade.Text : Local("发来一条交易私信。", "傳來一則交易私訊。", "Sent you a trade message.");
        if (Hidden) {
            Title = Local("你有新的交易提醒", "你有新的交易提醒", "You have a new trade alert");
            Detail = Local("打开应用查看。", "開啟應用程式查看。", "Open the app to view it.");
        } else if (Chat) {
            Title = Peer.Length > 0 ? Peer : Local("新的交易私信", "新的交易私訊", "New trade message");
            Detail = ChatText;
        } else {
            Title = trade.Title;
            var parts = new List<string>();
            if (trade.Item.Length > 0) parts.Add(trade.Item);
            if (trade.Quantity > 0) parts.Add(Local($"{trade.Quantity} 件", $"{trade.Quantity} 件", $"× {trade.Quantity}"));
            if (trade.Amount.Length > 0) parts.Add(trade.Amount + " UEC");
            Detail = parts.Count > 0 ? string.Join(" · ", parts) : trade.Body;
        }
        Automation = $"StarBridge. {Local("SCM 交易", "SCM 交易", "SCM trade")}. {Title}. {Detail}";
    }

    internal string Local(string cn, string traditional, string english) =>
        !_locale.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? english
        : _locale is "zh-TW" or "zh-Hant" ? traditional : cn;

    internal string Action(bool noActivation) => noActivation || Hidden ? Local("打开应用 →", "開啟應用程式 →", "Open app →")
        : Chat ? Local("查看交易私信 →", "查看交易私訊 →", "View trade message →")
        : Local("查看交易 →", "查看交易 →", "View trade →");

    internal Brush Paint(string value) => TradeLook.Solid(value);
    internal static Brush Solid(string value)
    {
        var brush = new SolidColorBrush((Color)ColorConverter.ConvertFromString(value)); brush.Freeze(); return brush;
    }

    // Warm SCM tint at the crate side fading into the normal card ground.
    internal Brush Ground(double stop)
    {
        var brush = new LinearGradientBrush { StartPoint = new(0, 0.5), EndPoint = new(1, 0.5) };
        brush.GradientStops.Add(new((Color)ColorConverter.ConvertFromString(Light ? "#FBF6EF" : "#16140F"), 0));
        brush.GradientStops.Add(new((Color)ColorConverter.ConvertFromString(Light ? "#F5F8FA" : "#101A21"), stop));
        brush.Freeze(); return brush;
    }

    internal static TextBlock Text(string value, Brush brush, double size, bool emphasis = false) => new() {
        Text = value, Foreground = brush, FontSize = size, FontFamily = new("Segoe UI, Microsoft YaHei UI"),
        FontWeight = emphasis ? FontWeights.SemiBold : FontWeights.Normal, VerticalAlignment = VerticalAlignment.Center,
        TextTrimming = TextTrimming.CharacterEllipsis
    };

    // StarBridge star, then the SCM wordmark, then "交易".
    internal FrameworkElement Brand(double star, double wordmark, double size)
    {
        var row = new StackPanel { Orientation = Orientation.Horizontal, VerticalAlignment = VerticalAlignment.Center };
        var mark = new Image { Name = "StarBridgeMark", Width = star, Height = star, Margin = new(0, 0, 6, 0), Stretch = Stretch.Uniform,
            Source = TradeAssets.StarBridgeMark(Light), VerticalAlignment = VerticalAlignment.Center };
        RenderOptions.SetBitmapScalingMode(mark, BitmapScalingMode.HighQuality);
        row.Children.Add(mark);
        if (TradeAssets.Mask("scm_wordmark.png") is {} word)
            row.Children.Add(new Rectangle { Name = "ScmWordmark", Width = wordmark, Height = wordmark / 4.1, Fill = Scm,
                OpacityMask = word, Margin = new(0, 0, 5, 0), VerticalAlignment = VerticalAlignment.Center });
        else row.Children.Add(Text("SCM ", Scm, size, true));
        row.Children.Add(Text(Local("交易", "交易", "Trade"), Primary, size, true));
        return row;
    }

    // Crate (or the peer's initial for trade messages) with a round status badge.
    internal FrameworkElement Box(double column, double crate, double badge, Thickness margin, double chatAvatar)
    {
        var box = new Grid { Width = column, HorizontalAlignment = HorizontalAlignment.Left, Margin = margin };
        box.Children.Add(new Ellipse { Width = crate, Height = crate, IsHitTestVisible = false,
            Fill = new RadialGradientBrush(Color.FromArgb(Light ? (byte)26 : (byte)34, 0xFF, 0x90, 0), Colors.Transparent) });
        var anchor = new Grid { Width = Chat ? chatAvatar : crate, Height = Chat ? chatAvatar : crate,
            HorizontalAlignment = HorizontalAlignment.Center, VerticalAlignment = VerticalAlignment.Center };
        if (Chat) {
            anchor.Children.Add(new Border { Name = "TradePeerInitial", CornerRadius = new(chatAvatar / 2),
                Background = Paint(Light ? "#E0EAF0" : "#233743"),
                Child = new TextBlock { Text = Peer.Length == 0 ? "?" : StringInfo.GetNextTextElement(Peer).ToUpperInvariant(),
                    Foreground = Primary, FontSize = chatAvatar * 0.4, HorizontalAlignment = HorizontalAlignment.Center,
                    VerticalAlignment = VerticalAlignment.Center } });
        } else {
            var image = new Image { Name = "TradeCrate", Source = TradeAssets.Crate(), Stretch = Stretch.Uniform };
            RenderOptions.SetBitmapScalingMode(image, BitmapScalingMode.HighQuality);
            anchor.Children.Add(image);
        }
        if (!Hidden && Kind.Length > 0)
            anchor.Children.Add(new Border { Name = "TradeStatusBadge", Width = badge, Height = badge, CornerRadius = new(badge / 2),
                Background = Tone, BorderBrush = Paint(Light ? "#F5F8FA" : "#101A21"), BorderThickness = new(2),
                HorizontalAlignment = HorizontalAlignment.Right, VerticalAlignment = VerticalAlignment.Bottom,
                Margin = new(0, 0, -badge * 0.15, -badge * 0.15), Child = Glyph(badge * 0.5) });
        box.Children.Add(anchor);
        return box;
    }

    private FrameworkElement Glyph(double size)
    {
        var data = Kind switch {
            "request" => "M8,3 L8,13 M3,8 L13,8",
            "approved" or "completed" => "M3,8.5 L6,11.5 L13,4.5",
            "shipped" or "receipt" => "M2,5.5 L8,2.5 L14,5.5 L14,10.5 L8,13.5 L2,10.5 Z M2,5.5 L8,8.5 L14,5.5 M8,8.5 L8,13.5",
            "cancelled" => "M4,4 L12,12 M12,4 L4,12",
            "message" => "M2.5,3.5 L13.5,3.5 L13.5,10.5 L7.5,10.5 L4.5,13 L4.5,10.5 L2.5,10.5 Z",
            "review" => "M8,2 L9.8,6 L14,6.3 L10.8,9 L11.8,13.2 L8,11 L4.2,13.2 L5.2,9 L2,6.3 L6.2,6 Z",
            _ => "M8,4 L8,9 M8,11.5 L8,12",
        };
        return new Path { Data = Geometry.Parse(data), Stroke = Paint(Light ? "#F5F8FA" : "#101A21"), StrokeThickness = 1.8,
            StrokeLineJoin = PenLineJoin.Round, StrokeStartLineCap = PenLineCap.Round, StrokeEndLineCap = PenLineCap.Round,
            Stretch = Stretch.Uniform, Width = size, Height = size };
    }

    // Three-step track: request → shipped → received. Cancelled keeps every step grey.
    internal FrameworkElement Track(int step)
    {
        var row = new StackPanel { Name = "TradeTrack", Orientation = Orientation.Horizontal, Margin = new(0, 8, 0, 0) };
        var off = Paint(Light ? "#C6D1D9" : "#26343E");
        for (var i = 1; i <= 3; i++) {
            if (i > 1) row.Children.Add(new Rectangle { Width = 20, Height = 2, Fill = step >= i ? Tone : off, VerticalAlignment = VerticalAlignment.Center });
            row.Children.Add(new Ellipse { Width = 7, Height = 7, Fill = step >= i ? Tone : off, VerticalAlignment = VerticalAlignment.Center });
        }
        var label = Kind switch {
            "request" => Local("申请中", "申請中", "Requested"),
            "approved" => Local("已同意", "已同意", "Approved"),
            "shipped" => Local("已发货", "已出貨", "Shipped"),
            "receipt" => Local("待你收货", "待你收貨", "Awaiting your receipt"),
            "completed" => Local("已完成", "已完成", "Completed"),
            _ => Local("已取消", "已取消", "Cancelled"),
        };
        var text = Text(label, Secondary, 11); text.Margin = new(8, 0, 0, 0);
        row.Children.Add(text);
        return row;
    }

    internal FrameworkElement Quote(double size, double rule) => new Border {
        Name = "TradeMessageQuote", BorderBrush = Tone, BorderThickness = new(rule, 0, 0, 0), Padding = new(8, 0, 0, 0),
        Margin = new(0, 5, 0, 0), MaxHeight = 40,
        Child = new TextBlock { Text = ChatText, Foreground = Primary, FontSize = size, TextWrapping = TextWrapping.Wrap,
            LineHeight = 19, LineStackingStrategy = LineStackingStrategy.BlockLineHeight, TextTrimming = TextTrimming.CharacterEllipsis,
            FontFamily = new("Segoe UI, Microsoft YaHei UI") } };

    // The stamp lands shortly after the card: a 220 ms settle from 1.25×. Reduced motion: static.
    internal static void Press(FrameworkElement stamp, double angle, bool animate)
    {
        var scale = new ScaleTransform(1, 1);
        var group = new TransformGroup(); group.Children.Add(scale); group.Children.Add(new RotateTransform(angle));
        stamp.RenderTransformOrigin = new(0.5, 0.5); stamp.RenderTransform = group;
        if (!animate) return;
        var begin = TimeSpan.FromMilliseconds(120);
        var settle = new DoubleAnimation(1.25, 1, TimeSpan.FromMilliseconds(220)) { BeginTime = begin,
            EasingFunction = new BackEase { EasingMode = EasingMode.EaseOut, Amplitude = 0.3 }, FillBehavior = FillBehavior.HoldEnd };
        scale.BeginAnimation(ScaleTransform.ScaleXProperty, settle);
        scale.BeginAnimation(ScaleTransform.ScaleYProperty, settle);
        stamp.Opacity = 0;
        stamp.BeginAnimation(UIElement.OpacityProperty, new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(160)) { BeginTime = begin });
    }
}

/// <summary>Round SCM market stamp: two rings, ring text and the SCM mark, all in one tint at low opacity.</summary>
internal sealed class ScmMarketStamp : FrameworkElement
{
    private const string Ring = "SCM MARKET · 星际公民交易市场 · SCM MARKET · ";
    private readonly Brush _ink;
    private readonly double _strength;
    private List<FormattedText>? _glyphs;
    private double _glyphDpi;

    internal ScmMarketStamp(Brush ink, double strength)
    {
        _ink = ink; _strength = strength;
        IsHitTestVisible = false; Focusable = false;
    }

    protected override void OnRender(DrawingContext dc)
    {
        base.OnRender(dc);
        var size = Math.Min(RenderSize.Width, RenderSize.Height);
        if (size <= 0) return;
        dc.PushOpacity(_strength);
        dc.PushTransform(new ScaleTransform(size / 200, size / 200));
        var pen = new Pen(_ink, 5); pen.Freeze();
        dc.DrawEllipse(null, pen, new(100, 100), 95, 95);
        var inner = new Pen(_ink, 2.5); inner.Freeze();
        dc.DrawEllipse(null, inner, new(100, 100), 60, 60);
        var dpi = VisualTreeHelper.GetDpi(this).PixelsPerDip;
        var face = new Typeface(new FontFamily("Segoe UI, Microsoft YaHei UI"), FontStyles.Normal, FontWeights.Bold, FontStretches.Normal);
        if (_glyphs is null || _glyphDpi != dpi) {
            var glyphs = StringInfo.GetTextElementEnumerator(Ring);
            _glyphs = new List<FormattedText>(); _glyphDpi = dpi;
            while (glyphs.MoveNext())
                _glyphs.Add(new FormattedText(glyphs.GetTextElement(), CultureInfo.InvariantCulture, FlowDirection.LeftToRight, face, 15, _ink, dpi));
        }
        var parts = _glyphs;
        const double radius = 77;
        var spacing = (2 * Math.PI * radius - parts.Sum(p => p.WidthIncludingTrailingWhitespace)) / Math.Max(1, parts.Count);
        var travelled = 0d;
        foreach (var part in parts) {
            var width = part.WidthIncludingTrailingWhitespace;
            var angle = -Math.PI / 2 + (travelled + width / 2) / radius;
            travelled += width + spacing;
            dc.PushTransform(new TranslateTransform(100 + radius * Math.Cos(angle), 100 + radius * Math.Sin(angle)));
            dc.PushTransform(new RotateTransform(angle * 180 / Math.PI + 90));
            dc.DrawText(part, new(-width / 2, -part.Height / 2));
            dc.Pop(); dc.Pop();
        }
        if (TradeAssets.Mask("scm_mark.png") is {} mark) {
            // The mask maps onto the bounds of the rectangle drawn under it.
            var area = new Rect(64, 60, 72, 78);
            dc.PushOpacityMask(mark);
            dc.DrawRectangle(_ink, null, area);
            dc.Pop();
        }
        dc.Pop(); dc.Pop();
    }

    // Decoration only: never announced or focusable.
    protected override System.Windows.Automation.Peers.AutomationPeer? OnCreateAutomationPeer() => null;
}

/// <summary>Brand images bundled as WPF resources. Missing art never blocks a reminder.</summary>
internal static class TradeAssets
{
    private static readonly Dictionary<string, ImageBrush?> Masks = new(StringComparer.Ordinal);
    private static readonly Lazy<ImageSource?> CrateImage = new(() => Load("scm_market_crate.png", 192));

    internal static ImageSource? Crate() => CrateImage.Value;

    internal static ImageSource? StarBridgeMark(bool light) => Load(light ? "notification_mark_light.png" : "notification_mark_dark.png", 64);

    internal static ImageBrush? Mask(string name)
    {
        lock (Masks) {
            if (Masks.TryGetValue(name, out var cached)) return cached;
            var image = Load(name, 256);
            ImageBrush? brush = null;
            if (image is not null) { brush = new ImageBrush(image) { Stretch = Stretch.Uniform }; brush.Freeze(); }
            Masks[name] = brush;
            return brush;
        }
    }

    private static ImageSource? Load(string name, int width)
    {
        try {
            var assembly = Uri.EscapeDataString(typeof(TradeAssets).Assembly.GetName().Name!);
            var image = new BitmapImage(); image.BeginInit();
            image.CacheOption = BitmapCacheOption.OnLoad; image.DecodePixelWidth = width;
            image.UriSource = new Uri($"pack://application:,,,/{assembly};component/Assets/Brand/{name}");
            image.EndInit(); image.Freeze();
            return image;
        }
        catch (Exception) {
            // Missing or corrupt art (including FileFormatException) never blocks the reminder text.
            return null;
        }
    }
}
