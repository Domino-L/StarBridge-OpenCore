namespace StarBridge.Desktop;

internal readonly record struct MinimalOverlayFrameMetrics(
    double Chamfer,
    double HorizontalGap,
    double VerticalGap);

internal static class MinimalOverlaySkinStyle
{
    public const double ChamferRatio = 0.04;
    public const double MinimumChamfer = 3;
    public const double MaximumChamfer = 8;
    public const double CenterGapRatio = 0.60;
    public const double BorderThickness = 1;
    public const double GuideOpacity = 0.32;
    public const double GuideInset = 5;
    public const double GuideStartRatio = 0.20;
    public const double GuideEndRatio = 0.42;
    public const double GuideEndPadding = 8;
    public const byte BorderRed = 255;
    public const byte BorderGreen = 255;
    public const byte BorderBlue = 255;
    public const byte PreviewFillAlpha = 204;
    public const byte PreviewFillRed = 5;
    public const byte PreviewFillGreen = 18;
    public const byte PreviewFillBlue = 28;
    public const double TitleBrightness = 0.72;
    public const double TextBrightness = 0.30;
    public const double MutedBrightness = 0.58;
    public const double AccentBrightness = 0.18;
    public const double RowAccentBrightness = 0.24;
    public const double TitleFontSize = 14;
    public const double TextFontSize = 13;
    public const double MutedFontSize = 11;
    public const double TinyFontSize = 10;
    public const double TinyCenterFontSize = 9;
    public const double EventTitleFontSize = 13;
    public const double EventDetailFontSize = 12;

    public static MinimalOverlayFrameMetrics ResolveFrame(double width, double height)
    {
        var normalizedWidth = Math.Max(1, width);
        var normalizedHeight = Math.Max(1, height);
        var chamfer = Math.Clamp(
            Math.Min(normalizedWidth, normalizedHeight) * ChamferRatio,
            MinimumChamfer,
            MaximumChamfer);
        return new MinimalOverlayFrameMetrics(
            chamfer,
            Math.Max(1, normalizedWidth - chamfer * 2) * CenterGapRatio,
            Math.Max(1, normalizedHeight - chamfer * 2) * CenterGapRatio);
    }

    public static byte Brighten(byte channel, double amount)
    {
        var normalizedAmount = Math.Clamp(amount, 0, 1);
        return (byte)Math.Round(channel + (byte.MaxValue - channel) * normalizedAmount);
    }
}
