using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

public partial class TrayQuickPanel : Window
{
    private const uint SetWindowPosNoSize = 0x0001;
    private const uint SetWindowPosNoZOrder = 0x0004;
    private const uint SetWindowPosNoActivate = 0x0010;
    private bool _ignoreNextDeactivation;
    private bool _isClosing;

    public TrayQuickPanel()
    {
        InitializeComponent();
    }

    protected override void OnClosing(CancelEventArgs e)
    {
        _isClosing = true;
        base.OnClosing(e);
        if (e.Cancel)
        {
            _isClosing = false;
        }
    }

    internal void ShowNearTrayIcon()
    {
        RefreshState();
        if (!IsVisible)
        {
            Opacity = 0;
            Show();
        }

        UpdateLayout();
        PositionNearTaskbar();
        Opacity = 1;
        Activate();
    }

    internal void RefreshState()
    {
        var state = (System.Windows.Application.Current as App)?.GetTrayQuickPanelState() ??
                    TrayQuickPanelState.Unavailable;
        VersionText.Text = state.VersionText;
        RuntimeStatusText.Text = state.RuntimeStatusText;
        RuntimeStatusDot.Fill = PlayerPresencePresentation.Brush(state.Presence);
        OverlayStatusText.Text = state.OverlayStatusText;
        OverlayStatusText.Foreground = new SolidColorBrush((System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(
            state.IsOverlayRunning ? "#86E5AA" : "#AFC4D0"));
        ToggleOverlayButton.Content = state.OverlayActionText;
        ToggleOverlayButton.Tag = state.IsOverlayRunning;
        SceneText.Text = state.SceneText;
        TrayAvatarBrush.ImageSource = state.AvatarSource;
        TrayAvatarInitialText.Content = state.AvatarInitial;
        TrayAvatarInitialText.Visibility = state.AvatarSource is null ? Visibility.Visible : Visibility.Collapsed;
    }

    private void PositionNearTaskbar()
    {
        var handle = new WindowInteropHelper(this).Handle;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        var cursor = WinForms.Cursor.Position;
        var screen = WinForms.Screen.FromPoint(cursor);
        var dpi = GetDpiForWindow(handle);
        var scale = dpi > 0 ? dpi / 96d : 1d;
        var panelSize = new System.Drawing.Size(
            Math.Max(1, (int)Math.Ceiling(ActualWidth * scale)),
            Math.Max(1, (int)Math.Ceiling(ActualHeight * scale)));
        var position = TrayQuickPanelPlacement.Resolve(
            screen.Bounds,
            screen.WorkingArea,
            cursor,
            panelSize,
            Math.Max(6, (int)Math.Round(8 * scale)));
        SetWindowPos(
            handle,
            IntPtr.Zero,
            position.X,
            position.Y,
            0,
            0,
            SetWindowPosNoSize | SetWindowPosNoZOrder | SetWindowPosNoActivate);
    }

    private void ToggleOverlayButton_Click(object sender, RoutedEventArgs e)
    {
        _ignoreNextDeactivation = true;
        (System.Windows.Application.Current as App)?.ToggleOverlayFromTray();
        RefreshState();
        Dispatcher.BeginInvoke(new Action(() => _ignoreNextDeactivation = false));
    }

    private void OpenApplicationButton_Click(object sender, RoutedEventArgs e)
    {
        RequestClose();
        (System.Windows.Application.Current as App)?.ShowMainWindowFromBackground();
    }

    private void OpenOverlaySettingsButton_Click(object sender, RoutedEventArgs e)
    {
        RequestClose();
        (System.Windows.Application.Current as App)?.OpenOverlaySettingsFromTray();
    }

    private void ExitApplicationButton_Click(object sender, RoutedEventArgs e)
    {
        RequestClose();
        (System.Windows.Application.Current as App)?.RequestExit();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e) => RequestClose();

    private void TrayQuickPanel_Deactivated(object? sender, EventArgs e)
    {
        if (!_ignoreNextDeactivation)
        {
            RequestClose();
        }
    }

    private void TrayQuickPanel_PreviewKeyDown(object sender, System.Windows.Input.KeyEventArgs e)
    {
        if (e.Key == Key.Escape)
        {
            e.Handled = true;
            RequestClose();
        }
    }

    private void RequestClose()
    {
        if (_isClosing)
        {
            return;
        }

        _isClosing = true;
        try
        {
            Close();
        }
        catch
        {
            _isClosing = false;
            throw;
        }
    }

    [DllImport("user32.dll")]
    private static extern uint GetDpiForWindow(IntPtr window);

    [DllImport("user32.dll")]
    private static extern bool SetWindowPos(
        IntPtr window,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
