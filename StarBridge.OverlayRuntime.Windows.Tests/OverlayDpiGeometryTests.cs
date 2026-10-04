using System.Reflection;
using System.Windows;
using StarBridge.Core.Presence;
namespace StarBridge.Desktop.Tests;

internal static class OverlayDpiGeometryTests
{
    internal static void RunAll()
    {
        foreach (var scale in new[] { 1d, 1.25, 1.5, 2d })
        {
            var window = new OverlayCompositionHudWindow(new([]), [], [],
                OverlayDisplaySettings.Default, OverlayRosterSelectionSettings.Default, "en", false,
                new(null, null, null, null, null, null), PlayerPresenceKind.AppOnline, "",
                new Rect(-2560 / scale, 0, 2560 / scale, 1440 / scale),
                OverlayStartupTransitionContext.ForLanguage("en"), OverlaySceneContext.Local(OverlayScenePreference.Auto), scale);
            try
            {
                typeof(OverlayCompositionHudWindow).GetMethod("ResolveDeviceBounds", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(window, null);
                int Read(string name) => (int)typeof(OverlayCompositionHudWindow).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(window)!;
                if (Read("_pixelWidth") != 2560 || Read("_pixelHeight") != 1440 || Read("_left") != -2560)
                    throw new Exception($"Headless Host at {scale * 100}% must preserve physical monitor bounds; actual {Read("_pixelWidth")}x{Read("_pixelHeight")}");
            }
            finally { window.Close(); }
        }
    }
}
