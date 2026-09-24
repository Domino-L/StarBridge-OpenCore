using System.Globalization;
using System.Text.RegularExpressions;

namespace StarBridge.Core.Ships;

public sealed record ShipPresentation(string? ChineseName, string? TraditionalChineseName, string? CombatSize,
    string? CatalogId = null, string? Category = null, string? SizeClass = null,
    string? DeliveryStatus = null, decimal? PriceUsd = null, string? ImageKey = null,
    string? EnglishName = null, string? IconKey = null, ShipDisplayReview? Display = null,
    string? Manufacturer = null);

/// <summary>Read-only display catalog, never ownership or server-side classification authority.</summary>
public sealed class ShipPresentationCatalog
{
    private sealed record Row(string English, string Chinese, string? CombatSize, string? Category,
        string? SizeClass, string? DeliveryStatus, decimal? PriceUsd, string? ImageKey, string? IconKey, string? Manufacturer);
    private readonly ShipNameIndex _names;
    private readonly ShipDisplayReviewCatalog _review;
    private readonly Dictionary<string, Row?> _rows = new(StringComparer.Ordinal);
    private readonly Dictionary<string, Row?> _byCode = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, Row?> _byCatalogId = new(StringComparer.OrdinalIgnoreCase);

    public ShipPresentationCatalog(string? namesJson, string? catalogTsv, string? displayReviewJson = null)
    {
        _review = new(displayReviewJson);
        _names = ShipNameIndex.Parse(namesJson);
        // Exact aliases already used by the original hangar importer. No token/fuzzy inference.
        foreach (var (alias, code) in OfficialHangarAliases.Entries) _names.AddAlias(alias, code);
        if (string.IsNullOrWhiteSpace(catalogTsv) || catalogTsv.Length > 4 * 1024 * 1024) return;
        var lines = catalogTsv.Split('\n');
        if (lines.Length > 5001) return;
        var header = lines[0].TrimEnd('\r').TrimStart('\uFEFF').Split('\t');
        int Field(string name) => Array.IndexOf(header, name);
        var english = Field("英文飞船名"); var chinese = Field("中文飞船名");
        var size = Field("规格"); var role = Field("定位"); var tags = Field("隐藏标签");
        var status = Field("官网状态"); var price = Field("价格USD"); var image = Field("图片路径");
        var manufacturer = Field("制造商");
        if (new[] { english, chinese, size, role, tags }.Any(i => i < 0)) return;
        var required = new[] { english, chinese, size, role, tags }.Max();
        foreach (var line in lines.Skip(1))
        {
            var cells = line.TrimEnd('\r').Split('\t');
            if (cells.Length <= required) continue;
            var en = cells[english].Trim(); var zh = cells[chinese].Trim();
            if (Key(en).Length == 0 || Key(zh).Length == 0) continue;
            var combat = cells[role].Split('/')[0].Trim().Equals("Combat", StringComparison.OrdinalIgnoreCase)
                && !cells[tags].Split(',', ';', '|', ' ').Any(t => t.Equals("vehicle", StringComparison.OrdinalIgnoreCase));
            var combatSize = combat ? cells[size].Trim() switch {
                "小型" => "small", "中型" => "medium", "大型" => "large", "旗舰级" => "capital", _ => null
            } : null;
            string Cell(int index) => index >= 0 && index < cells.Length ? cells[index].Trim() : "";
            var category = Cell(role).Split('/')[0].Trim().ToLowerInvariant() switch {
                "combat" => "combat", "transport" => "transport", "industrial" => "industrial",
                "exploration" => "exploration", "support" => "support",
                "utility" or "competition" or "ground" or "multi-role" => "utility", _ => null
            };
            var physicalSize = Cell(size) switch {
                "小型" => "small", "中型" => "medium", "大型" => "large", "旗舰级" => "capital", _ => null
            };
            var delivery = Cell(status).ToLowerInvariant() switch {
                "可飞" or "flight ready" or "flyable" => "flyable", "概念" or "concept" => "concept", _ => null
            };
            decimal? priceUsd = decimal.TryParse(Cell(price), NumberStyles.AllowDecimalPoint,
                CultureInfo.InvariantCulture, out var amount) && amount >= 0 && amount <= 1_000_000_000m
                && decimal.Round(amount, 2) == amount ? amount : null;
            var imageMatch = Regex.Match(Cell(image).Replace('\\', '/'),
                @"^Data/ShipImages/([a-zA-Z0-9_-]+)\.(?:jpg|jpeg|png|webp)$", RegexOptions.CultureInvariant);
            var row = new Row(en, zh, combatSize, category, physicalSize, delivery, priceUsd,
                imageMatch.Success ? imageMatch.Groups[1].Value.ToLowerInvariant() : null,
                ShipCatalogIconKey.Resolve(Cell(role), Cell(tags), physicalSize),
                Cell(manufacturer) is { Length: > 0 and <= 128 } maker && !maker.Any(char.IsControl) ? maker : null);
            Add(_rows, Key(en), row);
            Add(_rows, Key(zh), row);
            Add(_byCatalogId, "catalog-" + Key(en).ToLowerInvariant(), row);
            // The original name catalog joins the full catalog through an unambiguous Chinese alias.
            var name = _names.Find(zh) ?? _names.Find(en);
            if (name is not null) Add(_byCode, name.RuntimeId, row);
        }
    }

    public ShipPresentation Find(string original)
    {
        var name = _names.Find(original);
        var key = Key(original);
        Row? row;
        if (!_byCatalogId.TryGetValue(original, out row) &&
            !_rows.TryGetValue(key, out row) && name is not null)
            _byCode.TryGetValue(name.RuntimeId, out row);
        // Published hangars use the stable display-catalog identity, not a game
        // runtime alias. Join the same exact row for names and artwork as locally.
        if (name is null && row is not null) name = _names.Find(row.English);
        return new(name?.ChineseName ?? row?.Chinese, name?.TraditionalChineseName, row?.CombatSize,
            row is null ? null : "catalog-" + Key(row.English).ToLowerInvariant(),
            row?.Category, row?.SizeClass, row?.DeliveryStatus, row?.PriceUsd, row?.ImageKey, row?.English ?? name?.EnglishName, row?.IconKey,
            _review.Find(original, name?.RuntimeId), row?.Manufacturer ?? ShipNameIndex.ManufacturerName(name?.RuntimeId));
    }

    /// <summary>Same exact-name fallback used by S2 profile presentation. Never registers a runtime alias.</summary>
    public ShipPresentation Find(string original, string displayName)
    {
        var result = Find(original);
        return result.CatalogId is null && result.Display is null ? Find(displayName) : result;
    }

    private static string Key(string value) => value.Length > 256 || value.Any(char.IsControl)
        ? "" : string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();
    private static void Add(Dictionary<string, Row?> index, string key, Row row)
    {
        if (index.TryGetValue(key, out var previous) && previous != row) index[key] = null;
        else index[key] = row;
    }
}
