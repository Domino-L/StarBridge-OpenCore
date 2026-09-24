namespace StarBridge.Core.Overlay;

using System.Globalization;

public class InformationOverlayLayoutItem
{
    public const string RetiredMissionKey = "Mission";

    public InformationOverlayLayoutItem(
        string key,
        double x,
        double y,
        double width,
        double height,
        OverlayHorizontalAnchor? horizontalAnchor = null,
        OverlayVerticalAnchor? verticalAnchor = null,
        bool isLocked = false,
        double textOpacity = 1.0,
        double backgroundOpacity = 1.0,
        double decorationOpacity = 1.0)
    {
        if (string.IsNullOrWhiteSpace(key))
        {
            throw new ArgumentException("Overlay module key is required.", nameof(key));
        }

        Key = key.Trim();
        X = Math.Clamp(x, 0, 0.95);
        Y = Math.Clamp(y, 0, 0.95);
        Width = Math.Clamp(width, 0.05, 1);
        Height = Math.Clamp(height, 0.05, 1);
        HorizontalAnchor = horizontalAnchor ?? InferHorizontalAnchor(X, Width);
        VerticalAnchor = verticalAnchor ?? InferVerticalAnchor(Y, Height);
        IsLocked = isLocked;
        TextOpacity = NormalizeTextOpacity(textOpacity);
        BackgroundOpacity = NormalizeBackgroundOpacity(backgroundOpacity);
        DecorationOpacity = NormalizeDecorationOpacity(decorationOpacity);
    }

    public string Key { get; }

    public double X { get; set; }

    public double Y { get; set; }

    public double Width { get; set; }

    public double Height { get; set; }

    public OverlayHorizontalAnchor HorizontalAnchor { get; set; }

    public OverlayVerticalAnchor VerticalAnchor { get; set; }

    public bool IsLocked { get; set; }

    public double TextOpacity { get; set; }

    public double BackgroundOpacity { get; set; }

    public double DecorationOpacity { get; set; }

    public string Serialize()
    {
        return string.Join(
            ",",
            Key,
            X.ToString("0.####", CultureInfo.InvariantCulture),
            Y.ToString("0.####", CultureInfo.InvariantCulture),
            Width.ToString("0.####", CultureInfo.InvariantCulture),
            Height.ToString("0.####", CultureInfo.InvariantCulture),
            HorizontalAnchor,
            VerticalAnchor,
            IsLocked ? "1" : "0",
            NormalizeTextOpacity(TextOpacity).ToString("0.##", CultureInfo.InvariantCulture),
            NormalizeBackgroundOpacity(BackgroundOpacity).ToString("0.##", CultureInfo.InvariantCulture),
            NormalizeDecorationOpacity(DecorationOpacity).ToString("0.##", CultureInfo.InvariantCulture));
    }

    public static string SerializeMany(IEnumerable<InformationOverlayLayoutItem> layout)
    {
        ArgumentNullException.ThrowIfNull(layout);
        return string.Join(
            ";",
            layout
                .Where(item => !IsRetiredModuleKey(item.Key))
                .Select(item => item.Serialize()));
    }

    public static IEnumerable<InformationOverlayLayoutItem> ParseMany(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            yield break;
        }

        foreach (var item in value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = item.Split(',', StringSplitOptions.TrimEntries);
            if (parts.Length < 5 ||
                !TryParseLayoutNumber(parts[1], out var x) ||
                !TryParseLayoutNumber(parts[2], out var y) ||
                !TryParseLayoutNumber(parts[3], out var width) ||
                !TryParseLayoutNumber(parts[4], out var height))
            {
                continue;
            }

            var key = parts[0];
            if (IsRetiredModuleKey(key))
            {
                continue;
            }

            var horizontalAnchor = parts.Length > 5 &&
                Enum.TryParse<OverlayHorizontalAnchor>(parts[5], ignoreCase: true, out var parsedHorizontalAnchor)
                    ? parsedHorizontalAnchor
                    : InferHorizontalAnchor(x, width);
            var verticalAnchor = parts.Length > 6 &&
                Enum.TryParse<OverlayVerticalAnchor>(parts[6], ignoreCase: true, out var parsedVerticalAnchor)
                    ? parsedVerticalAnchor
                    : InferVerticalAnchor(y, height);
            var isLocked = parts.Length > 7 && ParseLayoutBool(parts[7]);
            var textOpacity = parts.Length > 8 && TryParseLayoutNumber(parts[8], out var parsedTextOpacity)
                ? parsedTextOpacity
                : 1.0;
            var backgroundOpacity = parts.Length > 9 && TryParseLayoutNumber(parts[9], out var parsedBackgroundOpacity)
                ? parsedBackgroundOpacity
                : 1.0;
            var decorationOpacity = parts.Length > 10 && TryParseLayoutNumber(parts[10], out var parsedDecorationOpacity)
                ? parsedDecorationOpacity
                : 1.0;
            yield return new InformationOverlayLayoutItem(
                key,
                x,
                y,
                width,
                height,
                horizontalAnchor,
                verticalAnchor,
                isLocked,
                textOpacity,
                backgroundOpacity,
                decorationOpacity);
        }
    }

    public static double NormalizeTextOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.15, 1.0) : 1.0;

    public static double NormalizeBackgroundOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 1.0;

    public static double NormalizeDecorationOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 1.0;

    public static bool IsRetiredModuleKey(string? key) =>
        RetiredMissionKey.Equals(key?.Trim(), StringComparison.OrdinalIgnoreCase);

    private static bool TryParseLayoutNumber(string value, out double number) =>
        double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) ||
        double.TryParse(value, NumberStyles.Float, CultureInfo.CurrentCulture, out number);

    private static bool ParseLayoutBool(string value) =>
        value.Equals("1", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
        value.Equals("locked", StringComparison.OrdinalIgnoreCase);

    private static OverlayHorizontalAnchor InferHorizontalAnchor(double x, double width)
    {
        var center = x + width / 2;
        if (center <= 0.38)
        {
            return OverlayHorizontalAnchor.Left;
        }

        return center >= 0.62 ? OverlayHorizontalAnchor.Right : OverlayHorizontalAnchor.Center;
    }

    private static OverlayVerticalAnchor InferVerticalAnchor(double y, double height)
    {
        var center = y + height / 2;
        if (center <= 0.36)
        {
            return OverlayVerticalAnchor.Top;
        }

        return center >= 0.68 ? OverlayVerticalAnchor.Bottom : OverlayVerticalAnchor.Middle;
    }
}
