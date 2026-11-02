using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceListingTests
{
    internal static async Task Run()
    {
        void Check(bool value, string reason) { if (!value) throw new InvalidOperationException(reason); }
        foreach (var (days, expected) in new[] { (7, 0), (14, 1), (0, 2) })
        {
            var mapped = BridgePayload.From(MarketplaceListingRequest.Create(BridgePayload.From(new {
                itemId = 123, side = "sell", quantity = 2, price = 12.5m, expiryDays = days,
                visible = true, location = "456", quality = "702"
            })));
            Check(mapped.GetProperty("expireTimeType").GetInt32() == expected, "Expiry translation");
            Check(mapped.GetProperty("locationId").GetInt64() == 456, "Location id translation");
            var item = mapped.GetProperty("items")[0];
            Check(item.GetProperty("price").GetDecimal() == 12.5m, "Price precision");
            Check(JsonDocument.Parse(item.GetProperty("qualityData").GetString()!).RootElement.GetProperty("quality").GetInt32() == 702, "Material quality JSON string");
        }
        var barter = BridgePayload.From(MarketplaceListingRequest.Create(BridgePayload.From(new {
            itemId = 123, side = "barter", quantity = 2, expiryDays = 7, visible = false, location = "456",
            wanted = new[] { new { itemId = 789, quantity = 3 } }
        })));
        Check(barter.GetProperty("exchangeItemsList")[0].GetProperty("itemId").GetInt64() == 789, "Barter uses IDs");
        Check(barter.GetProperty("items")[0].GetProperty("price").GetDecimal() == 0, "Barter price fixed zero");
        foreach (var (code, stable) in new[] {
            (1011011001,"account_unbound"),(1011011002,"listing_limit"),(1011011004,"listing_same_item_limit"),
            (1011011005,"listing_manifest_limit"),(1011011006,"listing_item_invalid"),(1011012007,"listing_item_invalid"),
            (1011009006,"listing_invalid"),(1011009007,"listing_invalid"),(1011009008,"listing_invalid"),
            (1011010010,"listing_has_ongoing"),(1011010011,"listing_cannot_publish"),(1011010012,"listing_cannot_publish"),
            (1011010013,"listing_quantity_below_ongoing"),(1011012002,"checklist_invalid"),(1011012004,"checklist_invalid"),
            (1011012005,"checklist_invalid"),(1011012006,"checklist_invalid"),(1011013002,"template_limit"),
            (1011013004,"template_system"),(1011009001,"not_owner"),(1011012003,"not_owner"),(1011013003,"not_owner") })
            Check(OAuthPkceClient.TradeRejection(BridgePayload.From(new { code })) == "marketplace." + stable, "Listing error " + code);
        var handler = new Handler();
        var endpoint = new Uri("https://fixture.invalid/");
        var options = new ScmOAuthOptions("fixture", endpoint, endpoint, endpoint, "desktop", "starbridge-api", "trade.write", "/callback");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), options);
        var session = new ScmOAuthSession("fixture", "opaque-subject", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["trade.write"]);
        var input = BridgePayload.From(new { operation = "visibility", id = "ORDER1", visible = true });
        await client.MarketplaceListingsAsync(session, input, () => true, default);
        Check(handler.Method == HttpMethod.Put && handler.Path == "/app-api/sc/orders/orderStatus?orderNumber=ORDER1&status=1", "Visibility route");
        handler.Fail = true;
        try { await client.MarketplaceListingsAsync(session, input, () => true, default); throw new Exception("Expected uncertain failure"); }
        catch (HttpRequestException) { }
        Check(handler.Count == 2, "Uncertain write is never replayed");
        handler.Fail = false;
        handler.Code = 403;
        try { await client.MarketplaceListingsAsync(session, input, () => true, default); throw new Exception("Expected 403"); }
        catch (AccountBridgeHostException e) { Check(e.Code == "marketplace.forbidden", "403 preserved"); }
        var projected = JsonSerializer.Serialize(MarketplaceListingProjection.Order(BridgePayload.From(new {
            orderNumber = "ORDER1", itemName = "Fixture", orderOwnerId = 123, userMobile = "private", status = 1
        })));
        Check(!projected.Contains("private") && !projected.Contains("orderOwnerId"), "Private fields are not projected");
        Check(projected.Contains("\"checklist\":false"), "Single-item listing is not a checklist");
        var checklist = JsonSerializer.Serialize(MarketplaceListingProjection.Order(BridgePayload.From(new {
            orderNumber = "ORDER2", itemName = "Bundle", displayType = 2, status = 1
        })));
        Check(checklist.Contains("\"checklist\":true"), "Checklist listing is marked for the crate art");
        Console.WriteLine("PASS listing request translation, rejection codes, exact visibility route, no replay and projection");
    }
    private sealed class Handler : HttpMessageHandler
    {
        internal int Count, Code;
        internal bool Fail;
        internal HttpMethod? Method;
        internal string? Path;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Count++; Method = request.Method; Path = request.RequestUri!.PathAndQuery;
            if (Fail) throw new HttpRequestException("fixture");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = Code, data = true })) });
        }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }
}
