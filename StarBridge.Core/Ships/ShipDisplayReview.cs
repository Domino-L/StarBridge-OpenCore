using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.Core.Ships;

/// <summary>Reviewed UI semantics, independent of official classifications and ownership.</summary>
public sealed record ShipDisplayReview(string Category, string SizeClass, string Domain, string? IconKey);

/// <summary>Optional private review data. Exact names and explicitly vetted runtime IDs only.</summary>
internal sealed class ShipDisplayReviewCatalog
{
    private readonly Dictionary<string, ShipDisplayReview?> _names = new(StringComparer.Ordinal);
    private readonly Dictionary<string, ShipDisplayReview?> _codes = new(StringComparer.OrdinalIgnoreCase);

    internal ShipDisplayReviewCatalog(string? json)
    {
        if (string.IsNullOrWhiteSpace(json) || json.Length > 2 * 1024 * 1024) return;
        try
        {
            using var doc = JsonDocument.Parse(json);
            var root = doc.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1) return;
            var rows = root.GetProperty("records");
            if (rows.GetArrayLength() > 5000) return;
            foreach (var row in rows.EnumerateArray())
            {
                var category = row.GetProperty("category").GetString();
                var size = row.GetProperty("sizeClass").GetString();
                var domain = row.GetProperty("domain").GetString();
                var icon = row.GetProperty("iconKey").GetString();
                if (category is not ("combat" or "exploration" or "industrial" or "support" or "transport" or "competition" or "multi-role") ||
                    size is not ("small" or "medium" or "large" or "capital") ||
                    domain is not ("spacecraft" or "ground" or "flying-utility") ||
                    domain == "ground" && size == "capital" ||
                    icon is not null && !Regex.IsMatch(icon, "^[a-z][a-z-]{0,95}$")) continue;
                var display = new ShipDisplayReview(category, size, domain, icon);
                foreach (var key in new[] { "englishName", "chineseName", "catalogId" }
                    .Select(field => Key(row.GetProperty(field).GetString())).Distinct(StringComparer.Ordinal))
                    Add(_names, key, display);
                // Null means identity unresolved; do not repair it via Chinese-name inference.
                var code = row.GetProperty("runtimeId").GetString();
                if (!string.IsNullOrWhiteSpace(code) && code.Length <= 256) Add(_codes, code, display);
            }
        }
        catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException)
        { _names.Clear(); _codes.Clear(); }
    }

    internal ShipDisplayReview? Find(string original, string? runtimeId)
    {
        if (_names.TryGetValue(Key(original), out var direct)) return direct;
        if (_codes.TryGetValue(original, out var exact)) return exact;
        return runtimeId is not null && _codes.TryGetValue(runtimeId, out var alias) ? alias : null;
    }

    private static string Key(string? value) => value is null || value.Length > 256 || value.Any(char.IsControl)
        ? "" : string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();
    private static void Add(Dictionary<string, ShipDisplayReview?> map, string key, ShipDisplayReview value)
    {
        if (key.Length == 0) return;
        // Even identical display facts do not resolve duplicate identities.
        if (!map.TryAdd(key, value)) map[key] = null;
    }
}
