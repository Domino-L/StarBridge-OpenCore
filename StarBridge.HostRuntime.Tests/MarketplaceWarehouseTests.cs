using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// 0.7.2 G2: the member's own SCM warehouse, read only. Personal owner only, bounded rows,
// no owner/actor ids, avatars, image URLs or package snapshots, and no write routes.
internal static class MarketplaceWarehouseTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<string> Requests = [];
        internal object? Cursor = "41";
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.PathAndQuery;
            lock (Requests) Requests.Add(request.Method.Method + " " + path);
            object data = request.RequestUri.AbsolutePath switch
            {
                "/app-api/warehouse/space/list" => new object[] {
                    new { id = 3, ownerType = "USER", ownerId = 4242000000000042, name = "主仓", code = "A1", locationId = 12, locationName = "洛维尔", locationFullPath = "斯坦顿 / 微科星 / 洛维尔",
                          isDefault = true, status = 1, inventoryLineCount = 8, onHandQuantity = 120, reservedQuantity = 20, availableQuantity = 100, permissionCodes = new[] { "x" } } },
                "/app-api/warehouse/inventory/page" => new { total = 1, list = new object[] {
                    new { id = 9, ownerId = 4242000000000042, spaceId = 3, spaceName = "主仓", locationName = "洛维尔", itemId = "it-1", itemName = "钛", thumbnailUrl = "https://cdn/t.png",
                          qualityKey = "44136fa355b3678a", qualityData = "{\"type\":\"material\",\"quality\":900}", onHandQuantity = 96, reservedQuantity = 16, availableQuantity = 80, version = 7 } } },
                "/app-api/warehouse/inventory/summary" => new { ownerId = 4242000000000042, spaceCount = 2, inventoryLineCount = 8, distinctItemCount = 5, onHandQuantity = 120, reservedQuantity = 20, availableQuantity = 100 },
                "/app-api/warehouse/ledger/page" => new { total = 1, list = new object[] {
                    new { id = 70, operationNo = "OP70", operationType = "STOCK_OUT", spaceName = "主仓", itemId = "it-1", itemName = "钛", deltaOnHand = -16, deltaReserved = -16, movedQuantity = 50, afterOnHand = 96,
                          businessType = "TRADE", businessNo = "TX88", actorUserId = 4242000000000042, actorNickname = "Self", actorAvatar = "https://cdn/s.png", occurredAt = 1760000000000 } } },
                "/app-api/warehouse/escrow/scroll" => new { hasMore = true, nextCursor = Cursor, list = new object[] {
                    new { id = 40, businessType = "ORDER", businessNo = "SO88", itemSide = "SELL", itemId = "it-1", itemName = "钛", quantity = 16, status = "LOCKED",
                          packageSnapshot = "{\"buyerId\":9090000000000009}", nodeId = 5, containerId = 6, thumbnailUrl = "https://cdn/t.png" } } },
                _ => throw new Exception("Unexpected route " + path),
            };
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) });
        }
    }

    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }

    internal static async Task Run()
    {
        await CursorAndQualityShapes();
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "trade.read"]);
        async Task<JsonElement> Call(object input) =>
            BridgePayload.From((await client.MarketplaceWarehouseAsync(session, BridgePayload.From(input), () => true, default)).Data);

        var spaces = await Call(new { schemaVersion = 1, operation = "spaces" });
        var space = spaces.GetProperty("rows")[0];
        Check(space.GetProperty("name").GetString() == "主仓" && space.GetProperty("available").GetInt32() == 100 && space.GetProperty("isDefault").GetBoolean(), "space projected");
        var inventory = await Call(new { schemaVersion = 1, operation = "inventory", spaceId = 3, keyword = "钛", available = true, page = 2 });
        Check(handler.Requests[^1] == "GET /app-api/warehouse/inventory/page?ownerType=USER&pageNo=2&pageSize=20&spaceId=3&itemKeyword=%E9%92%9B&onlyAvailable=true", "inventory filters");
        Check(inventory.GetProperty("rows")[0].GetProperty("reserved").GetInt32() == 16, "reserved by listings");
        var summary = await Call(new { schemaVersion = 1, operation = "summary" });
        Check(summary.GetProperty("items").GetInt32() == 5, "summary");
        var ledger = await Call(new { schemaVersion = 1, operation = "ledger" });
        Check(ledger.GetProperty("rows")[0].GetProperty("deltaOnHand").GetInt32() == -16 && ledger.GetProperty("rows")[0].GetProperty("businessNo").GetString() == "TX88", "ledger linked to the trade");
        var escrow = await Call(new { schemaVersion = 1, operation = "escrow", after = 40 });
        Check(handler.Requests[^1] == "GET /app-api/warehouse/escrow/scroll?limit=20&afterId=40" && escrow.GetProperty("next").GetInt64() == 41 && escrow.GetProperty("more").GetBoolean(), "escrow cursor");
        var all = spaces.GetRawText() + inventory.GetRawText() + summary.GetRawText() + ledger.GetRawText() + escrow.GetRawText();
        Check(!all.Contains("4242000000000042") && !all.Contains("9090000000000009") && !all.Contains("cdn/") && !all.Contains("Self") && !all.Contains("permission"),
            "no owner/actor ids, names, avatars, image URLs, snapshots or permission codes");
        Check(handler.Requests.All(r => r.StartsWith("GET ", StringComparison.Ordinal)) && handler.Requests.Where(r => !r.Contains("escrow")).All(r => r.Contains("ownerType=USER")),
            "read only, personal owner only");
        foreach (var bad in new object[] {
            new { schemaVersion = 1, operation = "transfer" },
            new { schemaVersion = 1, operation = "inventory", spaceId = -1 },
            new { schemaVersion = 1, operation = "inventory", ownerType = "ORGANIZATION" },
            new { schemaVersion = 1, operation = "inventory", keyword = new string('x', 51) },
        })
        {
            try { await Call(bad); throw new Exception("FAIL invalid warehouse request accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
        }
        Console.WriteLine("PASS marketplace warehouse: personal read-only spaces, inventory, summary, ledger, escrow without ids");
    }
    private static async Task CursorAndQualityShapes()
    {
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["trade.read"]);
        async Task<JsonElement> Call(string op) => BridgePayload.From((await client.MarketplaceWarehouseAsync(session,
            BridgePayload.From(new { operation = op }), () => true, default)).Data);
        foreach (var cursor in new object?[] { "41", 41L, null, "0", "bad" })
        {
            handler.Cursor = cursor;
            var data = await Call("escrow");
            var valid = cursor is "41" or 41L;
            Check(data.GetProperty("more").GetBoolean() == valid, "OT3 cursor string/number/null shapes");
            if (valid) Check(data.GetProperty("next").GetInt64() == 41, "OT3 cursor value");
            else Check(!data.TryGetProperty("next", out var next) || next.ValueKind == JsonValueKind.Null, "OT3 no next page");
        }
        var item = (await Call("inventory")).GetProperty("rows")[0];
        Check(item.GetProperty("qualityData").GetString()!.Contains("900") && !item.TryGetProperty("quality", out _) && !item.GetRawText().Contains("44136"), "OT4 real quality JSON, never hash digits");
        var noQuality = BridgePayload.From(StarBridge.HostRuntime.Marketplace.MarketplaceWarehouse.Inventory(
            BridgePayload.From(new { id = 10, qualityKey = "44136fa355b3678a" })));
        Check(!noQuality.TryGetProperty("qualityData", out var quality) || quality.ValueKind == JsonValueKind.Null, "OT4 missing quality stays absent");
        var ledger = (await Call("ledger")).GetProperty("rows")[0];
        Check(ledger.GetProperty("movedQuantity").GetInt32() == 50 && ledger.GetProperty("deltaReserved").GetInt32() == -16, "OT5 movement and reserved delta projected");
    }
}
