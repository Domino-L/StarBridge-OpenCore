namespace StarBridge.Core.Overlay;

using System.Globalization;

/// <summary>归档外观的旧值迁移；旧整数编号仅供读取，不再是可选枚举值。</summary>
public static class OverlayArchivedAppearanceMigration
{
    private static readonly (string Field, int CsvIndex, string Legacy, int LegacyId, string Default)[] Fields =
    [
        ("skin", 43, "LagrangeWeave", 2, nameof(OverlaySkin.Default)),
        ("requestedSkin", 72, "LagrangeWeave", 2, nameof(OverlaySkin.Default)),
        ("theme", 10, "LagrangeWeave", 14, nameof(OverlayVisualTheme.Default)),
        ("startupTransitionStyle", 20, "LagrangeWeaveEquilibrium", 6, nameof(OverlayStartupTransitionStyle.BridgeTerminal))
    ];

    public static bool IsArchivedValue(string field, string? value) =>
        Fields.Any(item => item.Field == field &&
            (string.Equals(value?.Trim(), item.Legacy, StringComparison.OrdinalIgnoreCase) ||
             (int.TryParse(value, NumberStyles.Integer, CultureInfo.InvariantCulture, out var id) && id == item.LegacyId)));

    /// <summary>The fields to replace and their defaults. An archived skin takes its locked
    /// theme and transition with it; an archived theme or transition left on another,
    /// valid appearance is replaced alone and the appearance is kept.</summary>
    public static IReadOnlyDictionary<string, string> Replacements(Func<string, string?> valueOf)
    {
        var skin = Fields.Take(2).Any(item => IsArchivedValue(item.Field, valueOf(item.Field)));
        return Fields.Where(item => skin || IsArchivedValue(item.Field, valueOf(item.Field)))
            .ToDictionary(item => item.Field, item => item.Default, StringComparer.Ordinal);
    }

    internal static void MigrateCsv(string[] parts)
    {
        var replacements = Replacements(field =>
            Fields.First(item => item.Field == field).CsvIndex is var index && parts.Length > index ? parts[index] : null);
        foreach (var item in Fields)
        {
            if (parts.Length > item.CsvIndex && replacements.TryGetValue(item.Field, out var value)) parts[item.CsvIndex] = value;
        }
    }
}
