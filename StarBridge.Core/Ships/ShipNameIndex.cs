using System.Text.Json;

namespace StarBridge.Core.Ships;

public sealed record ShipDisplayName(string? RuntimeId, string EnglishName, string ChineseName, string? TraditionalChineseName);

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
    private readonly Dictionary<string, ShipDisplayName?> _displayNames = new(StringComparer.Ordinal);
    private static readonly Lazy<ShipNameIndex> BundledNames = new(() => {
        using var stream = typeof(ShipNameIndex).Assembly.GetManifestResourceStream("StarBridge.ShipNamePack.json");
        if (stream is null) return Empty;
        using var reader = new StreamReader(stream);
        return Parse(reader.ReadToEnd());
    });
    private ShipNameIndex() { }
    public static ShipNameIndex Empty => new();
    public static ShipNameIndex Bundled => BundledNames.Value;
    public ShipDisplayName? Find(string? name) => _names.GetValueOrDefault(Key(name));
    // A unique display-catalog label may be translated even when that label is
    // shared by several runtime IDs. It must not establish a runtime identity.
    public ShipDisplayName? FindDisplay(string? name) => Find(name) ?? _displayNames.GetValueOrDefault(Key(name));
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

    public static ShipNameIndex Parse(string? json, string? displayCatalogTsv = null)
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
            foreach (var (alias, code) in OfficialHangarAliases.Entries)
            {
                if (index.Find(code) is not { } value) continue;
                index.Add(alias, value);
                index.AddManufacturerAliases(alias, value);
            }
            index.AddDisplayCatalog(displayCatalogTsv);
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
        if (_names.TryGetValue(key, out var previous) &&
            (previous is null || (value.RuntimeId is null ? previous != value : previous.RuntimeId != value.RuntimeId)))
            _names[key] = null; // Ambiguous aliases remain ambiguous, irrespective of entry order.
        else _names[key] = value;
    }

    private void AddGeneratedAliases(ShipDisplayName value)
    {
        AddManufacturerAliases(value.EnglishName, value);
    }

    private void AddManufacturerAliases(string alias, ShipDisplayName value, string? maker = null, bool displayOnly = false)
    {
        void AddName(string text) { if (displayOnly) AddDisplay(text, value); else Add(text, value); }
        var separator = value.RuntimeId?.IndexOf('_') ?? -1;
        var manufacturers = separator > 0 && ManufacturerEnglishNames.TryGetValue(value.RuntimeId![..separator], out var known)
            ? known : ManufacturerEnglishNames.Values.FirstOrDefault(names =>
                names.Any(name => string.Equals(name, maker, StringComparison.OrdinalIgnoreCase)));
        if (manufacturers is null)
        {
            if (!string.IsNullOrWhiteSpace(maker)) AddName(maker + " " + alias);
            return;
        }
        foreach (var manufacturer in manufacturers)
        {
            AddName(manufacturer + " " + alias);
        }
    }

    private void AddDisplayCatalog(string? tsv)
    {
        if (string.IsNullOrWhiteSpace(tsv) || tsv.Length > 4 * 1024 * 1024) return;
        var lines = tsv.Split('\n');
        if (lines.Length > 5001) return;
        var header = lines[0].TrimEnd('\r').TrimStart('\uFEFF').Split('\t');
        var english = Array.IndexOf(header, "英文飞船名");
        var chinese = Array.IndexOf(header, "中文飞船名");
        var maker = Array.IndexOf(header, "制造商");
        if (english < 0 || chinese < 0) return;
        // Resolve joins against the runtime index before adding display rows;
        // catalog order must not change which runtime a row may represent.
        var rows = lines.Skip(1).Select(line => line.TrimEnd('\r').Split('\t'))
            .Where(cells => cells.Length > Math.Max(english, chinese))
            .Select(cells => (En: cells[english].Trim(), Zh: cells[chinese].Trim(),
                Maker: maker >= 0 && maker < cells.Length ? cells[maker].Trim() : null))
            .Where(row => Key(row.En).Length != 0 && Key(row.Zh).Length != 0)
            .Select(row => (row.En, row.Zh, row.Maker, Name: Find(row.En) ?? Find(row.Zh))).ToArray();
        foreach (var row in rows)
        {
            // Display-only models have no invented runtime ID (e.g. a newer EX).
            var value = row.Name ?? new ShipDisplayName(null, row.En, row.Zh, null);
            Add(row.En, value);
            Add(row.Zh, value);
            AddManufacturerAliases(row.En, value, row.Maker);
            var display = new ShipDisplayName(null, row.En, row.Zh, null);
            AddDisplay(row.En, display);
            AddDisplay(row.Zh, display);
            AddManufacturerAliases(row.En, display, row.Maker, displayOnly: true);
        }
    }

    private void AddDisplay(string alias, ShipDisplayName value)
    {
        var key = Key(alias);
        if (key.Length == 0) return;
        if (_displayNames.TryGetValue(key, out var previous) && previous != value) _displayNames[key] = null;
        else _displayNames[key] = value;
    }
}
