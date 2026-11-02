using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

/// Native composition supplies the currently trusted primary-window lease.
/// Bridge payloads cannot choose this window, its PID, or any screen rectangle.
internal sealed class OverlayPreviewClientViewportResolver(Func<(IntPtr Window, int ClientProcessId, bool IsCurrent)> registered)
{
    internal OverlayPreviewClientViewport? Resolve()
    {
        var lease = registered();
        if (!lease.IsCurrent || lease.Window == IntPtr.Zero || lease.ClientProcessId <= 0 ||
            !IsWindow(lease.Window) || !IsWindowVisible(lease.Window) || IsIconic(lease.Window) ||
            GetAncestor(lease.Window, 2) != lease.Window) return null;
        GetWindowThreadProcessId(lease.Window, out var pid);
        if (pid != lease.ClientProcessId) return null;
        // Query physical pixels rather than DPI-virtualized logical coordinates.
        // This changes only this call's thread context, never display settings.
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous == IntPtr.Zero) return null;
        try
        {
            if (!GetClientRect(lease.Window, out var rect)) return null;
            var point = new NativePoint();
            if (!ClientToScreen(lease.Window, ref point)) return null;
            var result = new OverlayPreviewClientViewport(point.X, point.Y,
                rect.Right - rect.Left, rect.Bottom - rect.Top);
            return result.IsValid && registered() == lease ? result : null;
        }
        finally { SetThreadDpiAwarenessContext(previous); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [StructLayout(LayoutKind.Sequential)] private struct NativePoint { public int X, Y; }
    [DllImport("user32.dll")] private static extern bool IsWindow(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsWindowVisible(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern bool IsIconic(IntPtr hwnd);
    [DllImport("user32.dll")] private static extern IntPtr GetAncestor(IntPtr hwnd, uint flags);
    [DllImport("user32.dll")] private static extern uint GetWindowThreadProcessId(IntPtr hwnd, out uint pid);
    [DllImport("user32.dll")] private static extern bool GetClientRect(IntPtr hwnd, out NativeRect rect);
    [DllImport("user32.dll")] private static extern bool ClientToScreen(IntPtr hwnd, ref NativePoint point);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
