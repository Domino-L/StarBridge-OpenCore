namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;

internal enum IdentityLinkChoice
{
    Later,
    LinkExisting,
    CreateCompatibilityAccount
}

internal sealed class IdentityLinkChoiceDialog : Window
{
    private IdentityLinkChoiceDialog()
    {
        Title = "设置 StarBridge 兼容身份";
        Width = 520;
        MinWidth = 460;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        Content = BuildContent();
        PreviewKeyDown += (_, eventArgs) =>
        {
            if (eventArgs.Key == Key.Escape)
            {
                Complete(IdentityLinkChoice.Later);
                eventArgs.Handled = true;
            }
        };
    }

    private IdentityLinkChoice Choice { get; set; } = IdentityLinkChoice.Later;

    public static IdentityLinkChoice Show(Window owner)
    {
        var dialog = new IdentityLinkChoiceDialog { Owner = owner };
        return dialog.ShowDialog() == true ? dialog.Choice : IdentityLinkChoice.Later;
    }

    private FrameworkElement BuildContent()
    {
        var root = new Border
        {
            Background = FindBrush("HudGlassBrush", new SolidColorBrush(Color.FromRgb(7, 16, 25))),
            BorderBrush = FindBrush("BorderDefaultBrush", new SolidColorBrush(Color.FromRgb(26, 83, 112))),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2)
        };
        var layout = new StackPanel();
        var titleBar = new Border
        {
            Background = FindBrush("HudHeaderBrush", new SolidColorBrush(Color.FromRgb(9, 17, 25))),
            Padding = new Thickness(18, 12, 18, 12),
            Cursor = Cursors.SizeAll,
            Child = new TextBlock
            {
                Text = Title,
                Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
                FontSize = 15,
                FontWeight = FontWeights.SemiBold
            }
        };
        titleBar.MouseLeftButtonDown += (_, eventArgs) =>
        {
            if (eventArgs.ButtonState == MouseButtonState.Pressed)
            {
                DragMove();
            }
        };
        layout.Children.Add(titleBar);

        var body = new StackPanel { Margin = new Thickness(18) };
        body.Children.Add(new TextBlock
        {
            Text = "当前 SCM 账号尚未设置 StarBridge 兼容身份。请选择与你实际情况一致的方式。",
            Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
            TextWrapping = TextWrapping.Wrap,
            LineHeight = 20,
            Margin = new Thickness(0, 0, 0, 16)
        });
        body.Children.Add(CreateChoiceButton(
            "关联已有 StarBridge 账号",
            "保留原舰队、好友、聊天、房间和历史数据。",
            IdentityLinkChoice.LinkExisting,
            true));
        body.Children.Add(CreateChoiceButton(
            "我没有旧账号，创建兼容档案",
            "创建一个不可单独登录的内部档案，用于尚未迁移的旧业务。",
            IdentityLinkChoice.CreateCompatibilityAccount,
            false));

        var laterButton = new Button
        {
            Content = "暂不处理",
            MinWidth = 92,
            Height = 32,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(0, 8, 0, 0),
            IsCancel = true
        };
        if (TryFindResource("SecondaryButton") is Style laterStyle)
        {
            laterButton.Style = laterStyle;
        }
        laterButton.Click += (_, _) => Complete(IdentityLinkChoice.Later);
        body.Children.Add(laterButton);
        layout.Children.Add(body);
        root.Child = layout;
        return root;
    }

    private Button CreateChoiceButton(
        string title,
        string detail,
        IdentityLinkChoice choice,
        bool primary)
    {
        var content = new StackPanel();
        content.Children.Add(new TextBlock
        {
            Text = title,
            FontWeight = FontWeights.SemiBold,
            TextWrapping = TextWrapping.Wrap
        });
        content.Children.Add(new TextBlock
        {
            Text = detail,
            Opacity = 0.78,
            Margin = new Thickness(0, 3, 0, 0),
            TextWrapping = TextWrapping.Wrap
        });
        var button = new Button
        {
            Content = content,
            MinHeight = 62,
            HorizontalContentAlignment = HorizontalAlignment.Left,
            Padding = new Thickness(14, 10, 14, 10),
            Margin = new Thickness(0, 0, 0, 10),
            IsDefault = primary
        };
        if (TryFindResource(primary ? "PrimaryButton" : "SecondaryButton") is Style style)
        {
            button.Style = style;
        }
        button.Click += (_, _) => Complete(choice);
        return button;
    }

    private void Complete(IdentityLinkChoice choice)
    {
        Choice = choice;
        DialogResult = true;
        Close();
    }

    private Brush FindBrush(string key, Brush fallback) => TryFindResource(key) as Brush ?? fallback;
}
