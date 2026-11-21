using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal static class MarketplaceTradeDetails
{
    // SCM zone-less LocalDateTime values are Beijing civil time, not the Host's zone.
    internal static DateTimeOffset? Instant(JsonElement row, string key)
    {
        if (!row.TryGetProperty(key, out var value)) return null;
        if (value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var ms))
        {
            try { return DateTimeOffset.FromUnixTimeMilliseconds(ms); }
            catch (ArgumentOutOfRangeException) { return null; }
        }
        if (value.ValueKind != JsonValueKind.String || value.GetString() is not { } text) return null;
        if (text.Length < 16) return null;
        if (!text.EndsWith("Z", StringComparison.OrdinalIgnoreCase) &&
            !text[10..].Contains('+') && !text[10..].Contains('-')) text += "+08:00";
        return DateTimeOffset.TryParse(text, CultureInfo.InvariantCulture, DateTimeStyles.None, out var at) ? at : null;
    }

    // Same rule as SCM (OrderReportServiceImpl): refused only when whole days since creation > 7,
    // so a report is allowed until 8 full days have passed.
    internal static bool ReportWithinWindow(JsonElement row, DateTimeOffset? now = null) =>
        Instant(row, "createTime") is { } created &&
        (now ?? DateTimeOffset.UtcNow) < created.AddDays(8);

    internal static bool ReceiptExpired(JsonElement row) =>
        Instant(row, "receiptDeadline") is { } due && DateTimeOffset.UtcNow >= due;

    internal static void ProjectItems(JsonElement row, Dictionary<string, object?> result)
    {
        foreach (var key in new[] { "itemDetails", "wantedItems" })
        {
            if (!row.TryGetProperty(key, out var items) || items.ValueKind != JsonValueKind.Array) continue;
            result[key] = items.EnumerateArray().Where(x => x.ValueKind == JsonValueKind.Object).Take(50)
                .Select(item =>
                {
                    var fields = new Dictionary<string, object?>();
                    foreach (var field in new[] { "itemId", "itemName", "thumbnailUrl", "quantity", "unitPrice", "qualityData" })
                        if (item.TryGetProperty(field, out var value)) fields[field] = value.Clone();
                    return fields;
                }).ToArray();
            if (key == "itemDetails" && MarketplaceTradePolicy.Number(row, "displayType") == 1 &&
                items.GetArrayLength() > 0 && items[0].ValueKind == JsonValueKind.Object &&
                items[0].TryGetProperty("qualityData", out var quality))
                result["qualityData"] = quality.Clone();
        }
    }

    // Detail SQL joins reports from either party. Only an authenticated page row can
    // supply the current actor's report state. No cache miss triggers another SCM read.
    internal static JsonElement Merge(JsonElement detail, JsonElement? listRow)
    {
        var fields = detail.EnumerateObject().ToDictionary(p => p.Name, p => p.Value.Clone());
        fields.Remove("hasReported");
        fields.Remove("reportHandleStatus");
        if (listRow is { } row)
        {
            foreach (var key in new[] { "hasReported", "reportHandleStatus" })
                if (row.TryGetProperty(key, out var value)) fields[key] = value.Clone();
            if (MarketplaceTradePolicy.Number(detail, "displayType") == 2 &&
                detail.TryGetProperty("amount", out var amount) && amount.ValueKind == JsonValueKind.Number && amount.TryGetDecimal(out var price) && price == 0 &&
                row.TryGetProperty("amount", out var previous)) fields["amount"] = previous.Clone();
        }
        return JsonSerializer.SerializeToElement(fields);
    }
}