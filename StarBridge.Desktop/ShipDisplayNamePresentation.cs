namespace StarBridge.Desktop;

internal static class ShipDisplayNamePresentation
{
    public const string UnknownShip = "未知舰船";

    public static string ResolveChinese(string? value, string emptyFallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return emptyFallback;
        }

        var text = value.Trim();
        if (PlayerSessionStatePresentation.IsSessionStateText(text) ||
            text.Equals(emptyFallback, StringComparison.Ordinal))
        {
            return text;
        }

        var code = ShipNameLocalizer.ResolveCode(text);
        if (ShipNameLocalizer.KnownChineseNames.TryGetValue(code, out var chineseName) &&
            !string.IsNullOrWhiteSpace(chineseName))
        {
            return chineseName.Trim();
        }

        return IsAlreadyChinese(text) ? text : UnknownShip;
    }

    private static bool IsAlreadyChinese(string value) =>
        value.Any(character => character is >= '\u3400' and <= '\u9fff') &&
        !value.Any(character => character is >= 'A' and <= 'Z' or >= 'a' and <= 'z');
}
