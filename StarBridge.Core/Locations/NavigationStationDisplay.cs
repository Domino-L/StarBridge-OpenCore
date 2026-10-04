using System.Text.Json;

namespace StarBridge.Core.Locations;

/// <summary>
/// Exact display pairings for observed navigation identifiers. This does not
/// canonicalize game events, change location confidence, or confirm an arrival.
/// Names come from the destination station in the caller's location catalog.
/// </summary>
public static class NavigationStationDisplay
{
    public sealed record StationName(string EnglishName, string ChineseName);
    private static readonly (Dictionary<string, string> Routes, Dictionary<string, StationName> Names) Map = Load();
    private static readonly Dictionary<string, string> Stations = Map.Routes;
    private static readonly HashSet<string> StationCodes = new(Stations.Values, StringComparer.OrdinalIgnoreCase);

    // Callers strip their supported instance suffix before looking up display names.
    public static bool TryGetStationCode(string? normalizedCode, out string stationCode)
    {
        var code = normalizedCode?.Trim() ?? "";
        if (code.StartsWith("LOC_", StringComparison.OrdinalIgnoreCase)) code = code[4..];
        return Stations.TryGetValue(code, out stationCode!);
    }

    public static bool PreferCatalogStationName(string code) => StationCodes.Contains(code);

    public static bool TryGetStationName(string stationCode, out StationName name) => Map.Names.TryGetValue(stationCode, out name!);

    // Shared snapshots carry display names. Contextual gateway labels must also
    // round-trip back through each receiver's localizer without losing Chinese.
    public static bool TryGetStationCodeFromDisplayName(string displayName, out string stationCode)
    {
        stationCode = "";
        foreach (var pair in Map.Names)
        {
            if (!pair.Value.EnglishName.Equals(displayName.Trim(), StringComparison.OrdinalIgnoreCase)) continue;
            if (stationCode.Length > 0) { stationCode = ""; return false; }
            stationCode = pair.Key;
        }
        return stationCode.Length > 0;
    }

    private static (Dictionary<string, string> Routes, Dictionary<string, StationName> Names) Load()
    {
        static (Dictionary<string, string>, Dictionary<string, StationName>) Empty() =>
            (new(StringComparer.OrdinalIgnoreCase), new(StringComparer.OrdinalIgnoreCase));
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var names = new Dictionary<string, StationName>(StringComparer.OrdinalIgnoreCase);
        using var stream = typeof(NavigationStationDisplay).Assembly
            .GetManifestResourceStream("StarBridge.NavigationStationDisplay.json");
        if (stream is null) return Empty();
        try
        {
            using var json = JsonDocument.Parse(stream);
            if (json.RootElement.GetProperty("schemaVersion").GetInt32() != 1) return Empty();
            foreach (var row in json.RootElement.GetProperty("entries").EnumerateArray())
            {
                var navigation = row.GetProperty("navigationCode").GetString();
                var station = row.GetProperty("stationCode").GetString();
                if (string.IsNullOrWhiteSpace(navigation) || string.IsNullOrWhiteSpace(station) ||
                    !result.TryAdd(navigation, station)) return Empty();
                if (row.TryGetProperty("nameEn", out var english) || row.TryGetProperty("nameZh", out _))
                {
                    var en = english.GetString();
                    var zh = row.GetProperty("nameZh").GetString();
                    if (string.IsNullOrWhiteSpace(en) || string.IsNullOrWhiteSpace(zh)) return Empty();
                    var label = new StationName(en, zh);
                    if (names.TryGetValue(station, out var previous) && previous != label) return Empty();
                    names[station] = label;
                }
            }
            return (result, names);
        }
        catch (Exception error) when (error is JsonException or KeyNotFoundException or InvalidOperationException or FormatException)
        {
            return Empty();
        }
    }
}
