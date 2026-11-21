namespace StarBridge.OverlayRuntime.Windows;

using System.Drawing;

internal readonly record struct AchievementCelebrationPlacement(Rectangle Bounds, Rectangle CardBounds, double Scale)
{
    internal static AchievementCelebrationPlacement ForWorkArea(Rectangle work, uint windowDpi)
    {
        if (work.Width <= 0 || work.Height <= 0 || windowDpi == 0)
            throw new ArgumentException("An available work area and window DPI are required.");
        var scale = windowDpi / 96d;
        const double widthDip = AchievementCelebrationCard.CardWidth + AchievementCelebrationCard.Bleed;
        const double heightDip = AchievementCelebrationCard.CardHeight + AchievementCelebrationCard.Bleed;
        // Retain the whole composition even on a small work area at high scale.
        var fit = Math.Min(scale, Math.Min(work.Width / widthDip, work.Height / heightDip));
        var width = (int)Math.Ceiling(widthDip * fit);
        var height = (int)Math.Ceiling(heightDip * fit);
        var cardWidth = (int)Math.Ceiling(AchievementCelebrationCard.CardWidth * fit);
        var cardHeight = (int)Math.Ceiling(AchievementCelebrationCard.CardHeight * fit);
        return new(new(work.Right - width, work.Bottom - height, width, height),
            new(work.Right - cardWidth, work.Bottom - cardHeight, cardWidth, cardHeight), fit);
    }

    internal bool ContainsCard(Point pointer)
    {
        if (!CardBounds.Contains(pointer)) return false;
        var x = (pointer.X + .5 - (CardBounds.Right - AchievementCelebrationCard.CardWidth * Scale)) / Scale;
        var y = (pointer.Y + .5 - (CardBounds.Bottom - AchievementCelebrationCard.CardHeight * Scale)) / Scale;
        var fromLongEdge = Math.Min(y, AchievementCelebrationCard.CardHeight - y);
        return x >= 0 && fromLongEdge >= 0 &&
            x / AchievementCelebrationCard.CutWidth + fromLongEdge / AchievementCelebrationCard.CutHeight >= 1;
    }
}
