using System.Windows;
using System.Windows.Media;
using StarBridge.Desktop.Theming;
using WpfBrush = System.Windows.Media.Brush;
using WpfColor = System.Windows.Media.Color;

namespace StarBridge.Desktop;

/// <summary>
/// Owns the fixed scene used by both the real in-game menu and its settings preview.
/// Keeping the decision here prevents the preview from drifting into a different
/// colour contract while still allowing its layout to be scaled independently.
/// </summary>
internal static class InGameMenuVisualContext
{
    internal static void Apply(DependencyObject surface) =>
        BridgeSceneContext.ApplyFixed(surface, BridgeSceneKind.Overlay);

    internal static WpfBrush CreateDimBrush(FrameworkElement surface, int percent)
    {
        var token = surface.FindResource("BridgeScrim") as SolidColorBrush
            ?? throw new InvalidOperationException("BridgeScrim must be a solid colour brush.");
        var alpha = (byte)Math.Round(
            Math.Clamp(percent, 0, 100) / 100d * token.Color.A);
        var brush = new SolidColorBrush(WpfColor.FromArgb(
            alpha,
            token.Color.R,
            token.Color.G,
            token.Color.B));
        brush.Freeze();
        return brush;
    }

    internal static WpfBrush ResolveStrongBorder(FrameworkElement surface, bool highContrast)
    {
        if (highContrast)
        {
            return surface.FindResource("BridgeSignal") as WpfBrush
                ?? throw new InvalidOperationException("BridgeSignal must resolve to a brush.");
        }

        return BridgeSceneContext.GetAccentBrush(surface)
            ?? throw new InvalidOperationException("The in-game menu scene must be applied before its appearance.");
    }
}
