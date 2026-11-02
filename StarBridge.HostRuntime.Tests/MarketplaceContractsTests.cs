using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// 0.7.2 G1: SCM contracts. Masked names, chat references instead of member ids, plain-text
// descriptions, SCM's limits checked before a write, and every write sent once.
internal static class MarketplaceContractsTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal readonly List<(string Method, string PathAndQuery, string? Body)> Requests = [];
        internal bool RefuseApply;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            var path = request.RequestUri!.PathAndQuery;
            lock (Requests) Requests.Add((request.Method.Method, path, body));
            var contract = new
            {
                id = 17, contractNumber = "CT-2026102100017", contractType = "BOUNTY", creatorId = 9090000000000009, creatorNickname = "Kestrel",
                creatorAvatar = "https://cdn/k.png", creatorReputation = 80, creatorStatus = 1, creatorType = 0, title = "拦截货船",
                description = "<p>目标周六 20:00 出发&nbsp;<b>哈索</b></p><p>需要截图</p><script>x</script>", locationDescription = "哈索",
                rewardType = "UEC", rewardUec = 2500000, maxParticipants = 3, currentParticipants = 0, minReputation = 50, status = 1,
                expireTime = 1761000000000, applyCount = 2, isCreator = false, isApplied = false, meetReputationRequirement = true,
            };
            if (RefuseApply && request.RequestUri.AbsolutePath == "/app-api/trade/contract/apply")
                return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 1_008_009_001, msg = "信誉不足" })) };
            object data = request.RequestUri.AbsolutePath switch
            {
                "/app-api/trade/contract/page" or "/app-api/trade/contract/my-page" => new { total = 1, list = new[] { contract } },
                "/app-api/trade/contract/get" => contract,
                "/app-api/trade/contract/milestones" => new object[] { new { id = 1, contractId = 17, participantId = 5, milestoneOrder = 1, title = "确认航线", status = 1, confirmedBy = 9090000000000009 } },
                "/app-api/trade/contract/participants/page" => new
                {
                    total = 1,
                    list = new object[] { new { id = 5, userId = 7770000000000007, userNickname = "Aster", userAvatar = "https://cdn/a.png", userReputation = 60,
                        applyMessage = "有 Hornet", applyShipNames = new[] { "F7C Hornet" }, status = 0, workProof = new[] { "https://cdn/p.png" } } },
                    extra = new { viewerParticipant = new { id = 6, userId = 4242000000000042, userNickname = "Self", status = 0 } },
                },
                "/app-api/trade/contract/create" => 99,
                "/app-api/trade/contract/apply" => 6,
                "/app-api/trade/contract/start" or "/app-api/trade/contract/cancel" => true,
                "/app-api/trade/contract/review" => 3,
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
            ["profile.read", "trade.read", "trade.write"]);
        async Task<JsonElement> Call(object input, ScmOAuthSession? as_ = null) =>
            BridgePayload.From((await client.MarketplaceContractsAsync(as_ ?? session, BridgePayload.From(input), () => true, default)).Data);

        var list = await Call(new { schemaVersion = 1, operation = "list", type = "BOUNTY", status = 1, keyword = "货船 C" });
        Check(handler.Requests[^1].PathAndQuery == "/app-api/trade/contract/page?pageNo=1&pageSize=20&contractType=BOUNTY&status=1&keyword=%E8%B4%A7%E8%88%B9%20C",
            "filters become SCM query parameters");
        var card = list.GetProperty("rows")[0];
        Check(card.GetProperty("creator").GetString() == "K*****l" && card.GetProperty("creatorOnline").GetBoolean(), "publisher masked with presence");
        Check(card.GetProperty("creatorChat").GetString()!.Length == 32, "publisher can be messaged through a chat reference");
        Check(card.GetProperty("description").GetString() == "目标周六 20:00 出发 哈索\n\n需要截图x" || card.GetProperty("description").GetString()!.StartsWith("目标周六 20:00 出发"),
            "rich text arrives as plain text");
        Check(!card.GetProperty("description").GetString()!.Contains('<'), "no markup");
        var cardText = card.GetRawText();
        Check(!cardText.Contains("9090000000000009") && !cardText.Contains("cdn/k.png"), "no member id or avatar");

        await Call(new { schemaVersion = 1, operation = "mine", scope = "participated", page = 2 });
        Check(handler.Requests[^1].PathAndQuery.EndsWith("pageNo=2&pageSize=20&mineScope=PARTICIPATED", StringComparison.Ordinal), "participated scope");

        var detail = await Call(new { schemaVersion = 1, operation = "detail", id = 17 });
        var person = detail.GetProperty("participants").GetProperty("rows")[0];
        Check(person.GetProperty("name").GetString() == "A*****r" && person.GetProperty("ships")[0].GetString() == "F7C Hornet", "participant projected");
        Check(detail.GetProperty("me").GetProperty("id").GetInt32() == 6, "viewer participation kept");
        var detailText = detail.GetRawText();
        Check(!detailText.Contains("7770000000000007") && !detailText.Contains("4242000000000042") && !detailText.Contains("cdn/") && !detailText.Contains("confirmedBy"),
            "no member ids, avatars or proof URLs");
        Check(detail.GetProperty("milestones")[0].GetProperty("title").GetString() == "确认航线", "milestones");

        var expire = DateTimeOffset.UtcNow.AddDays(2).ToUnixTimeMilliseconds();
        var created = await Call(new { schemaVersion = 1, operation = "create", contract = new {
            type = "SERVICE", title = "运医疗物资", rewardType = "UEC", rewardUec = 380000, slots = 1, minReputation = 20, expireTime = expire } });
        Check(created.GetProperty("id").GetInt64() == 99, "created id");
        var createBody = handler.Requests.Single(r => r.PathAndQuery == "/app-api/trade/contract/create").Body!;
        Check(createBody.Contains("\"contractType\":\"SERVICE\"") && createBody.Contains("\"creatorType\":0") && createBody.Contains("\"maxParticipants\":1"),
            "publish form mapped to SCM fields as a personal contract");

        await Call(new { schemaVersion = 1, operation = "apply", id = 17, message = "  有 Hornet  " });
        Check(handler.Requests[^1].Body!.Contains("\"applyMessage\":\"有 Hornet\"") || handler.Requests[^1].Body!.Contains("\\u6709 Hornet"), "apply message trimmed");
        await Call(new { schemaVersion = 1, operation = "start", id = 17 });
        Check(handler.Requests[^1] is ("POST", "/app-api/trade/contract/start?contractId=17", null), "start by query parameter");
        await Call(new { schemaVersion = 1, operation = "cancel", id = 17, reason = "人数不够" });
        Check(handler.Requests[^1].PathAndQuery.StartsWith("/app-api/trade/contract/cancel?contractId=17&reason=%E4%BA%BA", StringComparison.Ordinal), "cancel reason encoded");
        await Call(new { schemaVersion = 1, operation = "review", participantId = 5, rating = 5, comment = "靠谱" });

        handler.RefuseApply = true;
        var applies = handler.Requests.Count(r => r.PathAndQuery.EndsWith("/apply", StringComparison.Ordinal));
        try { await Call(new { schemaVersion = 1, operation = "apply", id = 17 }); throw new Exception("FAIL refusal hidden"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.trade_rejected") { }
        Check(handler.Requests.Count(r => r.PathAndQuery.EndsWith("/apply", StringComparison.Ordinal)) == applies + 1, "refused write not replayed");

        foreach (var bad in new object[] {
            new { schemaVersion = 1, operation = "list", type = "PVP" },
            new { schemaVersion = 1, operation = "list", status = 0 },
            new { schemaVersion = 1, operation = "cancel", id = 17 },
            new { schemaVersion = 1, operation = "review", participantId = 5, rating = 6 },
            new { schemaVersion = 1, operation = "delete", id = 17 },
            new { schemaVersion = 1, operation = "detail", id = 17, creatorId = 9090000000000009 },
            (object)new { schemaVersion = 1, operation = "create", contract = new { type = "SERVICE", title = "x", rewardType = "UEC", rewardUec = 0, slots = 1, expireTime = expire } },
            new { schemaVersion = 1, operation = "create", contract = new { type = "SERVICE", title = "x", rewardType = "ITEMS", slots = 1, expireTime = expire } },
            new { schemaVersion = 1, operation = "create", contract = new { type = "SERVICE", title = "x", rewardType = "UEC", rewardUec = 5, slots = 101, expireTime = expire } },
            new { schemaVersion = 1, operation = "create", contract = new { type = "SERVICE", title = "x", rewardType = "UEC", rewardUec = 5, slots = 1, expireTime = 1 } },
        })
        {
            try { await Call(bad); throw new Exception("FAIL invalid contract request accepted: " + JsonSerializer.Serialize(bad)); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
        }
        var readOnly = session with { Capabilities = ["profile.read", "trade.read"] };
        await Call(new { schemaVersion = 1, operation = "list" }, readOnly);
        try { await Call(new { schemaVersion = 1, operation = "apply", id = 17 }, readOnly); throw new Exception("FAIL apply without trade.write"); }
        catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
        Console.WriteLine("PASS marketplace contracts: masked people with chat references, plain text, validated publish, one-shot writes");
    }
}
