using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal static class MarketplaceListingProjection
{
    private static object? Value(JsonElement row, string key) => row.TryGetProperty(key, out var v) ? v.Clone() : null;
    // Match the public catalog's item-image projection; no image is downloaded here.
    private static string? Image(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Object) return null;
        foreach (var key in new[] { "thumbnailUrl", "thumbnailUrlHd" })
            if (row.TryGetProperty(key, out var value) && value.ValueKind == JsonValueKind.String &&
                !string.IsNullOrWhiteSpace(value.GetString())) return value.GetString();
        return null;
    }
    internal static object Order(JsonElement row)
    {
        var first = row.TryGetProperty("itemDetails", out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray().FirstOrDefault() : default;
        object? Item(string key) => first.ValueKind == JsonValueKind.Object ? Value(first, key) : null;
        return new {
            id = Value(row, "orderNumber"), name = Value(row, "itemName"), itemId = Item("itemId"),
            side = MarketplaceTradePolicy.Number(row, "displayType") == 3 ? "barter" : MarketplaceTradePolicy.Number(row, "creatorType") == 0 ? "buy" : "sell",
            quantity = Value(row, "remainingQuantity"), price = Value(row, "unitPrice"),
            visible = MarketplaceTradePolicy.Number(row, "status") == 1,
            checklist = MarketplaceTradePolicy.Number(row, "displayType") == 2,
            location = Value(row, "locationId"), locationName = Value(row, "locationName"),
            qualityData = Item("qualityData"), image = Image(first) ?? MarketplaceTradePolicy.Text(row, "thumbnailUrl"),
            displayType = Value(row, "displayType"), creatorType = Value(row, "creatorType"),
            // A list can contain only the first item. Do not invent a total of one.
            itemCount = Value(row, "itemCount"),
            expiry = Value(row, "expireTime"), timezoneId = Value(row, "timezoneId"),
            hasOngoingTransactions = Value(row, "hasOngoingTransactions"),
            ongoing = (int?)null, bestSell = (decimal?)null, bestBuy = (decimal?)null
        };
    }
    internal static object Manifest(JsonElement row) => new {
        id = Value(row, "id"), name = Value(row, "title"), remark = Value(row, "remark"), updated = Value(row, "updateTime"),
        items = row.TryGetProperty("itemDetails", out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray().Take(50).Select(item => new {
                itemId = Value(item, "itemId"), name = Value(item, "itemName"), quantity = Value(item, "quantity"),
                price = Value(item, "unitPrice"), qualityData = Value(item, "qualityData"), thumbnailUrl = Image(item)
            }).ToArray() : []
    };
}
