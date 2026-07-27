namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;

internal static class StarBridgeMessageBox
{
    public static MessageBoxResult ShowAcknowledgement(
        Window owner,
        string message,
        string caption,
        string actionText,
        MessageBoxImage icon = MessageBoxImage.Information)
    {
        var dialog = new StarBridgeMessageBoxWindow(
            message,
            caption,
            MessageBoxButton.OK,
            icon,
            actionText)
        {
            Owner = owner,
            WindowStartupLocation = WindowStartupLocation.CenterOwner
        };
        return dialog.ShowDialog() == true
            ? dialog.Result
            : MessageBoxResult.OK;
    }

    public static bool ShowAction(
        Window owner,
        string message,
        string caption,
        string primaryActionText,
        string secondaryActionText,
        MessageBoxImage icon = MessageBoxImage.Question)
    {
        var dialog = new StarBridgeMessageBoxWindow(
            message,
            caption,
            MessageBoxButton.YesNo,
            icon,
            primaryActionText,
            secondaryActionText)
        {
            Owner = owner,
            WindowStartupLocation = WindowStartupLocation.CenterOwner
        };
        return dialog.ShowDialog() == true && dialog.Result == MessageBoxResult.Yes;
    }

    public static MessageBoxResult Show(
        string messageBoxText,
        string caption,
        MessageBoxButton button = MessageBoxButton.OK,
        MessageBoxImage icon = MessageBoxImage.None)
    {
        return Show(null, messageBoxText, caption, button, icon);
    }

    public static MessageBoxResult Show(
        Window? owner,
        string messageBoxText,
        string caption,
        MessageBoxButton button = MessageBoxButton.OK,
        MessageBoxImage icon = MessageBoxImage.None)
    {
        var dialog = new StarBridgeMessageBoxWindow(messageBoxText, caption, button, icon);
        var resolvedOwner = owner ?? Application.Current?.Windows.OfType<Window>().FirstOrDefault(window => window.IsActive);
        if (resolvedOwner is not null && !ReferenceEquals(resolvedOwner, dialog))
        {
            dialog.Owner = resolvedOwner;
            dialog.WindowStartupLocation = WindowStartupLocation.CenterOwner;
        }

        return dialog.ShowDialog() == true
            ? dialog.Result
            : GetFallbackResult(button);
    }

    private static MessageBoxResult GetFallbackResult(MessageBoxButton button)
    {
        return button switch
        {
            MessageBoxButton.OK => MessageBoxResult.OK,
            MessageBoxButton.OKCancel => MessageBoxResult.Cancel,
            MessageBoxButton.YesNo => MessageBoxResult.No,
            MessageBoxButton.YesNoCancel => MessageBoxResult.Cancel,
            _ => MessageBoxResult.None
        };
    }
}

internal sealed class StarBridgeMessageBoxWindow : Window
{
    private readonly MessageBoxButton _buttons;
    private readonly string? _primaryActionText;
    private readonly string? _secondaryActionText;

    public StarBridgeMessageBoxWindow(
        string message,
        string caption,
        MessageBoxButton buttons,
        MessageBoxImage icon,
        string? primaryActionText = null,
        string? secondaryActionText = null)
    {
        _buttons = buttons;
        _primaryActionText = primaryActionText;
        _secondaryActionText = secondaryActionText;
        Result = MessageBoxResult.None;
        Title = string.IsNullOrWhiteSpace(caption) ? "星海舰桥" : caption;
        Width = 480;
        MinWidth = 420;
        MaxWidth = 640;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterScreen;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
        SnapsToDevicePixels = true;

        Content = BuildChrome(message, Title, icon);
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key != Key.Escape)
            {
                return;
            }

            SetResult(GetEscapeResult());
            e.Handled = true;
        };
        Loaded += (_, _) => FocusDefaultButton();
    }

    public MessageBoxResult Result { get; private set; }

    private FrameworkElement BuildChrome(string message, string caption, MessageBoxImage icon)
    {
        var root = new Border
        {
            Background = FindBrush("HudGlassBrush", new SolidColorBrush(Color.FromRgb(7, 16, 25))),
            BorderBrush = FindBrush("BorderDefaultBrush", new SolidColorBrush(Color.FromRgb(26, 83, 112))),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2),
            Padding = new Thickness(0)
        };

        var grid = new Grid();
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });
        grid.RowDefinitions.Add(new RowDefinition { Height = GridLength.Auto });

        var titleBar = new Grid
        {
            Background = FindBrush("HudHeaderBrush", new SolidColorBrush(Color.FromRgb(9, 17, 25))),
            MinHeight = 42,
            Cursor = Cursors.SizeAll
        };
        titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });
        titleBar.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        titleBar.MouseLeftButtonDown += (_, e) =>
        {
            if (e.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        };

        var tone = GetToneBrush(icon);
        titleBar.Children.Add(new Border
        {
            Width = 3,
            Margin = new Thickness(0),
            Background = tone
        });

        var title = new TextBlock
        {
            Text = string.IsNullOrWhiteSpace(caption) ? "星海舰桥" : caption,
            Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(14, 0, 12, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(title, 1);
        titleBar.Children.Add(title);

        var closeButton = CreateCloseButton();
        closeButton.Margin = new Thickness(0, 7, 8, 7);
        Grid.SetColumn(closeButton, 2);
        titleBar.Children.Add(closeButton);
        Grid.SetRow(titleBar, 0);
        grid.Children.Add(titleBar);

        var body = new Grid
        {
            Margin = new Thickness(18, 18, 18, 16)
        };
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
        body.ColumnDefinitions.Add(new ColumnDefinition { Width = new GridLength(1, GridUnitType.Star) });

        var mark = new Border
        {
            Width = 34,
            Height = 34,
            BorderBrush = tone,
            BorderThickness = new Thickness(1),
            Background = FindBrush(GetToneSurfaceKey(icon), new SolidColorBrush(Color.FromArgb(68, 8, 24, 35))),
            CornerRadius = new CornerRadius(2),
            VerticalAlignment = VerticalAlignment.Top,
            Margin = new Thickness(0, 1, 14, 0)
        };
        mark.Child = new TextBlock
        {
            Text = GetIconText(icon),
            Foreground = tone,
            FontSize = 17,
            FontWeight = FontWeights.Bold,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center
        };
        body.Children.Add(mark);

        var messageText = new TextBlock
        {
            Text = message,
            Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
            FontSize = 13,
            LineHeight = 20,
            TextWrapping = TextWrapping.Wrap,
            MaxWidth = 520
        };
        var messageScroller = new ScrollViewer
        {
            Content = messageText,
            MaxHeight = System.Math.Max(
                220,
                System.Math.Min(520, SystemParameters.WorkArea.Height * 0.55)),
            HorizontalScrollBarVisibility = ScrollBarVisibility.Disabled,
            VerticalScrollBarVisibility = ScrollBarVisibility.Auto
        };
        Grid.SetColumn(messageScroller, 1);
        body.Children.Add(messageScroller);
        Grid.SetRow(body, 1);
        grid.Children.Add(body);

        var buttonPanel = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(18, 0, 18, 18)
        };
        foreach (var button in CreateButtons())
        {
            buttonPanel.Children.Add(button);
        }

        Grid.SetRow(buttonPanel, 2);
        grid.Children.Add(buttonPanel);
        root.Child = grid;
        return root;
    }

    private IEnumerable<Button> CreateButtons()
    {
        return _buttons switch
        {
            MessageBoxButton.OK => [CreateDialogButton(_primaryActionText ?? "确定", MessageBoxResult.OK, true)],
            MessageBoxButton.OKCancel =>
            [
                CreateDialogButton("取消", MessageBoxResult.Cancel, false),
                CreateDialogButton("确定", MessageBoxResult.OK, true)
            ],
            MessageBoxButton.YesNo =>
            [
                CreateDialogButton(_secondaryActionText ?? "否", MessageBoxResult.No, false),
                CreateDialogButton(_primaryActionText ?? "是", MessageBoxResult.Yes, true)
            ],
            MessageBoxButton.YesNoCancel =>
            [
                CreateDialogButton("取消", MessageBoxResult.Cancel, false),
                CreateDialogButton("否", MessageBoxResult.No, false),
                CreateDialogButton("是", MessageBoxResult.Yes, true)
            ],
            _ => [CreateDialogButton("确定", MessageBoxResult.OK, true)]
        };
    }

    private Button CreateDialogButton(string text, MessageBoxResult result, bool primary)
    {
        var button = new Button
        {
            Content = text,
            MinWidth = 78,
            Height = 32,
            Margin = new Thickness(8, 0, 0, 0),
            IsDefault = primary,
            IsCancel = result == MessageBoxResult.Cancel
        };

        var styleKey = primary ? "PrimaryButton" : "SecondaryButton";
        if (TryFindResource(styleKey) is Style style)
        {
            button.Style = style;
        }

        button.Click += (_, _) => SetResult(result);
        return button;
    }

    private Button CreateCloseButton()
    {
        var button = new Button
        {
            Width = 30,
            MinWidth = 30,
            Height = 28,
            Padding = new Thickness(0),
            ToolTip = "关闭",
            IsCancel = true
        };

        if (TryFindResource("DialogCloseButton") is Style style)
        {
            button.Style = style;
            button.Height = 28;
        }

        button.Click += (_, _) => SetResult(GetEscapeResult());
        return button;
    }

    private void FocusDefaultButton()
    {
        var buttons = FindVisualChildren<Button>(this).ToArray();
        var target = buttons.FirstOrDefault(button => button.IsDefault) ?? buttons.LastOrDefault();
        target?.Focus();
    }

    private void SetResult(MessageBoxResult result)
    {
        Result = result == MessageBoxResult.None ? GetEscapeResult() : result;
        DialogResult = true;
        Close();
    }

    private MessageBoxResult GetEscapeResult()
    {
        return _buttons switch
        {
            MessageBoxButton.OK => MessageBoxResult.OK,
            MessageBoxButton.OKCancel => MessageBoxResult.Cancel,
            MessageBoxButton.YesNo => MessageBoxResult.No,
            MessageBoxButton.YesNoCancel => MessageBoxResult.Cancel,
            _ => MessageBoxResult.Cancel
        };
    }

    private Brush GetToneBrush(MessageBoxImage icon)
    {
        return icon switch
        {
            MessageBoxImage.Error => FindBrush("StatusDangerBrush", Brushes.IndianRed),
            MessageBoxImage.Warning => FindBrush("StatusWarningBrush", Brushes.Goldenrod),
            MessageBoxImage.Question => FindBrush("AccentBrush", Brushes.DeepSkyBlue),
            MessageBoxImage.Information => FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue),
            _ => FindBrush("AccentDimBrush", Brushes.SteelBlue)
        };
    }

    private static string GetToneSurfaceKey(MessageBoxImage icon)
    {
        return icon switch
        {
            MessageBoxImage.Error => "StatusDangerSurfaceBrush",
            MessageBoxImage.Warning => "StatusWarningSurfaceBrush",
            MessageBoxImage.Question => "StatusInfoSurfaceBrush",
            MessageBoxImage.Information => "StatusInfoSurfaceBrush",
            _ => "StatusDisabledSurfaceBrush"
        };
    }

    private static string GetIconText(MessageBoxImage icon)
    {
        return icon switch
        {
            MessageBoxImage.Error => "!",
            MessageBoxImage.Warning => "!",
            MessageBoxImage.Question => "?",
            MessageBoxImage.Information => "i",
            _ => "*"
        };
    }

    private Brush FindBrush(string key, Brush fallback)
    {
        return TryFindResource(key) as Brush ??
               Application.Current?.TryFindResource(key) as Brush ??
               fallback;
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject parent)
        where T : DependencyObject
    {
        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T typed)
            {
                yield return typed;
            }

            foreach (var descendant in FindVisualChildren<T>(child))
            {
                yield return descendant;
            }
        }
    }
}
