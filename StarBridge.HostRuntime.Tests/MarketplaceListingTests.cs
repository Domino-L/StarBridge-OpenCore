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
        WriteDataRegression();
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
            // Stock is remainingQuantity only; each unit holds one item (SCM site sends 1).
            Check(item.GetProperty("quantity").GetInt32() == 1 && mapped.GetProperty("remainingQuantity").GetInt32() == 2,
                "Single listing: one item per unit, stock in remainingQuantity");
            Check(JsonDocument.Parse(item.GetProperty("qualityData").GetString()!).RootElement.GetProperty("quality").GetInt32() == 702, "Material quality JSON string");
        }
        // A buy order's quality is the least it accepts: SCM's qualityMin (user 2026-11-07).
        JsonElement QualityOf(object request, bool items = true)
        {
            var mapped = BridgePayload.From(request);
            var data = items ? mapped.GetProperty("items")[0].GetProperty("qualityData") : mapped.GetProperty("qualityData");
            return JsonDocument.Parse(data.GetString()!).RootElement;
        }
        var bid = QualityOf(MarketplaceListingRequest.Create(BridgePayload.From(new {
            itemId = 123, side = "buy", quantity = 1, price = 2500000m, expiryDays = 7,
            visible = true, location = "456", quality = 975
        })));
        Check(bid.GetProperty("type").GetString() == "material" && bid.GetProperty("qualityMin").GetInt32() == 975 &&
            !bid.TryGetProperty("quality", out _), "Buy order quality is qualityMin");
        var update = new { id = "SO1", price = 12m, quantity = 1, visible = true, expiryDays = 7, quality = 640 };
        var bidUpdate = QualityOf(MarketplaceListingRequest.Update(BridgePayload.From(update), false, buy: true), items: false);
        Check(bidUpdate.GetProperty("qualityMin").GetInt32() == 640 && !bidUpdate.TryGetProperty("quality", out _),
            "Buy order update keeps qualityMin");
        var askUpdate = QualityOf(MarketplaceListingRequest.Update(BridgePayload.From(update), false), items: false);
        Check(askUpdate.GetProperty("quality").GetInt32() == 640 && !askUpdate.TryGetProperty("qualityMin", out _),
            "Sell listing update keeps exact quality");
        var barter = BridgePayload.From(MarketplaceListingRequest.Create(BridgePayload.From(new {
            itemId = 123, side = "barter", quantity = 2, expiryDays = 7, visible = false, location = "456",
            wanted = new[] { new { itemId = 789, quantity = 3 } }
        })));
        Check(barter.GetProperty("exchangeItemsList")[0].GetProperty("itemId").GetInt64() == 789, "Barter uses IDs");
        Check(barter.GetProperty("items")[0].GetProperty("price").GetDecimal() == 0, "Barter price fixed zero");
        Check(barter.GetProperty("items")[0].GetProperty("quantity").GetInt32() == 1 &&
            barter.GetProperty("remainingQuantity").GetInt32() == 2 &&
            barter.GetProperty("exchangeItemsList")[0].GetProperty("quantity").GetInt32() == 3,
            "Barter: one offered item per trade, trades in remainingQuantity, wanted quantity kept");
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
        // Editing through the OAuth entry: the order's side, read back first, decides qualityMin vs quality,
        // and an unknown side never reaches the write (CX-BUYTAG-REVIEW P2-1).
        handler.Code = 0;
        var edit = BridgePayload.From(new { operation = "update", id = "SO1", price = 12m, quantity = 1, visible = true, expiryDays = 7, quality = 640 });
        foreach (var (creator, key) in new (object Creator, string Key)[] { (0, "qualityMin"), (1, "quality") })
        {
            handler.Order = new Dictionary<string, object?> { ["orderNumber"] = "SO1", ["displayType"] = 1, ["creatorType"] = creator };
            handler.Methods.Clear();
            await client.MarketplaceListingsAsync(session, edit, () => true, default);
            Check(handler.Method == HttpMethod.Put && handler.Path == "/app-api/sc/orders/update", "Edit writes the order");
            var written = JsonDocument.Parse(JsonDocument.Parse(handler.Body!).RootElement.GetProperty("qualityData").GetString()!).RootElement;
            Check(written.GetProperty(key).GetInt32() == 640 && !written.TryGetProperty(key == "quality" ? "qualityMin" : "quality", out _),
                "Edit of creatorType " + creator + " writes " + key);
        }
        foreach (var creator in new object?[] { null, "0", 2, -1, 0.5, true, "missing" })
        {
            var order = new Dictionary<string, object?> { ["orderNumber"] = "SO1", ["displayType"] = 1 };
            if (!Equals(creator, "missing")) order["creatorType"] = creator;
            handler.Order = order;
            handler.Methods.Clear();
            try { await client.MarketplaceListingsAsync(session, edit, () => true, default); throw new Exception("Expected refusal for " + (creator ?? "null")); }
            catch (AccountBridgeHostException e) { Check(e.Code == "marketplace.listing_invalid", "Unknown side refused: " + (creator ?? "null")); }
            Check(handler.Methods.Count == 1 && handler.Methods[0] == HttpMethod.Get, "Unknown side never writes: " + (creator ?? "null"));
        }
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
    private static void WriteDataRegression()
    {
        void Check(bool value, string reason) { if (!value) throw new InvalidOperationException(reason); }
        foreach (var offered in new[] { 1, 7, 999 })
        {
            var mapped = BridgePayload.From(MarketplaceListingRequest.Create(BridgePayload.From(new {
                itemId = 123, side = "barter", quantity = 12, offeredQuantity = offered,
                expiryDays = 7, visible = true, location = 456,
                wanted = new[] { new { itemId = 789, quantity = 8 } }
            })));
            Check(mapped.GetProperty("items")[0].GetProperty("quantity").GetInt64() == offered,
                "Barter offered quantity mapped");
            Check(mapped.GetProperty("remainingQuantity").GetInt64() == 12 &&
                mapped.GetProperty("exchangeItemsList")[0].GetProperty("quantity").GetInt64() == 8,
                "Barter stock and wanted quantities stay independent");
        }
        foreach (var offered in new[] { 0, -1, 1000 })
        {
            try
            {
                MarketplaceListingRequest.Create(BridgePayload.From(new {
                    itemId = 123, side = "barter", quantity = 12, offeredQuantity = offered,
                    expiryDays = 7, visible = true, location = 456,
                    wanted = new[] { new { itemId = 789, quantity = 8 } }
                }));
                throw new InvalidOperationException("Expected offered quantity rejection");
            }
            catch (AccountBridgeHostException e) { Check(e.Code == "marketplace.listing_invalid", "Range rejection"); }
        }
        foreach (var side in new[] { "sell", "buy" })
        {
            var mapped = BridgePayload.From(MarketplaceListingRequest.Create(BridgePayload.From(new {
                itemId = 123, side, quantity = 12, offeredQuantity = 7, price = 8,
                expiryDays = 7, visible = true, location = 456
            })));
            Check(mapped.GetProperty("items")[0].GetProperty("quantity").GetInt64() == 1,
                "Currency orders still offer one per unit");
        }
        var partial = BridgePayload.From(MarketplaceListingProjection.Order(BridgePayload.From(new {
            displayType = 3, creatorType = 1, itemDetails = new[] { new { itemId = 1 } }
        })));
        // Null fields are left out of the bridge payload.
        Check(!partial.TryGetProperty("itemCount", out var partialCount) || partialCount.ValueKind == JsonValueKind.Null,
            "A first-item-only list never claims there is just one item");
        foreach (var (thumbnail, hd, expected) in new[] {
            ("https://fixture.invalid/item.png", "https://fixture.invalid/hd.png", "https://fixture.invalid/item.png"),
            ("", "https://fixture.invalid/hd.png", "https://fixture.invalid/hd.png"),
            ("", "", "https://fixture.invalid/top.png")
        })
        {
            var row = BridgePayload.From(new {
                displayType = 3, creatorType = 0, itemCount = 2, thumbnailUrl = "https://fixture.invalid/top.png",
                itemDetails = new[] { new { itemId = 1, thumbnailUrl = thumbnail, thumbnailUrlHd = hd } }
            });
            var order = BridgePayload.From(MarketplaceListingProjection.Order(row));
            Check(order.GetProperty("image").GetString() == expected, "Own listing image fallback");
            Check(order.GetProperty("displayType").GetInt32() == 3 &&
                order.GetProperty("creatorType").GetInt32() == 0 &&
                order.GetProperty("itemCount").GetInt32() == 2, "Copy eligibility facts projected");
            var manifest = BridgePayload.From(MarketplaceListingProjection.Manifest(row));
            // A null image is left out of the bridge payload.
            var manifestImage = manifest.GetProperty("items")[0].TryGetProperty("thumbnailUrl", out var image) ? image.GetString() : null;
            Check(manifestImage == (thumbnail.Length > 0 ? thumbnail : hd.Length > 0 ? hd : null), "Manifest image projected");
        }
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal int Count, Code;
        internal bool Fail;
        internal HttpMethod? Method;
        internal string? Path, Body;
        internal readonly List<HttpMethod> Methods = [];

        /// <summary>The order <c>sc/orders/get</c> returns; other reads and writes answer <c>true</c>.</summary>
        internal object? Order;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Count++; Method = request.Method; Path = request.RequestUri!.PathAndQuery; Methods.Add(request.Method);
            Body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            if (Fail) throw new HttpRequestException("fixture");
            var data = Path.StartsWith("/app-api/sc/orders/get?", StringComparison.Ordinal) ? Order : true;
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = Code, data })) };
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
