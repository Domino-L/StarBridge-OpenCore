namespace StarBridge.Desktop;

// Owner-to-renderer snapshot: the pixels and drawing DPI must travel with the
// same immutable layout frame, never be re-read from a newer owner refresh.
internal readonly record struct OverlayCompositionViewport(
    int Left, int Top, int Width, int Height, double DpiScaleX, double DpiScaleY)
{
    internal static OverlayCompositionViewport FromDips(
        double left, double top, double width, double height, double dpiScaleX, double dpiScaleY)
    {
        if (!double.IsFinite(left) || !double.IsFinite(top) ||
            !double.IsFinite(width) || width <= 0 || !double.IsFinite(height) || height <= 0 ||
            !double.IsFinite(dpiScaleX) || dpiScaleX <= 0 || !double.IsFinite(dpiScaleY) || dpiScaleY <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(width), "Composition viewport must be finite with positive extent and DPI.");
        }

        return new(
            checked((int)Math.Floor(left * dpiScaleX)),
            checked((int)Math.Floor(top * dpiScaleY)),
            checked((int)Math.Ceiling(Math.Max(1, width) * dpiScaleX)),
            checked((int)Math.Ceiling(Math.Max(1, height) * dpiScaleY)),
            dpiScaleX, dpiScaleY);
    }

    // Windows treats a topmost window that covers a whole monitor as a
    // full-screen app (SHQueryUserNotificationState reports QUNS_BUSY), and
    // Windows 11 then turns on Do Not Disturb. The click-through overlay stops
    // one physical row short of its monitor so it never matches that rule.
    // Rounding, not the coverage ceiling, so DPI error cannot add the row back.
    internal static OverlayCompositionViewport ShortOfFullScreen(
        double left, double top, double width, double height, double dpiScaleX, double dpiScaleY)
    {
        var viewport = FromDips(left, top, width, height, dpiScaleX, dpiScaleY);
        var pixelTop = checked((int)Math.Round(top * dpiScaleY));
        var pixelBottom = checked((int)Math.Round((top + height) * dpiScaleY));
        return viewport with { Top = pixelTop, Height = Math.Max(1, pixelBottom - pixelTop - 1) };
    }
}
