using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    private readonly object _notificationTradeGate = new();
    private readonly Dictionary<string, (string Owner, string Number)> _notificationTrades = new(StringComparer.Ordinal);

    internal void ClearNotificationTradeReferences()
    {
        lock (_notificationTradeGate)
        {
            _notificationTrades.Clear(); _stationReceipts.Clear();
            _stationReceiptEpoch++; _stationReadRevision++;
            _stationReadBarriers.Clear(); _stationReconciliations.Clear(); _stationPollBaselines.Clear(); _stationPolled.Clear();
            foreach (var pending in _stationPendingReads) pending.Completed.TrySetResult();
            _stationPendingReads.Clear();
        }
    }

    private string NotificationTradeReference(string owner, string number)
    {
        lock (_notificationTradeGate) {
            foreach (var (key, value) in _notificationTrades)
                if (value.Owner == owner && value.Number == number) return key;
            if (_notificationTrades.Count >= 4096) return "";
            var reference = Guid.NewGuid().ToString("N");
            _notificationTrades.Add(reference, (owner, number));
            return reference;
        }
    }

    internal string ResolveNotificationTradeReference(string owner, string reference)
    {
        lock (_notificationTradeGate)
            return _notificationTrades.TryGetValue(reference, out var target) && target.Owner == owner ? target.Number
                : throw new AccountBridgeHostException("marketplace.state_changed");
    }

    private static bool IsStationTradeNotification(JsonElement row)
    {
        if (row.ValueKind != JsonValueKind.Object || MarketplaceChat.Id(row, "id") <= 0) return false;
        var type = MarketplaceTradePolicy.Number(row, "type");
        var subtype = MarketplaceTradePolicy.Number(row, "subType") ?? 0;
        return type == 0 && TradeNotificationEvent.TextField(row, "title") == "收货提醒" || type == 1 && subtype is >= 1 and <= 10;
    }

    internal TradeNotificationEvent? ProjectTradeNotification(string owner, JsonElement row)
    {
        if (!IsStationTradeNotification(row)) return null;
        var type = MarketplaceTradePolicy.Number(row, "type");
        var subType = MarketplaceTradePolicy.Number(row, "subType") ?? 0;
        var title = TradeNotificationEvent.TextField(row, "title");
        var reminder = type == 0 && title == "收货提醒";
        var alreadyRead = row.TryGetProperty("isRead", out var read) &&
            (read.ValueKind == JsonValueKind.True || read.ValueKind == JsonValueKind.Number && read.TryGetInt32(out var flag) && flag == 1);
        if (!ObserveStationReceipt(owner, MarketplaceChat.Id(row, "id"), type ?? -1, alreadyRead)) return null;
        var order = row.TryGetProperty("orderInfo", out var info) && info.ValueKind == JsonValueKind.Object ? info : default;
        var legacy = TradeNotificationEvent.JavaStationText(row, subType, reminder);
        var number = TradeNotificationEvent.StationTransactionNumber(row, order, legacy.Number);
        var reference = number.Length == 0 ? null : NotificationTradeReference(owner, number);
        string Safe(string text) => SafeNotificationText(row, text);
        var name = TradeNotificationEvent.TextField(order, "traderName");
        if (name.Length == 0) name = legacy.Peer;
        var item = TradeNotificationEvent.TextField(order, "productName");
        if (item.Length == 0 && order.ValueKind == JsonValueKind.Object &&
            order.TryGetProperty("providedItems", out var items) && items.ValueKind == JsonValueKind.Array)
            item = string.Join("、", items.EnumerateArray().Take(3).Select(i => TradeNotificationEvent.TextField(i, "name")));
        if (item.Length == 0) item = legacy.Item;
        // Station cards never carry the counterparty name, masked or not.
        if (name.Length > 0) title = title.Replace(name, "对方", StringComparison.Ordinal);
        var figures = TradeNotificationEvent.StationFigures(row, subType, reminder, new[] {
            TradeNotificationEvent.TextField(row, "transactionId"), TradeNotificationEvent.TextField(order, "transactionId"),
            legacy.Number, TradeNotificationEvent.TextField(order, "orderNumber"), MarketplaceChat.Id(row, "userId").ToString(),
            MarketplaceChat.Id(row, "senderId").ToString(), MarketplaceChat.Id(order, "traderId").ToString() }.Where(v => v != "0"));
        return new(TradeNotificationEvent.KeyFor("station", MarketplaceChat.Id(row, "id")), false,
            reference, subType, Safe(title), Safe(item),
            MarketplaceRecords.Mask(Safe(name)) ?? "", "", reminder, figures.Quantity, figures.Amount);
    }
}
