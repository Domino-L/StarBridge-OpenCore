using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

// Synthetic transport only: no sockets, real account storage, or credential reads/writes.
internal static class TradeNotificationTransactionIdTests
{
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new InvalidOperationException("No credential writes");
        public void DeleteRefreshToken(string key) { }
    }

    private sealed class DetailHttp : HttpMessageHandler
    {
        internal readonly List<string> Paths = [];
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method != HttpMethod.Get || request.RequestUri!.Host != "trade-notification-id.invalid" ||
                request.RequestUri.AbsolutePath != "/app-api/sc/order-transactions/get")
                throw new InvalidOperationException("Unexpected synthetic detail request");
            Paths.Add(request.RequestUri.PathAndQuery);
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) {
                Content = new StringContent("""{"code":0,"data":{"actorRole":"buyer","creatorType":0,"transactionStatus":1,"deliveryStatus":2}}""")
            });
        }
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

    internal static async Task<int> Run()
    {
        var checks = 0;
        void Check(bool valid, string label)
        {
            if (!valid) throw new InvalidOperationException("CX-T23c " + label);
            checks++;
        }
        var previousRoot = HostDataRoot.CurrentRoot;
        var root = Directory.CreateTempSubdirectory("cxt23c-id-").FullName;
        var originalOutput = Console.Out;
        using var output = new StringWriter();
        try
        {
            HostDataRoot.UsePreparedRoot(root);
            Console.SetOut(output);
            var uri = new Uri("https://trade-notification-id.invalid/");
            var http = new DetailHttp();
            var oauth = new OAuthPkceClient(new ScmHttpClient(http), new Vault(),
                new("fixture", uri, uri, uri, "fixture", "fixture", "", "/callback"));
            var session = new ScmOAuthSession("fixture", "synthetic-owner", "Fixture", "synthetic-only",
                DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "trade.read", "trade.write"]);
            var owner = OAuthPkceClient.ChatOwner(session);
            var context = new BridgeAccountContext("fixture", "scm", "synthetic-owner");
            var sink = new Desktop();
            // These settings belong only to this test's TEMP root.
            File.WriteAllText(Path.Combine(root, "notification-settings.v1.json"),
                """{"schemaVersion":1,"revision":0,"inAppEnabled":true,"position":"bottomRight","preview":"fullContent","windowsEnabled":true,"tradeWindowsEnabled":true}""");
            long sequence = 0;
            using var settings = new NotificationSettingsBridgeDispatcher(root, () => 1, () => true,
                desktop: sink, activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, ++sequence, payload));
            var events = new List<BridgeEnvelope>();
            settings.EventReady += events.Add;
            const string top = "Ab9-Priority";
            const string nested = "Cd8-Nested";
            const string template = "Ef7-Template";
            const string body = "用户 Kestrel 申请购买您的Aurora，数量：1，交易编号：" + template + "，联系方式：hidden";
            var rawNumbers = new HashSet<string>(StringComparer.Ordinal) { top, nested, template };
            long id = 10000;

            async Task Verify(object? candidate, object? order, bool hasTemplate, string? expected,
                bool reminder = false, bool missing = false)
            {
                var orderNumber = TradeNotificationEvent.TextField(JsonSerializer.SerializeToElement(order), "transactionId");
                var displayNumbers = string.Join(" ", new[] { candidate as string, orderNumber, hasTemplate ? template : null });
                var row = new Dictionary<string, object?> {
                    ["id"] = ++id, ["type"] = reminder ? 0 : 1, ["subType"] = 1,
                    ["title"] = reminder ? "收货提醒" : "交易提醒 " + displayNumbers,
                    ["content"] = reminder ? "您的订单Aurora已发货超过1小时，请尽快确认收货。" : hasTemplate ? body : "",
                    ["isRead"] = false, ["orderInfo"] = order,
                };
                if (!missing) {
                    row["transactionId"] = candidate;
                    // All three new fields may have any JSON shape; only the transaction string is used.
                    row["orderId"] = new { ignored = true };
                    row["productId"] = new[] { "ignored" };
                }
                if (candidate is string { Length: > 0 } candidateText) rawNumbers.Add(candidateText);
                var notice = oauth.ProjectTradeNotification(owner, JsonSerializer.SerializeToElement(row));
                Check(notice is not null, "station shape remains accepted");
                Check((notice!.Reference is { Length: 32 }) == (expected is not null), "reference availability");
                if (expected is not null) {
                    Check(oauth.ResolveNotificationTradeReference(owner, notice.Reference!) == expected, "priority and validation");
                    var beforeRequests = http.Paths.Count;
                    await oauth.MarketplaceTradeAsync(session,
                        BridgePayload.From(new { schemaVersion = 1, operation = "detail", transactionRef = notice.Reference }),
                        () => true, default);
                    Check(http.Paths.Count == beforeRequests + 1 && http.Paths[^1] ==
                        "/app-api/sc/order-transactions/get?transactionNumber=" + expected,
                        "detail resolves opaque reference to exact number inside fake transport");
                }
                var beforeEvents = events.Count;
                await settings.PresentTradeAsync(context, 1, notice, () => true);
                var card = sink.Notices.Last();
                card.Diagnostic?.Invoke("windowShown");
                card.Activated!();
                Check(events.Count == beforeEvents + 1 && events[^1].Name == "notificationSettings.activated", "shared activation event");
                var activation = (await settings.DispatchAsync(BridgeEnvelope.Request("notificationSettings.consumeActivation",
                    Guid.NewGuid().ToString("N"), 1, events[^1].Payload))).Response;
                Check(activation.Status == "ok" && activation.Payload.GetProperty("destination").GetString() ==
                    (expected is null ? "myTrades" : "trade"), "activation destination");
                Check((activation.Payload.TryGetProperty("ref", out var eventRef) ? eventRef.GetString() : null) == notice.Reference,
                    "activation forwards only the opaque reference");
                var exposed = JsonSerializer.Serialize(notice) + JsonSerializer.Serialize(card.Trade) +
                    JsonSerializer.Serialize(events[^1]) + JsonSerializer.Serialize(activation);
                // Even lower-priority candidates repeated in title/item fields must be removed.
                foreach (var number in new[] { candidate as string, expected, orderNumber, hasTemplate ? template : null }
                    .Where(n => !string.IsNullOrEmpty(n)))
                    Check(!exposed.Contains(number!, StringComparison.Ordinal), "no raw number on notification surfaces");
                Check(!exposed.Contains("transactionId", StringComparison.Ordinal) &&
                    !exposed.Contains("orderId", StringComparison.Ordinal) && !exposed.Contains("productId", StringComparison.Ordinal),
                    "new source fields are not forwarded");
            }

            var order = new { transactionId = nested, productName = "Aurora " + top + " " + nested, traderName = "Kestrel" };
            await Verify(top, null, false, top);
            await Verify(top, order, true, top);
            await Verify(top, null, false, top, reminder: true);
            await Verify("bad space", order, false, nested, reminder: true);
            await Verify(12345, null, false, null, reminder: true);
            // Boundary lengths and the complete accepted ASCII alphabet are not trimmed/truncated/coerced.
            await Verify(new string('a', 100), null, false, new string('a', 100));
            await Verify("Z", null, false, "Z");
            await Verify("azAZ09-", null, false, "azAZ09-");
            foreach (var invalid in new object?[] { null, "", "bad space", " leading", "trailing ",
                new string('x', 101), "bad_id", "编号", "Ａ１", "abc\n", "abc/def", 12345, true,
                new { value = top }, new[] { top } })
            {
                await Verify(invalid, order, true, nested);
                await Verify(invalid, null, true, template);
                await Verify(invalid, null, false, null);
            }
            await Verify(null, order, false, nested, missing: true);
            await Verify(null, null, true, template, missing: true);
            await Verify(null, null, false, null, missing: true);
            await Verify(null, null, false, null, reminder: true, missing: true);
            foreach (var invalidOrder in new object?[] { null, 42, "wrong", new { transactionId = 42 },
                new { transactionId = "bad space" }, new { transactionId = new string('x', 101) } })
                await Verify("bad space", invalidOrder, true, template);
            // The pre-existing page projection ignores the newly added top-level metadata.
            var oldRow = JsonSerializer.SerializeToElement(new { id = 1, type = 0, title = "公告" });
            var newRow = JsonSerializer.SerializeToElement(new { id = 1, type = 0, title = "公告",
                transactionId = top, orderId = 42, productId = 24 });
            Check(JsonSerializer.Serialize(StarBridge.HostRuntime.Marketplace.MarketplaceNotices.Notice(oldRow, _ => "")) ==
                JsonSerializer.Serialize(StarBridge.HostRuntime.Marketplace.MarketplaceNotices.Notice(newRow, _ => "")),
                "page contract ignores optional top-level metadata");
            var diagnostics = string.Join("\n", Directory.EnumerateFiles(root, "*.log", SearchOption.AllDirectories).Select(File.ReadAllText));
            Check(diagnostics.Contains("marketplace-trade") && diagnostics.Contains("NativeLifecycle"), "privacy checks cover actual diagnostic output");
            foreach (var number in rawNumbers.Where(n => n.Length > 1)) {
                Check(!diagnostics.Contains(number, StringComparison.Ordinal), "diagnostics omit raw candidates");
                Check(!output.ToString().Contains(number, StringComparison.Ordinal), "console log omits raw candidates");
            }
            return checks;
        }
        finally
        {
            Console.SetOut(originalOutput);
            HostDataRoot.UsePreparedRoot(previousRoot);
            Directory.Delete(root, true);
        }
    }
}
