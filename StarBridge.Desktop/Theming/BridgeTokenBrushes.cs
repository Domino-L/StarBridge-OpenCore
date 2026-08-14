using System.Windows;
using WpfBrush = System.Windows.Media.Brush;

namespace StarBridge.Desktop.Theming;

public enum BridgeBrushToken
{
    Ground,
    Rail,
    Panel,
    PanelRaised,
    RowHover,
    RowSelected,
    Hairline,
    RowHairline,
    ChipHairline,
    Scrim,
    Ink,
    Ink2,
    Ink3,
    StatusInfo,
    StatusOk,
    StatusWarn,
    StatusBad,
    StatusOff,
    MetricInfo,
    MetricValue,
    MetricDuration,
    Signal,
    SignalSurface
}

/// <summary>
/// Resolves shared Bridge brush resources for code-created WPF visuals.
/// Callers use typed tokens; this module alone owns the XAML resource keys
/// and treats a missing or mistyped resource as a configuration failure.
/// </summary>
public static class BridgeTokenBrushes
{
    public static WpfBrush GetRequired(FrameworkElement resourceScope, BridgeBrushToken token)
    {
        ArgumentNullException.ThrowIfNull(resourceScope);

        var resourceKey = GetResourceKey(token);
        return resourceScope.TryFindResource(resourceKey) is WpfBrush brush
            ? brush
            : throw new InvalidOperationException(
                $"Required Bridge brush token '{resourceKey}' is missing or is not a Brush.");
    }

    private static string GetResourceKey(BridgeBrushToken token) => token switch
    {
        BridgeBrushToken.Ground => "BridgeGround",
        BridgeBrushToken.Rail => "BridgeRail",
        BridgeBrushToken.Panel => "BridgePanel",
        BridgeBrushToken.PanelRaised => "BridgePanelRaised",
        BridgeBrushToken.RowHover => "BridgeRowHover",
        BridgeBrushToken.RowSelected => "BridgeRowSelected",
        BridgeBrushToken.Hairline => "BridgeHairline",
        BridgeBrushToken.RowHairline => "BridgeRowHairline",
        BridgeBrushToken.ChipHairline => "BridgeChipHairline",
        BridgeBrushToken.Scrim => "BridgeScrim",
        BridgeBrushToken.Ink => "BridgeInk",
        BridgeBrushToken.Ink2 => "BridgeInk2",
        BridgeBrushToken.Ink3 => "BridgeInk3",
        BridgeBrushToken.StatusInfo => "BridgeStatusInfo",
        BridgeBrushToken.StatusOk => "BridgeStatusOk",
        BridgeBrushToken.StatusWarn => "BridgeStatusWarn",
        BridgeBrushToken.StatusBad => "BridgeStatusBad",
        BridgeBrushToken.StatusOff => "BridgeStatusOff",
        BridgeBrushToken.MetricInfo => "BridgeMetricInfo",
        BridgeBrushToken.MetricValue => "BridgeMetricValue",
        BridgeBrushToken.MetricDuration => "BridgeMetricDuration",
        BridgeBrushToken.Signal => "BridgeSignal",
        BridgeBrushToken.SignalSurface => "BridgeSignalSurface",
        _ => throw new ArgumentOutOfRangeException(nameof(token), token, "Unknown Bridge brush token.")
    };
}
