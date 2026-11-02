using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Bounded projection for SCM station messages (0.7.2 G8). The trader is masked as in the hall
/// and reachable through an opaque chat reference; user, sender and trader ids and product URLs stay
/// in the Host. <c>type</c>: 0 system, 1 trade, 2 chat fallback; trade <c>subType</c>: 1 request,
/// 2 approved, 3 cancelled, 4 delivered, 5 received, 6 review, 7 timeout.</summary>
internal static class MarketplaceNotices
{
    private static object? Value(JsonElement row, string key, int max = 500)
    {
        if (row.ValueKind != JsonValueKind.Object || !row.TryGetProperty(key, out var v)) return null;
        return v.ValueKind switch
        {
            JsonValueKind.String => v.GetString() is { } text ? text.Length > max ? text[..max] : text : null,
            JsonValueKind.Number => v.Clone(),
            JsonValueKind.True or JsonValueKind.False => v.GetBoolean(),
            _ => null,
        };
    }

    private static object[] Items(JsonElement order, string key) =>
        order.ValueKind == JsonValueKind.Object && order.TryGetProperty(key, out var items) && items.ValueKind == JsonValueKind.Array
            ? items.EnumerateArray().Take(20).Select(item => (object)new
            {
                itemId = Value(item, "itemId", 60),
                name = Value(item, "name", 200),
                quantity = Value(item, "quantity"),
            }).ToArray()
            : [];

    internal static object Notice(JsonElement row, Func<long, string> chat)
    {
        var order = row.ValueKind == JsonValueKind.Object && row.TryGetProperty("orderInfo", out var o) && o.ValueKind == JsonValueKind.Object ? o : default;
        var trader = MarketplaceChat.Id(order, "traderId");
        return new
        {
            id = Value(row, "id"),
            type = Value(row, "type"),
            subType = Value(row, "subType"),
            rating = Value(row, "rating"),
            title = Value(row, "title", 200),
            content = Value(row, "content", 1000),
            read = Value(row, "isRead") is true || Value(row, "isRead") is JsonElement r && r.TryGetInt32(out var flag) && flag == 1,
            time = Value(row, "createTime", 40),
            expiry = Value(row, "expiryTime", 40),
            order = order.ValueKind != JsonValueKind.Object ? null : new
            {
                orderId = Value(order, "orderId"),
                orderNumber = Value(order, "orderNumber", 60),
                transactionId = Value(order, "transactionId", 60),
                productName = Value(order, "productName", 200),
                quantity = Value(order, "quantity"),
                amount = Value(order, "amount"),
                trader = MarketplaceRecords.Mask(Value(order, "traderName", 100) as string),
                traderChat = trader > 0 ? chat(trader) : null,
                provided = Items(order, "providedItems"),
                wanted = Items(order, "wantedItems"),
            },
        };
    }
}
