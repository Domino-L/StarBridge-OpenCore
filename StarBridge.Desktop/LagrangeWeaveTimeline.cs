namespace StarBridge.Desktop;

internal static class LagrangeWeaveTimeline
{
    public const double DurationMs = 3000;
    public const double AnchorsEndMs = 520;
    public const double FieldSolveEndMs = 1280;
    public const double EquilibriumEndMs = 1710;
    public const double ModuleRevealStartMs = 1660;
    public const double ModuleRevealEndMs = 2580;
    public const double ClearStartMs = 2380;
    public const double FocusHandoffMs = 1460;

    public static double At(double milliseconds) =>
        Math.Clamp(milliseconds / DurationMs, 0, 1);
}
