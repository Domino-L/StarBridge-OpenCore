using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Bounded projections for SCM trade messages (0.7.2 G9). Trade messages show the other
/// member's full handle, as on the SCM site; SCM member ids, avatars and the sender/buyer/seller ids
/// inside quote snapshots never leave the Host. The peer is an opaque per-process reference.</summary>
internal static class MarketplaceChat
{
    internal const int MaxContent = 150;

    internal static bool ValidOrderNumber(string? value) => value is not null &&
        System.Text.RegularExpressions.Regex.IsMatch(value, @"\A[A-Za-z0-9_-]{1,64}\z");

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

    internal static long Id(JsonElement row, string key) =>
        row.ValueKind == JsonValueKind.Object && row.TryGetProperty(key, out var v) &&
        v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var id) && id > 0 ? id : 0;

    private static bool Flag(JsonElement row, string key) =>
        row.ValueKind == JsonValueKind.Object && row.TryGetProperty(key, out var v) &&
        (v.ValueKind == JsonValueKind.True || v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n) && n == 1);

    internal static object Conversation(JsonElement row, string reference, Func<string> blockReference)
    {
        var result = new Dictionary<string, object?>
        {
            ["ref"] = reference,
            ["name"] = Value(row, "otherUserNickname", 100),
            // SCM shows stealth as offline already; anything else is unknown.
            ["online"] = Value(row, "otherUserSignInStatus") is JsonElement s && s.TryGetInt32(out var status) && status is >= 0 and <= 2 ? status : (int?)null,
            ["locale"] = Value(row, "otherUserLocale", 10),
            ["lastMessage"] = Value(row, "lastMessageContent", 200),
            ["lastTime"] = Value(row, "lastMessageTime", 40),
            ["unread"] = Value(row, "unreadCount"),
            ["blockedMe"] = Flag(row, "isBlockedByOther"),
            ["blockedByMe"] = Flag(row, "hasBlockedOther"),
            ["banHistory"] = Flag(row, "otherUserHasBanHistory"),
            ["banCount"] = Value(row, "otherUserBanCount"),
            ["banActive"] = Flag(row, "otherUserBanActive"),
            ["banReason"] = Value(row, "otherUserLastBanReason", 200),
        };
        if (Flag(row, "hasBlockedOther")) result["blockRef"] = blockReference();
        return result;
    }

    /// <summary>A message in one conversation; <c>mine</c> is decided by the Host from the peer id.</summary>
    internal static object Message(JsonElement row, long peer) => new
    {
        id = Value(row, "id"),
        mine = Id(row, "fromUserId") is var from && from != 0 && from != peer,
        content = Value(row, "content", 1000),
        quote = Quote(row),
        risky = Flag(row, "hasRiskyLink"),
        read = Flag(row, "isRead"),
        time = Value(row, "createTime", 40),
    };

    private static object? Quote(JsonElement row)
    {
        var type = Value(row, "quoteType", 20) as string;
        if (type is not ("order" or "image")) return null;
        JsonElement snapshot = default;
        if (Value(row, "quoteSnapshot", 8000) is string raw)
        {
            try { snapshot = JsonDocument.Parse(raw).RootElement.Clone(); }
            catch (JsonException) { }
        }
        // An order quote without a usable snapshot (missing, unparsable, truncated, no valid
        // order number) is no attachment at all: report none, so the client can say
        // "订单没有附上" instead of drawing an empty card.
        if (type == "order" && (snapshot.ValueKind != JsonValueKind.Object ||
            Value(snapshot, "orderNo", 65) is not string quoted || !ValidOrderNumber(quoted))) return null;
        return type == "order"
            ? (object)new
            {
                type,
                orderId = Value(snapshot, "orderId") ?? Value(row, "quoteId", 40),
                orderNo = Value(snapshot, "orderNo", 65) is string number && ValidOrderNumber(number) ? number : null,
                displayType = Value(snapshot, "displayType"),
                mainImage = Value(snapshot, "mainImage", 2000),
                qualityData = Value(snapshot, "qualityData", 4000),
                itemId = Value(snapshot, "itemId", 60),
                itemName = Value(snapshot, "itemName", 200),
                itemNameEn = Value(snapshot, "itemNameEn", 200),
                amount = Value(snapshot, "amount"),
                status = Value(snapshot, "status", 40),
                statusText = Value(snapshot, "statusText", 60),
                remaining = Value(snapshot, "remainingQuantity"),
            }
            : new { type, width = Value(snapshot, "width"), height = Value(snapshot, "height") };
    }
}
