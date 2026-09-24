namespace StarBridge.HostRuntime.Overlay;

public static class InformationOverlayLanguage
{
    public static string Resolve(string? value)
    {
        var language = string.IsNullOrWhiteSpace(value)
            ? System.Globalization.CultureInfo.CurrentUICulture.Name : value.Trim();
        if (language.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase) ||
            language.Equals("zh-TW", StringComparison.OrdinalIgnoreCase) ||
            language.Equals("zh-HK", StringComparison.OrdinalIgnoreCase)) return "zh-Hant";
        return language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? "zh" : "en";
    }
}
