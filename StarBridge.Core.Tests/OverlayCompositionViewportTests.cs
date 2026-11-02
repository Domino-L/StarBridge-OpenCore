using StarBridge.Desktop;

namespace StarBridge.Core.Tests;

internal static class OverlayCompositionViewportTests
{
    internal static void RunAll()
    {
        static void Check(bool condition, string message)
        {
            if (!condition) throw new InvalidOperationException(message);
        }
        foreach (var scale in new[] { 1d, 1.25, 1.5, 2 })
        {
            var initial = OverlayCompositionViewport.FromDips(-5000 / scale, -5000 / scale, 2560 / scale, 1440 / scale, scale, scale);
            var moved = OverlayCompositionViewport.FromDips(-5200 / scale, -5300 / scale, 2560 / scale, 1440 / scale, scale, scale);
            var resized = OverlayCompositionViewport.FromDips(-5200 / scale, -5300 / scale, 1920 / scale, 1080 / scale, scale, scale);
            Check(initial is { Left: -5000, Top: -5000, Width: 2560, Height: 1440 }, "Initial physical pixels must be converted exactly once");
            Check(moved is { Left: -5200, Top: -5300, Width: 2560, Height: 1440 }, "Movement must not change physical capacity");
            Check(resized is { Left: -5200, Top: -5300, Width: 1920, Height: 1080 }, "Resize must carry the new drawing capacity");
            Check(initial.Left == -5000 && initial.Width == 2560 && initial.DpiScaleX == scale, "Queued old snapshot changed after a newer refresh");
        }
        var asymmetric = OverlayCompositionViewport.FromDips(-1.1, 2.1, 10.1, 20.1, 1.25, 1.5);
        Check(asymmetric is { Left: -2, Top: 3, Width: 13, Height: 31 }, "Origin floors and coverage ceilings must use their own axis DPI");
        foreach (var invalid in new[] { 0d, -1, double.NaN, double.PositiveInfinity })
        {
            try { OverlayCompositionViewport.FromDips(0, 0, 2560, 1440, invalid, 1); throw new InvalidOperationException("Invalid DPI accepted"); }
            catch (ArgumentOutOfRangeException) { }
        }
        try { OverlayCompositionViewport.FromDips(double.NaN, 0, 2560, 1440, 1, 1); throw new InvalidOperationException("Invalid origin accepted"); }
        catch (ArgumentOutOfRangeException) { }
        foreach (var (top, height) in new[] { (0, 1440), (-1440, 1440), (0, 1081), (1080, 1081), (-5000, 2160) })
        {
            foreach (var scale in new[] { 1d, 1.25, 1.5, 1.75, 2 })
            {
                var overlay = OverlayCompositionViewport.ShortOfFullScreen(0, top / scale, 2560 / scale, height / scale, scale, scale);
                Check(overlay.Top >= top && overlay.Top + overlay.Height < top + height,
                    "Topmost overlay must never cover its whole monitor, or Windows turns on Do Not Disturb");
                Check(overlay.Top + overlay.Height == top + height - 1 && overlay.Width >= 2560,
                    "Overlay keeps every row but the last and the full monitor width");
            }
        }
    }
}
