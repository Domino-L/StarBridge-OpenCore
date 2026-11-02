using System.Text.Json;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Translates the client draft contract. Never forwards arbitrary client fields to SCM.</summary>
internal static class MarketplaceListingRequest
{
    internal static int Expiry(long days) => days switch
    {
        7 => 0, 14 => 1, 0 => 2, _ => throw Invalid()
    };

    internal static AccountBridgeHostException Invalid() => new("marketplace.listing_invalid");
    internal static long Integer(JsonElement input, string key, long min = 1, long max = 999999)
    {
        if (!input.TryGetProperty(key, out var value)) throw Invalid();
        var parsed = value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var number)
            ? number : value.ValueKind == JsonValueKind.String && long.TryParse(value.GetString(), out number)
                ? number : throw Invalid();
        return parsed >= min && parsed <= max ? parsed : throw Invalid();
    }
    internal static string Text(JsonElement input, string key, int maximum)
    {
        var text = MarketplaceTradePolicy.Text(input, key);
        if (string.IsNullOrWhiteSpace(text) || text.Length > maximum || text.Any(char.IsControl)) throw Invalid();
        return text;
    }
    internal static bool Visible(JsonElement input) => input.TryGetProperty("visible", out var value) &&
        value.ValueKind is JsonValueKind.True or JsonValueKind.False ? value.GetBoolean() : throw Invalid();
    internal static decimal Price(JsonElement input, bool barter = false)
    {
        if (barter) return 0;
        if (!input.TryGetProperty("price", out var value) || value.ValueKind != JsonValueKind.Number ||
            !value.TryGetDecimal(out var price) || price <= 0 || price > 1000000000000000m) throw Invalid();
        return price;
    }
    internal static string? Quality(JsonElement input)
    {
        if (!input.TryGetProperty("quality", out var value) || value.ValueKind == JsonValueKind.Null ||
            value.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(value.GetString())) return null;
        return JsonSerializer.Serialize(new { type = "material", quality = Integer(input, "quality", 0, 1000) });
    }
    internal static object Create(JsonElement input, JsonElement manifest = default)
    {
        var side = Text(input, "side", 6);
        if (side is not ("sell" or "buy" or "barter")) throw Invalid();
        var fromManifest = manifest.ValueKind == JsonValueKind.Object;
        var item = fromManifest ? 0 : Integer(input, "itemId", 1, long.MaxValue);
        var count = Integer(input, "quantity");
        object[]? wanted = null;
        if (side == "barter")
        {
            if (!input.TryGetProperty("wanted", out var requested) || requested.ValueKind != JsonValueKind.Array ||
                requested.GetArrayLength() is < 1 or > 50) throw Invalid();
            var ids = new HashSet<long>();
            wanted = requested.EnumerateArray().Select(row =>
            {
                var id = Integer(row, "itemId", 1, long.MaxValue);
                if (id == item || !ids.Add(id)) throw Invalid();
                return (object)new { itemId = id, quantity = Integer(row, "quantity") };
            }).ToArray();
        }
        object[] provided = fromManifest
            ? ManifestItems(manifest)
            : new object[] { new { itemId = item, quantity = count, price = Price(input, side == "barter"), qualityData = Quality(input) } };
        return new
        {
            creatorType = side == "buy" ? 0 : 1,
            locationId = Integer(input, "location", 1, long.MaxValue),
            remainingQuantity = count,
            status = Visible(input) ? 1 : 0,
            expireTimeType = Expiry(Integer(input, "expiryDays", 0, 14)),
            items = provided,
            exchangeItemsList = wanted,
            manifestId = input.TryGetProperty("manifestId", out var manifestValue) && manifestValue.ValueKind != JsonValueKind.Null
                ? (long?)Integer(input, "manifestId", 1, long.MaxValue) : null
        };
    }
    private static object[] ManifestItems(JsonElement manifest)
    {
        if (!manifest.TryGetProperty("itemDetails", out var rows) || rows.ValueKind != JsonValueKind.Array || rows.GetArrayLength() is < 2 or > 50) throw Invalid();
        return rows.EnumerateArray().Select(row => {
            if (!row.TryGetProperty("unitPrice", out var price) || !price.TryGetDecimal(out var amount) || amount <= 0) throw Invalid();
            return (object)new { itemId = Integer(row, "itemId", 1, long.MaxValue), quantity = Integer(row, "quantity"),
                price = amount, qualityData = MarketplaceTradePolicy.Text(row, "qualityData") };
        }).ToArray();
    }
    internal static object Update(JsonElement input, bool barter) => new
    {
        orderNumber = Text(input, "id", 100),
        unitPrice = Price(input, barter),
        remainingQuantity = Integer(input, "quantity"),
        status = Visible(input) ? 1 : 0,
        expireTimeType = Expiry(Integer(input, "expiryDays", 0, 14)),
        qualityData = Quality(input)
    };
    internal static object Checklist(JsonElement input, bool update)
    {
        var title = Text(input, "name", 50);
        if (!input.TryGetProperty("items", out var items) || items.ValueKind != JsonValueKind.Array ||
            items.GetArrayLength() is < 2 or > 50) throw Invalid();
        var ids = new HashSet<long>();
        var lines = items.EnumerateArray().Select(row => {
            var id = Integer(row, "itemId", 1, long.MaxValue);
            if (!ids.Add(id)) throw Invalid();
            return new { itemId = id, quantity = Integer(row, "quantity"), unitPrice = Price(row), qualityData = Quality(row) };
        }).ToArray();
        var remark = MarketplaceTradePolicy.Text(input, "remark") ?? "";
        if (remark.Length > 200) throw Invalid();
        return new { id = update ? (long?)Integer(input, "id", 1, long.MaxValue) : null, title, items = lines, remark };
    }
}
