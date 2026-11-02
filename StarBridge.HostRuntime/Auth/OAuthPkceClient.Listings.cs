using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceListingsAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token)
    {
        var op = MarketplaceListingRequest.Text(input, "operation", 24);
        if (op is not ("read" or "create" or "update" or "visibility" or "quantityAdd" or "delete" or
            "listCreate" or "listUpdate" or "listDelete" or "templates")) throw MarketplaceListingRequest.Invalid();
        var write = op is not ("read" or "templates");
        if (write && !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (write && !active.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        async Task<JsonElement> Send(HttpMethod method, string path, object? body = null)
        {
            token.ThrowIfCancellationRequested();
            if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
            using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri, "app-api/" + path));
            if (body is not null) request.Content = JsonContent.Create(body);
            // No retry, including token refresh on write failure. Unknown outcomes require a read-back.
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
            var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, "marketplace-listings", token)
                : ReadMarketplaceWriteEnvelopeAsync(response, "marketplace-listings", token));
            var code = envelope.GetProperty("code").GetInt64();
            if (code == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
            if (code == 403) throw new AccountBridgeHostException("marketplace.forbidden");
            if (code != 0)
            {
                var reason = TradeRejection(envelope);
                throw new AccountBridgeHostException(reason == "marketplace.trade_rejected" ? "marketplace.listing_rejected" : reason);
            }
            if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
            return envelope.GetProperty("data").Clone();
        }
        if (op == "read")
        {
            var page = input.TryGetProperty("page", out _) ? MarketplaceListingRequest.Integer(input, "page", 1, 10000) : 1;
            var own = await Send(HttpMethod.Get, $"sc/orders/page-of-own?pageNo={page}&pageSize=20&language=CN");
            var lists = await Send(HttpMethod.Get, "sc/item-list/page?pageNo=1&pageSize=50");
            return (new {
                rows = own.GetProperty("list").EnumerateArray().Take(20).Select(MarketplaceListingProjection.Order).ToArray(),
                total = own.GetProperty("total").Clone(),
                manifests = lists.GetProperty("list").EnumerateArray().Take(50).Select(MarketplaceListingProjection.Manifest).ToArray(),
                limit = (int?)null, tradeWindow = (string?)null,
                tradeWindowUnavailable = "member_id_not_exposed"
            }, active);
        }
        if (op == "templates")
        {
            var data = await Send(HttpMethod.Get, "sc/item-list-template/system-templates");
            return (new { rows = data.EnumerateArray().Take(100).Select(MarketplaceListingProjection.Manifest).ToArray() }, active);
        }
        object? result;
        if (op == "create")
        {
            var manifest = input.TryGetProperty("manifestId", out var manifestId) && manifestId.ValueKind != JsonValueKind.Null
                ? await Send(HttpMethod.Get, "sc/item-list/get?id=" + MarketplaceListingRequest.Integer(input, "manifestId", 1, long.MaxValue)) : default;
            result = await Send(HttpMethod.Post, "sc/orders/create", MarketplaceListingRequest.Create(input, manifest));
        }
        else if (op is "listCreate" or "listUpdate")
            result = await Send(op == "listCreate" ? HttpMethod.Post : HttpMethod.Put,
                "sc/item-list/" + (op == "listCreate" ? "create" : "update"), MarketplaceListingRequest.Checklist(input, op == "listUpdate"));
        else if (op == "listDelete") result = await Send(HttpMethod.Delete,
            "sc/item-list/delete?id=" + MarketplaceListingRequest.Integer(input, "id", 1, long.MaxValue));
        else
        {
            var id = MarketplaceListingRequest.Text(input, "id", 100);
            if (id.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-')) throw MarketplaceListingRequest.Invalid();
            var escaped = Uri.EscapeDataString(id);
            if (op == "update")
            {
                var order = await Send(HttpMethod.Get, "sc/orders/get?orderNumber=" + escaped + "&language=CN");
                result = await Send(HttpMethod.Put, "sc/orders/update", MarketplaceListingRequest.Update(input,
                    MarketplaceTradePolicy.Number(order, "displayType") == 3));
            }
            else result = await Send(op == "delete" ? HttpMethod.Delete : HttpMethod.Put,
                "sc/orders/" + (op == "delete" ? "delete" : op == "quantityAdd" ? "quantity-add" : "orderStatus") +
                "?orderNumber=" + escaped + (op == "visibility" ? "&status=" + (MarketplaceListingRequest.Visible(input) ? "1" : "0") : ""));
        }
        return (new { confirmed = true, result }, active);
    }
}
