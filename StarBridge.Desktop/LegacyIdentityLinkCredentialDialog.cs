namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using StarBridge.HostRuntime.Auth;
using Brushes = System.Windows.Media.Brushes;

internal sealed class LegacyIdentityLinkCredentialDialog : Window
{
    private readonly TextBox _accountNameBox;
    private readonly PasswordBox _passwordBox;
    private readonly TextBlock _validationText;

    private LegacyIdentityLinkCredentialDialog(string? initialAccountName)
    {
        Title = "关联旧 StarBridge 账号";
        Width = 460;
        MinWidth = 420;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;

        _accountNameBox = new TextBox
        {
            Text = initialAccountName ?? "",
            Height = 36,
            Margin = new Thickness(0, 6, 0, 14),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        _passwordBox = new PasswordBox
        {
            Height = 36,
            Margin = new Thickness(0, 6, 0, 8),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        _validationText = new TextBlock
        {
            Foreground = FindBrush("DangerBrush", Brushes.OrangeRed),
            Margin = new Thickness(0, 0, 0, 8),
            Visibility = Visibility.Collapsed
        };

        Content = BuildContent();
        Loaded += (_, _) =>
        {
            if (string.IsNullOrWhiteSpace(_accountNameBox.Text))
            {
                _accountNameBox.Focus();
            }
            else
            {
                _passwordBox.Focus();
            }
        };
        Closed += (_, _) => _passwordBox.Clear();
        PreviewKeyDown += (_, eventArgs) =>
        {
            if (eventArgs.Key == Key.Escape)
            {
                DialogResult = false;
                Close();
                eventArgs.Handled = true;
            }
        };
    }

    private LegacyIdentityLinkPasswordCredential? Result { get; set; }

    public static LegacyIdentityLinkPasswordCredential? Show(Window owner, string? initialAccountName)
    {
        var dialog = new LegacyIdentityLinkCredentialDialog(initialAccountName) { Owner = owner };
        return dialog.ShowDialog() == true ? dialog.Result : null;
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
        body.Children.Add(CreateLabel("旧账号名或邮箱"));
        body.Children.Add(_accountNameBox);
        body.Children.Add(CreateLabel("旧账号密码"));
        body.Children.Add(_passwordBox);
        body.Children.Add(_validationText);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right
        };
        var cancelButton = CreateButton("取消", false);
        cancelButton.Click += (_, _) =>
        {
            DialogResult = false;
            Close();
        };
        buttons.Children.Add(cancelButton);
        var confirmButton = CreateButton("验证并关联", true);
        confirmButton.Click += (_, _) => Submit();
        buttons.Children.Add(confirmButton);
        body.Children.Add(buttons);
        layout.Children.Add(body);
        root.Child = layout;
        return root;
    }

    private void Submit()
    {
        var accountName = _accountNameBox.Text.Trim();
        var password = _passwordBox.Password;
        if (string.IsNullOrWhiteSpace(accountName) || string.IsNullOrWhiteSpace(password))
        {
            _validationText.Text = "请输入旧账号名或邮箱和密码。";
            _validationText.Visibility = Visibility.Visible;
            return;
        }

        Result = new LegacyIdentityLinkPasswordCredential(accountName, password);
        DialogResult = true;
        Close();
    }

    private TextBlock CreateLabel(string text) => new()
    {
        Text = text,
        Foreground = FindBrush("MutedTextBrush", Brushes.LightSteelBlue)
    };

    private Button CreateButton(string text, bool primary)
    {
        var button = new Button
        {
            Content = text,
            MinWidth = primary ? 106 : 78,
            Height = 32,
            Margin = new Thickness(8, 0, 0, 0),
            IsDefault = primary,
            IsCancel = !primary
        };
        if (TryFindResource(primary ? "PrimaryButton" : "SecondaryButton") is Style style)
        {
            button.Style = style;
        }

        return button;
    }

    private Brush FindBrush(string key, Brush fallback) => TryFindResource(key) as Brush ?? fallback;
}
