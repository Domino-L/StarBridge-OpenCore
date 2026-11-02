namespace StarBridge.OverlayRuntime.Windows;

using System.Drawing;

internal readonly record struct AchievementCelebrationPlacement(Rectangle Bounds, int Margin)
{
    internal static AchievementCelebrationPlacement ForWorkArea(Rectangle work, uint windowDpi)
    {
        if (work.Width <= 0 || work.Height <= 0 || windowDpi == 0)
            throw new ArgumentException("An available work area and window DPI are required.");
        var scale = windowDpi / 96d;
        const int margin = 0;
        // Retain the whole composition even on a small work area at high scale.
        var fit = Math.Min(scale, Math.Min((work.Width - margin * 2) / AchievementCelebrationCard.CardWidth,
            (work.Height - margin * 2) / AchievementCelebrationCard.CardHeight));
        var width = Math.Max(1, (int)Math.Ceiling(AchievementCelebrationCard.CardWidth * fit));
        var height = Math.Max(1, (int)Math.Ceiling(AchievementCelebrationCard.CardHeight * fit));
        return new(new(work.Right - width - margin, work.Bottom - height - margin, width, height), margin);
    }
}
