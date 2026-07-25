namespace StarBridge.Desktop;

using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using Brushes = System.Windows.Media.Brushes;

internal sealed class StarBridgeTextInputDialog : Window
{
    private readonly TextBox _inputBox;

    private StarBridgeTextInputDialog(string title, string prompt, string initialValue)
    {
        Title = string.IsNullOrWhiteSpace(title) ? "星海舰桥" : title;
        Width = 460;
        MinWidth = 420;
        SizeToContent = SizeToContent.Height;
        WindowStartupLocation = WindowStartupLocation.CenterOwner;
        WindowStyle = WindowStyle.None;
        ResizeMode = ResizeMode.NoResize;
        ShowInTaskbar = false;
        AllowsTransparency = true;
        Background = Brushes.Transparent;
        BorderThickness = new Thickness(0);
        SnapsToDevicePixels = true;

        _inputBox = new TextBox
        {
            Text = initialValue,
            Height = 32,
            Margin = new Thickness(0, 10, 0, 0),
            VerticalContentAlignment = VerticalAlignment.Center
        };
        if (TryFindResource("StarBridgeTextBox") is Style textBoxStyle)
        {
            _inputBox.Style = textBoxStyle;
        }

        Content = BuildChrome(prompt);
        Loaded += (_, _) =>
        {
            _inputBox.Focus();
            _inputBox.SelectAll();
        };
        PreviewKeyDown += (_, e) =>
        {
            if (e.Key == Key.Escape)
            {
                DialogResult = false;
                Close();
                e.Handled = true;
            }
        };
    }

    public string Value => _inputBox.Text.Trim();

    public static string? Show(Window owner, string title, string prompt, string initialValue)
    {
        var dialog = new StarBridgeTextInputDialog(title, prompt, initialValue)
        {
            Owner = owner
        };
        return dialog.ShowDialog() == true ? dialog.Value : null;
    }

    private FrameworkElement BuildChrome(string prompt)
    {
        var root = new Border
        {
            Background = FindBrush("HudGlassBrush", new SolidColorBrush(Color.FromRgb(7, 16, 25))),
            BorderBrush = FindBrush("BorderDefaultBrush", new SolidColorBrush(Color.FromRgb(26, 83, 112))),
            BorderThickness = new Thickness(1),
            CornerRadius = new CornerRadius(2)
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

        titleBar.Children.Add(new Border
        {
            Width = 3,
            Background = FindBrush("AccentBrush", Brushes.DeepSkyBlue)
        });

        var title = new TextBlock
        {
            Text = Title,
            Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
            FontSize = 15,
            FontWeight = FontWeights.SemiBold,
            VerticalAlignment = VerticalAlignment.Center,
            Margin = new Thickness(14, 0, 12, 0),
            TextTrimming = TextTrimming.CharacterEllipsis
        };
        Grid.SetColumn(title, 1);
        titleBar.Children.Add(title);

        var closeButton = CreateButton("X", false);
        closeButton.Width = 36;
        closeButton.MinWidth = 36;
        closeButton.Height = 28;
        closeButton.Margin = new Thickness(0, 7, 8, 7);
        closeButton.Click += (_, _) =>
        {
            DialogResult = false;
            Close();
        };
        Grid.SetColumn(closeButton, 2);
        titleBar.Children.Add(closeButton);

        Grid.SetRow(titleBar, 0);
        grid.Children.Add(titleBar);

        var body = new StackPanel
        {
            Margin = new Thickness(18, 18, 18, 16)
        };
        body.Children.Add(new TextBlock
        {
            Text = prompt,
            Foreground = FindBrush("TextPrimaryBrush", Brushes.AliceBlue),
            FontSize = 13,
            LineHeight = 20,
            TextWrapping = TextWrapping.Wrap
        });
        body.Children.Add(_inputBox);
        Grid.SetRow(body, 1);
        grid.Children.Add(body);

        var buttons = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            HorizontalAlignment = HorizontalAlignment.Right,
            Margin = new Thickness(18, 0, 18, 18)
        };
        var cancel = CreateButton("取消", false);
        cancel.Click += (_, _) =>
        {
            DialogResult = false;
            Close();
        };
        buttons.Children.Add(cancel);

        var ok = CreateButton("确定", true);
        ok.Click += (_, _) =>
        {
            DialogResult = true;
            Close();
        };
        buttons.Children.Add(ok);

        Grid.SetRow(buttons, 2);
        grid.Children.Add(buttons);
        root.Child = grid;
        return root;
    }

    private Button CreateButton(string text, bool primary)
    {
        var button = new Button
        {
            Content = text,
            MinWidth = 78,
            Height = 32,
            Margin = new Thickness(8, 0, 0, 0),
            IsDefault = primary,
            IsCancel = !primary
        };

        var styleKey = primary ? "PrimaryButton" : "SecondaryButton";
        if (TryFindResource(styleKey) is Style style)
        {
            button.Style = style;
        }

        return button;
    }

    private Brush FindBrush(string key, Brush fallback)
    {
        return TryFindResource(key) as Brush ?? fallback;
    }
}
