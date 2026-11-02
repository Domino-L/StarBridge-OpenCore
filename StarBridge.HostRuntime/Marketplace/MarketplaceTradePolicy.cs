using StarBridge.HostRuntime.Account;
using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>SCM is authoritative. Unknown roles/states never grant an action.</summary>
internal static class MarketplaceTradePolicy
{
    internal static string? Action(JsonElement row)
    {
        var role = Text(row, "actorRole");
        var state = Number(row, "deliveryStatus");
        if (role is not ("buyer" or "seller")) return null;
        if (state != 3 && Number(row, "transactionStatus") != 1) return null;
        if (state == 0 && role == "buyer" && Number(row, "creatorType") == 0) return "approve";
        if (state == 1 && role == "seller") return "ship";
        if (state == 2 && role == "buyer") return "receive";
        if (state == 3 && Number(row, "transactionStatus") == 2 &&
            !Has(row, role + "CommentId")) return "review";
        return null;
    }
    internal static bool Allows(JsonElement row, string action) =>
        Text(row, "actorRole") is "buyer" or "seller" &&
        (action == Action(row) || action == "cancel" && Number(row, "transactionStatus") == 1 && Number(row, "deliveryStatus") is 0 or 1 ||
         action == "report" && Number(row, "transactionStatus") == 2 && Number(row, "deliveryStatus") == 3 &&
         !(row.TryGetProperty("hasReported", out var reported) && reported.ValueKind == JsonValueKind.True));

    /// <param name="chat">Mints the opaque trade-chat reference for the counterparty (0.7.2 G9
    /// "私信对方"); the SCM member id itself never leaves the Host.</param>
    internal static object Project(JsonElement row, Func<long, string>? chat = null)
    {
        var result = new Dictionary<string, object?>();
        foreach (var key in new[] { "transactionNumber", "orderId", "creatorType", "actorRole", "actorTradeType", "orderType",
            "itemsId", "itemsName", "thumbnailUrl", "displayType", "number", "amount", "transactionStatus", "deliveryStatus",
            "locationName", "transactionLocationName", "receiptDeadline", "shipmentDeadline", "createTime", "shippedTime", "approvalTime",
            "completionTime", "cancellationTime", "cancellationReason", "deliveryProof", "deliveryMethod", "shippingFee", "qualityData",
            "buyerCommentId", "buyerRating", "buyerContent", "buyerCommentTime", "sellerCommentId", "sellerRating",
            "sellerContent", "sellerCommentTime", "hasReported" })
            if (row.TryGetProperty(key, out var value)) result[key] = value.Clone();
        if (Text(row, "itemsName") is { } name)
            result["itemsNameHant"] = ScmMarketplaceReader.Traditional(name);
        // Names are display data; role is supplied by SCM, never inferred from a name.
        var ownerIsBuyer = Number(row, "creatorType") == 0;
        var actorIsBuyer = Text(row, "actorRole") == "buyer";
        result["counterpartyName"] = Text(row, ownerIsBuyer == actorIsBuyer ? "tradingerName" : "orderOwnerName");
        result["counterpartyAvatar"] = RsiAvatarImage.Validate(Text(row, ownerIsBuyer == actorIsBuyer ? "tradingerAvatar" : "orderOwnerAvatar"))?.AbsoluteUri;
        // creatorStatus describes the order owner, not necessarily the counterparty.
        result["counterpartyStatus"] = ownerIsBuyer == actorIsBuyer ? null : Number(row, "creatorStatus");
        if (chat is not null && row.TryGetProperty(ownerIsBuyer == actorIsBuyer ? "tradingerId" : "orderOwnerId", out var counterparty) &&
            counterparty.ValueKind == JsonValueKind.Number && counterparty.TryGetInt64(out var member) && member > 0)
            result["counterpartyChat"] = chat(member);
        result["action"] = Action(row);
        result["canCancel"] = Allows(row, "cancel");
        result["canReport"] = Allows(row, "report");
        return result;
    }
    internal static string? Text(JsonElement row, string key) => row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString() : null;
    internal static int? Number(JsonElement row, string key) => row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt32(out var n) ? n : null;
    private static bool Has(JsonElement row, string key) => row.TryGetProperty(key, out var v) && v.ValueKind is not (JsonValueKind.Null or JsonValueKind.Undefined);
}
