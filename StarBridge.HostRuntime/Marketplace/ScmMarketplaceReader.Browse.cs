using System.Globalization;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed partial class ScmMarketplaceReader
{
    internal static Dictionary<string, string> BrowseOptions(JsonElement options)
    {
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        if (options.ValueKind == JsonValueKind.Undefined) return result;
        if (options.ValueKind != JsonValueKind.Object || options.GetRawText().Length > 8192) throw new ArgumentException("Invalid browse options.");
        foreach (var p in options.EnumerateObject())
        {
            if (result.Count >= 40 || p.Name.Length > 160 || p.Value.ValueKind != JsonValueKind.String || !result.TryAdd(p.Name, p.Value.GetString()!))
                throw new ArgumentException("Invalid browse options.");
            var v = result[p.Name];
            if (v.Length > 500 || v.Any(char.IsControl)) throw new ArgumentException("Invalid browse value.");
            var valid = p.Name switch
            {
                "minOrderCount" => v == "1",
                "creatorType" => v is "0" or "1",
                "displayType" => v is "1" or "2" or "3",
                "creatorStatus" => v is "1" or "2",
                "hasQuality" => v == "true",
                "sortOrder" => v is "asc" or "desc",
                "sortType" => v is "time" or "price",
                "sortKey" => v is "totalOrderCount" or "sellOrderCount" or "buyOrderCount" || JsonPath(v),
                "minPrice" or "maxPrice" or "locationId" => long.TryParse(v, out var n) && n >= 0,
                "minQuality" or "maxQuality" => int.TryParse(v, out var n) && n is >= 0 and <= 1000,
                _ => (p.Name.StartsWith("enum:") && JsonPath(p.Name[5..]) && v.Length > 0) ||
                    ((p.Name.StartsWith("min:") || p.Name.StartsWith("max:")) && JsonPath(p.Name[4..]) &&
                        decimal.TryParse(v, NumberStyles.Float, CultureInfo.InvariantCulture, out _))
            };
            if (!valid) throw new ArgumentException("Unsupported browse filter.");
        }
        return result;
    }
    private static bool JsonPath(string path) => Regex.IsMatch(path, @"^\$\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*$");

    private async Task<object> Browse(string operation, string keyword, long category, int page, string language, JsonElement options,
        CancellationToken ct, Func<JsonElement, string?>? traderReference)
    {
        var values = BrowseOptions(options);
        var orders = operation == "marketOrders";
        var dynamic = values.Keys.Any(k => k.Contains(':')) || values.GetValueOrDefault("sortKey", "").StartsWith('$');
        if (orders && values.Keys.Any(k => k is "sortKey" or "minOrderCount" || k.Contains(':')) ||
            !orders && values.Keys.Any(k => k is not ("sortKey" or "sortOrder" or "minOrderCount") && !k.Contains(':')))
            throw new ArgumentException("Filter is not available in this view.");
        if (dynamic)
        {
            var categories = await CategoryTree(ct);
            var current = category;
            JsonElement config = default;
            var visited = new HashSet<long>();
            while (current > 0 && visited.Add(current))
            {
                var cat = categories.EnumerateArray().FirstOrDefault(c => Long(c, "id") == current);
                if (cat.ValueKind == JsonValueKind.Undefined) break;
                var raw = Text(cat, "filterConfig");
                if (!string.IsNullOrWhiteSpace(raw))
                {
                    try { using var document = JsonDocument.Parse(raw); config = document.RootElement.Clone(); break; }
                    catch (JsonException) { }
                }
                current = Long(cat, "parentId") ?? 0;
            }
            foreach (var (key, value) in values)
            {
                if (key == "sortKey" && value.StartsWith('$'))
                {
                    var sorts = At(config, "sorts");
                    if (sorts.ValueKind != JsonValueKind.Array || !sorts.EnumerateArray().Any(s => Text(s, "jsonPath") == value)) throw new ArgumentException("Unknown category sort.");
                }
                if (!key.Contains(':')) continue;
                var path = key[(key.IndexOf(':') + 1)..];
                var filters = At(config, "filters");
                if (filters.ValueKind != JsonValueKind.Array) throw new ArgumentException("Missing category filters.");
                var filter = filters.EnumerateArray().FirstOrDefault(f => Text(f, "jsonPath") == path);
                if (key.StartsWith("enum:"))
                {
                    var choices = At(filter, "options");
                    if (Text(filter, "type") != "enum" || choices.ValueKind != JsonValueKind.Array ||
                        value.Split(',').Any(v => !choices.EnumerateArray().Any(c => Text(c, "value") == v))) throw new ArgumentException("Unknown category enum.");
                }
                else if (Text(filter, "type") != "range") throw new ArgumentException("Unknown category range.");
            }
        }
        string Query(bool listed, bool count = false)
        {
            var fields = new Dictionary<string, string> { ["pageNo"] = page.ToString(), ["pageSize"] = "20", ["keyword"] = keyword, ["language"] = language };
            if (category > 0) fields["categoryId"] = category.ToString();
            foreach (var (key, value) in values)
            {
                if (!listed && key == "minOrderCount") continue;
                var name = key.StartsWith("enum:") ? $"enumFilters[{key[5..]}]" : key.StartsWith("min:") ? $"rangeFilters[{key[4..]}].min" : key.StartsWith("max:") ? $"rangeFilters[{key[4..]}].max" : key;
                fields[name] = value;
            }
            if (count) { fields["pageNo"] = "1"; fields["pageSize"] = "1"; }
            return string.Join("&", fields.Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));
        }
        var data = await Get((orders ? "sc/orders/page?" : "product/items/search-list?") + Query(true), ct);
        var total = Long(data, "total") ?? throw new JsonException("Missing total.");
        long? allTotal = total;
        long? listedTotal = orders ? null : total;
        if (!orders && values.ContainsKey("minOrderCount"))
        {
            // One aggregate page per query, never one request per item.
            allTotal = Long(await Get("product/items/search-list?" + Query(false, true) + "&maxOrderCount=0", ct), "total") is long absent ? total + absent : null;
        }
        else if (!orders) listedTotal = Long(await Get("product/items/search-list?" + Query(false, true) + "&minOrderCount=1", ct), "total");
        var rows = Rows(At(data, "list"), orders ? p => Quote(p, traderReference) : Item);
        if (orders) await WithImagelessCategories(rows, true, ct);
        return new { rows, total, allTotal, listedTotal };
    }
}
