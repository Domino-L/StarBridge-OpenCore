using System.Net.Http;
using System.Net.Http.Json;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class OAuthPkceClient
{
    /// <summary>
    /// SCM's account checks before a trade (MemberUserServiceImpl) get their own stable codes,
    /// so the client can say exactly what is missing. Anything else stays a generic rejection.
    /// </summary>
    internal static string TradeRejection(JsonElement envelope) =>
        envelope.ValueKind == JsonValueKind.Object && envelope.TryGetProperty("code", out var code) &&
        code.ValueKind == JsonValueKind.Number && code.TryGetInt64(out var value)
            ? value switch
            {
                1_004_001_009 => "marketplace.account_unbound",
                1_004_001_010 => "marketplace.trade_time_required",
                1_004_001_011 => "marketplace.contact_required",
                1_004_001_012 => "marketplace.account_abnormal",
                1_004_015_007 => "marketplace.account_banned",
                1_011_010_004 => "marketplace.own_listing",
                1_011_011_001 => "marketplace.account_unbound",
                1_011_011_002 => "marketplace.listing_limit",
                1_011_011_004 => "marketplace.listing_same_item_limit",
                1_011_011_005 => "marketplace.listing_manifest_limit",
                1_011_011_006 or 1_011_012_007 => "marketplace.listing_item_invalid",
                1_011_009_005 or 1_011_009_006 or 1_011_009_007 or 1_011_009_008 => "marketplace.listing_invalid",
                1_011_010_010 => "marketplace.listing_has_ongoing",
                1_011_010_011 or 1_011_010_012 => "marketplace.listing_cannot_publish",
                1_011_010_013 => "marketplace.listing_quantity_below_ongoing",
                1_011_012_002 or 1_011_012_004 or 1_011_012_005 or 1_011_012_006 => "marketplace.checklist_invalid",
                1_011_013_002 => "marketplace.template_limit",
                1_011_013_004 => "marketplace.template_system",
                1_011_009_001 or 1_011_012_003 or 1_011_013_003 => "marketplace.not_owner",
                _ => "marketplace.trade_rejected",
            }
            : "marketplace.trade_rejected";

    internal async Task<(object Data, ScmOAuthSession ActiveSession)> MarketplaceTradeAsync(
        ScmOAuthSession session, JsonElement input, Func<bool> current, CancellationToken token)
    {
        if (input.ValueKind != JsonValueKind.Object) throw new AccountBridgeHostException("marketplace.invalid_request");
        var op = MarketplaceTradePolicy.Text(input, "operation") ?? "";
        if (op is not ("list" or "detail" or "create" or "approve" or "ship" or "receive" or "cancel" or "review" or "report" or "block"))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var number = MarketplaceTradePolicy.Text(input, "transactionNumber") ?? "";
        if (input.TryGetProperty("transactionRef", out var notificationRef)) {
            if (op != "detail" || number.Length != 0 || notificationRef.ValueKind != JsonValueKind.String)
                throw new AccountBridgeHostException("marketplace.invalid_request");
            number = ResolveNotificationTradeReference(ChatOwner(session), notificationRef.GetString()!);
        }
        if (input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 8192 ||
            number.Length > 100 || number.Any(c => !char.IsAsciiLetterOrDigit(c) && c != '-'))
            throw new AccountBridgeHostException("marketplace.invalid_request");
        var write = op is not ("list" or "detail");
        if (write && !session.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        var active = await EnsureActiveSessionAsync(session, token);
        if (write && !active.Capabilities.Contains("trade.write", StringComparer.Ordinal))
            throw new AccountBridgeHostException("marketplace.reauthorize_required");
        async Task<JsonElement> Send(HttpMethod method, string path, object? body = null)
        {
            var diagnosticId = ScmAuthDiagnostics.NewCorrelationId();
            var watch = ScmAuthDiagnostics.Start(diagnosticId, "marketplace-trade", $"operation={op} method={method.Method}");
            try
            {
            token.ThrowIfCancellationRequested();
            if (!current()) throw new AccountBridgeHostException("marketplace.context_changed");
            using var request = new HttpRequestMessage(method, new Uri(options.ResourceServerBaseUri, "app-api/" + path));
            request.Headers.TryAddWithoutValidation(ScmAuthDiagnostics.CorrelationHeader, diagnosticId);
            if (body is not null) request.Content = JsonContent.Create(body);
            // Writes are sent once. An uncertain response is reconciled by reading, never replayed here.
            using var response = await scmHttpClient.SendAsync(request, active.AccessToken, token);
            var envelope = await (method == HttpMethod.Get ? ReadMarketplaceEnvelopeAsync(response, "marketplace-trade", token)
                : ReadMarketplaceWriteEnvelopeAsync(response, "marketplace-trade", token));
            ScmAuthDiagnostics.Write(diagnosticId, "marketplace-trade-envelope", "received",
                $"kind={envelope.ValueKind} code={(envelope.ValueKind == JsonValueKind.Object && envelope.TryGetProperty("code", out var diagnosticCode) && diagnosticCode.ValueKind == JsonValueKind.Number && diagnosticCode.TryGetInt32(out var numericCode) ? numericCode.ToString(System.Globalization.CultureInfo.InvariantCulture) : "non-numeric")}");
            if (envelope.TryGetProperty("code", out var authCode) && authCode.ValueKind == JsonValueKind.Number)
            {
                if (authCode.GetInt32() == 401) throw new AccountBridgeHostException("marketplace.sign_in_required");
                if (authCode.GetInt32() == 403) throw new AccountBridgeHostException("marketplace.forbidden");
            }
            if (!envelope.TryGetProperty("code", out var code) || code.GetInt32() != 0)
                throw new AccountBridgeHostException(TradeRejection(envelope));
            var data = envelope.GetProperty("data").Clone();
            ScmAuthDiagnostics.Completed(diagnosticId, "marketplace-trade", watch, $"dataKind={data.ValueKind}");
            return data;
            }
            catch (Exception exception)
            {
                ScmAuthDiagnostics.Failed(diagnosticId, "marketplace-trade", watch, exception);
                throw;
            }
        }
        string Chat(long member) => ChatPeerReference(ChatOwner(active), member);
        var escaped = Uri.EscapeDataString(number);
        if (op == "list")
        {
            var page = MarketplaceTradePolicy.Number(input, "page") ?? 1;
            var status = MarketplaceTradePolicy.Number(input, "status");
            if (page is < 1 or > 10000 || status is < 1 or > 3) throw new AccountBridgeHostException("marketplace.invalid_request");
            var data = await Send(HttpMethod.Get, "sc/order-transactions/page?pageSize=20&pageNo=" + page +
                (status is null ? "" : "&transactionStatus=" + status));
            var rows = data.GetProperty("list").EnumerateArray().Take(20).Select(row => MarketplaceTradePolicy.Project(row, Chat)).ToArray();
            return (new { rows, total = data.GetProperty("total").Clone() }, active);
        }
        if (op == "create")
        {
            var order = MarketplaceTradePolicy.Text(input, "orderNumber") ?? "";
            var quantity = MarketplaceTradePolicy.Number(input, "number") ?? 0;
            var method = MarketplaceTradePolicy.Number(input, "deliveryMethod") ?? -1;
            if (order.Length is < 1 or > 100 || order.Any(c => !char.IsAsciiLetterOrDigit(c)) || quantity < 1 ||
                method is < 0 or > 3 || !input.TryGetProperty("locationId", out var location) ||
                location.ValueKind != JsonValueKind.Number || !location.TryGetInt64(out var locationId) || locationId <= 0 ||
                !input.TryGetProperty("shippingFee", out var fee) || fee.ValueKind != JsonValueKind.Number ||
                !fee.TryGetDecimal(out var shippingFee) || shippingFee is < 0 or > 1000000000000000m)
                throw new AccountBridgeHostException("marketplace.invalid_request");
            var ongoing = await Send(HttpMethod.Get, "sc/order-transactions/check-ongoing?orderNumber=" + Uri.EscapeDataString(order));
            if (ongoing.ValueKind == JsonValueKind.True) throw new AccountBridgeHostException("marketplace.state_changed");
            var created = await Send(HttpMethod.Post, "sc/order-transactions/create",
                new { orderNumber = order, number = quantity, locationId, deliveryMethod = method, shippingFee });
            return (new { transactionNumber = created.GetString() }, active);
        }
        if (number.Length == 0) throw new AccountBridgeHostException("marketplace.invalid_request");
        var detail = await Send(HttpMethod.Get, "sc/order-transactions/get?transactionNumber=" + escaped);
        if (MarketplaceTradePolicy.Text(detail, "actorRole") is not ("buyer" or "seller"))
            throw new AccountBridgeHostException("marketplace.not_participant");
        if (op == "detail") return (MarketplaceTradePolicy.Project(detail, Chat), active);
        if (op == "block")
        {
            // Resolve the counterparty only from an authenticated SCM detail, never a Flutter user id.
            var ownerIsBuyer = MarketplaceTradePolicy.Number(detail, "creatorType") == 0;
            var actorIsBuyer = MarketplaceTradePolicy.Text(detail, "actorRole") == "buyer";
            var key = ownerIsBuyer == actorIsBuyer ? "tradingerId" : "orderOwnerId";
            if (!detail.TryGetProperty(key, out var id) || id.ValueKind != JsonValueKind.Number ||
                !id.TryGetInt64(out var blockedUserId) || blockedUserId <= 0)
                throw new AccountBridgeHostException("marketplace.unavailable");
            await Send(HttpMethod.Post, "member/user-blacklist/create", new { blockedUserId, reason = "交易单中拉黑" });
            return (new { transactionNumber = number, confirmed = true }, active);
        }
        if (!MarketplaceTradePolicy.Allows(detail, op)) throw new AccountBridgeHostException("marketplace.state_changed");
        switch (op)
        {
            case "approve":
                await Send(HttpMethod.Put, "sc/order-transactions/approve?transactionNumber=" + escaped);
                break;
            case "ship": case "receive": case "cancel":
                await Send(HttpMethod.Put, "sc/order-transactions/update-status",
                    new { transactionNumber = number, deliveryStatus = op == "ship" ? 2 : op == "receive" ? 3 : 4 });
                break;
            case "review":
                var rating = MarketplaceTradePolicy.Number(input, "rating") ?? 0;
                var content = MarketplaceTradePolicy.Text(input, "content") ?? "";
                if (rating is < 1 or > 5 || content.Length > 100) throw new AccountBridgeHostException("marketplace.invalid_request");
                await Send(HttpMethod.Post, "sc/order-reviews/create", new { transactionId = number, rating, content });
                break;
            case "report":
                var reportType = MarketplaceTradePolicy.Number(input, "reportType") ?? 0;
                var reportContent = MarketplaceTradePolicy.Text(input, "content") ?? "";
                if (reportType is < 1 or > 4 || string.IsNullOrWhiteSpace(reportContent) || reportContent.Length > 200)
                    throw new AccountBridgeHostException("marketplace.invalid_request");
                await Send(HttpMethod.Post, "trade/order-report/create", new { transactionNumber = number, reportType, reportContent });
                break;
            default: throw new AccountBridgeHostException("marketplace.invalid_request");
        }
        return (new { transactionNumber = number, confirmed = true }, active);
    }
}
