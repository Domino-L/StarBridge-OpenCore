using System.Text.Json;

namespace StarBridge.HostRuntime.Notifications;

internal static class NotificationPolicyWire
{
    internal static void ValidateRow(JsonElement row, bool extended)
    {
        var fields = row.EnumerateObject().Select(p => p.Name).ToArray();
        if (!fields.Contains("sourceRef") || !fields.Contains("mode") || fields.Any(f =>
            f is not ("sourceRef" or "mode") && (!extended || f is not ("typeRules" or "quietHours")))) throw new JsonException();
    }
    internal static NotificationTypeRule[]? Types(JsonElement row)
    {
        if (!row.TryGetProperty("typeRules", out var list)) return null;
        if (list.ValueKind != JsonValueKind.Array || list.GetArrayLength() > 3) throw new JsonException();
        var result = list.EnumerateArray().Select(t => {
            if (t.EnumerateObject().Count() != 2 || t.EnumerateObject().Any(p => p.Name is not ("type" or "mode"))) throw new JsonException();
            var type = t.GetProperty("type").GetString(); var mode = t.GetProperty("mode").GetString();
            if (type is not ("chat" or "announcement" or "activity") || mode is not ("inherit" or "enabled" or "disabled")) throw new JsonException();
            return new NotificationTypeRule(type, mode);
        }).ToArray();
        if (result.Select(t => t.Type).Distinct().Count() != result.Length) throw new JsonException();
        return result;
    }
    internal static NotificationQuietHours? Quiet(JsonElement row)
    {
        if (!row.TryGetProperty("quietHours", out var q)) return null;
        if (q.EnumerateObject().Count() != 4 || q.EnumerateObject().Any(p =>
            p.Name is not ("enabled" or "startMinute" or "endMinute" or "clock"))) throw new JsonException();
        var result = new NotificationQuietHours(q.GetProperty("enabled").GetBoolean(), q.GetProperty("startMinute").GetInt32(),
            q.GetProperty("endMinute").GetInt32(), q.GetProperty("clock").GetString() ?? "");
        if (result.Clock != "local" || result.StartMinute is < 0 or > 1439 || result.EndMinute is < 0 or > 1439 ||
            result.StartMinute == result.EndMinute) throw new JsonException();
        return result;
    }
    internal static object[] TypeOutput(NotificationPolicyRule rule) =>
        new[] { "chat", "announcement", "activity" }.Select(type => (object)new { type,
            mode = rule.TypeRules?.FirstOrDefault(t => t.Type == type)?.Mode ?? (type == "chat" ? "inherit" : "disabled") }).ToArray();
    internal static object QuietOutput(NotificationPolicyRule rule)
    {
        var q = rule.QuietHours ?? new();
        return new { enabled = q.Enabled, startMinute = q.StartMinute, endMinute = q.EndMinute, clock = q.Clock };
    }
}
