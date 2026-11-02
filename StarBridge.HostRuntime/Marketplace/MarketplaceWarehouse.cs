using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Bounded projections for the member's own SCM warehouse (0.7.2 G2, read only). Owner and
/// actor ids, avatars, image URLs and package snapshots stay in the Host.</summary>
internal static class MarketplaceWarehouse
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

    internal static object Space(JsonElement row) => new
    {
        id = Value(row, "id"),
        name = Value(row, "name", 100),
        code = Value(row, "code", 60),
        note = Value(row, "description", 300),
        locationId = Value(row, "locationId"),
        location = Value(row, "locationName", 100),
        locationPath = Value(row, "locationFullPath", 300),
        isDefault = Value(row, "isDefault") is true,
        status = Value(row, "status"),
        lines = Value(row, "inventoryLineCount"),
        onHand = Value(row, "onHandQuantity"),
        reserved = Value(row, "reservedQuantity"),
        available = Value(row, "availableQuantity"),
    };

    internal static object Inventory(JsonElement row) => new
    {
        id = Value(row, "id"),
        spaceId = Value(row, "spaceId"),
        space = Value(row, "spaceName", 100),
        location = Value(row, "locationName", 100),
        locationPath = Value(row, "locationFullPath", 300),
        itemId = Value(row, "itemId", 60),
        itemName = Value(row, "itemName", 200),
        itemNameEn = Value(row, "itemNameEn", 200),
        quality = Value(row, "qualityKey", 100),
        onHand = Value(row, "onHandQuantity"),
        reserved = Value(row, "reservedQuantity"),
        available = Value(row, "availableQuantity"),
    };

    internal static object Summary(JsonElement row) => new
    {
        spaces = Value(row, "spaceCount"),
        lines = Value(row, "inventoryLineCount"),
        items = Value(row, "distinctItemCount"),
        onHand = Value(row, "onHandQuantity"),
        reserved = Value(row, "reservedQuantity"),
        available = Value(row, "availableQuantity"),
    };

    internal static object Ledger(JsonElement row) => new
    {
        id = Value(row, "id"),
        operationNo = Value(row, "operationNo", 60),
        operationType = Value(row, "operationType", 40),
        space = Value(row, "spaceName", 100),
        location = Value(row, "locationName", 100),
        from = Value(row, "sourceSpaceName", 100),
        to = Value(row, "targetSpaceName", 100),
        itemId = Value(row, "itemId", 60),
        itemName = Value(row, "itemName", 200),
        itemNameEn = Value(row, "itemNameEn", 200),
        quality = Value(row, "qualityKey", 100),
        deltaOnHand = Value(row, "deltaOnHand"),
        deltaReserved = Value(row, "deltaReserved"),
        afterOnHand = Value(row, "afterOnHand"),
        businessType = Value(row, "businessType", 40),
        businessNo = Value(row, "businessNo", 60),
        reason = Value(row, "reasonCode", 60),
        note = Value(row, "note", 200),
        time = Value(row, "occurredAt", 40),
    };

    internal static object Escrow(JsonElement row) => new
    {
        id = Value(row, "id"),
        businessType = Value(row, "businessType", 40),
        businessNo = Value(row, "businessNo", 60),
        side = Value(row, "itemSide", 20),
        itemId = Value(row, "itemId", 60),
        itemName = Value(row, "itemName", 200),
        itemNameEn = Value(row, "itemNameEn", 200),
        quantity = Value(row, "quantity"),
        locationId = Value(row, "locationId"),
        status = Value(row, "status", 40),
        orderStatus = Value(row, "orderStatus", 40),
        transactionStatus = Value(row, "transactionStatus", 40),
        deliveryStatus = Value(row, "deliveryStatus", 40),
        time = Value(row, "createTime", 40),
    };
}
