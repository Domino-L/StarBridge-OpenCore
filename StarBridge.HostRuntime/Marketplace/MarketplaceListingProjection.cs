using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal static class MarketplaceListingProjection
{
    private static object? Value(JsonElement row, string key) => row.TryGetProperty(key, out var v) ? v.Clone() : null;
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
            qualityData = Item("qualityData"), image = Value(row, "thumbnailUrl"),
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
                price = Value(item, "unitPrice"), qualityData = Value(item, "qualityData")
            }).ToArray() : []
    };
}
