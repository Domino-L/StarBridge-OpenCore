namespace StarBridge.Core.Overlay;

/// <summary>What the screen the overlay runs on is: its height in real pixels, the Windows scaling (1 = 100%) and,
/// when Windows can tell, its physical height in millimetres.</summary>
public readonly record struct OverlayScreenFacts(int PixelHeight, double Scale, double? PhysicalHeightMm);

/// <summary>
/// 0.7.3 m102 (11-18 user: "0.7.3 做甲"): the visor size a preset the user never saved starts with, from the screen.
/// The visor is drawn in proportion to the screen's pixel height (OverlayVisorRenderer: 1080 rows = 1), so how big its
/// text looks depends on the screen's physical height alone: a member's name at the medium size is 13/1440 of it (about
/// 1.8 mm on a 15.6" laptop, 2.7 mm on a 24" monitor; OVERLAY-SCREEN-ADAPT-073.md). Saved presets keep their size.
/// </summary>
public static class OverlayVisorAutoSize
{
    /// <summary>Screens lower than this (laptops; 16:9 under about 21") start at the large size.</summary>
    public const double LargeBelowMm = 260;

    /// <summary>The physical heights Windows reports that are believed (anything else falls back).</summary>
    public const double MinPlausibleMm = 100, MaxPlausibleMm = 1500;

    /// <summary>
    /// Large on a low screen, otherwise medium; never small (a big screen is looked at from further away). Without a
    /// believable physical height: large when Windows scales a laptop-like screen up (at least 125% with at most 1200
    /// rows, or at least 150% with at most 1600 rows), otherwise medium.
    /// </summary>
    public static OverlayVisorSize Pick(OverlayScreenFacts screen)
    {
        if (screen.PhysicalHeightMm is { } mm && double.IsFinite(mm) && mm >= MinPlausibleMm && mm <= MaxPlausibleMm)
        {
            return mm < LargeBelowMm ? OverlayVisorSize.Large : OverlayVisorSize.Medium;
        }
        var laptop = screen.PixelHeight > 0 && double.IsFinite(screen.Scale) &&
            (screen.Scale >= 1.25 - 1e-6 && screen.PixelHeight <= 1200 || screen.Scale >= 1.5 - 1e-6 && screen.PixelHeight <= 1600);
        return laptop ? OverlayVisorSize.Large : OverlayVisorSize.Medium;
    }
}
