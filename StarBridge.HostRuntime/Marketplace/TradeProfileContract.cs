using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.HostRuntime.Account;

namespace StarBridge.HostRuntime.Marketplace;

internal static class TradeProfileContract
{
    internal static AccountBridgeHostException Error(string suffix) => new("trade_profile." + suffix);
    internal static object Project(JsonElement raw)
    {
        object? Value(JsonElement source, string key) => source.ValueKind == JsonValueKind.Object && source.TryGetProperty(key, out var v) ? v.Clone() : null;
        var achievement = raw.TryGetProperty("achievement", out var a) ? a : default;
        return new {
            tradeTime = StoredDays(raw), tradeStartTime = Value(raw, "tradeStartTime"), tradeEndTime = Value(raw, "tradeEndTime"),
            timezoneId = Value(raw, "timezoneId"), userMobile = Value(raw, "userMobile"), mark = Value(raw, "mark"),
            language = Value(raw, "language"), point = Value(achievement, "point"), orderLimit = Value(achievement, "orderLimit"),
            completedTransactionCount = Value(raw, "completedTransactionCount")
        };
    }
    // SCM treats a blank tradeTime as "not set"; a read must show that state instead of failing.
    internal static int[] StoredDays(JsonElement raw)
    {
        try { return Days(raw); }
        catch (AccountBridgeHostException) { return new int[7]; }
    }
    internal static int[] Days(JsonElement raw)
    {
        if (!raw.TryGetProperty("tradeTime", out var v) || v.ValueKind == JsonValueKind.Null ||
            v.ValueKind == JsonValueKind.String && string.IsNullOrWhiteSpace(v.GetString())) return new int[7];
        try {
            if (v.ValueKind == JsonValueKind.String) v = JsonSerializer.Deserialize<JsonElement>(v.GetString()!);
            var days = v.EnumerateArray().Select(x => x.GetInt32()).ToArray();
            if (days.Length != 7 || days.Any(x => x is not (0 or 1))) throw Error("no_day");
            return days;
        } catch (Exception e) when (e is JsonException or InvalidOperationException or FormatException) { throw Error("no_day"); }
    }
    internal static Dictionary<string, object> Merge(JsonElement current, JsonElement changes)
    {
        string[] required = ["tradeTime", "tradeStartTime", "tradeEndTime", "timezoneId", "userMobile"];
        string[] optional = ["mark", "language", "profileBackground"];
        if (changes.ValueKind != JsonValueKind.Object || changes.EnumerateObject().Any(p => !required.Contains(p.Name) && !optional.Contains(p.Name))) throw Error("rejected");
        var result = new Dictionary<string, object>();
        foreach (var key in required) {
            var source = changes.TryGetProperty(key, out _) ? changes : current;
            if (key == "tradeTime") { result[key] = Days(source); continue; }
            if (!source.TryGetProperty(key, out var v) || v.ValueKind == JsonValueKind.Null) throw Error(key == "timezoneId" ? "timezone_invalid" : key == "userMobile" ? "contact_invalid" : "time_range");
            result[key] = v.Clone();
        }
        var days = (int[])result["tradeTime"];
        if (!days.Contains(1)) throw Error("no_day");
        int Minutes(string key) {
            var value = ((JsonElement)result[key]);
            var text = value.ValueKind == JsonValueKind.String ? value.GetString()! : "";
            if (!Regex.IsMatch(text, "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$")) throw Error("time_range");
            return int.Parse(text[..2]) * 60 + int.Parse(text[3..]);
        }
        var duration = (Minutes("tradeEndTime") - Minutes("tradeStartTime") + 1440) % 1440;
        if (duration < 60) throw Error("time_range");
        var contact = (JsonElement)result["userMobile"];
        if (contact.ValueKind != JsonValueKind.String || (contact.GetString()?.Trim().Length ?? 0) < 5) throw Error("contact_invalid");
        var zone = (JsonElement)result["timezoneId"];
        if (zone.ValueKind != JsonValueKind.Number || !zone.TryGetInt64(out var zoneId) || zoneId <= 0) throw Error("timezone_invalid");
        foreach (var key in optional) if (changes.TryGetProperty(key, out var value)) {
            if (value.ValueKind != JsonValueKind.String) throw Error("rejected");
            var text = value.GetString()!;
            if (key == "language" && text is not ("0" or "1") || key == "profileBackground" && text.Length > 512) throw Error("rejected");
            result[key] = text;
        }
        return result;
    }
    internal static string Rejection(long code, string? message)
    {
        if (code == 403) return "marketplace.forbidden";
        if (code == 401) return "marketplace.sign_in_required";
        var text = message ?? "";
        return "trade_profile." + (text.Contains("时区") ? "timezone_invalid" :
            text.Contains("联系方式") ? "contact_invalid" : text.Contains("选择一天") || text.Contains("交易开启配置") ? "no_day" :
            text.Contains("交易时间") || text.Contains("交易开始时间") || text.Contains("交易结束时间") ? "time_range" : "rejected");
    }
}
