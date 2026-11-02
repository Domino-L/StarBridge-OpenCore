using System.Runtime.InteropServices;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private bool _protectPreviewOnCreate;
    internal void PreparePreviewControlProtection()
    {
        if (_source is not null || _isVisible) throw new InvalidOperationException("Preview already shown.");
        _protectPreviewOnCreate = true;
    }
    private void ProtectCreatedPreviewWindow(IntPtr hwnd)
    {
        if (_protectPreviewOnCreate) OverlayPreviewControlRegion.Hide(hwnd);
    }
}

/// Clips only the temporary HUD HWND. It never changes saved module geometry,
/// application stacking, input hooks or any other process's window.
internal static class OverlayPreviewControlRegion
{
    private const int Difference = 4;
    internal static void Hide(IntPtr hwnd) => Apply(hwnd, null, []);
    internal static void Apply(IntPtr hwnd, OverlayPreviewClientViewport? viewport,
        IReadOnlyList<OverlayPreviewControlArea> areas)
    {
        var previous = SetThreadDpiAwarenessContext(new IntPtr(-4));
        if (previous == IntPtr.Zero) throw new InvalidOperationException("Preview physical coordinates unavailable.");
        try { ApplyPhysical(hwnd, viewport, areas); }
        finally { SetThreadDpiAwarenessContext(previous); }
    }
    private static void ApplyPhysical(IntPtr hwnd, OverlayPreviewClientViewport? viewport,
        IReadOnlyList<OverlayPreviewControlArea> areas)
    {
        if (!GetWindowRect(hwnd, out var bounds)) throw new InvalidOperationException("Preview window unavailable.");
        var region = viewport is null ? CreateRectRgn(0, 0, 0, 0) :
            CreateRectRgn(0, 0, bounds.Right - bounds.Left, bounds.Bottom - bounds.Top);
        if (region == IntPtr.Zero) throw new InvalidOperationException("Preview region unavailable.");
        try
        {
            if (viewport is { } client)
            {
                if (!client.IsValid || areas.Count > 16 || areas.Any(a => !a.IsValid))
                    throw new FormatException("Invalid control areas.");
                foreach (var area in areas)
                {
                    // Physical client bounds already account for the actual DPI.
                    // Round outward so a fractional edge cannot reveal a glow.
                    var left = (int)Math.Floor(client.X + area.X * client.Width - bounds.Left);
                    var top = (int)Math.Floor(client.Y + area.Y * client.Height - bounds.Top);
                    var right = (int)Math.Ceiling(client.X + (area.X + area.Width) * client.Width - bounds.Left);
                    var bottom = (int)Math.Ceiling(client.Y + (area.Y + area.Height) * client.Height - bounds.Top);
                    var hole = CreateRectRgn(left, top, right, bottom);
                    if (hole == IntPtr.Zero) throw new InvalidOperationException("Preview region unavailable.");
                    try
                    {
                        if (CombineRgn(region, region, hole, Difference) == 0)
                            throw new InvalidOperationException("Preview region unavailable.");
                    }
                    finally { DeleteObject(hole); }
                }
            }
            if (SetWindowRgn(hwnd, region, true) == 0) throw new InvalidOperationException("Preview region unavailable.");
            region = IntPtr.Zero; // Successful SetWindowRgn transfers ownership to Windows.
        }
        finally { if (region != IntPtr.Zero) DeleteObject(region); }
    }
    [StructLayout(LayoutKind.Sequential)] private struct NativeRect { public int Left, Top, Right, Bottom; }
    [DllImport("user32.dll", SetLastError = true)] private static extern bool GetWindowRect(IntPtr hwnd, out NativeRect bounds);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern IntPtr CreateRectRgn(int left, int top, int right, int bottom);
    [DllImport("gdi32.dll", SetLastError = true)] private static extern int CombineRgn(IntPtr destination, IntPtr first, IntPtr second, int mode);
    [DllImport("gdi32.dll")] private static extern bool DeleteObject(IntPtr value);
    [DllImport("user32.dll", SetLastError = true)] private static extern int SetWindowRgn(IntPtr hwnd, IntPtr region, bool redraw);
    [DllImport("user32.dll", SetLastError = true)] private static extern IntPtr SetThreadDpiAwarenessContext(IntPtr context);
}
