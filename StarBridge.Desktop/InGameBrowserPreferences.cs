using System.IO;
using System.Text.Json;

namespace StarBridge.Desktop;

internal sealed record InGameBrowserProviderOption(
    string Key,
    string DisplayName,
    Uri HomePage)
{
    public override string ToString() => DisplayName;
}

internal sealed record InGameBrowserPreferences(
    string ProviderKey,
    string LastPageUrl = "")
{
    private const string DefaultProviderKey = "bing-cn";
    private static readonly string PreferencesPath = Path.Combine(
        DesktopAppConfig.ConfigDirectory,
        "in-game-browser.json");

    internal static IReadOnlyList<InGameBrowserProviderOption> Providers { get; } =
    [
        new("bing-cn", "必应中国", new Uri("https://cn.bing.com/")),
        new("baidu", "百度", new Uri("https://www.baidu.com/")),
        new("google", "Google", new Uri("https://www.google.com/")),
        new("duckduckgo", "DuckDuckGo", new Uri("https://duckduckgo.com/")),
        new("bing-global", "必应国际", new Uri("https://www.bing.com/"))
    ];

    internal static string NormalizeProviderKey(string? providerKey)
    {
        var candidate = providerKey?.Trim().ToLowerInvariant();
        return Providers.Any(provider => provider.Key.Equals(
            candidate,
            StringComparison.OrdinalIgnoreCase))
            ? candidate!
            : DefaultProviderKey;
    }

    internal static Uri ResolveHomePage(string? providerKey)
    {
        var normalized = NormalizeProviderKey(providerKey);
        return Providers.First(provider => provider.Key == normalized).HomePage;
    }

    internal static InGameBrowserPreferences Load()
    {
        try
        {
            if (File.Exists(PreferencesPath))
            {
                var loaded = JsonSerializer.Deserialize<InGameBrowserPreferences>(
                    File.ReadAllText(PreferencesPath));
                return new InGameBrowserPreferences(
                    NormalizeProviderKey(loaded?.ProviderKey),
                    NormalizePageUrl(loaded?.LastPageUrl));
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }

        return new InGameBrowserPreferences(DefaultProviderKey);
    }

    internal void Save()
    {
        Directory.CreateDirectory(DesktopAppConfig.ConfigDirectory);
        var normalized = this with
        {
            ProviderKey = NormalizeProviderKey(ProviderKey),
            LastPageUrl = NormalizePageUrl(LastPageUrl)
        };
        File.WriteAllText(
            PreferencesPath,
            JsonSerializer.Serialize(
                normalized,
                new JsonSerializerOptions { WriteIndented = true }));
    }

    internal static Uri? LoadLastPage()
    {
        var value = Load().LastPageUrl;
        return Uri.TryCreate(value, UriKind.Absolute, out var uri) &&
               InGameBrowserAddressPolicy.TryNormalize(
                   uri.AbsoluteUri,
                   out var normalized)
            ? normalized
            : null;
    }

    internal static void SaveLastPage(Uri page)
    {
        ArgumentNullException.ThrowIfNull(page);
        var current = Load();
        (current with { LastPageUrl = page.AbsoluteUri }).Save();
    }

    private static string NormalizePageUrl(string? value) =>
        Uri.TryCreate(value?.Trim(), UriKind.Absolute, out var uri) &&
        InGameBrowserAddressPolicy.TryNormalize(
            uri.AbsoluteUri,
            out var normalized)
            ? normalized.AbsoluteUri
            : "";
}
