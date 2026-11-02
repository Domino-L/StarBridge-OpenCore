using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Bounded projections for the member's records (0.7.2 G5/G6/G7). Only display fields leave
/// the Host: no SCM member ids, avatars, handler names or evidence URLs; other members' nicknames are
/// masked as in every hall list.</summary>
internal static class MarketplaceRecords
{
    private static object? Value(JsonElement row, string key, int max = 2000)
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

    internal static string? Mask(string? name)
    {
        if (string.IsNullOrEmpty(name)) return null;
        if (name.Contains('*')) return name;
        // Keep whole text elements: a UTF-16 cut would split emoji into lone surrogates.
        var starts = StringInfo.ParseCombiningCharacters(name);
        return starts.Length < 2 ? "*" : name[..starts[1]] + "*****" + name[starts[^1]..];
    }

    internal static object Review(JsonElement row) => new
    {
        id = Value(row, "id"),
        transactionId = Value(row, "transactionId", 100),
        reviewer = Mask(Value(row, "reviewerName", 100) as string),
        rating = Value(row, "rating"),
        content = Value(row, "content", 500),
        auditStatus = Value(row, "auditStatus"),
        createTime = Value(row, "createTime", 40),
        source = Value(row, "sourceLabel", 40),
    };

    internal static object Report(JsonElement row) => new
    {
        id = Value(row, "id"),
        transactionNumber = Value(row, "transactionNumber", 100),
        reported = Mask(Value(row, "reportedUserNickname", 100) as string),
        reportType = Value(row, "reportTypeName", 60),
        content = Value(row, "reportContent", 500),
        status = Value(row, "handleStatusName", 40),
        result = Value(row, "handleResult", 500),
        handleTime = Value(row, "handleTime", 40),
        createTime = Value(row, "createTime", 40),
    };

    internal static object Block(JsonElement row, Func<long, string> reference)
    {
        var blocked = row.ValueKind == JsonValueKind.Object && row.TryGetProperty("blockedUserId", out var id) &&
            id.ValueKind == JsonValueKind.Number && id.TryGetInt64(out var value) && value > 0 ? value : 0;
        if (blocked == 0) throw new JsonException("Blocked user without id.");
        return new
        {
            @ref = reference(blocked),
            name = Mask(Value(row, "blockedUserNickname", 100) as string),
            reason = Value(row, "reason", 200),
            active = Value(row, "status") is JsonElement status && status.TryGetInt32(out var s) ? s == 1 : (bool?)null,
            createTime = Value(row, "createTime", 40),
        };
    }
}
