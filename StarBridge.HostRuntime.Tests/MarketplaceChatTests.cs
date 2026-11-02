using System.Net;
using System.Reflection;
using StarBridge.HostRuntime;
using System.Text.Json;
using System.Threading.Channels;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

// 0.7.2 G9: SCM trade messages. Full handles like the SCM site, no SCM member ids or avatars,
// quote snapshots whitelisted, sends go once over the chat socket and are never replayed.
internal static class MarketplaceChatTests
{
    private static void Check(bool condition, string message)
    {
        if (!condition) throw new Exception("FAIL " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal bool ProfileFails;
        internal readonly List<(string Method, string PathAndQuery, string? Body)> Requests = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var body = request.Content is null ? null : await request.Content.ReadAsStringAsync(token);
            var path = request.RequestUri!.PathAndQuery;
            lock (Requests) Requests.Add((request.Method.Method, path, body));
            if (path == "/app-api/member/user/get" && ProfileFails)
                return new HttpResponseMessage(HttpStatusCode.ServiceUnavailable);
            var snapshot = JsonSerializer.Serialize(new { type = "order", orderId = 88, orderNo = "SO88", itemName = "Aurora", amount = 1200000, buyerId = 4242000000000042, sellerId = 9090000000000009, senderId = 9090000000000009, buyerNickname = "Self", mainImage = "https://cdn/x.png" });
            object data = request.RequestUri.AbsolutePath switch
            {
                "/app-api/member/user/get" => new { id = 4242000000000042 },
                "/app-api/sc/order-reviews/page" => new { list = Array.Empty<object>(), total = 0 },
                "/app-api/member/chat/conversations/list" => new object[] {
                    new { id = 31, otherUserId = 9090000000000009, otherUserNickname = "Trader_Long_Handle_9000", otherUserAvatar = "https://cdn/a.png", otherUserSignInStatus = 1,
                          lastMessageContent = "还在吗", lastMessageTime = 1760000000000, unreadCount = 2, isBlockedByOther = false, hasBlockedOther = true,
                          otherUserHasBanHistory = true, otherUserBanCount = 1, otherUserBanActive = false, otherUserLastBanReason = "刷单" } },
                "/app-api/member/user-blacklist/remove" => true,
                "/app-api/member/chat/unread/count" => 2,
                "/app-api/member/chat/messages/history" => new object[] {
                    new { id = 501, fromUserId = 9090000000000009, toUserId = 4242000000000042, content = "看下这个", quoteType = "order", quoteId = "88", quoteSnapshot = snapshot, hasRiskyLink = 0, isRead = 1, createTime = 1760000000001 },
                    new { id = 502, fromUserId = 4242000000000042, toUserId = 9090000000000009, content = "好", hasRiskyLink = 1, isRead = 0, createTime = 1760000000002 } },
                "/app-api/member/chat/conversations/31/mark-read" => true,
                "/app-api/member/chat/ws-ticket" => "ticket-1",
                "/app-api/sc/orders/get" => new { orderNumber = "SO88", orderOwnerId = 9090000000000009, creatorId = 1 },
                "/app-api/member/chat/conversations/create" => new { id = 31, otherUserId = 9090000000000009, otherUserNickname = "Trader_Long_Handle_9000", otherUserSignInStatus = 1 },
                _ => throw new Exception("Unexpected route " + path),
            };
            return new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) };
        }
    }

    private sealed class Refusing(bool httpForbidden) : HttpMessageHandler
    {
        internal int Tickets;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.RequestUri!.AbsolutePath == "/app-api/member/user/get")
                return Task.FromResult(new HttpResponseMessage(HttpStatusCode.ServiceUnavailable));
            Interlocked.Increment(ref Tickets);
            return Task.FromResult(httpForbidden
                ? new HttpResponseMessage(HttpStatusCode.Forbidden)
                : new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent("{\"code\":403,\"msg\":\"没有该操作权限\"}") });
        }
    }

    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) { }
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class Socket : IScmChatTransport
    {
        internal static readonly List<string> Sent = [];
        internal static readonly List<Uri> Connected = [];
        internal static string Reply = "accept";
        private readonly Channel<string?> _inbox = Channel.CreateUnbounded<string?>();
        internal static Socket? Live;
        public Task ConnectAsync(Uri endpoint, CancellationToken token) { lock (Sent) Connected.Add(endpoint); Live = this; return Task.CompletedTask; }
        public Task SendAsync(string text, CancellationToken token)
        {
            lock (Sent) Sent.Add(text);
            using var frame = JsonDocument.Parse(text);
            if (frame.RootElement.GetProperty("type").GetString() != "chat-send") return Task.CompletedTask;
            using var content = JsonDocument.Parse(frame.RootElement.GetProperty("content").GetString()!);
            var id = content.RootElement.GetProperty("clientMessageId").GetString();
            object? result = Reply switch
            {
                "accept" => new { success = true, clientMessageId = id, message = new { id = 600, fromUserId = 4242000000000042, toUserId = 9090000000000009, content = "成交", createTime = 1760000000003 } },
                "reject" => new { success = false, clientMessageId = id, error = "对方已将你拉黑" },
                _ => null,
            };
            if (result is not null)
                _inbox.Writer.TryWrite(JsonSerializer.Serialize(new { type = "chat-send-result", content = JsonSerializer.Serialize(result) }));
            return Task.CompletedTask;
        }
        internal void Push(string frame) => _inbox.Writer.TryWrite(frame);
        public async Task<string?> ReceiveAsync(CancellationToken token) => await _inbox.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() => ValueTask.CompletedTask;
    }

    public class OfflineHost : DispatchProxy
    {
        internal static readonly BridgeAccountContext Owner = new("scm", "fixture", "opaque");
        protected override object? Invoke(MethodInfo? method, object?[]? args) => method!.Name switch
        {
            "get_Generation" => 1L,
            "get_CurrentContext" => Owner,
            "get_SupportsConcurrentReads" => false,
            "add_AccountChanged" or "remove_AccountChanged" or "Dispose" => null,
            _ => throw new Exception("Offline request reached host: " + method.Name),
        };
    }

    private static async Task VerifyOffline()
    {
        using var runtime = new AccountBridgeRuntime(DispatchProxy.Create<IAccountBridgeHost, OfflineHost>());
        var response = (await runtime.DispatchAsync(BridgeEnvelope.Request("marketplace.chat", "offline-chat", 1,
            new { schemaVersion = 1, operation = "openScm", @ref = new string('a', 32) }, OfflineHost.Owner))).Response;
        Check(response.Error?.Code == "marketplace.offline", "closed device network gate rejects openScm before host/browser work");
    }

    internal static async Task Run()
    {
        await VerifyOffline();
        var openedUris = new List<Uri>();
        var handler = new Handler();
        var uri = new Uri("https://fixture.invalid/");
        var client = new OAuthPkceClient(new ScmHttpClient(handler), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"))
        {
            ChatTransport = () => new Socket(),
            OpenScmBrowser = openedUris.Add,
        };
        ScmChatConnection.ReplyTimeout = TimeSpan.FromMilliseconds(400);
        var session = new ScmOAuthSession("fixture", "opaque", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1),
            ["profile.read", "trade.read", "trade.write", "blocklist.write"]);
        var pushes = new List<JsonElement>();
        ScmChatConnection Connection() => client.StartChat(OAuthPkceClient.ChatOwner(session),
            async t => (await client.IssueChatTicketAsync(session, t)).Ticket,
            payload => { lock (pushes) pushes.Add(BridgePayload.From(payload)); });
        async Task<JsonElement> Pushed(string kind, Func<JsonElement, bool>? match = null)
        {
            for (var i = 0; i < 100; i++)
            {
                lock (pushes)
                    foreach (var p in pushes)
                        if (p.GetProperty("kind").GetString() == kind && (match is null || match(p))) return p;
                await Task.Delay(10);
            }
            throw new Exception("FAIL no " + kind + " push");
        }
        async Task<JsonElement> Call(object input, ScmOAuthSession? as_ = null) =>
            BridgePayload.From((await client.MarketplaceChatAsync(as_ ?? session, BridgePayload.From(input), () => true,
                Connection, default)).Data);

        try
        {
            var list = await Call(new { schemaVersion = 1, operation = "conversations" });
            var row = list.GetProperty("rows")[0];
            var text = row.GetRawText();
            Check(row.GetProperty("name").GetString() == "Trader_Long_Handle_9000", "full handle, as on the SCM site");
            Check(!text.Contains("9090000000000009") && !text.Contains("cdn/a.png") && !text.Contains("otherUserId"), "no member id or avatar");
            Check(row.GetProperty("blockedByMe").GetBoolean() && !row.GetProperty("blockedMe").GetBoolean(), "block direction mapped from SCM fields");
            Check(row.GetProperty("unread").GetInt32() == 2 && row.GetProperty("banHistory").GetBoolean(), "unread and ban history kept");
            var reference = row.GetProperty("ref").GetString()!;
            Check(reference.Length == 32, "opaque peer reference");

            var browserResult = await Call(new { schemaVersion = 1, operation = "openScm", @ref = reference });
            Check(openedUris.Count == 1 && openedUris[0].AbsolutePath == "/message" && openedUris[0].Query == "?userId=9090000000000009" &&
                  openedUris[0].GetLeftPart(UriPartial.Authority) == StarBridge.HostRuntime.Support.HelpSupportBridgeDispatcher.ScmWebsiteRoot.GetLeftPart(UriPartial.Authority),
                "SCM browser targets the peer conversation on the shared website root");
            Check(browserResult.GetRawText() == "{\"confirmed\":true}", "browser result carries only confirmation, no member id");
            var blockRef = row.GetProperty("blockRef").GetString()!;
            Check(blockRef == client.BlockReference(OAuthPkceClient.ChatOwner(session), 9090000000000009), "conversation uses records block reference space");
            var unblocked = await client.MarketplaceRecordsAsync(session,
                BridgePayload.From(new { schemaVersion = 1, operation = "unblock", @ref = blockRef }), () => true, default);
            var removal = handler.Requests.Single(r => r.Method == "DELETE");
            using (var body = JsonDocument.Parse(removal.Body!))
                Check(removal.PathAndQuery == "/app-api/member/user-blacklist/remove" && body.RootElement.GetProperty("blockedUserId").GetInt64() == 9090000000000009 &&
                      BridgePayload.From(unblocked.Data).GetProperty("confirmed").GetBoolean(), "conversation block reference unblocks the correct peer");
            foreach (var invalid in new[] { new string('0', 32), new OAuthPkceClient(new ScmHttpClient(new Handler()), new Vault(),
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback")).ChatPeerReference(OAuthPkceClient.ChatOwner(session), 9090000000000009) })
            {
                try { await Call(new { schemaVersion = 1, operation = "openScm", @ref = invalid }); throw new Exception("FAIL stale chat reference opened"); }
                catch (AccountBridgeHostException e) when (e.Code == "marketplace.state_changed") { }
            }
            try { await Call(new { schemaVersion = 1, operation = "openScm", @ref = reference }, session with { Capabilities = ["trade.write"] }); throw new Exception("FAIL openScm without trade.read"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
            await Call(new { schemaVersion = 1, operation = "openScm", @ref = reference }, session with { Capabilities = ["trade.read"] });
            Check(openedUris.Count == 2, "trade.read alone opens SCM; invalid references and missing scope do not open browser");

            var history = await Call(new { schemaVersion = 1, operation = "history", @ref = reference, before = 999 });
            Check(handler.Requests.Any(r => r.PathAndQuery == "/app-api/member/chat/messages/history?otherUserId=9090000000000009&pageSize=20&lastMessageId=999"),
                "history maps the reference to the SCM id inside the Host");
            var first = history.GetProperty("rows")[0];
            var second = history.GetProperty("rows")[1];
            Check(!first.GetProperty("mine").GetBoolean() && second.GetProperty("mine").GetBoolean(), "mine decided from the peer");
            Check(second.GetProperty("risky").GetBoolean(), "risky link flag kept");
            var quote = first.GetProperty("quote");
            Check(quote.GetProperty("orderNo").GetString() == "SO88" && quote.GetProperty("itemName").GetString() == "Aurora", "order quote projected");
            var historyText = history.GetRawText();
            Check(!historyText.Contains("4242000000000042") && !historyText.Contains("9090000000000009") && !historyText.Contains("cdn/x.png") && !historyText.Contains("Self"),
                "no sender/buyer/seller ids, names or images from the snapshot");

            // 订单详情「联系卖家」: the Host finds the seller; the client only ever sees the reference.
            var opened = await Call(new { schemaVersion = 1, operation = "openOrder", orderNumber = "SO88" });
            Check(opened.GetProperty("ref").GetString() == reference && handler.Requests.Any(r => r.PathAndQuery == "/app-api/sc/orders/get?orderNumber=SO88") &&
                  handler.Requests.Single(r => r.PathAndQuery == "/app-api/member/chat/conversations/create").Body!.Contains("9090000000000009") && !opened.GetRawText().Contains("9090000000000009"),
                "contact the seller by order number, same opaque reference");
            // 交易单「私信对方」: the trade projection carries the counterparty's reference.
            using var trade = JsonDocument.Parse("""{"creatorType":0,"actorRole":"seller","orderOwnerId":9090000000000009,"tradingerId":4242000000000042}""");
            var projected = BridgePayload.From(StarBridge.HostRuntime.Marketplace.MarketplaceTradePolicy.Project(trade.RootElement,
                member => client.ChatPeerReference(OAuthPkceClient.ChatOwner(session), member)));
            Check(projected.GetProperty("counterpartyChat").GetString() == reference, "trade counterparty reference matches the conversation");

            Check(!opened.GetProperty("blockedByMe").GetBoolean() && !opened.TryGetProperty("blockRef", out _), "unblocked conversation omits blockRef entirely");

            var read = await Call(new { schemaVersion = 1, operation = "read", @ref = reference });
            Check(read.GetProperty("confirmed").GetBoolean() && handler.Requests.Any(r => r.Method == "PUT"), "mark read by conversation");

            foreach (var invalidId in new object?[] { null, 123, "", "short", "invalid_id-123", new string('a', 65) })
            {
                int before; lock (Socket.Sent) before = Socket.Sent.Count;
                try
                {
                    await Call(JsonSerializer.SerializeToElement(new { schemaVersion = 1, operation = "send", @ref = reference, content = "hello", clientMessageId = invalidId }));
                    throw new Exception("FAIL invalid bridge id accepted");
                }
                catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
                lock (Socket.Sent) Check(Socket.Sent.Count == before, "invalid bridge id sent a frame");
            }
            var sent = await Call(new { schemaVersion = 1, operation = "send", @ref = reference, content = "  成交  ", orderId = 88, clientMessageId = "bridge-stable-001" });
            Check(sent.GetProperty("status").GetString() == "sent" && sent.GetProperty("message").GetProperty("mine").GetBoolean(), "send confirmed by SCM");
            Check(Socket.Connected.Single().Query == "?ticket=ticket-1" && Socket.Connected.Single().AbsolutePath == "/infra/ws/chat", "chat socket uses a one-time ticket");
            string[] frames;
            lock (Socket.Sent) frames = [.. Socket.Sent];
            Check(frames[0].Contains("chat-subscribe"), "subscribes before sending");
            static JsonElement Content(string frame) =>
                JsonDocument.Parse(JsonDocument.Parse(frame).RootElement.GetProperty("content").GetString()!).RootElement.Clone();
            var send = Content(frames.Single(f => f.Contains("chat-send")));
            Check(send.GetProperty("clientMessageId").GetString() == "bridge-stable-001", "bridge retains client id");
            Check(send.GetProperty("toUserId").GetInt64() == 9090000000000009, "send carries the SCM id only on the wire");
            Check(send.GetProperty("content").GetString() == "成交" && send.GetProperty("quoteType").GetString() == "order" &&
                  send.GetProperty("quoteId").GetString() == "88", "trimmed content with order quote");

            Socket.Reply = "reject";
            var rejected = await Call(new { schemaVersion = 1, operation = "send", @ref = reference, content = "再问一次" });
            Check(rejected.GetProperty("status").GetString() == "rejected" && rejected.GetProperty("reason").GetString() == "对方已将你拉黑", "SCM refusal shown");
            Socket.Reply = "silent";
            var uncertain = await Call(new { schemaVersion = 1, operation = "send", @ref = reference, content = "在吗" });
            lock (Socket.Sent) frames = [.. Socket.Sent];
            Check(uncertain.GetProperty("status").GetString() == "uncertain" && frames.Count(f => f.Contains("chat-send") && Content(f).GetProperty("content").GetString() == "在吗") == 1,
                "no answer is uncertain and never resent");

            await Pushed("resync");
            var sentPush = await Pushed("message", p => p.GetProperty("message").GetProperty("id").GetInt32() == 600);
            Check(sentPush.GetProperty("ref").GetString() == reference && sentPush.GetProperty("message").GetProperty("mine").GetBoolean(),
                "own send pushed as a message of the same conversation");
            Socket.Live!.Push(JsonSerializer.Serialize(new { type = "new-chat-message", content = JsonSerializer.Serialize(
                new { id = 700, fromUserId = 9090000000000009, toUserId = 4242000000000042, fromUserNickname = "Trader_Long_Handle_9000", fromUserAvatar = "https://cdn/a.png", content = "到了", createTime = 1760000000009 }) }));
            var incoming = await Pushed("message", p => p.GetProperty("message").GetProperty("id").GetInt32() == 700);
            Check(incoming.GetProperty("ref").GetString() == reference && incoming.GetProperty("name").GetString() == "Trader_Long_Handle_9000" &&
                  incoming.GetProperty("message").GetProperty("content").GetString() == "到了" && !incoming.GetProperty("message").GetProperty("mine").GetBoolean(),
                "incoming push carries the message itself, full handle, same reference");
            Socket.Live!.Push(JsonSerializer.Serialize(new { type = "chat-message-echo", content = JsonSerializer.Serialize(
                new { id = 701, fromUserId = 4242000000000042, toUserId = 9090000000000009, content = "网站上发的", createTime = 1760000000010 }) }));
            var echo = await Pushed("message", p => p.GetProperty("message").GetProperty("id").GetInt32() == 701);
            Check(echo.GetProperty("ref").GetString() == reference && echo.GetProperty("message").GetProperty("mine").GetBoolean(), "own message from another device");
            Check(!echo.TryGetProperty("name", out _), "legacy echo omits name");
            Socket.Live!.Push(JsonSerializer.Serialize(new { type = "new-chat-message", content = JsonSerializer.Serialize(
                new { id = 702, fromUserId = 4242000000000042, toUserId = 9090000000000009, fromUserNickname = "Self", content = "Elsewhere", createTime = 1760000000011 }) }));
            var selfPush = await Pushed("message", p => p.GetProperty("message").GetProperty("id").GetInt32() == 702);
            Check(selfPush.GetProperty("ref").GetString() == reference && selfPush.GetProperty("message").GetProperty("mine").GetBoolean() &&
                  !selfPush.TryGetProperty("name", out _), "new-chat-message from self is an echo without name");
            Socket.Live!.Push(JsonSerializer.Serialize(new { type = "chat-unread-count", content = "5" }));
            Check((await Pushed("unread")).GetProperty("count").GetInt64() == 5, "unread count pushed as a number");
            string allPushes;
            lock (pushes) allPushes = string.Join("", pushes.Select(p => p.GetRawText()));
            Check(!allPushes.Contains("9090000000000009") && !allPushes.Contains("4242000000000042") && !allPushes.Contains("cdn/"), "pushes carry no member ids or avatars");

            await Call(new { schemaVersion = 1, operation = "focus", @ref = reference });
            lock (Socket.Sent) Check(Content(Socket.Sent[^1]).GetProperty("otherUserId").GetInt64() == 9090000000000009, "focus subscribes to the open conversation");

            foreach (var bad in new object[] {
                new { schemaVersion = 1, operation = "send", @ref = reference, content = new string('字', 151) },
                new { schemaVersion = 1, operation = "send", @ref = reference, content = "   " },
                new { schemaVersion = 1, operation = "history", @ref = reference, otherUserId = 9090000000000009 },
                new { schemaVersion = 1, operation = "delete", @ref = reference },
            })
            {
                try { await Call(bad); throw new Exception("FAIL invalid chat request accepted"); }
                catch (AccountBridgeHostException e) when (e.Code == "marketplace.invalid_request") { }
            }
            try { await Call(new { schemaVersion = 1, operation = "history", @ref = new string('0', 32) }); throw new Exception("FAIL unknown peer"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.state_changed") { }
            var readOnly = session with { Capabilities = ["profile.read", "trade.read"] };
            await Call(new { schemaVersion = 1, operation = "unread" }, readOnly);
            try { await Call(new { schemaVersion = 1, operation = "send", @ref = reference, content = "x" }, readOnly); throw new Exception("FAIL send without trade.write"); }
            catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
            // SCM issues the ticket only for trade.read + trade.write: ask again before any request.
            var tickets = handler.Requests.Count(r => r.PathAndQuery.EndsWith("member/chat/ws-ticket", StringComparison.Ordinal));
            foreach (var scopes in new[] { new[] { "profile.read", "trade.write" }, new[] { "profile.read", "trade.read" } })
            {
                try { await client.IssueChatTicketAsync(session with { Capabilities = scopes }, default); throw new Exception("FAIL ticket without both trade scopes"); }
                catch (AccountBridgeHostException e) when (e.Code == "marketplace.reauthorize_required") { }
            }
            Check(handler.Requests.Count(r => r.PathAndQuery.EndsWith("member/chat/ws-ticket", StringComparison.Ordinal)) == tickets,
                "a ticket without both trade scopes is never requested");
            Check(handler.Requests.Count(r => r.PathAndQuery == "/app-api/member/user/get") == 1 &&
                  handler.Requests.FindIndex(r => r.PathAndQuery == "/app-api/member/user/get") <
                  handler.Requests.FindIndex(r => r.PathAndQuery == "/app-api/member/chat/ws-ticket"), "self profile read once before first ticket");
            await client.StopChatAsync();
            await Connection().FocusAsync(null, default);
            Check(handler.Requests.Count(r => r.PathAndQuery == "/app-api/member/user/get") == 1 &&
                  handler.Requests.Count(r => r.PathAndQuery == "/app-api/member/chat/ws-ticket") == tickets + 1,
                "second connection reuses self member cache");
            await client.MarketplaceRecordsAsync(session, BridgePayload.From(new { operation = "reviews" }), () => true, default);
            Check(handler.Requests.Count(r => r.PathAndQuery == "/app-api/member/user/get") == 1,
                "reviews reuse the same self member cache as chat");
        }
        finally { await client.StopChatAsync(); }

        foreach (var profileScope in new[] { true, false })
        {
            var fallbackHandler = new Handler { ProfileFails = true };
            var fallback = new OAuthPkceClient(new ScmHttpClient(fallbackHandler), new Vault(),
                new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback")) { ChatTransport = () => new Socket() };
            var fallbackSession = session with { Capabilities = profileScope ? ["profile.read", "trade.read", "trade.write"] : ["trade.read", "trade.write"] };
            var received = new TaskCompletionSource<JsonElement>(TaskCreationOptions.RunContinuationsAsynchronously);
            try
            {
                var connection = fallback.StartChat(OAuthPkceClient.ChatOwner(fallbackSession),
                    async t => (await fallback.IssueChatTicketAsync(fallbackSession, t)).Ticket, payload =>
                    {
                        var p = BridgePayload.From(payload);
                        if (p.GetProperty("kind").GetString() == "message") received.TrySetResult(p);
                    });
                await connection.FocusAsync(null, default).WaitAsync(TimeSpan.FromSeconds(3));
                Socket.Live!.Push(JsonSerializer.Serialize(new { type = "new-chat-message", content = JsonSerializer.Serialize(
                    new { id = 703, fromUserId = 4242000000000042, toUserId = 9090000000000009, fromUserNickname = "Self", content = "Unknown self" }) }));
                var p = await received.Task.WaitAsync(TimeSpan.FromSeconds(3));
                Check(!connection.Faulted && fallbackHandler.Requests.Count(r => r.PathAndQuery == "/app-api/member/user/get") == (profileScope ? 1 : 0),
                    "profile failure or absent scope still connects; absent scope never reads profile");
                Check(p.GetProperty("ref").GetString() == fallback.ChatPeerReference(OAuthPkceClient.ChatOwner(fallbackSession), 4242000000000042) &&
                      !p.GetProperty("message").GetProperty("mine").GetBoolean() && p.GetProperty("name").GetString() == "Self",
                    "unknown self preserves original incoming projection");
                Check(!p.GetRawText().Contains("4242000000000042") && !p.GetRawText().Contains("9090000000000009"), "unknown-self projection contains no member ids");
            }
            finally { await fallback.StopChatAsync(); }
        }

        // Before SCM grants the chat routes the ticket is refused (code 403 in the body, or HTTP 403):
        // the socket stops after one try and the sign-in is untouched.
        foreach (var httpForbidden in new[] { false, true })
        {
            var refusing = new Refusing(httpForbidden);
            var refused = new OAuthPkceClient(new ScmHttpClient(refusing), new Vault(), new("fixture", uri, uri, uri, "desktop", "starbridge-api", "", "/callback"))
            {
                ChatTransport = () => new Socket(),
                OpenScmBrowser = openedUris.Add,
            };
            var connection = refused.StartChat(OAuthPkceClient.ChatOwner(session),
                async t => (await refused.IssueChatTicketAsync(session, t)).Ticket, _ => { });
            for (var i = 0; i < 100 && !connection.Faulted; i++) await Task.Delay(10);
            await Task.Delay(100);
            Check(connection.Faulted && refusing.Tickets == 1, $"refused ticket stops after one try (http403={httpForbidden})");
            await refused.StopChatAsync();
        }
        Console.WriteLine("PASS marketplace chat: full handles, opaque peers, whitelisted quotes, one-shot sends over the ticketed socket");
    }
}
