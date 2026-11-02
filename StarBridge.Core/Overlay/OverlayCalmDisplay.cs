namespace StarBridge.Core.Overlay;

/// <summary>
/// Calm display: persistent modules rest at a lower opacity when nothing changes.
/// Unset is a settings file from before the feature: it behaves as Off and lets
/// the settings page introduce the feature once.
/// </summary>
public enum OverlayCalmDisplay
{
    Unset,
    Off,
    On
}

/// <summary>Which content changes bring a resting module back to its lit opacity.</summary>
public enum OverlayCalmLightWhen
{
    /// <summary>Only changes that concern the viewer (same server or location, new chat).</summary>
    Relevant,
    Any
}

/// <summary>The resting and lit opacities calm display actually uses.</summary>
public readonly record struct OverlayCalmDisplayLevels(bool Enabled, double Idle, double Lit, TimeSpan Wait, OverlayCalmLightWhen LightWhen)
{
    /// <summary>No setting ever makes a module fainter than this.</summary>
    public const double MinimumOpacity = 0.15;
    public const double DefaultIdleCeiling = 0.35;
    public const double DefaultLitFloor = 0.85;
    public const int DefaultWaitSeconds = 10;
    public static IReadOnlyList<int> WaitChoices { get; } = [5, 10, 20, 30];

    /// <summary>
    /// Unset idle/lit values (0) follow the existing opacity: resting never makes a
    /// module darker than the user already set it, and lighting lifts a low setting
    /// to a readable level. Resting is never brighter than lit.
    /// </summary>
    public static OverlayCalmDisplayLevels Resolve(OverlayDisplaySettings settings)
    {
        var baseOpacity = Math.Clamp(settings.Opacity, MinimumOpacity, 1);
        var idle = settings.CalmIdleOpacity > 0
            ? Math.Clamp(settings.CalmIdleOpacity, MinimumOpacity, 1)
            : Math.Max(MinimumOpacity, Math.Min(baseOpacity, DefaultIdleCeiling));
        var lit = settings.CalmLitOpacity > 0
            ? Math.Clamp(settings.CalmLitOpacity, MinimumOpacity, 1)
            : Math.Max(baseOpacity, DefaultLitFloor);
        return new(
            settings.CalmDisplay == OverlayCalmDisplay.On,
            Math.Min(idle, lit),
            lit,
            TimeSpan.FromSeconds(NormalizeWaitSeconds(settings.CalmWaitSeconds)),
            settings.CalmLightWhen);
    }

    public static int NormalizeWaitSeconds(int seconds) =>
        WaitChoices.Contains(seconds) ? seconds : DefaultWaitSeconds;

    /// <summary>0 keeps "follow the existing opacity"; anything else is clamped to the readable range.</summary>
    public static double NormalizeOpacity(double value) =>
        !double.IsFinite(value) || value <= 0 ? 0 : Math.Clamp(value, MinimumOpacity, 1);

    /// <summary>A hotkey label such as "Ctrl+Space"; empty when unbound or unusable in the CSV payload.</summary>
    public static string NormalizePeekHotkey(string? value)
    {
        var text = (value ?? "").Trim();
        return text.Length is 0 or > 32 || text.Contains(',') || text.Contains(';') ? "" : text;
    }
}
