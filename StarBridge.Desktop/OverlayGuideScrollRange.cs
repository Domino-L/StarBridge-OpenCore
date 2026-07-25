namespace StarBridge.Desktop;

public readonly record struct OverlayGuideScrollRange(double Minimum, double Maximum)
{
    private const double DefaultViewportPadding = 10;

    public double Clamp(double offset) => Math.Clamp(offset, Minimum, Maximum);

    public static OverlayGuideScrollRange Resolve(
        double sectionTop,
        double sectionHeight,
        double viewportHeight,
        double scrollableHeight,
        double viewportPadding = DefaultViewportPadding)
    {
        scrollableHeight = Math.Max(0, scrollableHeight);
        viewportHeight = Math.Max(0, viewportHeight);
        sectionHeight = Math.Max(0, sectionHeight);
        viewportPadding = Math.Max(0, viewportPadding);

        var minimum = Math.Clamp(sectionTop - viewportPadding, 0, scrollableHeight);
        if (sectionHeight + viewportPadding * 2 <= viewportHeight)
        {
            return new OverlayGuideScrollRange(minimum, minimum);
        }

        var maximum = Math.Clamp(
            sectionTop + sectionHeight - viewportHeight + viewportPadding,
            minimum,
            scrollableHeight);
        return new OverlayGuideScrollRange(minimum, maximum);
    }
}
