using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

internal static class MainWindowPlacementService
{
    private const double WorkAreaMargin = 8;

    internal static void FitInitialWindow(Window window)
    {
        if (window.WindowState != WindowState.Normal || !TryGetWorkingArea(window, out var workingArea))
        {
            return;
        }

        var requested = ReadWindowBounds(window);
        Apply(window, MainWindowPlacementPolicy.FitAndCenter(requested, workingArea, WorkAreaMargin));
    }

    internal static void EnsureVisible(Window window)
    {
        if (window.WindowState != WindowState.Normal || !TryGetWorkingArea(window, out var workingArea))
        {
            return;
        }

        var requested = ReadWindowBounds(window);
        Apply(window, MainWindowPlacementPolicy.EnsureVisible(requested, workingArea, WorkAreaMargin));
    }

    private static AppWindowBounds ReadWindowBounds(Window window)
    {
        var width = double.IsFinite(window.Width) && window.Width > 0
            ? window.Width
            : Math.Max(window.ActualWidth, window.MinWidth);
        var height = double.IsFinite(window.Height) && window.Height > 0
            ? window.Height
            : Math.Max(window.ActualHeight, window.MinHeight);
        var left = double.IsFinite(window.Left) ? window.Left : 0;
        var top = double.IsFinite(window.Top) ? window.Top : 0;
        return new AppWindowBounds(left, top, width, height);
    }

    private static bool TryGetWorkingArea(Window window, out AppWindowBounds workingArea)
    {
        var handle = new WindowInteropHelper(window).Handle;
        if (handle == IntPtr.Zero)
        {
            workingArea = default;
            return false;
        }

        var screen = WinForms.Screen.FromHandle(handle);
        var dpi = VisualTreeHelper.GetDpi(window);
        var scaleX = dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1;
        var scaleY = dpi.DpiScaleY > 0 ? dpi.DpiScaleY : 1;
        var area = screen.WorkingArea;
        workingArea = new AppWindowBounds(
            area.Left / scaleX,
            area.Top / scaleY,
            area.Width / scaleX,
            area.Height / scaleY);
        return workingArea.Width > 0 && workingArea.Height > 0;
    }

    private static void Apply(Window window, AppWindowBounds bounds)
    {
        if (bounds.Width <= 0 || bounds.Height <= 0)
        {
            return;
        }

        // On compact or scaled displays, keeping the window operable is more important than
        // preserving a desktop-size minimum that cannot physically fit the monitor.
        window.MinWidth = Math.Min(window.MinWidth, bounds.Width);
        window.MinHeight = Math.Min(window.MinHeight, bounds.Height);
        window.Width = bounds.Width;
        window.Height = bounds.Height;
        window.Left = bounds.Left;
        window.Top = bounds.Top;
    }
}
