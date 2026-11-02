using System.Net;
using System.Text.Json;
using System.Threading.Channels;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class TradeNotificationTests
{
    private static int _checks;
    private static void Check(bool value, string message) {
        if (!value) throw new InvalidOperationException(message);
        _checks++;
    }
    private sealed class Clock : TimeProvider {
        internal long Seconds;
        public override long TimestampFrequency => 1;
        public override long GetTimestamp() => Seconds;
    }
    private sealed class Desktop : IDesktopNotificationSink {
        internal readonly List<DesktopNotification> Notices = [];
        internal bool Fail;
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token) {
            if (Fail) throw new IOException("Synthetic uncertain submission");
            Notices.Add(notice); return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class DenyHttp : HttpMessageHandler {
        internal int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token) {
            Requests++; throw new InvalidOperationException("Network forbidden in trade notification fixture");
        }
    }
    private sealed class Vault : ITokenVault {
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential writes");
        public string? LoadRefreshToken(string key) => null;
        public string? LoadActiveAccountKey() => null;
        public void DeleteRefreshToken(string key) { }
    }
    private static ScmOAuthOptions Options() {
        var uri = new Uri("https://trade-notifications.invalid/");
        return new("fixture", uri, uri, uri, "fixture", "fixture", "profile.read presence.write trade.read trade.write", "/callback");
    }
    private static OAuthPkceClient OAuth(DenyHttp handler) => new(new ScmHttpClient(handler), new Vault(), Options());
    private static JsonElement Row(long id = 1, int subType = 4, int type = 1, string title = "对方已发货", bool read = false) =>
        JsonSerializer.SerializeToElement(new { id, type, subType, title, isRead = read,
            userId = 424242, senderId = 909090, content = "不允许展示的内容 联系：12345678901", createTime = "2026-10-28T01:00:00",
            orderInfo = new { transactionId = "TXN-fixture-ABC", orderNumber = "ORD-fixture-XYZ", productName = "Aurora",
                traderName = "Kestrel", traderId = 909090 } });

    internal static async Task Run()
    {
        _checks = 0;
        _checks += await TradeNotificationRedactionTests.Run();
        VerifyGrantGates();
        await PreferencesAndDelivery();
        await PushTransport();
        _checks += await TradeNotificationActivationTests.Run();
        _checks += await TradeNotificationTransactionIdTests.Run();
        _checks += await TradeNotificationSoundTests.Run();
        Console.WriteLine($"PASS CX-T23 trade notification assertions: {_checks} passed, 0 failed");
    }

    private static void VerifyGrantGates()
    {
        var root = Directory.CreateTempSubdirectory("cxt23-grants-").FullName;
        try {
            var http = new DenyHttp();
            foreach (var grants in new[] { Array.Empty<string>(), ["profile.read"], ["trade.read"],
                ["trade.read", "trade.write"], ["profile.read", "trade.read", "trade.write"] }) {
                var session = new ScmOAuthSession("fixture", "fixture", "fixture", "synthetic-only",
                    DateTimeOffset.UtcNow.AddHours(1), grants);
                using var host = new ScmAccountBridgeHost(OAuth(http), new ScmProfileCacheStore(root), "fixture", () => null, initialSession: session);
                Check(host.AllowsTradeNotification(false) == grants.Contains("profile.read"), "Station delivery requires current profile.read grant");
                Check(host.AllowsTradeNotification(true) == (grants.Contains("trade.read") && grants.Contains("trade.write")),
                    "Chat delivery requires both grants of the existing chat connection");
                host.Dispose();
                Check(!host.AllowsTradeNotification(false) && !host.AllowsTradeNotification(true), "Disposed account has no notification authority");
            }
            var deferredSession = new ScmOAuthSession("fixture", "fixture", "fixture", "synthetic-only",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "trade.read", "trade.write"]);
            using var deferred = new ScmAccountBridgeHost(OAuth(http), new ScmProfileCacheStore(root), "fixture", () => null,
                initialSession: deferredSession, deferBusinessStartup: true);
            Check(!deferred.AllowsTradeNotification(false) && !deferred.AllowsTradeNotification(true), "Deferred login cannot start business notifications");
            Check(http.Requests == 0, "Grant checks never issue tickets, requests or credential writes");
        }
        finally { Directory.Delete(root, true); }
    }

    private static async Task PreferencesAndDelivery()
    {
        var root = Directory.CreateTempSubdirectory("cxt23-trade-").FullName;
        try {
            var clock = new Clock(); var sink = new Desktop(); var http = new DenyHttp(); var oauth = OAuth(http);
            var owner = new BridgeAccountContext("fixture", "scm", "synthetic-owner");
            long generation = 1, sequence = 0; var online = true; var eligible = true;
            new ApplicationPreferencesStore(root).Save(ApplicationPreferencesSnapshot.Default with { LocaleOverride = "zh-CN" });
            // Deliberately old JSON without the new field. This is an isolated fixture root.
            File.WriteAllText(Path.Combine(root, "notification-settings.v1.json"),
                """{"schemaVersion":1,"revision":0,"inAppEnabled":true,"position":"bottomRight","preview":"sourceOnly","windowsEnabled":false,"directMessageWindowsEnabled":false}""");
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => generation, () => eligible,
                desktop: sink, time: clock, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, payload));
            var events = new List<BridgeEnvelope>(); settings.EventReady += events.Add;
            BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request("notificationSettings." + name,
                Guid.NewGuid().ToString("N"), generation, payload);
            async Task<JsonElement> Consume() => (await settings.DispatchAsync(Request("consumeActivation", events.Last().Payload))).Response.Payload;
            async Task<JsonElement> Read() => (await settings.DispatchAsync(Request("read", new { schemaVersion = 1 }))).Response.Payload;
            async Task Save(bool master, bool trade, string preview = "sourceOnly") {
                var revision = (await Read()).GetProperty("revision").GetInt32();
                var result = await settings.DispatchAsync(Request("save", new { schemaVersion = 1, expectedRevision = revision,
                    windowsEnabled = master, tradeWindowsEnabled = trade, preview, position = "bottomRight", inAppEnabled = true }));
                Check(result.Response.Status == "ok", "New preference must save through the canonical device dispatcher");
            }
            var legacy = await Read();
            Check(legacy.GetProperty("tradeWindowsEnabled").GetBoolean() && !legacy.GetProperty("windowsEnabled").GetBoolean(),
                "Legacy settings default trade on without enabling the master switch");
            var tradeOwner = "fixture-owner";
            TradeNotificationEvent Notice(long id) => oauth.ProjectTradeNotification(tradeOwner, Row(id))!;
            Task Present(TradeNotificationEvent notice) => settings.PresentTradeAsync(owner, generation, notice, () => online);
            await Present(Notice(1)); Check(sink.Notices.Count == 0, "Master off suppresses trade delivery");
            await Save(true, false); await Present(Notice(2)); Check(sink.Notices.Count == 0, "Trade child off suppresses delivery");
            await Save(true, true); await Present(Notice(1)); await Present(Notice(2));
            Check(sink.Notices.Count == 0, "Turning on cannot replay events consumed while muted");
            await Present(Notice(3));
            Check(sink.Notices.Count == 1 && sink.Notices[0].Trade is { Title: "对方已发货", Body: "Aurora",
                Kind: "shipped", Item: "Aurora", Quantity: 0, Amount: "", Peer: "", Text: "" },
                "Both on delivers SCM title, item and status; station cards carry no counterparty name");
            Check(events.Count == 0, "Showing never navigates or marks a message read");
            await Present(Notice(3)); Check(sink.Notices.Count == 1, "Duplicate event delivers once");
            var card = sink.Notices[0]; card.Activated!(); card.Activated!();
            Check(events.Count == 1 && events[0].Name == "notificationSettings.activated", "Click emits exactly one shared activation event");
            var activation = await Consume();
            var reference = activation.GetProperty("ref").GetString()!;
            Check(activation.GetProperty("destination").GetString() == "trade" && reference.Length == 32 &&
                !events[0].Payload.GetRawText().Contains("TXN-fixture-ABC") &&
                oauth.ResolveNotificationTradeReference(tradeOwner, reference) == "TXN-fixture-ABC", "Opaque click reference resolves only inside Host");
            try { oauth.ResolveNotificationTradeReference("other-owner", reference); throw new Exception("Wrong-owner ref accepted"); }
            catch (StarBridge.HostRuntime.Account.AccountBridgeHostException) { _checks++; }
            eligible = false; await Present(Notice(4)); eligible = true; await Present(Notice(4));
            Check(sink.Notices.Count == 1, "Foreground transaction is consumed without notification or replay");
            Check(DesktopNotificationVisibility.SuppressionReason(card, "notRunning", true).Length > 0 &&
                card.BackgroundOnly, "Native visibility suppresses any app foreground, including this transaction");
            await Present(Notice(5)); var old = sink.Notices.Last(); generation++;
            Check(!old.IsCurrent(), "Account generation immediately invalidates queued cards");
            var before = sink.Notices.Count;
            await settings.PresentTradeAsync(owner, generation - 1, Notice(6), () => true);
            Check(sink.Notices.Count == before, "Retired account push cannot deliver");
            settings.Reset(); old.Activated!(); Check(events.Count == 1, "Retired cards cannot navigate into a new account");
            online = false; await Present(Notice(7)); Check(sink.Notices.Count == before, "Logged-out source does not observe or deliver");
            online = true;
            var secondOwner = new BridgeAccountContext("fixture", "scm", "synthetic-second");
            await settings.PresentTradeAsync(secondOwner, generation, Notice(3), () => true);
            Check(sink.Notices.Count == before + 1, "Different owner has independent consumed state");
            Check(!old.IsCurrent(), "New owner cannot revive the previous observer lifetime");
            var peer = new string('a', 32);
            TradeNotificationEvent? Chat(long id, bool mine = false, bool read = false) => TradeNotificationEvent.ChatPush(
                JsonSerializer.SerializeToElement(new { kind = "message", @ref = peer, name = "Kestrel",
                    message = new { id, mine, read, content = "Aurora is ready" } }));
            Check(Chat(100, mine: true) is null && Chat(100, read: true) is null, "Own and already-read chat messages are excluded");
            Check(TradeNotificationEvent.ChatPush(JsonSerializer.SerializeToElement(new { kind = "resync" })) is null &&
                TradeNotificationEvent.ChatPush(JsonSerializer.SerializeToElement(new { kind = "unread", count = 99 })) is null,
                "First-login unread/resync snapshots are never notification sources");
            await Save(true, true, "fullContent"); await Present(Chat(100)!);
            Check(sink.Notices.Last().Trade is { Body: "Aurora is ready", Kind: "message", Peer: "Kestrel", Text: "Aurora is ready" },
                "Full preview shows sanitized incoming chat text and the verified handle");
            sink.Notices.Last().Activated!();
            activation = await Consume();
            Check(activation.GetProperty("ref").GetString() == peer &&
                activation.GetProperty("destination").GetString() == "tradeChat", "Chat activation uses the existing opaque peer reference");
            await Save(true, true, "sourceOnly"); await Present(Chat(101)!);
            Check(!sink.Notices.Last().Trade!.Body.Contains("Aurora") && sink.Notices.Last().Trade!.Title.Contains("Kestrel") &&
                sink.Notices.Last().Trade!.Text == "" && sink.Notices.Last().Trade!.Peer == "Kestrel",
                "Source-only preview shows the verified handle and hides chat content");
            await Save(true, true, "hiddenDetails"); await Present(Chat(102)!);
            Check(sink.Notices.Last().Trade == new TradeNotificationContent("", ""), "Hidden-details preview retains no display content");
            await Save(true, true, "fullContent");
            sink.Fail = true; await Present(Chat(103)!); sink.Fail = false; var afterFailure = sink.Notices.Count;
            await Present(Chat(103)!); Check(sink.Notices.Count == afterFailure, "Uncertain native failure never replays");
            await Present(Chat(104)!); clock.Seconds += 31;
            Check(!sink.Notices.Last().IsCurrent(), "Fake monotonic time expires pending delivery and activation");
            for (var subtype = 1; subtype <= 10; subtype++) {
                var item = oauth.ProjectTradeNotification(tradeOwner, Row(200 + subtype, subtype, title: ""))!;
                Check(item.LocalTitle(false).Length > 0 && item.LocalTitle(true).All(c => c < 128), "Every supported subtype has fixed Chinese and English fallback titles");
                await Present(item);
            }
            var javaTemplates = new[] {
                "用户 Kestrel 申请购买您的Aurora，数量：1，金额：123，交易编号：TXN-fixture-JAVA，联系方式：12345678901，请及时处理。",
                "收购者 Kestrel 已同意您的交易申请Aurora，数量：1，联系方式：12345678901，请及时发货。",
                "订单Aurora已被取消，数量：1。",
                "卖家 Kestrel 已发货Aurora，数量：1，联系方式：12345678901，请注意查收并确认收货。",
                "买家 Kestrel 已确认收货Aurora，数量：1，交易已完成！",
                "用户 Kestrel 对您的订单Aurora",
                "订单Aurora因买家 Kestrel 超时未收货已被系统自动取消，数量：1，库存已恢复。",
                "用户 Kestrel 申请与您交换物品：Aurora，交易编号：TXN-fixture-JAVA，联系方式：12345678901，请及时处理。",
                "您已确认收货Aurora，数量：1，交易已完成！",
                "订单Aurora已被取消，数量：1。",
            };
            for (var i = 0; i < javaTemplates.Length; i++) {
                var item = oauth.ProjectTradeNotification(tradeOwner, JsonSerializer.SerializeToElement(new {
                    id = 7000 + i, type = 1, subType = i + 1, title = "", content = javaTemplates[i], isRead = false,
                    orderInfo = (object?)null }))!;
                Check(item.Item == "Aurora" && !item.Peer.Contains("Kestrel") && !item.Text.Contains("12345678901"),
                    "Actual Java templates without orderInfo yield item and masked peer without copying the contact tail");
                Check((item.Reference is { Length: 32 }) == (i is 0 or 7), "Only explicit transaction numbers may mint an opaque ref from a legacy body");
                await Present(item);
                Check(!JsonSerializer.Serialize(sink.Notices.Last().Trade).Contains("12345678901"), "Java fallback content never exposes contacts");
                var kinds = new[] { "request", "approved", "cancelled", "shipped", "completed", "review", "cancelled", "request", "completed", "cancelled" };
                Check(sink.Notices.Last().Trade is {} card2 && card2.Kind == kinds[i] &&
                    card2.Quantity == (i is 5 or 7 ? 0 : 1) && card2.Amount == (i == 0 ? "123" : ""),
                    "Every Java template maps to a closed status word and parsed quantity/amount digits only");
            }
            var alternate = TradeNotificationEvent.JavaStationText(JsonSerializer.SerializeToElement(new {
                content = "用户 Kestrel 申请向您出售Aurora，数量：1，金额：123，交易编号：TXN-fixture-JAVA，联系方式：hidden" }), 1, false);
            Check(alternate.Item == "Aurora" && alternate.Number == "TXN-fixture-JAVA", "Purchase-order request template uses the same explicit reference rule");
            (int, string) Figures(string content, int subType = 1, string[]? known = null) => TradeNotificationEvent.StationFigures(
                JsonSerializer.SerializeToElement(new { content }), subType, false, known ?? []);
            Check(Figures("用户 K 申请购买您的Aurora，数量：12，金额：18000，交易编号：TXN-1，联系方式：13800138000，请及时处理。") == (12, "18,000") &&
                Figures("用户 K 申请购买您的Aurora，数量：1，金额：99.5，交易编号：TXN-1，联系方式：13800138000，请及时处理。") == (1, "99.5") &&
                Figures("订单Aurora已被取消，数量：1234567。", 3) == (0, "") &&
                Figures("订单Aurora已被取消，数量：3。", 3) == (3, "") &&
                Figures("数量：2，金额：123abc，") == (0, "") &&
                Figures(new string('x', 4097)) == (0, ""),
                "Quantity and amount are bounded digits from their own template position");
            // CX-T32 P1: figures after or around the contact tail, repeated labels and item-name injection.
            Check(Figures("卖家 Kestrel 已发货Aurora，数量：1，联系方式：微信，金额：13800138000，请注意查收并确认收货。", 4) == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：1，联系方式：微信，金额：13800138000，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的X，数量：99，金额：13800138000，数量：1，金额：5，交易编号：T，联系方式：1，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：1，金额：5，交易编号：T，联系方式：1，金额：13800138000。") == (0, "") &&
                Figures("卖家 Kestrel 已发货Aurora，数量：1，金额：88888，联系方式：x", 4) == (0, "") &&
                Figures("卖家 Kestrel 已发货Aurora，数量：4，联系方式：x，请注意查收并确认收货。", 4) == (4, "") &&
                Figures("卖家 Kestrel 已发货Aurora，数量：4，联系方式：x", 4) == (0, "") &&
                // CX-T32b: mixed punctuation, contact aliases and item-name injection all make the body ambiguous.
                Figures("用户 K 申请购买您的Aurora,数量:1,金额:5,联系：微信，数量：2，金额：13800138000，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：12，金额：13800138000，数量:1，金额:5，交易编号：T，联系方式：hidden，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：1，金额：5，交易编号：T，联系方式：数量 13800138000，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：01，金额：5，交易编号：T，联系方式：x") == (0, "") &&
                Figures("用户 K 申请与您交换物品：Aurora，交易编号：T，数量：1，联系方式：x", 8) == (0, "") &&
                Figures("Unrecognized prose，数量：1，金额：5。", 1) == (0, ""),
                "Contact-tail, repeated, misplaced and unrecognised-template figures are dropped");
            Check(Figures("用户 K 申请购买您的Aurora，数量：909090，金额：424242，交易编号：T，联系方式：1，请及时处理。", 1,
                    ["909090", "TXN-424242"]) == (0, ""),
                "Digits equal to a known identifier are dropped");
            Check(Figures("用户 K 申请购买您的Aurora，数量：2，金额：424242.00，交易编号：T，联系方式：1，请及时处理。", 1, ["424242"]) == (2, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：7，金额：9，交易编号：T，联系方式：1，请及时处理。", 1, ["ORD-000007"]) == (0, "9"),
                "Known identifiers are compared as numbers (trailing decimals, leading zeros)");
            // CX-T32c: whole-body templates and identifiers longer than any numeric type.
            Check(Figures("用户 K 申请购买您的Aurora，数量：12，金额：13800138000，交易编号：T，联系方式：\n任意非模板正文") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：12，金额：5，交易编号：T，联系方式：x，请及时处理。\n") == (0, "") &&
                Figures("订单Aurora已被取消，数量：3。\n", 3) == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，数量：2，金额：424242.00，交易编号：T，联系方式：1，请及时处理。", 1,
                    ["TXN-" + new string('0', 29) + "424242"]) == (2, "") &&
                Figures("收购者 K 已同意您的交易申请Aurora，数量：3，联系方式：x，请及时发货。", 2) == (3, "") &&
                Figures("卖家 K 已发货Aurora，数量：4，联系方式：微信，号码 x，请注意查收并确认收货。", 4) == (4, ""),
                "Only whole single-line templates yield figures; long zero-padded identifiers still match");
            // CX-T32d: zero-width / bidi / Unicode line breaks and fields smuggled through the item name.
            const string Valid = "用户 K 申请购买您的Aurora，数量：2，金额：5，交易编号：T，联系方式：x，请及时处理。";
            Check(Figures(Valid) == (2, "5") &&
                Figures("用户 K 申请购买您的Aurora，数\u200B量：1，金\u200B额：5，交易编号：T，联系方式：微信，数量：12，金额：13800138000，交易编号：T，联系方式：x，请及时处理。") == (0, "") &&
                Figures("用户 K 申请购买您的Aurora，X，数量：12，金额：13800138000，交易编号：T，联系方式：x，请及时处理。") == (0, "") &&
                new[] { "\u0085", "\u2028", "\u2029", "\r", "\u200B", "\u202E", "\uFEFF", "\uE000" }
                    .All(c => Figures(Valid.Replace("Aurora", "Aur" + c + "ora")) == (0, "") &&
                        Figures(Valid.Replace("联系方式：x", "联系方式：x" + c)) == (0, "")),
                "Bodies with invisible or line-separator characters, or a comma inside the item, yield no figures");
            // Verified handles show in full; anything that is not handle-shaped stays masked.
            Check(TradeNotificationEvent.ChatHandle("Pilot12345") == "Pilot12345" &&
                TradeNotificationEvent.ChatHandle("QQPilot") == "QQPilot" &&
                TradeNotificationEvent.ChatHandle(" Kestrel ") == "Kestrel" &&
                TradeNotificationEvent.ChatHandle("13800138000") != "13800138000" &&
                TradeNotificationEvent.ChatHandle("_pilot") != "_pilot" &&
                TradeNotificationEvent.ChatHandle("a") != "a" &&
                TradeNotificationEvent.ChatHandle(new string('a', 61)) != new string('a', 61) &&
                TradeNotificationEvent.ChatHandle("pilot@mail") != "pilot@mail" &&
                TradeNotificationEvent.ChatHandle("Kestrel_07") == "Kestrel_07" &&
                TradeNotificationEvent.ChatHandle("pilot-x") == "pilot-x" &&
                TradeNotificationEvent.ChatHandle("pilot.io") != "pilot.io" &&
                TradeNotificationEvent.ChatHandle("discord.gg/abc") is var dg && !dg.Contains("discord") &&
                TradeNotificationEvent.ChatHandle("星海旅人") != "星海旅人" &&
                TradeNotificationEvent.ChatHandle("Discord ID: trade_user") is var di && !di.Contains("trade_user") &&
                TradeNotificationEvent.ChatHandle("") is var empty && !empty.Contains('@'),
                "Only handle-shaped names are shown unmasked");
            var unsupported = TradeNotificationEvent.JavaStationText(JsonSerializer.SerializeToElement(new {
                content = "Unrecognized template 会员号：12345678901" }), 4, false);
            Check(unsupported == ("", "", ""), "Unknown Java prose is not guessed or copied into a notification");
            Check(oauth.ProjectTradeNotification(tradeOwner, Row(300, 0)) is null &&
                oauth.ProjectTradeNotification(tradeOwner, Row(301, type: 2)) is null &&
                oauth.ProjectTradeNotification(tradeOwner, Row(302, read: true)) is null,
                "General, fallback chat and read station messages are excluded");
            var reminder = oauth.ProjectTradeNotification(tradeOwner, JsonSerializer.SerializeToElement(new {
                id = 400, type = 0, title = "收货提醒", content = "您的订单Aurora已发货超过1小时，请尽快确认收货。", isRead = false }))!;
            Check(reminder.ReceiptReminder && reminder.Item == "Aurora" && reminder.Reference is null, "Actual Java reminder shape extracts only item, never guesses transaction");
            await Present(reminder); sink.Notices.Last().Activated!();
            Check((await Consume()).GetProperty("destination").GetString() == "myTrades", "Missing Java reminder reference has an explicit safe fallback");
            var unsafeItem = oauth.ProjectTradeNotification(tradeOwner, JsonSerializer.SerializeToElement(new {
                id = 401, type = 1, subType = 4, title = "对方已发货 TXN-fixture-ABC ORD-fixture-XYZ 424242",
                orderInfo = new { transactionId = "TXN-fixture-ABC", orderNumber = "ORD-fixture-XYZ", productName = "Aurora a@example.com +86 13800138000", traderName = "Kestrel" } }))!;
            await Present(unsafeItem);
            var text = JsonSerializer.Serialize(sink.Notices.Last().Trade);
            Check(!text.Contains("TXN-fixture-ABC") && !text.Contains("ORD-fixture-XYZ") && !text.Contains("424242") &&
                !text.Contains("example.com") && !text.Contains("13800138000"), "No raw account, transaction, order or contact data reaches desktop");
            oauth.ClearNotificationTradeReferences();
            try { oauth.ResolveNotificationTradeReference(tradeOwner, reference); throw new Exception("Retired ref accepted"); }
            catch (StarBridge.HostRuntime.Account.AccountBridgeHostException) { _checks++; }
            var bounded = new TradeNotificationObserver(clock);
            for (var i = 0; i < 4096; i++) Check(bounded.Observe(owner, 9, Notice(1000 + i)) is not null, "Bounded dedup admits a fresh session key");
            Check(bounded.Observe(owner, 9, Notice(6000)) is null, "Dedup cap fails closed instead of evicting consumed keys");
            Check(http.Requests == 0, "Observers, settings and opaque reference handling make zero HTTP requests");
        }
        finally { Directory.Delete(root, true); }
    }

    private sealed class Transport : IScmChatTransport
    {
        internal readonly Channel<string> Incoming = Channel.CreateUnbounded<string>();
        internal readonly List<string> Sent = [];
        internal readonly TaskCompletionSource Subscribed = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal bool Disposed;
        internal bool HoldAck;
        public Task ConnectAsync(Uri endpoint, CancellationToken token) => Task.CompletedTask;
        public Task SendAsync(string text, CancellationToken token) {
            Sent.Add(text);
            using var json = JsonDocument.Parse(text);
            switch (json.RootElement.GetProperty("type").GetString()) {
                case "message-subscribe":
                    Check(false, "message-subscribe is never sent on the relay socket (hotfix 10-29)"); break;
                case "member-online-heartbeat":
                    // The first heartbeat marks the connection as live for the push assertions below.
                    Subscribed.TrySetResult();
                    if (!HoldAck) Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "member-status-update", content = new { signInStatus = 1 } })); break;
                default:
                    Check(json.RootElement.GetProperty("type").GetString() is "member-online-heartbeat" or "fleet-broadcast-subscribe"
                        or "fleet-broadcast-unsubscribe" or "ping", "The relay socket only receives message types the relay accepts");
                    break;
            }
            return Task.CompletedTask;
        }
        public async Task<string?> ReceiveAsync(CancellationToken token) => await Incoming.Reader.ReadAsync(token);
        public ValueTask DisposeAsync() { Disposed = true; return ValueTask.CompletedTask; }
    }

    private static async Task PushTransport()
    {
        var http = new DenyHttp(); var oauth = OAuth(http); var transport = new Transport { HoldAck = true };
        var acknowledged = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var transaction = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var tickets = 0; var disconnects = 0; var invalidations = 0;
        var pushed = new Channel<TradeNotificationEvent>[] { Channel.CreateUnbounded<TradeNotificationEvent>() }[0];
        var session = new ScmOAuthSession("fixture", "fixture", "fixture", "synthetic-only",
            DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "presence.write"]);
        await using var client = new ScmRealtimeClient(oauth, Options(), "synthetic-device", (_, _) => { },
            (_, status) => { if (status == 2) acknowledged.TrySetResult(); }, (_, _) => { }, (_, _, _, _) => { },
            issueTicket: _ => { tickets++; return Task.FromResult(new ScmWebSocketTicketResult(new("synthetic-one-time", DateTimeOffset.UtcNow.AddMinutes(1)), session)); },
            disconnected: _ => disconnects++,
            marketplaceInvalidated: _ => { if (++invalidations > 1) transaction.TrySetResult(); },
            tradeNotice: (_, row) => { if (oauth.ProjectTradeNotification("fixture", row) is {} n) pushed.Writer.TryWrite(n); },
            transportFactory: () => transport);
        client.Start(session);
        await transport.Subscribed.Task.WaitAsync(TimeSpan.FromSeconds(2));
        Check(!pushed.Reader.TryRead(out _), "Initial unread count does not fan out existing station messages");
        foreach (var content in new object?[] { "{bad-json", 42, new string('x', 70000), new { }, null })
            transport.Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "new-message", content }));
        transport.Incoming.Writer.TryWrite("{\"type\":\"new-message\"}");
        transport.Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "member-status-update", content = new { signInStatus = 2 } }));
        transport.Incoming.Writer.TryWrite("{\"type\":\"transaction-event\"}");
        await Task.WhenAll(acknowledged.Task, transaction.Task).WaitAsync(TimeSpan.FromSeconds(2));
        Check(tickets == 1 && disconnects == 0, "Malformed, numeric, missing and oversized notices drop only their frame; later ACK and transaction survive without reconnect or tickets");
        transport.Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "new-message", content = Row(9000) }));
        using var timeout = new CancellationTokenSource(TimeSpan.FromSeconds(2));
        var first = await pushed.Reader.ReadAsync(timeout.Token);
        Check(first.Title == "对方已发货", "Object-content station frame reaches the existing realtime source");
        transport.Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "new-message", content = Row(9001).GetRawText() }));
        var second = await pushed.Reader.ReadAsync(timeout.Token);
        Check(second.Key != first.Key, "Java string-content frame also decodes without REST fetching");
        var topReminder = JsonSerializer.SerializeToElement(new { id = 9002, type = 0, title = "收货提醒",
            transactionId = "Ab9-Realtime", orderId = 42, productId = 24 });
        foreach (var content in new object[] { topReminder, topReminder.GetRawText() }) {
            transport.Incoming.Writer.TryWrite(JsonSerializer.Serialize(new { type = "new-message", content }));
            var reminder = await pushed.Reader.ReadAsync(timeout.Token);
            Check(reminder.ReceiptReminder && reminder.Reference is { Length: 32 } &&
                oauth.ResolveNotificationTradeReference("fixture", reminder.Reference) == "Ab9-Realtime" &&
                !JsonSerializer.Serialize(reminder).Contains("Ab9-Realtime"),
                "Object and string push envelopes preserve top-level reminder references without exposing numbers");
        }
        client.Stop(); await client.StopCompletion;
        Check(transport.Disposed && http.Requests == 0, "Stopping account retires fake socket; no REST polling or contention exists");
        var subscription = transport.Sent.Select(t => JsonDocument.Parse(t)).Where(d => d.RootElement.GetProperty("type").GetString() == "message-subscribe").ToArray();
        Check(subscription.Length == 0, "The relay socket never carries message-subscribe; station notices stay on REST reads");
        foreach (var document in subscription) document.Dispose();
        var falseDisconnects = 0; var falseInvalidations = 0;
        await using var noConnection = new ScmRealtimeClient(oauth, Options(), "synthetic-device", (_, _) => { },
            (_, _) => { }, (_, _) => { }, (_, _, _, _) => { },
            issueTicket: _ => Task.FromException<ScmWebSocketTicketResult>(new HttpRequestException("synthetic ticket failure")),
            disconnected: _ => falseDisconnects++, marketplaceInvalidated: _ => falseInvalidations++,
            transportFactory: () => throw new InvalidOperationException("No socket before a ticket"));
        noConnection.Start(session);
        noConnection.Stop(); await noConnection.StopCompletion;
        Check(falseDisconnects == 0 && falseInvalidations == 0,
            "Failed ticket attempts never create false disconnect invalidations or automatic marketplace reads");
    }
}
