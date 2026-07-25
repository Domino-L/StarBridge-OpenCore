using System.Runtime.InteropServices;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

internal sealed class PlayerActivityToastManager : IDisposable
{
    private const int MaximumVisibleToasts = 3;
    private const uint NoActivate = 0x0010;
    private const uint NoZOrder = 0x0004;
    private readonly List<PlayerActivityToastWindow> _active = [];
    private DesktopNotificationPosition _position = DesktopNotificationPosition.BottomRight;
    private WinForms.Screen? _screen;

    public event EventHandler<PlayerActivityDesktopNotification>? ProfileRequested;

    public void Show(
        PlayerActivityDesktopNotification notification,
        DesktopNotificationPosition position,
        Window contextWindow)
    {
        while (_active.Count >= MaximumVisibleToasts)
        {
            var oldest = _active[^1];
            _active.RemoveAt(_active.Count - 1);
            oldest.Dismiss(immediate: true);
        }

        _position = position;
        _screen = ResolveScreen(contextWindow);
        var toast = new PlayerActivityToastWindow(notification);
        toast.ProfileRequested += Toast_ProfileRequested;
        toast.Closed += Toast_Closed;
        _active.Insert(0, toast);
        toast.Show();
        Reposition();
        toast.BeginEnter(position is DesktopNotificationPosition.TopRight or DesktopNotificationPosition.BottomRight);
    }

    public void Dispose()
    {
        foreach (var toast in _active.ToArray())
        {
            toast.ProfileRequested -= Toast_ProfileRequested;
            toast.Closed -= Toast_Closed;
            toast.Dismiss(immediate: true);
        }

        _active.Clear();
    }

    private void Toast_ProfileRequested(object? sender, PlayerActivityDesktopNotification notification) =>
        ProfileRequested?.Invoke(this, notification);

    private void Toast_Closed(object? sender, EventArgs e)
    {
        if (sender is not PlayerActivityToastWindow toast)
        {
            return;
        }

        toast.ProfileRequested -= Toast_ProfileRequested;
        toast.Closed -= Toast_Closed;
        if (_active.Remove(toast))
        {
            Reposition();
        }
    }

    private void Reposition()
    {
        if (_screen is null)
        {
            return;
        }

        var area = _screen.WorkingArea;
        var workArea = new DesktopToastWorkArea(area.Left, area.Top, area.Width, area.Height);
        for (var index = 0; index < _active.Count; index++)
        {
            var toast = _active[index];
            var handle = new WindowInteropHelper(toast).Handle;
            var dpi = VisualTreeHelper.GetDpi(toast);
            var width = Math.Max(1, (int)Math.Round(toast.Width * dpi.DpiScaleX));
            var height = Math.Max(1, (int)Math.Round(toast.Height * dpi.DpiScaleY));
            var point = DesktopToastPlacement.Resolve(workArea, width, height, _position, index);
            SetWindowPos(handle, IntPtr.Zero, point.X, point.Y, width, height, NoActivate | NoZOrder);
        }
    }

    private static WinForms.Screen ResolveScreen(Window contextWindow)
    {
        if (contextWindow.IsVisible && contextWindow.WindowState != WindowState.Minimized)
        {
            var handle = new WindowInteropHelper(contextWindow).Handle;
            if (handle != IntPtr.Zero)
            {
                return WinForms.Screen.FromHandle(handle);
            }
        }

        return WinForms.Screen.FromPoint(WinForms.Cursor.Position);
    }

    [DllImport("user32.dll", SetLastError = true)]
    private static extern bool SetWindowPos(
        IntPtr handle,
        IntPtr insertAfter,
        int x,
        int y,
        int width,
        int height,
        uint flags);
}
