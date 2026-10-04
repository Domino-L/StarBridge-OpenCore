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

        if (text.Length > 256 || text.Any(char.IsControl) ||
            text.Equals("Unknown", StringComparison.OrdinalIgnoreCase) || text.Equals("None", StringComparison.OrdinalIgnoreCase))
            return emptyFallback;
        // Already-translated labels (including Latin model suffixes) must be
        // stable when the scene and member-row presenters both format them.
        if (text.Any(character => character is >= '\u3400' and <= '\u9fff')) return text;
        if (StarBridge.HostRuntime.Presence.GameShipNames.Find(text) is { } name)
            return string.IsNullOrWhiteSpace(name.ChineseName) ? name.EnglishName : name.ChineseName;

        // Detection and translation are separate. Keep a bounded detected name
        // even when an optional/new catalog entry has no Chinese translation.
        return text;
    }
}
