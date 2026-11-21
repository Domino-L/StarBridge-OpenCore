using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceTradeDetailTests
{
    private static void Check(bool ok, string message)
    {
        if (!ok) throw new Exception(message);
    }

    internal static async Task Run()
    {
        Projection();
        ReportingAndDeadlines();
        ErrorCodes();
        await DetailUsesOwnListAndLanguage();
    }

    private static void Projection()
    {
        var items = Enumerable.Range(1, 55).Select(i => new {
            itemId = i, itemName = "物品", thumbnailUrl = "https://fixture.invalid/item.png",
            quantity = 3, unitPrice = 12, qualityData = new { type = "material", quality = 900 },
            warehouseId = 99,
        }).ToArray();
        var row = BridgePayload.From(new {
            displayType = 2, itemCount = 55, itemDetails = items,
            wantedItems = new[] { new { itemId = 10, itemName = "换回的物品", qualityData = new { quality = 800 } } },
        });
        var projected = BridgePayload.From(MarketplaceTradePolicy.Project(row));
        Check(projected.GetProperty("itemDetails").GetArrayLength() == 50, "TR1/TR2: bounded details");
        Check(projected.GetProperty("itemCount").GetInt32() == 55, "item count preserved");
        var item = projected.GetProperty("itemDetails")[0];
        Check(item.GetProperty("quantity").GetInt32() == 3 && item.GetProperty("unitPrice").GetInt32() == 12,
            "per-set quantity and SCM line price retained");
        Check(!item.TryGetProperty("warehouseId", out _), "private nested fields excluded");
        Check(!projected.GetProperty("wantedItems")[0].TryGetProperty("quantity", out _), "unknown wanted quantity stays absent");
        var single = BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new {
            displayType = 1, itemDetails = items.Take(1).ToArray(),
        })));
        Check(single.GetProperty("qualityData").GetProperty("quality").GetInt32() == 900, "TR8: detail quality lifted");
        var list = BridgePayload.From(MarketplaceTradePolicy.Project(BridgePayload.From(new { displayType = 2 })));
        Check(!list.TryGetProperty("itemDetails", out _), "list never invents contents");
        foreach (var removed in new[] { "approvalTime", "shippedTime", "shipmentDeadline", "cancellationReason" })
            Check(!list.TryGetProperty(removed, out _), "TR7: unsupported field absent");
    }

    private static void ReportingAndDeadlines()
    {
        foreach (var state in new[] { 1, 2, 3 })
        {
            var row = BridgePayload.From(new { actorRole = "buyer", transactionStatus = state,
                createTime = DateTimeOffset.UtcNow.AddDays(-1).ToUnixTimeMilliseconds(), hasReported = false });
            Check(MarketplaceTradePolicy.Allows(row, "report"), "TR3: any transaction state within seven days");
        }
        var old = BridgePayload.From(new { actorRole = "seller", createTime = DateTimeOffset.UtcNow.AddDays(-8) });
        Check(!MarketplaceTradePolicy.Allows(old, "report"), "old report denied");
        var now = new DateTimeOffset(2026, 11, 14, 0, 0, 0, TimeSpan.Zero);
        // SCM: refused only when whole days since creation > 7 (Duration.toDays()).
        Check(MarketplaceTradeDetails.ReportWithinWindow(BridgePayload.From(new { createTime = "2026-11-06 08:00:01" }), now),
            "Beijing time; 7 whole days and 23:59:59 is still allowed");
        Check(!MarketplaceTradeDetails.ReportWithinWindow(BridgePayload.From(new { createTime = "2026-11-06 08:00:00" }), now),
            "8 whole days is refused");
        var expired = BridgePayload.From(new { actorRole = "buyer", transactionStatus = 1,
            deliveryStatus = 2, receiptDeadline = "2020-01-01 00:00:00" });
        Check(MarketplaceTradePolicy.Action(expired) == null, "expired receipt has no receive action");
    }

    private static void ErrorCodes()
    {
        foreach (var (code, key) in new[] {
            (1011014010, "report_expired"), (1011014002, "report_exists"),
            (1004017004, "trade_blocked_self"), (1004017005, "trade_blocked_other"),
            (1004015000, "trade_restricted"), (1004015001, "trade_rate_limited"),
            (1011015002, "trade_rate_limited"), (1011010009, "trade_quantity_unavailable"),
            (1011010003, "trade_quantity_unavailable"), (1011010001, "trade_listing_unavailable"),
            (1011009003, "trade_listing_unavailable"), (1011010002, "trade_expired"),
        })
            Check(OAuthPkceClient.TradeRejection(BridgePayload.From(new { code })) == "marketplace." + key, key);
    }

    private static async Task DetailUsesOwnListAndLanguage()
    {
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(),
            new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        var session = new ScmOAuthSession("fixture", "owner", "Fixture", "synthetic",
            DateTimeOffset.UtcNow.AddHours(1), ["trade.read", "trade.write"]);
        async Task<JsonElement> Call(object input, ScmOAuthSession? asSession = null) =>
            BridgePayload.From((await client.MarketplaceTradeAsync(asSession ?? session,
                BridgePayload.From(input), () => true, default)).Data);
        await Call(new { operation = "list", language = "EN", status = 1 });
        var row = await Call(new { operation = "detail", transactionNumber = "T1", language = "EN" });
        Check(row.GetProperty("itemsNameEn").GetString() == "Cargo set", "TR10: EN name projected");
        Check(row.GetProperty("amount").GetInt32() == 120, "zero checklist detail preserves list amount");
        Check(!row.GetProperty("hasReported").GetBoolean() && row.GetProperty("canReport").GetBoolean(),
            "counterparty report cannot suppress own report");
        Check(handler.Paths[0].Contains("transactionStatus=1") && handler.Paths.Take(2).All(p => p.Contains("language=EN")),
            "list filter and language on both reads");
        Check(handler.Paths.Count == 2, "no per-row or auxiliary reads");
        await Call(new { operation = "report", transactionNumber = "T1", reportType = 1, content = "未交付" });
        Check(handler.Writes == 1, "report preflight uses own list state, sends once");
        // Account isolation of the list-row cache (owner key) is a code-review check: this client
        // refuses a different subject mid-test ("SCM account changed during request").
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal List<string> Paths = [];
        internal int Writes;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Paths.Add(request.RequestUri!.PathAndQuery);
            if (request.Method != HttpMethod.Get) Writes++;
            object row = new {
                transactionNumber = "T1", actorRole = "buyer", creatorType = 1, displayType = 2,
                transactionStatus = 1, deliveryStatus = 1, number = 2, itemsName = "Cargo set",
                amount = request.RequestUri.AbsolutePath.EndsWith("/page") ? 120 : 0,
                createTime = DateTimeOffset.UtcNow.AddDays(-1),
                hasReported = !request.RequestUri.AbsolutePath.EndsWith("/page"),
                reportHandleStatus = 0,
            };
            object data = request.RequestUri.AbsolutePath.EndsWith("/page")
                ? new { list = new[] { row }, total = 1 } : row;
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })),
            });
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