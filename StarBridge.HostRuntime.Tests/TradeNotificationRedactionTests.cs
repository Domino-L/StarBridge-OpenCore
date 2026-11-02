using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class TradeNotificationRedactionTests
{
    private sealed class DenyHttp : HttpMessageHandler
    {
        internal int Requests;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            Requests++;
            throw new InvalidOperationException("No HTTP in redaction fixtures");
        }
    }

    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential writes");
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class Desktop : IDesktopNotificationSink
    {
        internal readonly List<DesktopNotification> Notices = [];
        public ValueTask<bool> TryPresentAsync(DesktopNotification notice, CancellationToken token)
        {
            Notices.Add(notice);
            return ValueTask.FromResult(true);
        }
        public void Clear() { }
        public void Dispose() { }
    }

    // Synthetic messages and isolated TEMP only. No real HTTP, accounts or credentials.
    internal static async Task<int> Run()
    {
        var checks = 0;
        void Check(bool valid, string label)
        {
            // Failure labels deliberately exclude the original message and handles.
            if (!valid) throw new InvalidOperationException("CX-T23h assertion " + (checks + 1) + ": " + label);
            checks++;
        }
        const string probe = "单号 Ab9-Realtime，Telegram: trade_user";
        const string chat = "今晚 8 点在新巴贝奇见";
        var blocked = new[] { "微信号： trade_user", "Telegram username: trade_user", "Discord ID: trade_user", probe,
            "加我 qq 12345", "my wechat: abc", "call my phone 13800138000", "👍 微信 trade_user",
            "请查收 " + probe + " 明天见", "明天见 微信 trade_user,private_tail", "discord\tusername: trade_user",
            "discord\nID: trade_user", "dis\u202ecord: trade_user",
            "Telegram user name: trade_user", "discord nickname: trade_user", "line screen name = trade_user",
            "微\u202c信号： trade_user", "dis\u200ecord ID: trade_user", "微\u200b信号： trade_user",
            "微\u200d信: abc", "ｗｅｃｈａｔ: abc", "Tele\ufeffgram: abc", "今晚见\u202e",
            "微\t信号： trade_user", "dis\ncord ID: trade_user", "微\ufe0f信号： trade_user",
            "dis\ufe00cord ID: trade_user", "微\U000E0100信号： trade_user", "微\u0301信号： trade_user",
            "微 信号： trade_user", "微\0信号： trade_user", "dis\0cord ID: trade_user", "I D 号： trade_user",
            // A value cut by the display limit is still detected on the full text.
            new string('x', 195) + " 13800138000", new string('x', 190) + " 微信号： trade_user",
            new string('x', 200) + " 微信 trade_user", new string('x', 199) + "微信 trade_user",
            // CX-T28: the cut creates a word boundary the full text lacks; the shown text is checked again.
            new string('x', 192) + " ORD-1ab中", new string('x', 188) + " example.com中" };
        var ordinary = new[] { "TGIF, see you tomorrow", "mobile app updated", chat, "order looks good, thanks", "the line is long",
            "The doctor arrives at 8 tonight.", "mydiscord: abc", "discordant: abc", "tg_name: abc", "tg2: abc",
            "TGid99", "Order looks good, thanks", "ORDER looks good, thanks", "member joined", "Ab9-Realtime", "👍",
            "an ordinary shipment", "I ordered it yesterday", "members only event", "好的👍🏽", "👨‍👩‍👧 一起来",
            "ordinary", "ordered", "order", "members", "Member since 2024", "Member since 2024A88",
            "TXN-fixture-ABC", "ORD-fixture-XYZ", "MEMBERabc", "txn-lower", "member_lower", "txnabc", "ordabc", "memberabc",
            "ORD-ABCDEF", "TXN#abc", "MEMBER abc", "ｗｅｌｌ ｄｏｎｅ", "明天\u200b见", "❤️ 谢谢", "Café",
            "members only", "order looks good", "dis cord app updated", "mydis cord: abc",
            "dis cord username account id: abc", "ORD-a1", "TXN-1a" };
        var global = new[] { "a@example.com", "https://example.invalid/test", "www.example.invalid/test", "example.com/test",
            "+86 13800138000", "424242", "ORD-2024A88", "TXN#99812", "MEMBER 12ab34", "ord1234",
            "txn_A1b2", "member:ab12", "TXNabcd1", "Member since 20245", "ORD-1ab", "TXN-ab1",
            "TXN-ABCD-1234", "ORD2024", "TXN-ab12", "MEMBER-a-1", "ORD-1-a" };
        // Include supplementary Format characters: a UTF-16 char loop would miss these.
        var invisible = Enumerable.Range(0, 0x110000).Where(value => value is not (>= 0xd800 and <= 0xdfff))
            .Select(value => new System.Text.Rune(value))
            .Where(rune => System.Text.Rune.GetUnicodeCategory(rune) == System.Globalization.UnicodeCategory.Format)
            .Select(rune => rune.ToString()).Concat(new[] { "\u034f", "\u115f", "\u1160", "\u3164", "\uffa0",
                "\ufe0f", "\ufe00", "\U000E0100", "\u0301", "\u20dd" }).ToArray();
        var unicodeBlocked = invisible.SelectMany(value => new[] {
            "微" + value + "信: abc", "dis" + value + "cord ID: trade_user", "example.c" + value + "om/test",
            "a@example.c" + value + "om", "12" + value + "345", "OR" + value + "D-2024A88"
        }).Concat(new[] { "ａ＠ｅｘａｍｐｌｅ．ｃｏｍ", "１２３４５", "ＯＲＤ－２０２４Ａ８８", "ｈｔｔｐｓ：／／example.invalid/test" })
            .Concat(Enumerable.Range(0x202a, 5).Concat(Enumerable.Range(0x2066, 4)).Select(value => "今晚见" + (char)value));
        var displayCases = new (string Source, string Display)[] {
            (new string('x', 199) + "👍🏽", new string('x', 199)),
            (new string('x', 198) + "👍🏽", new string('x', 198)),
            (new string('x', 196) + "👍🏽", new string('x', 196) + "👍🏽"),
            (new string('x', 195) + "👨‍👩‍👧", new string('x', 195)),
            (new string('x', 192) + "👨‍👩‍👧", new string('x', 192) + "👨‍👩‍👧"),
            (new string('x', 199) + "❤️", new string('x', 199)),
            (new string('x', 198) + "❤️", new string('x', 198) + "❤️"),
            (new string('x', 199) + "a\u0301", new string('x', 199)),
            ("今晚\n8 点见", "今晚 8 点见"), ("今晚\t8 点见", "今晚 8 点见"),
            ("今晚\0见", "今晚见"), (" \t今晚见\n ", "今晚见")
        };
        var root = Directory.CreateTempSubdirectory("cxt23h-redaction-").FullName;
        var originalOut = Console.Out;
        var originalError = Console.Error;
        using var output = new StringWriter();
        using var errors = new StringWriter();
        var http = new DenyHttp();
        try {
            Console.SetOut(output);
            Console.SetError(errors);
            var uri = new Uri("https://redaction.invalid/");
            var oauth = new OAuthPkceClient(new ScmHttpClient(http), new Vault(), new("fixture", uri, uri, uri, "fixture", "fixture", "", "/callback"));
            var owner = new BridgeAccountContext("fixture", "scm", "synthetic-owner");
            long id = 0;
            TradeNotificationEvent Chat(string content, string name = "Kestrel") => TradeNotificationEvent.ChatPush(JsonSerializer.SerializeToElement(new {
                kind = "message", @ref = new string('a', 32), name, message = new { id = ++id, mine = false, read = false, content }
            }))!;
            foreach (var locale in new[] { "zh-CN", "en-US" })
            foreach (var preview in new[] { "fullContent", "sourceOnly", "hiddenDetails" }) {
                var fixtureRoot = Directory.CreateDirectory(Path.Combine(root, locale, preview)).FullName;
                new ApplicationPreferencesStore(fixtureRoot).Save(ApplicationPreferencesSnapshot.Default with { LocaleOverride = locale });
                File.WriteAllText(Path.Combine(fixtureRoot, "notification-settings.v1.json"), JsonSerializer.Serialize(new {
                    schemaVersion = 1, revision = 0, inAppEnabled = true, position = "bottomRight", preview,
                    windowsEnabled = true, tradeWindowsEnabled = true
                }));
                var sink = new Desktop();
                using var dispatcher = new NotificationSettingsBridgeDispatcher(fixtureRoot, () => 1, () => true, desktop: sink);
                async Task<TradeNotificationContent> Present(TradeNotificationEvent item) {
                    var count = sink.Notices.Count;
                    await dispatcher.PresentTradeAsync(owner, 1, item, () => true);
                    Check(sink.Notices.Count == count + 1, "synthetic notification delivered once");
                    return sink.Notices.Last().Trade!;
                }
                var generic = locale == "zh-CN" ? "发来一条交易私信。" : "Sent you a trade message.";
                // Every review probe exercises ChatPush -> dispatcher -> submitted notification card.
                foreach (var source in blocked.Concat(unicodeBlocked).Concat(global).Concat(global.Select(value => "明天见 " + value))
                    .Concat(new[] { "...，!!! *** …", "", new string('x', 4097), new string('x', 200) + "\u202e" }).Concat(ordinary)) {
                    var shown = await Present(Chat(source));
                    var expected = preview == "hiddenDetails" ? "" : preview == "sourceOnly" ? generic
                        : ordinary.Contains(source) ? source : generic;
                    Check(shown.Body == expected, "locale and preview body matrix");
                    Check(preview == "hiddenDetails" ? shown.Title == "" : shown.Title.EndsWith(" · Kestrel"),
                        "verified handle shown in full; hiddenDetails title unchanged");
                }
                foreach (var (source, display) in displayCases) {
                    var shown = await Present(Chat(source));
                    var expected = preview == "hiddenDetails" ? "" : preview == "sourceOnly" ? generic : display;
                    // Exact equality also rejects lone surrogates, half a skin-tone emoji,
                    // a detached variation selector, and partial ZWJ/combining sequences.
                    Check(shown.Body == expected && shown.Body.Length <= 200,
                        "display cleanup and complete text elements reach the actual card");
                    Check(preview == "hiddenDetails" ? shown.Title == "" : shown.Title.EndsWith(" · Kestrel"),
                        "display changes preserve the handle and preview modes");
                    Check(preview == "fullContent" ? shown.Text == (shown.Body == generic ? "" : shown.Body) : shown.Text == "",
                        "card text field follows the preview mode exactly");
                }
                // Structured station body, title and legacy extracted product text share SafeText.
                foreach (var legacy in new[] { false, true }) {
                    var station = oauth.ProjectTradeNotification("synthetic-owner", JsonSerializer.SerializeToElement(new {
                        id = ++id, type = 1, subType = 4, title = "提醒 " + probe,
                        content = legacy ? "卖家 Kestrel 已发货请查收 " + probe + " 明天见，数量：1，联系方式：unused" : "",
                        isRead = false, orderInfo = legacy ? null : new { productName = "请查收 " + probe + " 明天见", traderName = "Kestrel" }
                    }))!;
                    var shown = await Present(station);
                    Check(preview == "hiddenDetails" ? shown == new TradeNotificationContent("", "")
                        : shown.Title == (locale == "zh-CN" ? "对方已发货" : "Item shipped") && shown.Body == "" &&
                          !System.Text.Json.JsonSerializer.Serialize(shown).Contains("K*****l"),
                        "structured and legacy station fields filter contacts before presentation");
                }
                var sensitivePeer = Chat(chat, "Discord ID: trade_user");
                var peerShown = await Present(sensitivePeer);
                Check(peerShown.Title == (preview == "hiddenDetails" ? "" : locale == "zh-CN" ? "新的交易私信" : "New trade message"),
                    "sensitive sender omitted from card title");
                var cleanStation = oauth.ProjectTradeNotification("synthetic-owner", JsonSerializer.SerializeToElement(new {
                    id = ++id, type = 1, subType = 4, title = "", isRead = false,
                    content = "微信号： trade_user", orderInfo = new { productName = "Aurora", traderName = "Kestrel" }
                }))!;
                var cleanShown = await Present(cleanStation);
                Check(preview == "hiddenDetails" ? cleanShown == new TradeNotificationContent("", "")
                    : cleanShown.Body == "Aurora" && !cleanShown.Title.Contains("Kestrel") && !cleanShown.Title.Contains("K*****l"),
                    "station body uses the item only and never the counterparty name");
                const string known = "Cd8-Known";
                var withKnown = oauth.ProjectTradeNotification("synthetic-owner", JsonSerializer.SerializeToElement(new {
                    id = ++id, type = 1, subType = 4, isRead = false, title = "提醒 " + known,
                    orderInfo = new { transactionId = known, orderNumber = "Ef7-Order", productName = "物品 " + known + " Ef7-Order", traderName = "Kestrel" }
                }))!;
                Check(!JsonSerializer.Serialize(await Present(withKnown)).Contains(known), "known station transaction number remains redacted");
            }
            Check(http.Requests == 0, "redaction and station projections never request HTTP");
            foreach (var stream in new[] { output.ToString(), errors.ToString() })
                Check(!stream.Contains("Ab9-Realtime") && !stream.Contains("trade_user") && !stream.Contains("a@example.com"),
                    "raw fixture messages do not enter stdout or stderr diagnostics");
        }
        finally {
            Console.SetOut(originalOut);
            Console.SetError(originalError);
            Directory.Delete(root, true);
        }
        var chinese = new[] { "单号", "订单号", "交易号", "交易编号", "编号", "订单", "会员号", "会员编号", "用户编号",
            "用户ID", "联系方式", "联系", "加我", "微信", "V信", "QQ", "Q群", "电话", "手机", "号码", "账号", "ID 号" };
        var english = new[] { "wechat", "weixin", "wx", "vx", "qq", "telegram", "tg", "discord", "dc", "phone", "telephone",
            "mobile", "contact", "order", "transaction", "line", "whatsapp", "kakao", "skype" };
        foreach (var keyword in chinese)
        foreach (var label in (keyword == "QQ" ? new[] { keyword } : new[] { keyword, keyword.ToUpperInvariant(), keyword.ToLowerInvariant() }).Distinct())
        foreach (var separator in new[] { "", " ", ":", "：", ": ", " ： ", "是", "为", " 是 ", " 为： ", "=", "#" })
        foreach (var handle in new[] { "Ab9-Realtime", "trade_user", "中文联络标识" })
            Check(TradeNotificationEvent.SafeText("请查收 " + label + separator + handle + " 明天见") == "",
                "Chinese labels suppress the whole free-text field");
        foreach (var keyword in english)
        foreach (var label in new[] { keyword, keyword.ToUpperInvariant(), keyword.ToLowerInvariant() }.Distinct()) {
            foreach (var modifiers in new[] { "", " username", " id", " number", " no.", " no", " handle", " account", " information", " info", " username id", " user name", " nickname" })
            foreach (var separator in new[] { ":", "：", "#", "=", " : ", " ： " })
                Check(TradeNotificationEvent.SafeText("Please use " + label + modifiers + separator + "trade_user tomorrow") == "",
                    "English labels accept zero to two modifiers before a delimiter");
            foreach (var value in new[] { "123", "@short" })
            foreach (var modifiers in new[] { "", " id", " username id" })
                Check(TradeNotificationEvent.SafeText("Please use " + label + modifiers + " " + value) == "",
                    "English labels accept short numbers and at-signs");
            foreach (var suffix in new[] { " app updated", " username account id: abc" }.Where(_ => label != "QQ"))
                Check(TradeNotificationEvent.SafeText(label + suffix) == label + suffix,
                    "English labels require a delimiter or number within two modifier words");
        }
        foreach (var value in blocked.Concat(global).Concat(global.Select(value => "明天见 " + value)))
            Check(TradeNotificationEvent.SafeText(value) == "", "sensitive text uses whole-field suppression");
        foreach (var value in ordinary)
            Check(TradeNotificationEvent.SafeText(value) == value, "ordinary conversation remains unchanged");
        // CX-T23e proximity/token-size boundaries are obsolete: any Chinese label is sufficient.
        foreach (var fragment in new[] { "Ab9-x", "Ab9-xy", "Ab9-Realtime", "A1" + new string('x', 98), "A1" + new string('x', 99), "Abcdef", "1234--" })
        foreach (var gap in new[] { 0, 12, 13 }) {
            Check(TradeNotificationEvent.SafeText("明天见 " + fragment + new string(' ', gap) + "编号") == "",
                "Chinese labels suppress regardless of preceding token length or distance");
            Check(TradeNotificationEvent.SafeText("明天见 编号，" + new string(' ', gap) + fragment) == "",
                "Chinese labels suppress regardless of following token length or distance");
        }
        Check(TradeNotificationEvent.SafeText(new string('x', 4096)).Length == 200, "existing inclusive source limit and preview limit");
        // CX-T28 P3: nickname masking keeps whole text elements, never lone surrogates.
        Check(StarBridge.HostRuntime.Marketplace.MarketplaceRecords.Mask("👍") == "*", "single emoji nickname masks fully");
        Check(StarBridge.HostRuntime.Marketplace.MarketplaceRecords.Mask("👍🏽abc👨‍👩‍👧") == "👍🏽*****👨‍👩‍👧", "emoji nickname keeps whole first and last elements");
        Check(StarBridge.HostRuntime.Marketplace.MarketplaceRecords.Mask("Kestrel") == "K*****l", "plain nickname masking unchanged");
        Check(TradeNotificationEvent.SafeText(new string('x', 4097)) == "", "oversized source fails closed");
        Check(TradeNotificationEvent.SafeText("明天见 " + new string('x', 4090) + " 微信 trade_user") == "", "oversized sensitive source fails closed");
        Check(TradeNotificationEvent.SafeText("明天见\u202e") == "", "any bidi display reordering requests generic body");
        Check(TradeNotificationEvent.SafeText("...，!!! *** …") == "", "punctuation-only text still requests generic body");
        Console.WriteLine($"PASS CX-T23h redaction assertions: {checks} passed, 0 failed");
        return checks;
    }
}
