using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// 0.7.2 G8: SCM station messages for the notification center. Type/subType kept for categories,
// trader masked with a chat reference, no user/sender/trader ids or product URLs, marks only.
internal static class MarketplaceNoticesTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<(string Method, string PathAndQuery, string? Body)> Requests = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            var path = request.RequestUri!.PathAndQuery;
            lock (Requests) Requests.Add((request.Method.Method, path, body));
            object data = request.RequestUri.AbsolutePath switch
            {
                "/app-api/member/message/page" => new { total = 2, list = new object[] {
                    new { id = 11, userId = 4242000000000042, senderId = 9090000000000009, type = 1, subType = 4, title = "卖家已发货", content = "订单 SO88 已发货", isRead = 0, createTime = 1760000000000,
                          orderInfo = new { orderId = 88, orderNumber = "SO88", transactionId = "TX88", productName = "钛", productUrl = "https://cdn/p", quantity = 16, amount = 120000,
                                            traderName = "Kestrel", traderId = 9090000000000009, providedItems = new object[] { new { itemId = "it-1", name = "钛", quantity = 16, qualityData = "{}" } } } },
                    new { id = 12, userId = 4242000000000042, type = 0, title = "维护公告", content = "今晚维护", isRead = true, createTime = 1760000000001 } } },
                "/app-api/member/message/unread-count" => new { total = 3, stationUnreadCount = 2, chatFallbackUnreadCount = 1 },
                "/app-api/member/message/mark-read" or "/app-api/member/message/mark-all-read" => true,
                _ => throw new Exception("Unexpected route " + path),
            };
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) };
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
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "profile.write"]);
        async Task<JsonElement> Call(object input, ScmOAuthSession? as_ = null) =>
            BridgePayload.From((await client.MarketplaceNoticesAsync(as_ ?? session, BridgePayload.From(input), () => true, default)).Data);

        var page = await Call(new { schemaVersion = 1, operation = "page", type = 1, unread = true });
        Check(handler.Requests[^1].PathAndQuery == "/app-api/member/message/page?pageNo=1&pageSize=20&type=1&isRead=false", "type and unread filters");
        var trade = page.GetProperty("rows")[0];
        Check(trade.GetProperty("type").GetInt32() == 1 && trade.GetProperty("subType").GetInt32() == 4 && !trade.GetProperty("read").GetBoolean(), "category fields kept");
        var order = trade.GetProperty("order");
        Check(order.GetProperty("trader").GetString() == "K*****l" && order.GetProperty("traderChat").GetString()!.Length == 32, "trader masked, reachable by chat");
        Check(order.GetProperty("provided")[0].GetProperty("quantity").GetInt32() == 16, "items kept");
        Check(page.GetProperty("rows")[1].GetProperty("read").GetBoolean() && !page.GetProperty("rows")[1].TryGetProperty("order", out _), "system notice");
        var text = page.GetRawText();
        Check(!text.Contains("4242000000000042") && !text.Contains("9090000000000009") && !text.Contains("cdn/") && !text.Contains("senderId"), "no ids or product URLs");

        var unread = await Call(new { schemaVersion = 1, operation = "unread" });
        Check(unread.GetProperty("total").GetInt64() == 3 && unread.GetProperty("chatFallback").GetInt64() == 1, "unread counts");
        await Call(new { schemaVersion = 1, operation = "read", id = 11 });
        Check(handler.Requests[^1] is ("PUT", "/app-api/member/message/mark-read", "{\"id\":11}"), "mark one read");
        await Call(new { schemaVersion = 1, operation = "readAll", type = 1 });
        Check(handler.Requests[^1].PathAndQuery == "/app-api/member/message/mark-all-read?type=1", "mark a category read");

        foreach (var bad in new object[] {
            new { schemaVersion = 1, operation = "clear" },
            new { schemaVersion = 1, operation = "page", type = 3 },
            new { schemaVersion = 1, operation = "read" },
            new { schemaVersion = 1, operation = "page", userId = 1 },
        })
        {
            try { await Call(bad); throw new Exception("FAIL invalid notices request accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
        }
        var readOnly = session with { Capabilities = ["profile.read"] };
        try { await Call(new { schemaVersion = 1, operation = "readAll" }, readOnly); throw new Exception("FAIL mark without profile.write"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
        Console.WriteLine("PASS marketplace notices: categories, masked trader with chat reference, counts, read marks only");
    }
}
