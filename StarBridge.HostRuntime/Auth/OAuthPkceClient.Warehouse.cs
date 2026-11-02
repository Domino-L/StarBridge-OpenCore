using System.Net.Http;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    // 0.7.2 G2: the member's own SCM warehouse, read only (spaces, inventory, summary, ledger,
    // escrow). Fleet warehouses and every write stay on the SCM site for this version.
    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceWarehouseAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token)
    {
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 2048 ||
            input.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "page" or "spaceId" or "keyword" or "available" or "after")))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        if (op is not ("spaces" or "inventory" or "summary" or "ledger" or "escrow"))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var page = MarketplaceTradePolicy.Number(input, "page") ?? 1;
        if (page is < 1 or > 10000) throw new AccountBridgeHostException("marketplace.invalid_request");
        var active = await EnsureActiveSessionAsync(session, token);
        if (active.Subject != session.Subject || active.AuthorityId != session.AuthorityId || !current())
            throw new AccountBridgeHostException("marketplace.context_changed");
        if (!active.Capabilities.Contains("trade.read", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        Task<JsonElement> Send(string path) =>
            HallSendAsync(active, "marketplace-warehouse", op, HttpMethod.Get, "warehouse/" + path, null, current, token);

        long? Positive(string key) =>
            !input.TryGetProperty(key, out var v) ? null
            : v.ValueKind == JsonValueKind.Number && v.TryGetInt64(out var n) && n > 0 ? n
            : throw new AccountBridgeHostException("marketplace.invalid_request");
        var space = Positive("spaceId") is { } s ? $"&spaceId={s}" : "";
        var keyword = MarketplaceTradePolicy.Text(input, "keyword")?.Trim() is { Length: > 0 } k
            ? k.Length <= 50 ? "&itemKeyword=" + Uri.EscapeDataString(k) : throw new AccountBridgeHostException("marketplace.invalid_request")
            : "";
        object Page(JsonElement data, Func<JsonElement, object> project) => new
        {
            rows = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var list) && list.ValueKind == JsonValueKind.Array
                ? list.EnumerateArray().Take(50).Select(project).ToArray() : [],
            total = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("total", out var total) && total.TryGetInt64(out var t) ? t : 0,
        };

        switch (op)
        {
            case "spaces":
            {
                var data = await Send("space/list?ownerType=USER");
                return (new { rows = data.ValueKind == JsonValueKind.Array ? data.EnumerateArray().Take(200).Select(MarketplaceWarehouse.Space).ToArray() : [] }, active);
            }
            case "inventory":
            {
                var available = input.TryGetProperty("available", out var a) && a.ValueKind == JsonValueKind.True ? "&onlyAvailable=true" : "";
                var data = await Send($"inventory/page?ownerType=USER&pageNo={page}&pageSize=20{space}{keyword}{available}");
                return (Page(data, MarketplaceWarehouse.Inventory), active);
            }
            case "summary":
                return (MarketplaceWarehouse.Summary(await Send($"inventory/summary?ownerType=USER{space}")), active);
            case "ledger":
                return (Page(await Send($"ledger/page?ownerType=USER&pageNo={page}&pageSize=20{space}"), MarketplaceWarehouse.Ledger), active);
            default:
            {
                var after = Positive("after") is { } cursor ? $"&afterId={cursor}" : "";
                var data = await Send($"escrow/scroll?limit=20{after}{keyword}");
                return (new
                {
                    rows = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("list", out var list) && list.ValueKind == JsonValueKind.Array
                        ? list.EnumerateArray().Take(50).Select(MarketplaceWarehouse.Escrow).ToArray() : [],
                    next = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("nextCursor", out var next) && next.TryGetInt64(out var n) ? n : (long?)null,
                    more = data.ValueKind == JsonValueKind.Object && data.TryGetProperty("hasMore", out var more) && more.ValueKind == JsonValueKind.True,
                }, active);
            }
        }
    }
}
