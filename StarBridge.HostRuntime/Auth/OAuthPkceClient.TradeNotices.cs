using System.Net.Http;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // Inbox is a separate, bounded projection: never expose order, member or sender metadata.
    // SCM timestamps are Unix milliseconds or ISO/local date strings; offsetless dates use UTC.
    internal async Task<StarBridge.Core.TrustSafety.NotificationItemContract[]> ReadNotificationMessagesAsync(
        ScmOAuthSession session, Func<bool> current, CancellationToken token, object? lifetimeGate = null)
    {
        lifetimeGate ??= _notificationTradeGate;
        if (!session.Capabilities.Contains("profile.read", StringComparer.Ordinal)) return [];
        var scope = CaptureStationRead(ChatOwner(session), current, lifetimeGate);
        var data = await HallSendAsync(session, "marketplace-notices", "page", HttpMethod.Get,
            "member/message/page?pageNo=1&pageSize=50", null, current, token);
        if (data.ValueKind != JsonValueKind.Object || !data.TryGetProperty("list", out var list) ||
            list.ValueKind != JsonValueKind.Array) throw new ScmApiProtocolException("Invalid message page.");
        RegisterStationPage(scope, list, current, lifetimeGate, inboxPoll: true);
        var items = new List<StarBridge.Core.TrustSafety.NotificationItemContract>();
        var seen = new HashSet<long>();
        foreach (var row in list.EnumerateArray().Take(50))
        {
            var notice = JsonSerializer.SerializeToElement(MarketplaceNotices.Notice(row, _ => ""));
            if (!notice.TryGetProperty("id", out var idValue) || idValue.ValueKind != JsonValueKind.Number ||
                !idValue.TryGetInt64(out var id) || id <= 0 || !seen.Add(id)) continue;
            int Number(string key) => notice.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.Number &&
                v.TryGetInt32(out var n) ? n : -1;
            var type = Number("type");
            if (type is not (0 or 1 or 2)) continue;
            var time = notice.GetProperty("time");
            DateTimeOffset created;
            if (time.ValueKind == JsonValueKind.Number && time.TryGetInt64(out var milliseconds))
            {
                try { created = DateTimeOffset.FromUnixTimeMilliseconds(milliseconds); }
                catch (ArgumentOutOfRangeException) { continue; }
            }
            else if (time.ValueKind != JsonValueKind.String ||
                !DateTimeOffset.TryParse(time.GetString(), System.Globalization.CultureInfo.InvariantCulture,
                    System.Globalization.DateTimeStyles.AssumeUniversal, out created)) continue;
            string Text(string key, int max)
            {
                var value = row.TryGetProperty(key, out var v) && v.ValueKind == JsonValueKind.String ? v.GetString()! : "";
                var safe = SafeNotificationText(row, value.Length > max ? value[..max] : value);
                return safe.Length > 0 || key != "title" ? safe : type == 1 ? "\u4ea4\u6613\u901a\u77e5" : type == 2 ? "\u4ea4\u6613\u79c1\u4fe1" : "\u7cfb\u7edf\u901a\u77e5";
            }
            var isRead = notice.GetProperty("read").GetBoolean();
            items.Add(new("scm:" + id.ToString(System.Globalization.CultureInfo.InvariantCulture),
                type == 1 ? "trade" : type == 2 ? "tradeChat" : "system",
                type == 1 && Number("subType") is 1 or 4 or 6 ? "action_required" : "normal",
                Text("title", 2000), Text("content", 20000), created.ToUniversalTime(),
                isRead ? created : null, "",
                type == 1 ? "marketplace_trade" : type == 2 ? "marketplace_chat" : "",
                null, "scm", "", true));
        }
        return items.ToArray();
    }
    // 0.7.2 G8: SCM station messages (system / trade / chat fallback) for the StarBridge
    // notification center. Read and mark read only; deleting and sending stay on the SCM site.
    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceNoticesAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token, object? lifetimeGate = null,
        Action? onReadConfirmed = null)
    {
        lifetimeGate ??= _notificationTradeGate;
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 1024 ||
            input.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "page" or "type" or "unread" or "id")))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        if (op is not ("page" or "unread" or "read" or "readAll")) throw new AccountBridgeHostException("marketplace.invalid_request");
        var page = MarketplaceTradePolicy.Number(input, "page") ?? 1;
        var type = MarketplaceTradePolicy.Number(input, "type");
        if (page is < 1 or > 10000 || type is not (null or 0 or 1 or 2)) throw new AccountBridgeHostException("marketplace.invalid_request");
        var write = op is "read" or "readAll";
        if (write && !session.Capabilities.Contains("profile.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        if (!active.Capabilities.Contains(write ? "profile.write" : "profile.read", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var owner = active.AuthorityId + "\n" + active.Subject;
        Task<JsonElement> Send(HttpMethod method, string path, object? body = null) =>
            HallSendAsync(active, "marketplace-notices", op, method, "member/message/" + path, body, current, token);
        var typeQuery = type is { } t ? $"&type={t}" : "";

        switch (op)
        {
            case "page":
            {
                var scope = CaptureStationRead(owner, current, lifetimeGate);
                var unread = input.TryGetProperty("unread", out var u) && u.ValueKind == JsonValueKind.True ? "&isRead=false" : "";
                var data = await Send(HttpMethod.Get, $"page?pageNo={page}&pageSize=20{typeQuery}{unread}");
                if (data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var receipts) && receipts.ValueKind == JsonValueKind.Array)
                    RegisterStationPage(scope, receipts, current, lifetimeGate);
                return (new
                {
                    rows = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var list) && list.ValueKind == JsonValueKind.Array
                        ? list.EnumerateArray().Take(50).Select(row => MarketplaceNotices.Notice(row, member => ChatPeerReference(owner, member))).ToArray() : [],
                    total = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("total", out var total) && total.TryGetInt64(out var n) ? n : 0,
                }, active);
            }
            case "unread":
            {
                var data = await Send(HttpMethod.Get, "unread-count" + (type is { } only ? $"?type={only}" : ""));
                long Count(string key) => data.ValueKind == JsonValueKind.Object && data.TryGetProperty(key, out var v) && v.TryGetInt64(out var n) ? Math.Max(0, n) : 0;
                return (new { total = Count("total"), station = Count("stationUnreadCount"), chatFallback = Count("chatFallbackUnreadCount") }, active);
            }
            case "read":
            {
                var id = input.TryGetProperty("id", out var v) && v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) && n > 0 ? n
                    : throw new AccountBridgeHostException("marketplace.invalid_request");
                var scope = CaptureStationRead(owner, current, lifetimeGate);
                var data = await Send(HttpMethod.Put, "mark-read", new { id });
                if (data.ValueKind == JsonValueKind.True)
                {
                    onReadConfirmed?.Invoke();
                    ConfirmStationRead(scope, id, current, lifetimeGate);
                }
                return (new { confirmed = data.ValueKind == JsonValueKind.True }, active);
            }
            default:
            {
                var scope = CaptureStationRead(owner, current, lifetimeGate, type, all: true);
                try
                {
                    var data = await Send(HttpMethod.Put, "mark-all-read" + (type is { } only ? $"?type={only}" : ""));
                    if (data.ValueKind == JsonValueKind.True)
                    {
                        onReadConfirmed?.Invoke();
                        ConfirmStationRead(scope, null, current, lifetimeGate);
                    }
                    return (new { confirmed = data.ValueKind == JsonValueKind.True }, active);
                }
                finally { FinishStationRead(scope); }
            }
        }
    }
}
