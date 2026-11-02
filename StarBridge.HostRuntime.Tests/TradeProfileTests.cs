using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class TradeProfileTests
{
    static JsonElement Profile(string contact = "original") => BridgePayload.From(new {
        id = 98765, email = "private@example.invalid", banActive = true,
        profileBackground = "private-background", tradeTime = "[1,1,1,1,1,1,1]",
        tradeStartTime = "23:30", tradeEndTime = "01:00", timezoneId = 1,
        userMobile = contact, mark = "keep", language = 0,
        achievement = new { point = 12, orderLimit = 20 }, completedTransactionCount = 3
    });
    internal static async Task Run()
    {
        void Check(bool v, string message) { if (!v) throw new Exception(message); }
        var projected = JsonSerializer.Serialize(TradeProfileContract.Project(Profile()));
        foreach (var secret in new[] { "98765", "email", "banActive", "private-background" }) Check(!projected.Contains(secret), "Projection leaked " + secret);
        foreach (var unset in new[] { "\"\"", "null", "\"  \"", "\"broken\"" }) {
            var blank = JsonSerializer.Deserialize<JsonElement>("{\"tradeTime\":" + unset + ",\"tradeStartTime\":null,\"tradeEndTime\":null,\"timezoneId\":null,\"userMobile\":null}");
            var read = BridgePayload.From(TradeProfileContract.Project(blank));
            Check(read.GetProperty("tradeTime").EnumerateArray().All(d => d.GetInt32() == 0) && read.GetProperty("tradeStartTime").ValueKind == JsonValueKind.Null,
                "Unset SCM profile (tradeTime " + unset + ") reads as empty instead of failing");
            var filled = TradeProfileContract.Merge(blank, BridgePayload.From(new { tradeTime = new[] {1,0,0,0,0,0,0}, tradeStartTime = "20:00", tradeEndTime = "22:00", timezoneId = 1, userMobile = "discord:x" }));
            Check(filled.Count == 5, "Unset profile can be completed in one save");
        }
        var merged = TradeProfileContract.Merge(Profile(), BridgePayload.From(new { userMobile = "edited" }));
        Check(merged.Count == 5 && !JsonSerializer.Serialize(merged).Contains("null"), "Only required fields merged, no null");
        Check(!merged.ContainsKey("mark") && !merged.ContainsKey("language") && !merged.ContainsKey("profileBackground"), "Omitted optional fields preserved server-side");
        try { TradeProfileContract.Merge(Profile(), JsonSerializer.Deserialize<JsonElement>("{\"profileBackground\":null}")); throw new Exception("Null accepted"); }
        catch (AccountBridgeHostException e) { Check(e.Code == "trade_profile.rejected", "Null rejected"); }
        foreach (var (change, expected) in new[] {
            (BridgePayload.From(new { tradeStartTime = "10:00", tradeEndTime = "10:30" }), "time_range"),
            (BridgePayload.From(new { tradeTime = new[] {0,0,0,0,0,0,0} }), "no_day"),
            (BridgePayload.From(new { userMobile = "abc" }), "contact_invalid"),
            (BridgePayload.From(new { timezoneId = 0 }), "timezone_invalid") }) {
            try { TradeProfileContract.Merge(Profile(), change); throw new Exception("Validation missing " + expected); }
            catch (AccountBridgeHostException e) { Check(e.Code == "trade_profile." + expected, expected); }
        }
        foreach (var (message, expected) in new[] { ("交易时间范围不合法", "time_range"), ("至少需要选择一天开启交易", "no_day"),
            ("用户联系方式不得低于5个字符", "contact_invalid"), ("时区ID不存在或已禁用", "timezone_invalid"), ("其他", "rejected") })
            Check(TradeProfileContract.Rejection(400, message) == "trade_profile." + expected, "Error map " + expected);
        Check(TradeProfileContract.Rejection(403, null) == "marketplace.forbidden", "403 map");
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture",uri,uri,uri,"desktop","starbridge-api","", "/callback"));
        var session = new ScmOAuthSession("fixture","opaque","Fixture","synthetic",DateTimeOffset.UtcNow.AddHours(1),["profile.read","trade.read","profile.write","trade.write"]);
        var result = await client.TradeProfileAsync(session, true, BridgePayload.From(new { userMobile = "submitted" }), () => true, default);
        var data = BridgePayload.From(result.Data);
        Check(data.GetProperty("profile").GetProperty("userMobile").GetString() == "filtered", "Read-back is authoritative");
        Check(handler.Methods.SequenceEqual(new[] {"GET", "PUT", "GET"}), "Read merge write read order");
        Check(handler.Body is not null && !handler.Body.Contains("null") && !handler.Body.Contains("profileBackground"), "Wire omission");
        if (client.LastTradeWindowSync is { } sync) await sync;
        Check(handler.WindowBodies.Count == 1 && !handler.WindowBodies[0].Contains("filtered") && !handler.WindowBodies[0].Contains("userMobile") && !handler.WindowBodies[0].Contains("98765"),
            "Confirmed window copied to the profile service without contact");
        handler.Methods.Clear(); handler.FailWrite = true;
        result = await client.TradeProfileAsync(session,true,BridgePayload.From(new { userMobile = "again" }),()=>true,default);
        Check(handler.Methods.SequenceEqual(new[] {"GET","PUT","GET"}), "Uncertain PUT not replayed");
        Check(BridgePayload.From(result.Data).GetProperty("requiresReview").GetBoolean(), "Uncertain read-back review");
        handler.Methods.Clear(); handler.FailWrite = false; handler.TimeoutWrite = true;
        result = await client.TradeProfileAsync(session,true,BridgePayload.From(new { userMobile = "timeout" }),()=>true,default);
        Check(handler.Methods.SequenceEqual(new[] {"GET","PUT","GET"}) && BridgePayload.From(result.Data).GetProperty("requiresReview").GetBoolean(),
            "Client timeout is an uncertain write, not a cancel");
        handler.Methods.Clear(); handler.TimeoutWrite = false;
        try { await client.TradeProfileAsync(session with { Capabilities = ["profile.read","trade.read","profile.write"] },true,BridgePayload.From(new {}),()=>true,default); throw new Exception("Missing trade.write accepted"); }
        catch(AccountBridgeHostException e) { Check(e.Code == "marketplace.reauthorize_required" && handler.Methods.Count == 0, "Scope gate before request"); }
        Console.WriteLine("PASS trade profile projection, merge, validation, rejection, scopes, read-back and no replay");
    }
    sealed class Handler : HttpMessageHandler
    {
        internal List<string> Methods = [];
        internal string? Body;
        internal bool FailWrite, TimeoutWrite;
        // The background public trade-window sync (DEPLOY-QUEUE §4b), kept apart from the SCM order.
        internal List<string> WindowBodies = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath.EndsWith("/trade-window", StringComparison.Ordinal))
            {
                var windowBody = await request.Content!.ReadAsStringAsync(token);
                lock (WindowBodies) WindowBodies.Add(windowBody);
                return new(HttpStatusCode.NoContent);
            }
            Methods.Add(request.Method.Method);
            if (request.RequestUri!.AbsolutePath != "/app-api/member/user/" + (request.Method == HttpMethod.Get ? "get" : "update")) throw new Exception("Wrong route");
            if (request.Method == HttpMethod.Put) {
                Body = await request.Content!.ReadAsStringAsync(token);
                if (FailWrite) throw new HttpRequestException("fixture uncertain");
                if (TimeoutWrite) throw new TaskCanceledException("fixture timeout");
            }
            return new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data = request.Method == HttpMethod.Get ? (object)Profile("filtered") : true })) };
        }
    }
    sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }
}
