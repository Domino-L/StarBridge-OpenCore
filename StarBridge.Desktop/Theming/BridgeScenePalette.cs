using System.Windows;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;
using SolidColorBrush = System.Windows.Media.SolidColorBrush;

namespace StarBridge.Desktop.Theming;

public enum BridgeSceneKind
{
    Fleet,
    Party,
    Hangar,
    Social,
    Personal,
    Review,
    Overlay,
    System
}

public readonly record struct BridgeSceneColors(Color Accent, Color Ambient);

/// <summary>
/// Owns the canonical Bridge scene palette. Main-window animation and
/// independent tool windows must resolve their colours from this same table.
/// </summary>
public static class BridgeScenePalette
{
    public static BridgeSceneColors Resolve(BridgeSceneKind scene) => scene switch
    {
        BridgeSceneKind.Party => Pair(0x8A, 0x79, 0xBF, 0x24, 0x1E, 0x3C),
        BridgeSceneKind.Hangar => Pair(0xB0, 0x8A, 0x50, 0x33, 0x26, 0x12),
        BridgeSceneKind.Social => Pair(0x4E, 0x9E, 0x8C, 0x12, 0x2F, 0x2A),
        BridgeSceneKind.Personal => Pair(0x7E, 0x8D, 0x9B, 0x1B, 0x25, 0x2D),
        BridgeSceneKind.Review => Pair(0x8C, 0x97, 0xA3, 0x1B, 0x22, 0x29),
        BridgeSceneKind.Overlay => Pair(0x69, 0x8E, 0xB8, 0x17, 0x29, 0x3A),
        BridgeSceneKind.System => Pair(0x6C, 0x91, 0xA6, 0x17, 0x27, 0x31),
        _ => Pair(0x3E, 0x8F, 0xBF, 0x16, 0x30, 0x3F)
    };

    public static Brush CreateAccentBrush(BridgeSceneKind scene) =>
        CreateFrozenBrush(Resolve(scene).Accent);

    public static Brush CreateAmbientBrush(BridgeSceneKind scene) =>
        CreateFrozenBrush(Resolve(scene).Ambient);

    private static BridgeSceneColors Pair(
        byte accentRed,
        byte accentGreen,
        byte accentBlue,
        byte ambientRed,
        byte ambientGreen,
        byte ambientBlue) =>
        new(
            Color.FromRgb(accentRed, accentGreen, accentBlue),
            Color.FromRgb(ambientRed, ambientGreen, ambientBlue));

    private static Brush CreateFrozenBrush(Color color)
    {
        var brush = new SolidColorBrush(color);
        brush.Freeze();
        return brush;
    }
}

/// <summary>
/// Supplies one scene-palette seam to a visual subtree. The main shell provides
/// animated brushes while independent tool windows provide fixed, frozen ones.
/// Values inherit through the WPF tree so shared Bridge styles never need to
/// reach into a dispatcher-owned global scene singleton.
/// </summary>
public static class BridgeSceneContext
{
    public static readonly DependencyProperty AccentBrushProperty =
        DependencyProperty.RegisterAttached(
            "AccentBrush",
            typeof(Brush),
            typeof(BridgeSceneContext),
            new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.Inherits));

    public static readonly DependencyProperty AmbientBrushProperty =
        DependencyProperty.RegisterAttached(
            "AmbientBrush",
            typeof(Brush),
            typeof(BridgeSceneContext),
            new FrameworkPropertyMetadata(null, FrameworkPropertyMetadataOptions.Inherits));

    public static void SetAccentBrush(DependencyObject element, Brush? value) =>
        element.SetValue(AccentBrushProperty, value);

    public static Brush? GetAccentBrush(DependencyObject element) =>
        (Brush?)element.GetValue(AccentBrushProperty);

    public static Brush GetRequiredAccentBrush(DependencyObject element)
    {
        ArgumentNullException.ThrowIfNull(element);
        return GetAccentBrush(element) ?? throw new InvalidOperationException(
            "Required inherited Bridge scene accent brush is missing.");
    }

    public static void SetAmbientBrush(DependencyObject element, Brush? value) =>
        element.SetValue(AmbientBrushProperty, value);

    public static Brush? GetAmbientBrush(DependencyObject element) =>
        (Brush?)element.GetValue(AmbientBrushProperty);

    public static void ApplyFixed(DependencyObject element, BridgeSceneKind scene)
    {
        SetAccentBrush(element, BridgeScenePalette.CreateAccentBrush(scene));
        SetAmbientBrush(element, BridgeScenePalette.CreateAmbientBrush(scene));
    }

    public static void ApplyAnimated(DependencyObject element, SceneState state)
    {
        ArgumentNullException.ThrowIfNull(state);
        SetAccentBrush(element, CreateAnimatedBrush(state, nameof(SceneState.AccentColor)));
        SetAmbientBrush(element, CreateAnimatedBrush(state, nameof(SceneState.AmbientColor)));
    }

    private static Brush CreateAnimatedBrush(SceneState state, string propertyName)
    {
        var brush = new SolidColorBrush();
        System.Windows.Data.BindingOperations.SetBinding(
            brush,
            SolidColorBrush.ColorProperty,
            new System.Windows.Data.Binding(propertyName)
            {
                Source = state,
                Mode = System.Windows.Data.BindingMode.OneWay
            });
        return brush;
    }
}
