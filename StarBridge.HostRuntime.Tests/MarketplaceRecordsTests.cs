using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// 0.7.2 G5/G6/G7: received reviews, own reports, own blocklist and unblock. Only display fields
// leave the Host; SCM member ids stay behind an opaque per-process reference.
internal static class MarketplaceRecordsTests
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
            Requests.Add((request.Method.Method, path, body));
            object data = request.RequestUri.AbsolutePath switch
            {
                "/app-api/member/user/get" => new { id = 4242000000000042, nickname = "Self", userMobile = "QQ 1" },
                "/app-api/sc/order-reviews/page" => new { total = 2, list = new object[] {
                    new { id = 1, transactionId = "TX1", reviewerId = 77, reviewerName = "Aster", reviewerAvatar = "https://cdn/a.png", rating = 5, content = "快", auditStatus = 1, createTime = 1760000000000 },
                    new { id = 2, transactionId = "TX2", reviewerId = 78, reviewerName = "K", rating = 4, content = "", auditStatus = 0, createTime = 1760000000001 } } },
                "/app-api/trade/order-report/my-list" => new { total = 1, list = new object[] {
                    new { id = 9, transactionNumber = "TX9", reportedUserId = 55, reportedUserNickname = "Raider", reportTypeName = "欺诈", reportContent = "收款后拉黑", reportEvidence = "https://cdn/e.png", handleStatusName = "已处理", handleResult = "已封禁", handler = "admin", createTime = "2026-10-09" } } },
                "/app-api/member/user-blacklist/my-list" => new { total = 1, list = new object[] {
                    new { id = 3, blockedUserId = 5550000000000005, blockedUserNickname = "Dodger", blockedUserAvatar = "https://cdn/d.png", reason = "多次爽约", status = 1, createTime = 1760000000002 } } },
                "/app-api/member/user-blacklist/remove" => true,
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
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1),
            ["profile.read", "trade.read", "blocklist.read", "blocklist.write"]);
        async Task<JsonElement> Call(object input, ScmOAuthSession? as_ = null) =>
            BridgePayload.From((await client.MarketplaceRecordsAsync(as_ ?? session, BridgePayload.From(input), () => true, default)).Data);

        var reviews = await Call(new { schemaVersion = 1, operation = "reviews" });
        Check(handler.Requests.Any(r => r.PathAndQuery.StartsWith("/app-api/sc/order-reviews/page?reviewerId=4242000000000042&", StringComparison.Ordinal)),
            "reviews about me are read with my own SCM id, resolved by the Host");
        var review = reviews.GetProperty("rows")[0];
        Check(review.GetProperty("reviewer").GetString() == "A*****r", "reviewer masked");
        Check(!review.TryGetProperty("reviewerId", out _) && !review.TryGetProperty("reviewerAvatar", out _), "no reviewer id or avatar");
        Check(reviews.GetProperty("total").GetInt64() == 2, "total kept");
        await Call(new { schemaVersion = 1, operation = "reviews", page = 2 });
        Check(handler.Requests.Count(r => r.PathAndQuery == "/app-api/member/user/get") == 1, "own id read once per owner");

        var reports = await Call(new { schemaVersion = 1, operation = "reports" });
        var report = reports.GetProperty("rows")[0];
        Check(report.GetProperty("reported").GetString() == "R*****r" && report.GetProperty("result").GetString() == "已封禁", "report projected");
        var reportText = report.GetRawText();
        Check(!reportText.Contains("reportedUserId") && !reportText.Contains("admin") && !reportText.Contains("cdn/e.png"),
            "no reported id, handler or evidence URL");

        var blocklist = await Call(new { schemaVersion = 1, operation = "blocklist" });
        var blocked = blocklist.GetProperty("rows")[0];
        var reference = blocked.GetProperty("ref").GetString()!;
        Check(reference.Length == 32 && !blocked.GetRawText().Contains("5550000000000005") && blocked.GetProperty("active").GetBoolean(),
            "blocked user is an opaque reference, never the SCM id");
        await Call(new { schemaVersion = 1, operation = "unblock", @ref = reference });
        var remove = handler.Requests.Single(r => r.Method == "DELETE");
        Check(remove.PathAndQuery == "/app-api/member/user-blacklist/remove" && remove.Body!.Contains("\"blockedUserId\":5550000000000005"),
            "unblock maps the reference back to the SCM id in a DELETE body");
        try { await Call(new { schemaVersion = 1, operation = "unblock", @ref = reference }); throw new Exception("FAIL spent reference reused"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.state_changed") { }
        try { await Call(new { schemaVersion = 1, operation = "unblock", @ref = new string('0', 32) }); throw new Exception("FAIL unknown reference accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.state_changed") { }

        var readOnly = session with { Capabilities = ["profile.read", "trade.read", "blocklist.read"] };
        await Call(new { schemaVersion = 1, operation = "blocklist" }, readOnly);
        try { await Call(new { schemaVersion = 1, operation = "unblock", @ref = reference }, readOnly); throw new Exception("FAIL unblock without blocklist.write"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
        foreach (var bad in new object[] {
            new { schemaVersion = 1, operation = "delete" },
            new { schemaVersion = 1, operation = "reviews", page = 0 },
            new { schemaVersion = 1, operation = "reviews", reviewerId = 1 },
        })
        {
            try { await Call(bad); throw new Exception("FAIL invalid request accepted"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
        }
        Console.WriteLine("PASS marketplace records: reviews about me, reports, blocklist with opaque unblock, scopes, no ids");
    }
}
