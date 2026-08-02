using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Runtime.CompilerServices;
using WinForms = System.Windows.Forms;

namespace StarBridge.Desktop;

internal static class MainWindowPlacementService
{
    private const double WorkAreaMargin = 8;
    private static readonly ConditionalWeakTable<Window, DesignMinimum>
        DesignMinimums = new();

    internal static void FitInitialWindow(Window window)
        => FitInitialWindow(window, window);

    internal static void FitInitialWindow(Window window, Window placementReference)
    {
        if (window.WindowState != WindowState.Normal ||
            !TryGetWorkingArea(placementReference, out var workingArea))
        {
            return;
        }

        var requested = ReadWindowBounds(window);
        Apply(window, MainWindowPlacementPolicy.FitAndCenter(requested, workingArea, WorkAreaMargin));
    }

    internal static void EnsureVisible(Window window)
        => EnsureVisible(window, window);

    internal static void EnsureVisible(Window window, Window placementReference)
    {
        if (window.WindowState != WindowState.Normal ||
            !TryGetWorkingArea(placementReference, out var workingArea))
        {
            return;
        }

        var requested = ReadWindowBounds(window);
        Apply(window, MainWindowPlacementPolicy.EnsureVisible(requested, workingArea, WorkAreaMargin));
    }

    internal static void Restore(
        Window window,
        AppWindowBounds saved,
        Window placementReference)
    {
        if (window.WindowState != WindowState.Normal ||
            !TryGetWorkingArea(placementReference, out var workingArea))
        {
            return;
        }

        Apply(
            window,
            MainWindowPlacementPolicy.EnsureVisible(
                saved,
                workingArea,
                WorkAreaMargin));
    }

    internal static AppWindowBounds ReadBounds(Window window) =>
        ReadWindowBounds(window);

    internal static void SnapToWorkingArea(
        Window window,
        Window placementReference,
        double distance)
    {
        if (window.WindowState != WindowState.Normal ||
            distance <= 0 ||
            !TryGetWorkingArea(placementReference, out var workingArea))
        {
            return;
        }

        var requested = ReadWindowBounds(window);
        var left = requested.Left;
        var top = requested.Top;
        var workingRight = workingArea.Left + workingArea.Width;
        var workingBottom = workingArea.Top + workingArea.Height;
        if (Math.Abs(requested.Left - workingArea.Left) <= distance)
        {
            left = workingArea.Left;
        }
        else if (Math.Abs(
                     requested.Left + requested.Width - workingRight) <=
                 distance)
        {
            left = workingRight - requested.Width;
        }

        if (Math.Abs(requested.Top - workingArea.Top) <= distance)
        {
            top = workingArea.Top;
        }
        else if (Math.Abs(
                     requested.Top + requested.Height - workingBottom) <=
                 distance)
        {
            top = workingBottom - requested.Height;
        }

        if (Math.Abs(left - requested.Left) < 0.1 &&
            Math.Abs(top - requested.Top) < 0.1)
        {
            return;
        }

        Apply(
            window,
            requested with
            {
                Left = left,
                Top = top
            });
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

        var designMinimum = DesignMinimums.GetValue(
            window,
            static candidate => new DesignMinimum(candidate.MinWidth, candidate.MinHeight));
        // On compact or scaled displays, keeping the window operable is more important than
        // preserving a desktop-size minimum that cannot physically fit the monitor. Restore
        // the design minimum when the same retained window returns to a larger monitor.
        window.MinWidth = Math.Min(designMinimum.Width, bounds.Width);
        window.MinHeight = Math.Min(designMinimum.Height, bounds.Height);
        window.Width = bounds.Width;
        window.Height = bounds.Height;
        window.Left = bounds.Left;
        window.Top = bounds.Top;
    }

    private sealed record DesignMinimum(double Width, double Height);
}
