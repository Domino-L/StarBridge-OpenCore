using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using KeyEventArgs = System.Windows.Input.KeyEventArgs;

namespace StarBridge.Desktop;

public partial class InGameProfileWindow : Window
{
    private readonly string _profileKey;
    private bool _allowPermanentClose;
    private PersonalProfileSurfaceLease? _surfaceLease;

    internal event EventHandler? MenuCloseRequested;
    internal event EventHandler? ToolDeactivated;
    internal event EventHandler? ToolHidden;

    internal InGameProfileWindow(InGameProfileTarget target)
    {
        _profileKey = target.Key;
        InitializeComponent();
        InGameToolWindowBehavior.PreventSnapMaximize(this);
        ApplyIdentity(target);
    }

    internal string ProfileKey => _profileKey;

    internal void ShowForMenu()
    {
        if (WindowState == WindowState.Minimized)
        {
            WindowState = WindowState.Normal;
        }

        Show();
        Activate();
    }

    internal void AttachProfileSurface(
        TabItem sourceTab,
        IEnumerable<FrameworkElement> overlays,
        Action? released)
    {
        DetachProfileSurface();
        _surfaceLease = PersonalProfileSurfaceLease.Attach(
            sourceTab,
            ProfileSurfaceHost,
            overlays,
            released);
        ProfileLoadingPanel.Visibility = Visibility.Collapsed;
    }

    internal void DetachProfileSurface()
    {
        _surfaceLease?.Dispose();
        _surfaceLease = null;
        ProfileLoadingPanel.Visibility = Visibility.Visible;
    }

    internal void CloseForApplication()
    {
        DetachProfileSurface();
        _allowPermanentClose = true;
        Close();
    }

    internal void HideForMenu()
    {
        DetachProfileSurface();
        if (IsVisible)
        {
            Hide();
        }
    }

    private void ApplyIdentity(InGameProfileTarget target)
    {
        WindowTitleText.Text = target.IsOwner
            ? "我的个人资料"
            : $"{target.Callsign} 的个人资料";
        WindowSubtitleText.Text = target.IsOwner
            ? "编辑与应用内完全相同的个人资料"
            : "查看该用户公开的个人资料";
    }

    private void Header_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
    {
        if (e.ButtonState == MouseButtonState.Pressed)
        {
            DragMove();
        }
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) =>
        HideForUser();

    private void Window_PreviewKeyDown(object sender, KeyEventArgs e)
    {
        if (e.Key != Key.Escape)
        {
            return;
        }

        e.Handled = true;
        MenuCloseRequested?.Invoke(this, EventArgs.Empty);
    }

    private void Window_Deactivated(object? sender, EventArgs e) =>
        ToolDeactivated?.Invoke(this, EventArgs.Empty);

    private void HideForUser()
    {
        HideForMenu();
        ToolHidden?.Invoke(this, EventArgs.Empty);
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        if (!_allowPermanentClose)
        {
            e.Cancel = true;
            HideForUser();
        }

        base.OnClosing(e);
    }
}
