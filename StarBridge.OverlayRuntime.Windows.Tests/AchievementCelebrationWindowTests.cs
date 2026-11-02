using StarBridge.OverlayRuntime.Windows;
using System.Runtime.InteropServices;

internal static class AchievementCelebrationWindowTests
{
    // Agent-run probe of the real Show path. Elapsed zero keeps the artwork
    // clipped; no audio, cloud award, account access or client restart.
    internal static void RunShowLifecycleProbe()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
            try
            {
                var foreground = GetForegroundWindow();
                var screen = System.Windows.Forms.Screen.FromHandle(foreground);
                var card = new AchievementCelebrationCard("zh-CN", false, false);
                using var surface = NativeAchievementCelebrationRuntime.CreateHiddenSurface(card, screen.DeviceName);
                surface.Advance(0, 0);
                surface.Show();
                System.Windows.Threading.Dispatcher.CurrentDispatcher.Invoke(() => { },
                    System.Windows.Threading.DispatcherPriority.ApplicationIdle);
                Require(surface.IsVisible && IsWindowVisible(surface.Handle), "Production Show makes the native surface visible");
                Require(GetWindowRect(surface.Handle, out var rect), "Shown native HWND has bounds");
                var expected = AchievementCelebrationPlacement.ForWorkArea(screen.WorkingArea, GetDpiForWindow(surface.Handle)).Bounds;
                var actual = System.Drawing.Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
                Require(actual == expected, $"Production Show preserves bottom-right placement: expected {expected}, actual {actual}");
                Require(GetForegroundWindow() == foreground, "Production Show never steals foreground focus");
                Require(card.ActualWidth > 0 && card.ActualHeight > 0, "Shown surface measures its real card");
                Console.WriteLine("PASS achievement actual Show: visible HWND, correct physical placement, measured card and unchanged focus");
            }
            catch (Exception error) { failure = error; }
            finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw new InvalidOperationException("Achievement Show lifecycle probe failed", failure);
    }

    internal static void Run()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
            try
            {
                var foreground = GetForegroundWindow();
                var screens = System.Windows.Forms.Screen.AllScreens;
                foreach (var screen in screens)
                {
                    var card = new AchievementCelebrationCard("zh-CN", false, false);
                    var surface = NativeAchievementCelebrationRuntime.CreateHiddenSurface(card, screen.DeviceName);
                    var hwnd = surface.Handle;
                    try
                    {
                        Require(!surface.IsVisible && !IsWindowVisible(hwnd), "Lifecycle test must never show a window");
                        Require(GetWindowRect(hwnd, out var rect), "Hidden native HWND has physical bounds");
                        var dpi = GetDpiForWindow(hwnd);
                        var rasterScale = System.Windows.Interop.HwndSource.FromHwnd(hwnd).CompositionTarget.TransformToDevice.M11;
                        Require(Math.Abs(rasterScale - dpi / 96d) < .001,
                            $"WPF raster scale must match the native window DPI, not stretch a low-resolution surface: native {dpi}, WPF {rasterScale}");
                        var expected = AchievementCelebrationPlacement.ForWorkArea(screen.WorkingArea, dpi).Bounds;
                        var actual = System.Drawing.Rectangle.FromLTRB(rect.Left, rect.Top, rect.Right, rect.Bottom);
                        Require(actual == expected, "Production HWND uses the target screen DPI and actual work-area edge");
                        Require(actual.Right == screen.WorkingArea.Right && actual.Bottom == screen.WorkingArea.Bottom,
                            "Card is flush to the right edge and taskbar work-area boundary");
                        var style = GetWindowLongPtr(hwnd, -20).ToInt64();
                        Require((style & (0x08000000L | 0x80L | 0x20L)) == (0x08000000L | 0x80L | 0x20L),
                            "Native card preserves NOACTIVATE, TOOLWINDOW and pointer-pass-through styles");
                        surface.Advance(1400, 0); surface.UpdatePosition();
                        surface.ApplyPointerPosition(new(actual.Left + actual.Width / 2, actual.Top + actual.Height / 2));
                        Require(surface.PointerOpacity == .5 && card.Opacity == 1,
                            "Hover dims the complete native window without replacing the card animation opacity");
                        Require(GetWindowLongPtr(hwnd, -20).ToInt64() == style,
                            "Hover preserves passive click-through native styles");
                        surface.Advance(card.LifetimeMilliseconds - 90, 0);
                        surface.ApplyPointerPosition(new(actual.Left, actual.Top));
                        Require(surface.PointerOpacity == .5 && Math.Abs(card.Opacity - .5) < .001,
                            "Hover and animated exit opacity compose independently");
                        surface.ApplyPointerPosition(new(actual.Right, actual.Bottom - 1));
                        Require(surface.PointerOpacity == 1, "Leaving through the right boundary restores full opacity");
                        surface.ApplyPointerPosition(null);
                        Require(surface.PointerOpacity == 1, "Unavailable cursor restores full opacity");
                        Require(GetForegroundWindow() == foreground, "Hidden creation/render/position must not steal foreground focus");
                    }
                    finally { surface.Dispose(); }
                    Require(!IsWindow(hwnd), "Disposal destroys the native HWND instead of leaving a hidden topmost window");
                }
                Console.WriteLine($"PASS achievement hidden HWND: {screens.Length} physical monitors, DPI placement, passive style, focus and disposal");
            }
            catch (Exception error) { failure = error; }
            finally { if (previous != IntPtr.Zero) SetThreadDpiAwarenessContext(previous); }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw new InvalidOperationException("Achievement native window regression failed", failure);
    }
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { internal int Left, Top, Right, Bottom; }
    [DllImport("user32.dll")] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
    [DllImport("user32.dll")] private static extern IntPtr GetForegroundWindow();
    [DllImport("user32.dll")] private static extern uint GetDpiForWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll", EntryPoint = "GetWindowLongPtrW")] private static extern IntPtr GetWindowLongPtr(IntPtr hwnd, int index);
}
