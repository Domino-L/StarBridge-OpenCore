using System.Text.Json;

namespace StarBridge.Core.Ships;

public sealed record ShipDisplayName(string RuntimeId, string EnglishName, string ChineseName, string? TraditionalChineseName);

/// <summary>Display-only, exact catalog lookup. Never resolves ownership, size or combat capability.</summary>
public sealed class ShipNameIndex
{
    private static readonly IReadOnlyDictionary<string, string[]> ManufacturerEnglishNames =
        new Dictionary<string, string[]>(StringComparer.OrdinalIgnoreCase)
        {
            ["AEGS"] = ["Aegis Dynamics", "Aegis"],
            ["ANVL"] = ["Anvil Aerospace", "Anvil"],
            ["ARGO"] = ["Argo Astronautics", "Argo"],
            ["BANU"] = ["Banu"],
            ["CNOU"] = ["Consolidated Outland", "CNOU"],
            ["CRUS"] = ["Crusader Industries", "Crusader"],
            ["DRAK"] = ["Drake Interplanetary", "Drake"],
            ["ESPR"] = ["Esperia"],
            ["GAMA"] = ["Gatac"],
            ["KRIG"] = ["Kruger Intergalactic", "Kruger"],
            ["MISC"] = ["Musashi Industrial and Starflight Concern", "MISC", "Musashi"],
            ["MIRAI"] = ["Mirai"],
            ["MRAI"] = ["Mirai"],
            ["ORIG"] = ["Origin Jumpworks", "Origin"],
            ["RSI"] = ["Roberts Space Industries", "RSI"],
            ["TMBL"] = ["Tumbril Land Systems", "Tumbril"],
            ["VNCL"] = ["Vanduul"],
            ["XIAN"] = ["Aopoa", "Xi'an", "Xian"],
            ["XNAA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPOA"] = ["Aopoa", "Xi'an", "Xian"],
            ["AOPA"] = ["Aopoa", "Xi'an", "Xian"]
        };
    private readonly Dictionary<string, ShipDisplayName?> _names = new(StringComparer.Ordinal);
    private ShipNameIndex() { }
    public static ShipNameIndex Empty => new();
    public ShipDisplayName? Find(string? name) => _names.GetValueOrDefault(Key(name));
    internal static string? ManufacturerName(string? runtimeId)
    {
        var separator = runtimeId?.IndexOf('_') ?? -1;
        return separator > 0 && ManufacturerEnglishNames.TryGetValue(runtimeId![..separator], out var names)
            ? names[0] : null;
    }
    internal void AddAlias(string alias, string runtimeId)
    {
        if (Find(runtimeId) is { } value) Add(alias, value);
    }

    public static ShipNameIndex Parse(string? json)
    {
        if (string.IsNullOrWhiteSpace(json) || json.Length > 4 * 1024 * 1024) return Empty;
        try
        {
            using var document = JsonDocument.Parse(json);
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1) return Empty;
            var entries = root.GetProperty("entries");
            if (entries.GetArrayLength() > 5000) return Empty;
            var index = new ShipNameIndex();
            var ids = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            var values = new List<ShipDisplayName>();
            foreach (var entry in entries.EnumerateArray())
            {
                var id = Text(entry, "runtimeId");
                var english = Text(entry, "englishName");
                var chinese = Text(entry, "chineseName");
                if (id.Length == 0 || english.Length == 0 || !ids.Add(id)) return Empty;
                var traditional = Text(entry, "traditionalChineseName");
                var value = new ShipDisplayName(id, english, chinese, traditional.Length == 0 ? null : traditional);
                values.Add(value);
                index.Add(id, value);
                index.Add(english, value);
                index.Add(chinese, value);
                index.Add(traditional, value);
                var aliases = entry.GetProperty("aliases");
                if (aliases.GetArrayLength() > 100) return Empty;
                foreach (var alias in aliases.EnumerateArray()) index.Add(alias.GetString(), value);
            }
            foreach (var value in values) index.AddGeneratedAliases(value);
            return index;
        }
        catch (Exception error) when (error is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { return Empty; }
    }

    private static string Text(JsonElement entry, string name) =>
        entry.TryGetProperty(name, out var field) && field.ValueKind == JsonValueKind.String
            ? field.GetString()!.Trim() : "";

    private static string Key(string? value) =>
        string.IsNullOrWhiteSpace(value) || value.Length > 256 || value.Any(char.IsControl)
            ? "" : string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();

    private void Add(string? alias, ShipDisplayName value)
    {
        var key = Key(alias);
        if (key.Length == 0) return;
        if (_names.TryGetValue(key, out var previous) && previous?.RuntimeId != value.RuntimeId)
            _names[key] = null; // Ambiguous aliases remain ambiguous, irrespective of entry order.
        else _names[key] = value;
    }

    private void AddGeneratedAliases(ShipDisplayName value)
    {
        var separator = value.RuntimeId.IndexOf('_');
        if (separator <= 0 ||
            !ManufacturerEnglishNames.TryGetValue(value.RuntimeId[..separator], out var manufacturers))
        {
            return;
        }
        foreach (var manufacturer in manufacturers)
        {
            Add(manufacturer + " " + value.EnglishName, value);
        }
    }
}
