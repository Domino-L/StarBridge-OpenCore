using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime;

public sealed partial class AccountBridgeRuntime
{
    private ScmMarketplaceReader? _marketplace;
    private MarketplacePreferencesStore? _marketplacePreferences;
    private async ValueTask<BridgeDispatchBatch> DispatchMarketplaceAsync(BridgeEnvelope request, CancellationToken token)
    {
        try
        {
            BridgeEnvelopeValidator.ValidateWireShape(request);
            BridgeEnvelopeValidator.RequireCurrentVersion(request);
            var owner = _host.CurrentContext;
            var generation = Generation;
            if (request.MessageType != BridgeMessageTypes.Request || request.SessionGeneration != generation ||
                request.AccountContext is not null && request.AccountContext != owner || _disposed)
                return MarketError(request, "marketplace.context_changed");
            var body = request.Payload;
            if (body.ValueKind != JsonValueKind.Object || body.GetRawText().Length > 32768 ||
                body.GetProperty("schemaVersion").GetInt32() != 1 ||
                body.EnumerateObject().Select(p => p.Name).Distinct().Count() != body.EnumerateObject().Count())
                return MarketError(request, "marketplace.invalid_request");
            bool Current() => !_disposed && Generation == generation && _host.CurrentContext == owner && !token.IsCancellationRequested;
            object result;
            if (request.Name is "tradeProfile.read" or "tradeProfile.write")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                var write = request.Name == "tradeProfile.write";
                if (body.EnumerateObject().Any(p => p.Name != "schemaVersion" && !(write && p.Name == "changes")))
                    return MarketError(request, "marketplace.invalid_request");
                result = await _host.TradeProfileAsync(owner, write, write ? body.GetProperty("changes") : default, token);
            }
            else if (request.Name == "marketplace.listings")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceListingsAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.chat")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                var openScm = MarketplaceTradePolicy.Text(body, "operation") == "openScm";
                using var linkWork = openScm ? DeviceNetwork.Enter(token) : null;
                if (openScm && linkWork is null) return MarketError(request, "marketplace.offline");
                using var linkDeadline = CancellationTokenSource.CreateLinkedTokenSource(token, linkWork?.Token ?? CancellationToken.None);
                linkWork?.RequireCurrent();
                result = await _host.MarketplaceChatAsync(owner, body, linkDeadline.Token);
            }
            else if (request.Name == "marketplace.contracts")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceContractsAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.warehouse")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceWarehouseAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.notices")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceNoticesAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.records")
            {
                if (owner is null || request.AccountContext != owner) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceRecordsAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.trade")
            {
                if (owner is null) return MarketError(request, "marketplace.sign_in_required");
                result = await _host.MarketplaceTradeAsync(owner, body, token);
            }
            else if (request.Name == "marketplace.preferences")
            {
                if (_marketplacePreferences is null || body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "value")))
                    return MarketError(request, "marketplace.unavailable");
                result = body.TryGetProperty("value", out var value)
                    ? _marketplacePreferences.Save(owner, MarketplacePreferencesStore.Parse(value), Current)
                    : _marketplacePreferences.Read(owner);
            }
            else
            {
                if (_marketplace is null) return MarketError(request, "marketplace.unavailable");
                if (body.EnumerateObject().Any(p => p.Name is not ("schemaVersion" or "operation" or "id" or "keyword" or "category" or "side" or "page" or "language" or "options")))
                    return MarketError(request, "marketplace.invalid_request");
                var operation = body.GetProperty("operation").GetString() ?? "";
                var keyword = body.TryGetProperty("keyword", out var k) ? k.GetString() ?? "" : "";
                var language = body.TryGetProperty("language", out var lang) ? lang.GetString() : "CN";
                long Numeric(string key, long fallback) => body.TryGetProperty(key, out var v) ? v.GetInt64() : fallback;
                var id = Numeric("id", 0); var category = Numeric("category", 0);
                var side = Numeric("side", 1); var page = Numeric("page", 1);
                // side 3 = every listing type, only for the hall's latest listings (user 10-29: the filter can be cleared).
                if (language is not ("CN" or "EN") || id < 0 || category < 0 || side is < 0 or > 3 || side == 3 && operation != "latest" ||
                    page is < 1 or > 10000 ||
                    keyword.Length > 100 || keyword.Any(char.IsControl) ||
                    operation is not ("reputation" or "categories" or "trending" or "latest" or "search" or "hotWords" or "item" or "offers" or "trend" or "acquisition" or "blueprints" or "attachments" or "marketItems" or "marketOrders" or "locations" or "timezones" or "categoryListings" or "bestPrices" or "qualityTiers") ||
                    operation is "item" or "offers" or "trend" or "acquisition" or "blueprints" or "attachments" && id <= 0 ||
                    operation == "offers" && side > 1)
                    return MarketError(request, "marketplace.invalid_request");
                var options = body.TryGetProperty("options", out var supplied) ? supplied : default;
                if (options.ValueKind != JsonValueKind.Undefined)
                {
                    if (operation is not ("marketItems" or "marketOrders" or "offers")) return MarketError(request, "marketplace.invalid_request");
                    ScmMarketplaceReader.BrowseOptions(options);
                }
                var traderReference = owner is not null && operation is "latest" or "offers" or "marketOrders" &&
                    _host is Account.IMarketplaceTraderProfileTargets targets
                    ? await targets.PrepareMarketTraderReferencesAsync(owner, generation, token) : null;
                result = operation == "reputation"
                    ? owner is null ? new { schemaVersion = 1, readAt = DateTimeOffset.UtcNow, data = new { point = (long?)null } }
                        : await _host.ReadMarketplaceReputationAsync(owner, token)
                    : await _marketplace.ReadAsync(operation, id, keyword, category, (int)side, (int)page, token, language, options, traderReference);
            }
            if (!Current()) return MarketError(request, "marketplace.context_changed");
            return new(BridgeEnvelope.Response(request, result), []);
        }
        catch (Account.AccountBridgeHostException e) { return MarketError(request, e.Code, e); }
        catch (Auth.ScmApiAuthenticationException e) { return MarketError(request, "marketplace.sign_in_required", e); }
        catch (Auth.ScmApiForbiddenException e) { return MarketError(request, "marketplace.forbidden", e); }
        catch (Auth.ScmApiUnavailableException e) { return MarketError(request, "marketplace.unavailable", e); }
        catch (Auth.ScmApiProtocolException e) { return MarketError(request, "marketplace.unavailable", e); }
        catch (OperationCanceledException) { return new(BridgeEnvelope.CancelledResponse(request), []); }
        catch (Exception e) when (e is HttpRequestException or JsonException or IOException or UnauthorizedAccessException or InvalidOperationException or
            KeyNotFoundException or FormatException or ArgumentException or OverflowException or BridgeProtocolException or InvalidDataException)
        {
            if (request.Name == "marketplace.trade")
                Auth.ScmAuthDiagnostics.Write("marketplace", "marketplace-bridge", "failed", $"exceptionType={e.GetType().Name}");
            return MarketError(request, "marketplace.unavailable", e);
        }
    }
    private static BridgeDispatchBatch MarketError(BridgeEnvelope request, string code, Exception? exception = null)
    {
        if (request.Name == "marketplace.trade")
            Auth.ScmAuthDiagnostics.Write("marketplace", "marketplace-bridge", "rejected", $"code={code}");
        if (request.Name == "marketplace.read")
        {
            var operation = request.Payload.ValueKind == JsonValueKind.Object &&
                request.Payload.TryGetProperty("operation", out var value) && value.ValueKind == JsonValueKind.String
                ? value.GetString() : null;
            var safeOperation = operation is "reputation" or "categories" or "trending" or "latest" or "search" or
                "hotWords" or "item" or "offers" or "trend" or "acquisition" or "blueprints" or "attachments" or
                "marketItems" or "marketOrders" or "locations" or "timezones" or "categoryListings" or "bestPrices" or "qualityTiers"
                ? $"operation={operation} " : "";
            Auth.ScmAuthDiagnostics.Write("marketplace", "marketplace-read", "rejected",
                $"{safeOperation}code={code}" + (exception is null ? "" : $" exceptionType={exception.GetType().Name}"));
        }
        return new(BridgeEnvelope.ErrorResponse(request, new(code, "Marketplace read is unavailable.", true)), []);
    }
}
