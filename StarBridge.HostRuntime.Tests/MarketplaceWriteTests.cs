using System.Net;
using System.Reflection;
using System.Text.Json;
using System.Text.Json.Nodes;
using System.Threading.Channels;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// CX-T04: real dispatcher + real OAuth writer + fail-closed in-memory SCM.
// No real session, vault, browser, socket, or default HTTP transport is used.
internal static partial class MarketplaceWriteTests
{
    private sealed record Case(string Area, string Op, string Method, string Route,
        string Input, string? Body, string Rejection, bool UsesDedicatedScope = false, string? Variant = null);

    private static IEnumerable<Case> Cases()
    {
        const string listing = "marketplace.trade_rejected";
        yield return new("listings", "create", "POST", "sc/orders/create",
            """{"itemId":17,"side":"sell","quantity":2,"price":12.5,"expiryDays":7,"visible":true,"location":"31"}""",
            """{"creatorType":1,"locationId":31,"remainingQuantity":2,"status":1,"expireTimeType":0,"items":[{"itemId":17,"quantity":2,"price":12.5,"qualityData":null}],"exchangeItemsList":null,"manifestId":null}""", listing);
        yield return new("listings", "update", "PUT", "sc/orders/update",
            """{"id":"O1","quantity":3,"price":14.5,"expiryDays":14,"visible":false}""",
            """{"orderNumber":"O1","unitPrice":14.5,"remainingQuantity":3,"status":0,"expireTimeType":1,"qualityData":null}""", listing);
        foreach (var visible in new[] { true, false })
            yield return new("listings", "visibility", "PUT", "sc/orders/orderStatus?orderNumber=O1&status=" + (visible ? 1 : 0),
                JsonSerializer.Serialize(new { id = "O1", visible }), null, listing, false, visible ? "publish" : "withdraw");
        yield return new("listings", "quantityAdd", "PUT", "sc/orders/quantity-add?orderNumber=O1", """{"id":"O1"}""", null, listing);
        yield return new("listings", "delete", "DELETE", "sc/orders/delete?orderNumber=O1", """{"id":"O1"}""", null, listing);
        foreach (var update in new[] { false, true })
            yield return new("listings", update ? "listUpdate" : "listCreate", update ? "PUT" : "POST", "sc/item-list/" + (update ? "update" : "create"),
                """{"id":5,"name":"Kit","remark":"Note","items":[{"itemId":17,"quantity":2,"price":3},{"itemId":18,"quantity":1,"price":4}]}""",
                "{\"id\":" + (update ? "5" : "null") + ",\"title\":\"Kit\",\"remark\":\"Note\",\"items\":[{\"itemId\":17,\"quantity\":2,\"unitPrice\":3,\"qualityData\":null},{\"itemId\":18,\"quantity\":1,\"unitPrice\":4,\"qualityData\":null}]}", listing);
        yield return new("listings", "listDelete", "DELETE", "sc/item-list/delete?id=5", """{"id":5}""", null, listing);
        yield return new("trade", "create", "POST", "sc/order-transactions/create",
            """{"orderNumber":"O1","number":2,"locationId":31,"deliveryMethod":1,"shippingFee":12.5}""",
            """{"orderNumber":"O1","number":2,"locationId":31,"deliveryMethod":1,"shippingFee":12.5}""", "marketplace.trade_rejected");
        yield return new("trade", "approve", "PUT", "sc/order-transactions/approve?transactionNumber=T1", "{}", null, "marketplace.trade_rejected");
        foreach (var (op, state) in new[] { ("ship", 2), ("receive", 3), ("cancel", 4) })
            yield return new("trade", op, "PUT", "sc/order-transactions/update-status", "{}",
                JsonSerializer.Serialize(new { transactionNumber = "T1", deliveryStatus = state }), "marketplace.trade_rejected");
        yield return new("trade", "review", "POST", "sc/order-reviews/create", """{"rating":4,"content":"Useful"}""",
            """{"transactionId":"T1","rating":4,"content":"Useful"}""", "marketplace.trade_rejected");
        yield return new("trade", "report", "POST", "trade/order-report/create", """{"reportType":2,"content":"Evidence"}""",
            """{"transactionNumber":"T1","reportType":2,"reportContent":"Evidence"}""", "marketplace.trade_rejected");
        // SPEC-GAP: SCM blacklist requires a trusted counterparty ID in this body; a blanket
        // ban on every member ID is incompatible with the implemented wire contract.
        yield return new("trade", "block", "POST", "member/user-blacklist/create", """{"blockedUserId":12345}""",
            """{"blockedUserId":909,"reason":"交易单中拉黑"}""", "marketplace.trade_rejected");
        const string trade = "marketplace.trade_rejected";
        yield return new("contracts", "create", "POST", "trade/contract/create",
            """{"contract":{"type":"SERVICE","title":"Haul","description":"Cargo","location":"Port","rewardType":"UEC","rewardUec":100,"slots":2,"minReputation":3,"requirements":"Ship","expireTime":4102444800000}}""",
            """{"contractType":"SERVICE","creatorType":0,"title":"Haul","description":"Cargo","locationDescription":"Port","rewardType":"UEC","rewardUec":100,"rewardDescription":null,"maxParticipants":2,"minReputation":3,"otherRequirements":"Ship","expireTime":4102444800000}""", trade);
        yield return new("contracts", "apply", "POST", "trade/contract/apply", """{"id":7,"message":"  Ready  "}""",
            """{"contractId":7,"applyMessage":"Ready","applyShips":[]}""", trade);
        foreach (var op in new[] { "quit", "start", "complete" })
            yield return new("contracts", op, "POST", "trade/contract/" + op + "?contractId=7", """{"id":7}""", null, trade);
        yield return new("contracts", "cancel", "POST", "trade/contract/cancel?contractId=7&reason=A%26B", """{"id":7,"reason":"A&B"}""", null, trade);
        yield return new("contracts", "review", "POST", "trade/contract/review", """{"participantId":8,"rating":5,"comment":"Good"}""",
            """{"participantId":8,"rating":5,"comment":"Good"}""", trade);
        yield return new("contracts", "dispute", "POST", "trade/contract/dispute/create?contractId=7&reason=A%26B&evidence=C%20D",
            """{"id":7,"reason":"A&B","evidence":"C D"}""", null, trade);
        // SPEC-GAP: these operations gate blocklist.write/profile.write, not trade.write.
        yield return new("records", "unblock", "DELETE", "member/user-blacklist/remove", "{}",
            """{"blockedUserId":909}""", "marketplace.trade_rejected", true);
        foreach (var op in new[] { "open", "openOrder" })
            yield return new("chat", op, "POST", "member/chat/conversations/create", """{"orderNumber":"O1"}""",
                """{"otherUserId":909}""", "marketplace.trade_rejected");
        yield return new("chat", "read", "PUT", "member/chat/conversations/31/mark-read", "{}", null, "marketplace.trade_rejected");
        yield return new("notices", "read", "PUT", "member/message/mark-read", """{"id":7}""", """{"id":7}""", trade, true);
        yield return new("notices", "readAll", "PUT", "member/message/mark-all-read?type=1", """{"type":1}""", null, trade, true);
        yield return new("profile", "write", "PUT", "member/user/update", """{"tradeStartTime":"18:00","tradeEndTime":"22:00"}""",
            """{"tradeTime":[1,1,1,1,1,1,1],"tradeStartTime":"18:00","tradeEndTime":"22:00","timezoneId":1,"userMobile":"fixture-contact"}""", "marketplace.trade_rejected");
    }

    internal static async Task Run()
    {
        var passed = 0;
        var failed = new List<string>();
        foreach (var c in Cases())
        foreach (var mode in new[] { "ok", "business", "business401", "business403", "http401", "http403", "network", "timeout", "noScope", "expiredNoScope", "scopeBody", "scopeHeader", "httpBusiness", "scopeDescription", "HTTP200-known", "HTTP403-known", "HTTP200-1002", "HTTP403-1002" }.Concat(EnvelopeModes()))
        {
            var label = $"{c.Area}.{c.Op}/{c.Variant ?? "default"}/{mode}";
            try { await Verify(c, mode); passed++; }
            catch (Exception e) { failed.Add(label); Console.WriteLine($"FAIL {label}: {e.GetType().Name}: {e.Message}"); }
        }
        // Ticket issuance shares the write envelope samples, but has its own 401 retry policy.
        foreach (var mode in EnvelopeModes().Concat(new[] { "html", "htmlScope", "scopeHeader" }))
        {
            var label = "chat.ws-ticket/" + mode;
            try { await VerifyTicketEnvelope(mode); passed++; }
            catch (Exception e) { failed.Add(label); Console.WriteLine($"FAIL {label}: {e.GetType().Name}: {e.Message}"); }
        }
        foreach (var mode in new[] { "ok", "reject", "network", "timeout", "noScope", "focus" })
        {
            try { await VerifySocket(mode); passed++; }
            catch (Exception e) { failed.Add("socket/" + mode); Console.WriteLine($"FAIL socket/{mode}: {e.Message}"); }
        }
        passed += await VerifyExpiredExtraEntrypoints();
        passed += await VerifyTicketConnectionRejections();
        Console.WriteLine($"Marketplace write matrix: passed={passed}, failed={failed.Count}");
        if (failed.Count != 0) throw new Exception("Marketplace write matrix failed: " + string.Join(", ", failed));
    }

    // A chat-send is a WebSocket frame, not an HTTP write; code envelopes/HTTP 401/403
    // do not exist at this boundary. REST conversation creation is in the matrix above.
    private static async Task VerifySocket(string mode)
    {
        var oldTimeout = ScmChatConnection.ReplyTimeout;
        ScmChatConnection.ReplyTimeout = TimeSpan.FromSeconds(2);
        try
        {
            var socket = new Socket(mode);
            await using var connection = new ScmChatConnection(new("wss://fixture.invalid/infra/ws/chat"),
                _ => Task.FromResult("synthetic"), () => socket, _ => { });
            var c = Cases().First();
            using var handler = new Handler(c, "ok");
            var uri = new Uri("https://fixture.invalid/");
            var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
            var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1),
                mode == "noScope" ? ["trade.read"] : ["trade.read", "trade.write"]);
            var reference = client.ChatPeerReference("fixture\nopaque", 909, 31);
            var input = BridgePayload.From(mode == "focus" ? (object)new { operation = "focus", @ref = reference }
                : new { operation = "send", @ref = reference, content = " Hello ", orderId = 7, clientMessageId = "cxt04-message" });
            var requestedConnection = 0;
            try
            {
                var result = await client.MarketplaceChatAsync(session, input, () => true, () => { requestedConnection++; return connection; }, default);
                var data = BridgePayload.From(result.Data);
                Check(mode is not ("noScope" or "network"), "socket failure cannot succeed");
                if (mode == "focus") Check(data.GetProperty("focused").GetBoolean(), "focus result");
                else Check(data.GetProperty("status").GetString() == (mode == "ok" ? "sent" : mode == "reject" ? "rejected" : "uncertain"), "socket result");
            }
            catch (AccountBridgeHostException e) when (mode == "noScope")
            { Check(e.Code == "marketplace.reauthorize_required", "socket scope rejection"); }
            catch (HttpRequestException) when (mode == "network") { }
            Check(handler.Calls == 0, "send/focus must not create REST requests");
            Check(socket.Writes == (mode is "noScope" or "focus" ? 0 : 1), "one send frame; never replayed");
            if (mode == "noScope") Check(requestedConnection == 0, "scope denied before requesting connection");
            if (mode == "focus") Check(socket.Focused, "subscribe trusted peer");
        }
        finally { ScmChatConnection.ReplyTimeout = oldTimeout; }
    }

    private sealed class Socket(string mode) : IScmChatTransport
    {
        private readonly Channel<string> replies = Channel.CreateUnbounded<string>();
        internal int Writes;
        internal bool Focused;
        public Task ConnectAsync(Uri endpoint, CancellationToken token)
        { Check(endpoint.Host == "fixture.invalid" && endpoint.AbsolutePath == "/infra/ws/chat", "fake socket route"); return Task.CompletedTask; }
        public Task SendAsync(string text, CancellationToken token)
        {
            var frame = JsonNode.Parse(text)!;
            var body = JsonNode.Parse(frame["content"]!.GetValue<string>())!;
            if (frame["type"]!.GetValue<string>() == "chat-subscribe")
            {
                if (body["otherUserId"] is not null)
                { Check(body["otherUserId"]!.GetValue<long>() == 909, "trusted subscribe peer"); Focused = true; }
                return Task.CompletedTask;
            }
            Check(frame["type"]!.GetValue<string>() == "chat-send", "unexpected socket frame");
            Writes++;
            // The recipient is an explicit SCM-required field, never the viewer's identity.
            Check(JsonNode.DeepEquals(body, JsonNode.Parse("""{"clientMessageId":"cxt04-message","toUserId":909,"content":"Hello","quoteType":"order","quoteId":"7"}""")), "socket exact body whitelist");
            if (mode == "network") throw new HttpRequestException("synthetic socket failure");
            if (mode != "timeout") replies.Writer.TryWrite(JsonSerializer.Serialize(new
            {
                type = "chat-send-result", content = JsonSerializer.Serialize(new
                {
                    clientMessageId = "cxt04-message", success = mode == "ok", error = "synthetic refusal",
                    message = new { id = 19, fromUserId = 808, toUserId = 909, content = "Hello" },
                }),
            }));
            return Task.CompletedTask;
        }
        public async Task<string?> ReceiveAsync(CancellationToken token) => await replies.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    private static async Task Verify(Case c, string mode)
    {
        using var handler = new Handler(c, mode);
        var http = new ScmHttpClient(handler);
        var uri = new Uri("https://fixture.invalid/");
        var vault = new Vault();
        var client = new OAuthPkceClient(http, vault, new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"));
        string[] scopes = ["profile.read", "profile.write", "trade.read", "trade.write", "checklist.write", "blocklist.write"];
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(mode == "expiredNoScope" ? -1 : 1),
            mode == "expiredNoScope" ? scopes.Where(s => s != (c.Area == "notices" ? "profile.write" : c.Area == "records" ? "blocklist.write" : "trade.write")).ToArray() :
            mode == "noScope" ? scopes.Where(s => s != "trade.write").ToArray() : scopes);
        var input = JsonNode.Parse(c.Input)!.AsObject();
        input["schemaVersion"] = 1;
        if (c.Area != "profile") input["operation"] = c.Op;
        if (c.Area == "trade" && c.Op != "create") input["transactionNumber"] = "T1";
        if (c.Area == "records") input["ref"] = client.BlockReference("fixture\nopaque", 909);
        if (c.Area == "chat" && c.Op != "openOrder") input["ref"] = client.ChatPeerReference("fixture\nopaque", 909, 31);
        // Inject untrusted identity fields where the contract tolerates extra fields. Exact
        // recursive body comparison below proves they do not cross the SCM boundary.
        if (c.Area is "trade" or "listings")
        {
            input["memberId"] = 12345;
            input["accessToken"] = "must-not-forward";
        }
        var host = DispatchProxy.Create<IAccountBridgeHost, WriterHost>();
        var proxy = (WriterHost)(object)host;
        proxy.Call = async () =>
        {
            var payload = BridgePayload.From(input);
            var result = c.Area switch
            {
                "listings" => await client.MarketplaceListingsAsync(session, payload, () => true, default),
                "trade" => await client.MarketplaceTradeAsync(session, payload, () => true, default),
                "contracts" => await client.MarketplaceContractsAsync(session, payload, () => true, default),
                "records" => await client.MarketplaceRecordsAsync(session, payload, () => true, default),
                "chat" => await client.MarketplaceChatAsync(session, payload, () => true, () => throw new Exception("Unexpected socket"), default),
                "notices" => await client.MarketplaceNoticesAsync(session, payload, () => true, default),
                _ => await client.TradeProfileAsync(session, true, BridgePayload.From(JsonNode.Parse(c.Input)), () => true, default),
            };
            if (client.LastTradeWindowSync is { } sync) await sync;
            return new { schemaVersion = 1, data = result.Data };
        };
        if (mode == "expiredNoScope")
            host = new ScmAccountBridgeHost(client, new ScmProfileCacheStore(Path.Combine(Environment.CurrentDirectory, ".cxt11-patch", "test-cache")), "scm", () => null, session, 1);
        using var runtime = new AccountBridgeRuntime(host);
        var name = c.Area == "profile" ? "tradeProfile.write" : "marketplace." + c.Area;
        var requestBody = c.Area == "profile" ? BridgePayload.From(new { schemaVersion = 1, changes = JsonNode.Parse(c.Input) }) : BridgePayload.From(input);
        var response = (await runtime.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, requestBody, WriterHost.Owner))).Response;
        if (mode == "expiredNoScope" || mode == "noScope" && !c.UsesDedicatedScope)
        {
            Check(response.Error?.Code == "marketplace.reauthorize_required", "missing scope bridge error");
            Check(handler.Calls == 0, "missing scope must reject before any HTTP request");
            Check(vault.Reads == 0 && vault.Writes == 0, "missing scope must not access vault");
            return;
        }
        Check(handler.Writes == 1, "exactly one write including failures; no replay");
        if (mode == "ok" || mode == "noScope" || mode.EndsWith("-zero", StringComparison.Ordinal))
        {
            Check(response.Status == "ok", "success bridge response: " + response.Error?.Code);
            return;
        }
        if (c.Area == "profile" && mode is "network" or "timeout")
        {
            Check(response.Status == "ok", "profile uncertain result envelope");
            var data = response.Payload.GetProperty("data");
            Check(!data.GetProperty("confirmed").GetBoolean() && data.GetProperty("requiresReview").GetBoolean(), "uncertain cannot be confirmed");
            return;
        }
        if (c.Area == "profile" && mode == "http401") Check(handler.Calls == 2, "401 stops after preflight and one PUT; no replay or read-back");
        Check(response.Status != "ok", "failure cannot return success");
        if (mode == "timeout") { Check(response.Status == "cancelled", "timeout cancelled response"); return; }
        var expected = mode switch
        {
            "business" or "HTTP200-1002" or "HTTP403-1002" => c.Rejection,
            "HTTP200-known" or "HTTP403-known" => "marketplace.not_owner",
            "http401" or "business401" => "marketplace.sign_in_required",
            // Only explicit OAuth insufficient_scope asks for reauthorization; generic 403 is forbidden.
            "business403" => "marketplace.forbidden",
            "http403" or "scopeDescription" => "marketplace.unavailable",
            "scopeBody" or "scopeHeader" => "marketplace.reauthorize_required",
            "httpBusiness" => "marketplace.not_owner",
            _ => "marketplace.unavailable",
        };
        if (mode.StartsWith("envelope-", StringComparison.Ordinal)) expected = EnvelopeCase(c, mode).Expected;
        Check(response.Error?.Code == expected, $"bridge error expected {expected}, got {response.Error?.Code}");
    }

    public class WriterHost : DispatchProxy
    {
        internal static readonly BridgeAccountContext Owner = new("scm", "fixture", "opaque");
        internal Func<Task<object>> Call = null!;
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch
        {
            "get_Generation" => 1L,
            "get_CurrentContext" => Owner,
            "get_SupportsConcurrentReads" => false,
            "add_AccountChanged" or "remove_AccountChanged" or "Dispose" => null,
            "MarketplaceListingsAsync" or "MarketplaceTradeAsync" or "MarketplaceContractsAsync" or "MarketplaceRecordsAsync"
                or "MarketplaceChatAsync" or "MarketplaceNoticesAsync" or "TradeProfileAsync" => Call(),
            _ => throw new Exception("Unexpected host call: " + method.Name),
        };
    }

    private sealed class Handler(Case c, string mode) : HttpMessageHandler
    {
        internal int Calls, Writes;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Check(request.RequestUri!.Host == "fixture.invalid", "only fake authority allowed");
            Calls++;
            var path = request.RequestUri.PathAndQuery;
            // Background copy is not an SCM write; still intercept and whitelist it.
            if (c.Area == "profile" && path.EndsWith("/trade-window", StringComparison.Ordinal))
            {
                Check(request.Method == HttpMethod.Put, "window sync PUT");
                var body = JsonNode.Parse(await request.Content!.ReadAsStringAsync(token))!.AsObject();
                Check(body.All(p => new[] { "schemaVersion", "days", "start", "end", "timezoneId" }.Contains(p.Key)), "window sync privacy");
                return new(HttpStatusCode.NoContent);
            }
            if (request.Method == HttpMethod.Get)
            {
                object data = path switch
                {
                    "/app-api/sc/order-transactions/check-ongoing?orderNumber=O1" => false,
                    "/app-api/sc/order-transactions/get?transactionNumber=T1" => new
                    {
                        actorRole = c.Op is "approve" or "receive" ? "buyer" : "seller",
                        creatorType = c.Op == "approve" ? 0 : 1,
                        deliveryStatus = c.Op == "approve" ? 0 : c.Op == "receive" ? 2 : c.Op is "review" or "report" ? 3 : 1,
                        transactionStatus = c.Op is "review" or "report" ? 2 : 1,
                        tradingerId = 909, orderOwnerId = 808,
                    },
                    "/app-api/sc/orders/get?orderNumber=O1&language=CN" => new { displayType = 1 },
                    "/app-api/sc/orders/get?orderNumber=O1" => new { orderOwnerId = 909 },
                    "/app-api/member/user/get" => new { id = 12345, email = "must-not-forward", tradeTime = "[1,1,1,1,1,1,1]",
                        tradeStartTime = "18:00", tradeEndTime = "22:00", timezoneId = 1, userMobile = "fixture-contact" },
                    _ => throw new Exception("Unexpected preflight route"),
                };
                return Reply(data);
            }
            Writes++;
            Check(request.Method.Method == c.Method && path == "/app-api/" + c.Route, "write method/route/query mismatch");
            var actual = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            Check(c.Body is null ? actual is null : actual is not null && JsonNode.DeepEquals(JsonNode.Parse(c.Body), JsonNode.Parse(actual)), "exact recursive body whitelist/values");
            if (mode.StartsWith("envelope-", StringComparison.Ordinal))
            {
                var sample = EnvelopeCase(c, mode);
                return new(mode.StartsWith("envelope-200-", StringComparison.Ordinal) ? HttpStatusCode.OK : HttpStatusCode.Forbidden)
                { Content = new StringContent(sample.Body) };
            }
            if (mode.StartsWith("HTTP", StringComparison.Ordinal))
                return new(mode.StartsWith("HTTP200", StringComparison.Ordinal) ? HttpStatusCode.OK : HttpStatusCode.Forbidden)
                { Content = new StringContent(mode.EndsWith("known", StringComparison.Ordinal) ? "{\"code\":1011009001}" : "{\"code\":1002}") };
            if (mode == "network") throw new HttpRequestException("synthetic transport failure");
            if (mode == "timeout") throw new TaskCanceledException("synthetic transport timeout");
            if (mode is "scopeBody" or "scopeHeader" or "httpBusiness" or "scopeDescription")
            {
                var denied = new HttpResponseMessage(HttpStatusCode.Forbidden)
                { Content = new StringContent(mode == "scopeBody" ? "{\"error\":\"insufficient_scope\"}"
                    : mode == "httpBusiness" ? "{\"code\":1011009001}" : "{}") };
                if (mode == "scopeHeader") denied.Headers.WwwAuthenticate.ParseAdd("Bearer error=\"insufficient_scope\"");
                if (mode == "scopeDescription") denied.Headers.WwwAuthenticate.ParseAdd("Bearer error_description=\"insufficient_scope\"");
                return denied;
            }
            if (mode is "http401" or "http403") return new(mode == "http401" ? HttpStatusCode.Unauthorized : HttpStatusCode.Forbidden)
                { Content = new StringContent("{}") };
            var code = mode == "business" ? 123456 : mode == "business401" ? 401 : mode == "business403" ? 403 : 0;
            object result = c.Area == "trade" && c.Op == "create" ? "T1"
                : c.Area == "contracts" ? 19L
                : c.Area == "chat" && c.Op is "open" or "openOrder" ? new { id = 31, otherUserId = 909 }
                : true;
            return Reply(result, code);
        }
        private static HttpResponseMessage Reply(object data, int code = 0) => new(HttpStatusCode.OK)
        { Content = new StringContent(JsonSerializer.Serialize(new { code, data })) };
    }

    private static void Check(bool condition, string label)
    { if (!condition) throw new Exception(label); }

    private sealed class Vault : ITokenVault
    {
        internal int Reads, Writes;
        public string? LoadActiveAccountKey() { Reads++; throw new Exception("Unexpected vault read"); }
        public string? LoadRefreshToken(string key) { Reads++; throw new Exception("Unexpected vault read"); }
        public void SaveRefreshToken(string key, string token) { Writes++; throw new Exception("Unexpected vault write"); }
        public void DeleteRefreshToken(string key) { Writes++; throw new Exception("Unexpected vault write"); }
    }
}
