using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Notifications;

namespace StarBridge.HostRuntime.Marketplace;

internal static class MarketplaceNoticeItem
{
    // Only the notification's existing snapshot and parsed Java item text are used.
    internal static string Describe(JsonElement order, string legacy, string? language = null)
    {
        language ??= CultureInfo.CurrentUICulture.Name;
        var en = !language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var hant = language.Contains("TW", StringComparison.OrdinalIgnoreCase) ||
            language.Contains("Hant", StringComparison.OrdinalIgnoreCase) ||
            language.Contains("HK", StringComparison.OrdinalIgnoreCase);
        string Count(string name, int count) => en ? $"{name} ({count} items)" :
            hant ? $"{name}（共 {count} 件）" : $"{name}（共 {count} 件）";
        string Swap(string give, string want) => en ? $"Give {give} for {want}" :
            hant ? $"給出 {give} 換取 {want}" : $"给出 {give} 换取 {want}";
        JsonElement Items(string key) => order.ValueKind == JsonValueKind.Object &&
            order.TryGetProperty(key, out var rows) && rows.ValueKind == JsonValueKind.Array ? rows : default;
        string Names(JsonElement rows) => rows.ValueKind != JsonValueKind.Array ? "" :
            string.Join("、", rows.EnumerateArray().Take(3).Select(x => TradeNotificationEvent.TextField(x, "name")));
        string Summary(JsonElement rows) => rows.GetArrayLength() > 3
            ? Count(Names(rows), rows.GetArrayLength()) : Names(rows);
        var provided = Items("providedItems");
        var wanted = Items("wantedItems");
        var split = legacy.Split(" 换取 ", 2, StringSplitOptions.None);
        var give = split[0];
        var marker = give.IndexOf("】，包含物品：", StringComparison.Ordinal);
        if (give.StartsWith("清单【", StringComparison.Ordinal) && marker >= 4)
        {
            var count = provided.ValueKind == JsonValueKind.Array ? provided.GetArrayLength() :
                give[(marker + "】，包含物品：".Length)..].Split('、', StringSplitOptions.RemoveEmptyEntries).Length;
            give = Count(give[3..marker], count);
        }
        else if (provided.ValueKind == JsonValueKind.Array && provided.GetArrayLength() > 0)
            give = Summary(provided);
        else if (give.Length == 0) give = TradeNotificationEvent.TextField(order, "productName");
        if (wanted.ValueKind == JsonValueKind.Array && wanted.GetArrayLength() > 0)
            return Swap(give, Summary(wanted));
        return split.Length == 2 ? Swap(give, split[1]) : give;
    }
}
