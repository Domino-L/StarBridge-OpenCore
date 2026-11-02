using System.Net;
using System.Reflection;
using System.Text.Json;
using System.Text.RegularExpressions;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.NativeBridge;

internal static class NotificationInboxScmMessagesTests
{
    private static void Check(bool condition, string message)
    { if (!condition) throw new Exception(message); }

    internal static async Task Run()
    {
        await Merge();
        await Failures();
        await Marks();
        await Leases();
        await PushCacheAndReceipts();
        await PollFallback();
        await NotificationInboxReadBoundaryTests.Run();
    }

    private static async Task Merge()
    {
        using var f = new Fixture();
        var first = await f.Read();
        var items = first.GetProperty("items").EnumerateArray().ToArray();
        Check(items.Length == 5, "merge includes relay plus SCM, excludes friend chat");
        Check(first.GetProperty("unreadCount").GetInt32() == items.Count(x => !x.GetProperty("read").GetBoolean()), "unread count matches merged rows");
        var times = items.Select(x => x.GetProperty("createdAt").GetDateTimeOffset()).ToArray();
        Check(times.SequenceEqual(times.OrderDescending()), "merged timestamps descend");
        var trade = items.Single(x => x.GetProperty("category").GetString() == "trade");
        Check(trade.GetProperty("priority").GetString() == "action_required" && trade.GetProperty("actionTarget").GetString() == "marketplace_trade", "trade action mapping");
        Check(trade.GetProperty("title").GetString()!.Length <= 200 && trade.GetProperty("body").GetString()!.Length <= 200, "inbox text uses the trade notification privacy bound");
        var chat = items.Single(x => x.GetProperty("category").GetString() == "tradeChat");
        Check(chat.GetProperty("actionTarget").GetString() == "marketplace_chat" && chat.GetProperty("priority").GetString() == "normal", "chat mapping");
        Check(items.All(x => Regex.IsMatch(x.GetProperty("reference").GetString()!, "^[0-9a-f]{32}$") && x.GetProperty("isAvailable").GetBoolean()), "opaque reference shape and availability");
        var wire = first.GetRawText();
        Check(!wire.Contains("987654321") && !wire.Contains("876543219") && !wire.Contains("private-product") && !wire.Contains("senderId") && !wire.Contains("scm:"), "private identifiers and product URLs never projected");
        var expected = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(System.Text.Encoding.UTF8.GetBytes(JsonSerializer.Serialize(f.Host.CurrentContext) + "\nscm:11"))).ToLowerInvariant();
        Check(trade.GetProperty("eventKey").GetString() == expected, "SCM event key uses context and prefixed id");
        var again = (await f.Read()).GetProperty("items").EnumerateArray().ToArray();
        Check(!items.Select(Reference).Intersect(again.Select(Reference)).Any(), "each read issues fresh references");
        Check(items.Select(x => x.GetProperty("eventKey").GetString()).SequenceEqual(again.Select(x => x.GetProperty("eventKey").GetString())), "event keys stable across reads");
        Check(f.Scm.Reads == 2 && f.Scm.LastQuery == "?pageNo=1&pageSize=50", "only page one with fifty rows");
        f.Scm.Many = true;
        Check((await f.Read()).GetProperty("items").GetArrayLength() == 51, "at most fifty SCM rows");
        foreach (var subtype in new[] { 1, 2, 4, 6, 7 })
        {
            f.Scm.Many = false; f.Scm.Subtype = subtype;
            var row = (await f.Read()).GetProperty("items").EnumerateArray().Single(x => x.GetProperty("category").GetString() == "trade");
            Check(row.GetProperty("priority").GetString() == (subtype is 1 or 4 or 6 ? "action_required" : "normal"), "trade subtype priority");
        }
        Console.WriteLine("PASS CX04 merge, sort, unread count, bounded private projection, references and event keys");
    }

    private static async Task Failures()
    {
        foreach (var mode in new[] { "401", "403", "404", "timeout", "malformed" })
        {
            using var f = new Fixture(); f.Scm.Failure = mode;
            var result = await f.Read();
            Check(result.GetProperty("items").GetArrayLength() == 1 && result.GetProperty("unreadCount").GetInt32() == 1, "SCM " + mode + " degrades to relay");
        }
        using var noScope = new Fixture([]);
        Check((await noScope.Read()).GetProperty("items").GetArrayLength() == 1 && noScope.Scm.Reads == 0, "no profile.read means no SCM request");
        using var cancelled = new Fixture();
        using var cts = new CancellationTokenSource(); cts.Cancel();
        try { await cancelled.Host.ReadNotificationInboxAsync(cancelled.Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1 }), cts.Token); throw new Exception("cancellation swallowed"); }
        catch (OperationCanceledException) { }
        Console.WriteLine("PASS CX04 read failure fallback, scope and caller cancellation");
    }

    private static async Task Marks()
    {
        using var f = new Fixture();
        var rows = (await f.Read()).GetProperty("items").EnumerateArray().ToArray();
        Check((await f.Mark(rows)).GetProperty("confirmed").GetBoolean(), "mixed marks confirmed");
        Check(f.Relay.Marked.SequenceEqual(new[] { "relay-one" }) && f.Scm.Marked.Order().SequenceEqual(new long[] { 11, 12, 13, 14 }), "marks routed to their owners");
        foreach (var mode in new[] { "403", "timeout", "false" })
        {
            using var failed = new Fixture();
            var all = (await failed.Read()).GetProperty("items").EnumerateArray().ToArray();
            failed.Scm.Failure = mode;
            Check(!(await failed.Mark(all)).GetProperty("confirmed").GetBoolean() && failed.Scm.Writes == 1, "SCM write failure not confirmed or retried: " + mode);
        }
        using var readOnly = new Fixture(["profile.read"]);
        var readOnlyRows = (await readOnly.Read()).GetProperty("items").EnumerateArray().ToArray();
        Check(!(await readOnly.Mark(readOnlyRows)).GetProperty("confirmed").GetBoolean() && readOnly.Scm.Writes == 0, "profile.write required");
        using var only = new Fixture();
        var scmOnly = (await only.Read()).GetProperty("items").EnumerateArray().Where(x => x.GetProperty("category").GetString() == "trade").ToArray();
        Check((await only.Mark(scmOnly)).GetProperty("confirmed").GetBoolean() && only.Relay.Writes == 0, "SCM-only marks skip relay");
        Console.WriteLine("PASS CX04 mixed marks, SCM-only marks, scope and no write retries");
    }

    private static async Task Leases()
    {
        using var f = new Fixture();
        var oldRows = (await f.Read()).GetProperty("items").EnumerateArray().ToArray();
        await f.Read();
        await Reject(() => f.Mark(oldRows), "notificationInbox.invalid_request");
        var rows = (await f.Read()).GetProperty("items").EnumerateArray().ToArray();
        var leaseField = typeof(ScmAccountBridgeHost).GetField("_inboxLease", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var lease = leaseField.GetValue(f.Host)!;
        lease.GetType().GetProperty("Expires")!.SetValue(lease, DateTimeOffset.UtcNow.AddMinutes(-1));
        await Reject(() => f.Mark(rows), "notificationInbox.stale");
        rows = (await f.Read()).GetProperty("items").EnumerateArray().ToArray();
        using var other = new Fixture(subject: "second-fixture");
        leaseField.SetValue(other.Host, leaseField.GetValue(f.Host));
        await Reject(() => other.Mark(rows), "notificationInbox.stale");
        Check(f.Scm.Writes == 0 && f.Relay.Writes == 0 && other.Scm.Writes == 0, "stale or cross-account leases never write");
        Console.WriteLine("PASS CX04 replaced, expired and cross-account leases reject writes");
    }

    private static async Task PushCacheAndReceipts()
    {
        using var f = new Fixture();
        using var runtime = new StarBridge.HostRuntime.AccountBridgeRuntime(f.Host);
        var events = new List<BridgeEnvelope>();
        runtime.EventReady += events.Add;
        void Push(bool healthy) => typeof(ScmAccountBridgeHost).GetMethod("ObserveInboxPush", BindingFlags.NonPublic | BindingFlags.Instance)!
            .Invoke(f.Host, [healthy]);
        await f.Read(true); await f.Read(true);
        Check(f.Scm.Reads == 2, "Unhealthy source reads SCM on every existing 60-second poll");
        Push(true);
        var first = await f.Read(true);
        await f.Read(true); await f.Read(true);
        Check(f.Scm.Reads == 3 && f.Relay.Reads == 5 && first.GetProperty("scmPushHealthy").GetBoolean(),
            "Acknowledged push caches only SCM; Relay is still read on each poll");
        var pageField = typeof(ScmAccountBridgeHost).GetField("_inboxScmPage", BindingFlags.NonPublic | BindingFlags.Instance)!;
        var page = pageField.GetValue(f.Host)!;
        page.GetType().GetProperty("ReadAt")!.SetValue(page, DateTimeOffset.UtcNow.AddSeconds(-301));
        await f.Read(true);
        Check(f.Scm.Reads == 4, "Healthy source still fetches page one after five minutes");
        Push(true); await f.Read(true);
        Check(f.Scm.Reads == 5, "Each new message or unread acknowledgement invalidates cached SCM page");
        Push(false); await f.Read(true); await f.Read(true);
        Check(f.Scm.Reads == 7, "Disconnect restores reading SCM on every poll immediately");
        var inboxEvents = events.Where(x => x.Name == "notificationInbox.changed").ToArray();
        Check(inboxEvents.Length == 3 && inboxEvents.All(x => x.SessionGeneration == f.Host.Generation &&
            x.Payload.EnumerateObject().Count() == 2 && x.Payload.GetProperty("schemaVersion").GetInt32() == 1),
            "Runtime publishes only schema and health, never source identifiers or message bodies");
        var stationOwner = OAuthPkceClient.ChatOwner(f.HostFixtureSession);
        var row = JsonSerializer.SerializeToElement(new { id = 11, type = 1, subType = 4, title = "Shipped", isRead = false });
        var trade = f.OAuth.ProjectTradeNotification(stationOwner, row)!;
        var observer = new StarBridge.HostRuntime.Notifications.TradeNotificationObserver();
        Check(observer.Observe(f.Host.CurrentContext!, f.Host.Generation, trade) is not null, "First live trade notice may alert");
        var read = await f.Read(true);
        Check(observer.Observe(f.Host.CurrentContext!, f.Host.Generation, trade) is null, "Inbox readback does not create a second trade alert for the same message id");
        var selected = read.GetProperty("items").EnumerateArray().Where(x => x.GetProperty("category").GetString() == "trade").ToArray();
        await f.Mark(selected);
        Check(!f.OAuth.StationNotificationUnread(stationOwner, trade) && f.OAuth.ProjectTradeNotification(stationOwner, row) is null,
            "Confirmed inbox read retires pending trade cards and suppresses a delayed duplicate push");
        Check(events.Any(x => x.Name == "marketplace.changed"), "Inbox mark also invalidates the existing marketplace reader");
        Check((await f.Read(true)).GetProperty("items").EnumerateArray().Single(x => x.GetProperty("category").GetString() == "trade").GetProperty("read").GetBoolean(),
            "Authoritative readback shows the same read state");
        var other = f.OAuth.ProjectTradeNotification("other-owner", row);
        Check(other is not null, "Receipt state cannot cross account owners");
        f.Scm.Failure = "false";
        var second = f.OAuth.ProjectTradeNotification(stationOwner, JsonSerializer.SerializeToElement(new { id = 15, type = 1, subType = 4 }))!;
        await f.Host.MarketplaceNoticesAsync(f.Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, operation = "read", id = 15 }), default);
        Check(f.OAuth.StationNotificationUnread(stationOwner, second), "Unconfirmed marketplace mark cannot suppress unread trade alerts");
        f.Scm.Failure = null;
        await f.Host.MarketplaceNoticesAsync(f.Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, operation = "read", id = 15 }), default);
        Check(!f.OAuth.StationNotificationUnread(stationOwner, second), "Marketplace mark uses the same confirmed receipt authority");
        Check(events.Count(x => x.Name == "notificationInbox.changed") == 5, "Confirmed marks from either surface invalidate inbox; failed marks do not");
        f.Scm.SensitiveText = true;
        var sanitized = (await f.Read(true)).GetRawText();
        Check(!sanitized.Contains("TXN-private-123") && !sanitized.Contains("987654321") && !sanitized.Contains("876543219"),
            "SCM members and transaction numbers embedded in display text never reach Flutter");
        using var manual = new Fixture();
        typeof(ScmAccountBridgeHost).GetMethod("ObserveInboxPush", BindingFlags.NonPublic | BindingFlags.Instance)!.Invoke(manual.Host, [true]);
        await manual.Read(true); await manual.Read(true);
        Check(manual.Scm.Reads == 1, "Passive healthy polls may reuse SCM");
        await manual.Read();
        Check(manual.Scm.Reads == 2, "Manual refresh bypasses the healthy cache immediately");
        Console.WriteLine("PASS CX-L06 healthy five-minute SCM cache, unchanged Relay polls, bidirectional receipts and message-id dedup");
    }

    private static async Task Reject(Func<Task<JsonElement>> call, string code)
    {
        try { await call(); throw new Exception("invalid lease accepted"); }
        catch (AccountBridgeHostException e) when (e.Code == code) { }
    }
    // Hotfix 10-29: the relay socket carries no station pushes, so the existing 60-second inbox read
    // raises trade cards for new unread trade station messages. First read is history only.
    private static async Task PollFallback()
    {
        using var f = new Fixture();
        var cards = new List<StarBridge.HostRuntime.Notifications.TradeNotificationEvent>();
        f.Host.MarketplaceNoticePushed += (_, _, notice) => cards.Add(notice);
        await f.Read();
        Check(cards.Count == 0, "The first inbox read only sets the baseline; existing unread trade messages never pop");
        f.Scm.Extra.Add((21, 1));
        await f.Read();
        Check(cards.Count == 1 && cards[0].Key == StarBridge.HostRuntime.Notifications.TradeNotificationEvent.KeyFor("station", 21) &&
            cards[0].SubType == 4 && !cards[0].Chat, "A new unread trade station message found by the poll raises one card");
        await f.Read(); await f.Read();
        Check(cards.Count == 1, "The same message never raises a second card on later polls");
        f.Scm.Marked.Add(22); f.Scm.Extra.Add((22, 1));
        f.Scm.Extra.Add((23, 2)); f.Scm.Extra.Add((24, 0));
        await f.Read();
        Check(cards.Count == 1, "Already-read trade messages, trade-chat fallbacks and system messages never pop");
        // A trading-hall page read sees a new message first; the poll still raises its card once.
        f.Scm.Extra.Add((25, 1));
        var session = f.HostFixtureSession;
        await f.OAuth.MarketplaceNoticesAsync(session, BridgePayload.From(new { schemaVersion = 1, operation = "page", page = 1 }),
            () => true, default);
        Check(cards.Count == 1, "Trading-hall page reads never raise cards themselves");
        await f.Read();
        Check(cards.Count == 2 && cards[1].Key == StarBridge.HostRuntime.Notifications.TradeNotificationEvent.KeyFor("station", 25),
            "Hall reads do not suppress the poll's first sighting");
        // Several new messages in one poll arrive oldest first.
        f.Scm.Extra.Add((26, 1)); f.Scm.Extra.Add((27, 1));
        await f.Read();
        Check(cards.Count == 4 && cards[2].Key == StarBridge.HostRuntime.Notifications.TradeNotificationEvent.KeyFor("station", 26) &&
            cards[3].Key == StarBridge.HostRuntime.Notifications.TradeNotificationEvent.KeyFor("station", 27), "Batch is delivered oldest first");
        Console.WriteLine("PASS hotfix 10-29 inbox poll raises trade cards: baseline, once per message, unread trade only, hall reads isolated");
        await PollFallbackRaces();
    }

    // CX-T34: a first poll racing a pending "read all" that then fails, and a stale read after re-login.
    private static async Task PollFallbackRaces()
    {
        using (var f = new Fixture())
        {
            var cards = new List<StarBridge.HostRuntime.Notifications.TradeNotificationEvent>();
            f.Host.MarketplaceNoticePushed += (_, _, notice) => cards.Add(notice);
            var owner = OAuthPkceClient.ChatOwner(f.HostFixtureSession);
            var gate = new object();
            var capture = typeof(OAuthPkceClient).GetMethod("CaptureStationRead", BindingFlags.NonPublic | BindingFlags.Instance)!;
            var finish = typeof(OAuthPkceClient).GetMethod("FinishStationRead", BindingFlags.NonPublic | BindingFlags.Instance)!;
            // "Read all" in flight during the very first poll, then it fails (no confirm, just finish).
            var pending = capture.Invoke(f.OAuth, [owner, (Func<bool>)(() => true), gate, null, true])!;
            await f.Read();
            finish.Invoke(f.OAuth, [pending]);
            await f.Read(); await f.Read();
            Check(cards.Count == 0, "Rows skipped during a pending read-all never pop later when that read-all fails");
            f.Scm.Extra.Add((31, 1));
            await f.Read();
            Check(cards.Count == 1, "A genuinely new message after the race still pops once");
        }
        using (var f = new Fixture())
        {
            var cards = new List<StarBridge.HostRuntime.Notifications.TradeNotificationEvent>();
            f.Host.MarketplaceNoticePushed += (_, _, notice) => cards.Add(notice);
            var handler = typeof(ScmAccountBridgeHost).GetMethod("OnStationTradeDiscovered", BindingFlags.NonPublic | BindingFlags.Instance)!;
            await f.Read();
            f.Scm.Extra.Add((32, 1));
            // Capture the poll's event and replay it as if it arrived after the read went stale.
            var seen = new List<(string Owner, StarBridge.HostRuntime.Notifications.TradeNotificationEvent Notice, Func<bool> Current)>();
            void Spy(string o, StarBridge.HostRuntime.Notifications.TradeNotificationEvent n, Func<bool> current) => seen.Add((o, n, current));
            f.OAuth.StationTradeDiscovered += Spy;
            await f.Read();
            f.OAuth.StationTradeDiscovered -= Spy;
            Check(seen.Count == 1 && cards.Count == 1 && seen[0].Current(), "The live read still pops normally; its real predicate holds");
            // 1. Receipt epoch moves on (account cleared / re-login): the real predicate turns false.
            f.OAuth.ClearNotificationTradeReferences();
            Check(!seen[0].Current(), "Clearing receipts invalidates the read's own predicate");
            handler.Invoke(f.Host, [seen[0].Owner, seen[0].Notice, seen[0].Current]);
            Check(cards.Count == 1, "An event from a read before the epoch change never publishes");
        }
        using (var f = new Fixture())
        {
            var cards = new List<StarBridge.HostRuntime.Notifications.TradeNotificationEvent>();
            f.Host.MarketplaceNoticePushed += (_, _, notice) => cards.Add(notice);
            var handler = typeof(ScmAccountBridgeHost).GetMethod("OnStationTradeDiscovered", BindingFlags.NonPublic | BindingFlags.Instance)!;
            await f.Read();
            f.Scm.Extra.Add((33, 1));
            var seen = new List<(string Owner, StarBridge.HostRuntime.Notifications.TradeNotificationEvent Notice, Func<bool> Current)>();
            void Spy(string o, StarBridge.HostRuntime.Notifications.TradeNotificationEvent n, Func<bool> current) => seen.Add((o, n, current));
            f.OAuth.StationTradeDiscovered += Spy;
            await f.Read();
            f.OAuth.StationTradeDiscovered -= Spy;
            // 2. Same account, new Host generation (sign-out and back in): the read's context check fails.
            var generation = typeof(ScmAccountBridgeHost).GetField("_generation", BindingFlags.NonPublic | BindingFlags.Instance)!;
            generation.SetValue(f.Host, (long)generation.GetValue(f.Host)! + 1);
            Check(!seen[0].Current(), "A newer Host generation invalidates the read's own predicate");
            handler.Invoke(f.Host, [seen[0].Owner, seen[0].Notice, seen[0].Current]);
            Check(cards.Count == 1, "An event from the previous generation is never re-stamped with the current generation");
        }
        Console.WriteLine("PASS hotfix 10-29 poll races: pending read-all never seeds old cards; stale reads never publish");
    }

    private static string Reference(JsonElement row) => row.GetProperty("reference").GetString()!;
    private sealed class Fixture : IDisposable
    {
        internal readonly ScmHandler Scm = new();
        internal readonly RelayHandler Relay = new();
        internal readonly ScmAccountBridgeHost Host;
        private readonly AccountSafetyClient _safety;
        internal readonly OAuthPkceClient OAuth;
        internal readonly ScmOAuthSession HostFixtureSession;
        // A throwaway profile cache, never inside the repository or a real data root.
        private readonly string _root = Directory.CreateTempSubdirectory("starbridge-inbox-scm-").FullName;
        internal Fixture(string[]? scopes = null, string subject = "fixture-owner")
        {
            var uri = new Uri("https://fixture.invalid/");
            OAuth = new OAuthPkceClient(new ScmHttpClient(Scm), new Vault(), new("fixture", uri, uri, uri, "desktop", "api", "", "/callback"));
            HostFixtureSession = new("fixture", subject, "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), scopes ?? ["profile.read", "profile.write"]);
            _safety = new AccountSafetyClient(uri, Relay);
            Host = new(OAuth, new ScmProfileCacheStore(_root), "fixture", () => null,
                HostFixtureSession, 1, accountSafety: _safety);
        }
        internal async Task<JsonElement> Read(bool allowScmCache = false) => BridgePayload.From(await Host.ReadNotificationInboxAsync(Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, allowScmCache }), default));
        internal async Task<JsonElement> Mark(JsonElement[] rows) => BridgePayload.From(await Host.MarkNotificationInboxReadAsync(Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, references = rows.Select(Reference).ToArray() }), default));
        public void Dispose()
        {
            Host.Dispose(); _safety.Dispose(); Scm.Dispose();
            try { Directory.Delete(_root, true); } catch (IOException) { }
        }
    }
    private static HttpResponseMessage Response(object data) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(data, new JsonSerializerOptions(JsonSerializerDefaults.Web))) };
    private sealed class RelayHandler : HttpMessageHandler
    {
        internal readonly List<string> Marked = [];
        internal int Writes, Reads;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method == HttpMethod.Post)
            {
                Check(request.RequestUri!.AbsolutePath == "/api/notifications/read", "relay mark route");
                Writes++;
                using var doc = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Marked.AddRange(doc.RootElement.GetProperty("notificationIds").EnumerateArray().Select(x => x.GetString()!));
                return Response(new NotificationReadResponseContract(Marked.Count, DateTimeOffset.UtcNow));
            }
            Check(request.RequestUri!.AbsolutePath == "/api/notifications", "relay read route");
            Reads++;
            var time = DateTimeOffset.FromUnixTimeMilliseconds(1760000000002);
            return Response(new NotificationInboxContract([
                new("relay-one", "system", "normal", "Relay", "Body", time, null, "", "", null, "system", "test"),
                new("relay-chat", "social", "normal", "Chat", "Body", time, null, "", "friend_chat", null, "system", "test")
            ], 2, 0, time));
        }
    }
    private sealed class ScmHandler : HttpMessageHandler
    {
        internal int Reads, Writes, Subtype = 4;
        internal string? Failure, LastQuery;
        internal bool Many, SensitiveText;
        internal readonly List<long> Marked = [];
        // Newer rows placed on top of page one (id, type); later entries are newer.
        internal readonly List<(int Id, int Type)> Extra = [];
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var write = request.Method == HttpMethod.Put;
            Check(request.RequestUri!.AbsolutePath == (write ? "/app-api/member/message/mark-read" : "/app-api/member/message/page"), "SCM route");
            if (write) Writes++; else { Reads++; LastQuery = request.RequestUri.Query; }
            if (Failure == "timeout") throw new TaskCanceledException("fixture timeout");
            if (int.TryParse(Failure, out var status)) return new((HttpStatusCode)status) { Content = new StringContent("{}") };
            if (Failure == "malformed") return Response(new { code = 0, data = "invalid" });
            if (write)
            {
                using var doc = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                Marked.Add(doc.RootElement.GetProperty("id").GetInt64());
                return Response(new { code = 0, data = Failure != "false" });
            }
            object Message(int id, int type, object time, bool read = false) => new {
                id, type, subType = Subtype, title = SensitiveText ? "TXN-private-123 987654321 876543219" : type == 1 ? new string('T', 2100) : "Fixture",
                content = type == 1 ? new string('B', 20100) : "Body", isRead = read || Marked.Contains(id) ? 1 : 0, createTime = time,
                userId = 987654321, senderId = 876543219,
                orderInfo = new { transactionId = "TXN-private-123", traderId = 876543219, productUrl = "https://fixture.invalid/private-product" }
            };
            var list = Many ? Enumerable.Range(1, 60).Select(id => Message(id, 0, 1760000000000L)).ToArray() :
                Extra.AsEnumerable().Reverse().Select(e => Message(e.Id, e.Type, 1760000001000L + e.Id))
                    .Concat(new[] { Message(11, 1, 1760000000004L), Message(12, 2, 1760000000003L), Message(13, 0, "2025-10-09T08:53:20Z", true), Message(14, 0, "2025-10-09 08:53:19") })
                    .ToArray();
            return Response(new { code = 0, data = new { list, total = list.Length } });
        }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new Exception("fixture must not persist credentials");
        public void DeleteRefreshToken(string key) => throw new Exception("fixture must not delete credentials");
    }
}
