using System.Net;
using System.Reflection;
using System.Text.Json;
using StarBridge.Core.TrustSafety;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class NotificationInboxReadBoundaryTests
{
    private static int _checks;
    private static void Check(bool condition, string message)
    {
        _checks++;
        if (!condition) throw new Exception(message);
    }

    internal static async Task Run()
    {
        _checks = 0;
        var failures = new List<string>();
        var cases = new (string, Func<Task>)[] {
            ("readAll snapshot", Snapshot), ("late unknown and typed readAll", Unknown),
            ("old generation response", Generation), ("partial false", () => Partial("false")),
            ("partial timeout", () => Partial("timeout")), ("8192 receipts", Capacity),
            ("unknown authority failures", AuthorityFailures),
            ("marketplace read confirmed cancellation", () => MarketplaceReadBoundary("cancel", "read")),
            ("marketplace readAll confirmed cancellation", () => MarketplaceReadBoundary("cancel", "readAll")),
            ("marketplace confirmed success", () => MarketplaceReadBoundary("success")),
            ("marketplace confirmed old generation", () => MarketplaceReadBoundary("generation")),
            ("marketplace false", () => MarketplaceReadBoundary("false")),
            ("marketplace unknown timeout", () => MarketplaceReadBoundary("timeout")) };
        foreach (var (name, run) in cases)
        {
            try { await run(); Console.WriteLine("PASS L06b " + name); }
            catch (Exception e) { failures.Add(name); Console.WriteLine("FAIL L06b " + name + ": " + e.Message); }
        }
        Console.WriteLine($"L06b groups {cases.Length - failures.Count}/{cases.Length}; checks {_checks}; failures {failures.Count}");
        if (failures.Count > 0) throw new Exception("L06b: " + string.Join(", ", failures));
    }

    private static async Task Snapshot()
    {
        using var f = new Fixture();
        f.Scm.Add(900, 1); f.Scm.Add(17, 0);
        var card = f.Push(900)!;
        Check(card is not null, "known card is pending before readAll");
        using var cards = new Cards(f);
        var pending = await cards.Queue(card);
        await f.Page(); // Both existing REST readers must register IDs.
        f.Scm.HoldAll = true;
        var write = f.All();
        await f.Scm.AllApplied.Task.WaitAsync(TimeSpan.FromSeconds(5));
        // IDs deliberately descend: numeric order is not a delivery boundary.
        f.Scm.Add(8, 1);
        var during = f.PushAsync(8);
        f.Scm.ReleaseAll.TrySetResult();
        Check((await write).GetProperty("data").GetProperty("confirmed").GetBoolean(), "readAll confirmed");
        var fresh = await during;
        f.Scm.Add(3, 1);
        var after = await f.PushAsync(3);
        Check(!f.Unread(card) && f.Push(900) is null, "known confirmed card and duplicate retired");
        Check(f.Push(17, 0) is null, "IDs learned only from the marketplace REST page belong to the frozen scope");
        Check(fresh is not null && f.Unread(fresh) && after is not null && f.Unread(after), "new arrivals around old response remain unread");
        Check(!pending.IsCurrent() && (await cards.Queue(fresh!)).IsCurrent(), "real pending native cards follow snapshot receipt eligibility");
        pending.Activated!();
        Check(cards.Activations == 0, "confirmed old card cannot activate");
        var rest = (await f.Page()).GetProperty("data").GetProperty("rows").EnumerateArray().ToArray();
        Check(rest.Single(x => x.GetProperty("id").GetInt64() == 900).GetProperty("read").GetBoolean(), "REST agrees for confirmed ID");
        Check(!rest.Single(x => x.GetProperty("id").GetInt64() == 8).GetProperty("read").GetBoolean(), "REST agrees for new ID");
        var observer = new TradeNotificationObserver();
        Check(observer.Observe(f.Host.CurrentContext!, f.Host.Generation, fresh!) is not null &&
            observer.Observe(f.Host.CurrentContext!, f.Host.Generation, (await f.PushAsync(8))!) is null, "new unread alerts once");
    }

    private static async Task Unknown()
    {
        using var f = new Fixture();
        // Unknown old frame lives beyond page one; a page-one-only probe cannot prove it read.
        f.Scm.Add(700, 1);
        for (var id = 100; id < 160; id++) f.Scm.Add(id, 1);
        f.Scm.Add(2, 0);
        var unaffected = f.Push(2, 0)!;
        var knownTyped = f.Push(159)!;
        await f.All(1);
        Check(!f.Unread(knownTyped) && f.Push(159) is null, "typed readAll retires known matching type");
        Check(await f.PushAsync(700) is null && f.Push(700) is null, "unregistered late old frame reconciles to read and never alerts");
        Check(f.Scm.Reads == 2, "unknown old ID is found beyond authoritative page one");
        Check(f.Unread(unaffected), "typed readAll leaves other type unread");
        f.Scm.Add(1, 1);
        var fresh = await f.PushAsync(1);
        Check(fresh is not null && f.Unread(fresh), "unknown new nonmonotonic ID must reconcile to unread, not a blanket tombstone");
        await f.All();
        Check(!f.Unread(unaffected) && !f.Unread(fresh!), "untyped readAll confirms registered IDs from both types");
        Check(await f.PushAsync(1) is null, "duplicate cannot resurrect after second readAll");
    }

    private static async Task Generation()
    {
        using var f = new Fixture();
        f.Scm.Add(40, 1);
        f.Push(40);
        f.Scm.HoldAll = true;
        var old = f.All();
        await f.Scm.AllApplied.Task.WaitAsync(TimeSpan.FromSeconds(5));
        // Exercise real Host stop/clear, then a later login of the SAME owner.
        typeof(ScmAccountBridgeHost).GetField("_businessStartupDeferred", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(f.Host, true);
        var publish = typeof(ScmAccountBridgeHost).GetMethod("PublishSession", BindingFlags.Instance | BindingFlags.NonPublic)!;
        publish.Invoke(f.Host, [null, false, null, false, null, null, null, null]);
        publish.Invoke(f.Host, [f.Session, false, null, false, null, null, null, null]);
        f.Scm.Add(40, 1); // A new generation's unread fact must not be touched by the old response.
        var next = f.Push(40)!;
        f.Scm.ReleaseAll.TrySetResult();
        try { await old; throw new Exception("stale response accepted"); }
        catch (Exception e) when (e is AccountBridgeHostException or BridgeStaleGenerationException) { }
        Check(f.Unread(next) && f.Push(40) is not null, "old response cannot retire new generation's pending card or duplicate eligibility");
        Check(!(await f.Page()).GetProperty("data").GetProperty("rows")[0].GetProperty("read").GetBoolean(), "new generation REST agrees");
    }

    private static async Task Partial(string failure)
    {
        using var f = new Fixture();
        f.Scm.Add(6, 1); f.Scm.Add(5, 1);
        var a = f.Push(5)!; var b = f.Push(6)!;
        using var cards = new Cards(f);
        var pendingA = await cards.Queue(a); var pendingB = await cards.Queue(b);
        f.Healthy();
        var previousInbox = await f.Inbox();
        // Cached SCM rows still receive fresh references on every read. Mark only the latest lease.
        var inbox = await f.Inbox();
        Check(f.Scm.Reads == 1, "healthy cache established");
        var previousRefs = previousInbox.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("reference").GetString()).ToArray();
        try
        {
            await f.Host.MarkNotificationInboxReadAsync(f.Host.CurrentContext!,
                BridgePayload.From(new { schemaVersion = 1, references = previousRefs }), default);
            throw new Exception("replaced cached-read lease accepted");
        }
        catch (AccountBridgeHostException e) when (e.Code == "notificationInbox.invalid_request")
        { Check(f.Scm.Writes == 0, "replaced cached-read references reject before any SCM write"); }
        var events = new List<BridgeEnvelope>();
        using var runtime = new AccountBridgeRuntime(f.Host);
        runtime.EventReady += events.Add;
        var revision = typeof(ScmAccountBridgeHost).GetField("_inboxScmRevision", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var before = (long)revision.GetValue(f.Host)!;
        f.Scm.SecondFailure = failure;
        var refs = inbox.GetProperty("items").EnumerateArray().Select(x => x.GetProperty("reference").GetString()).ToArray();
        var result = BridgePayload.From(await f.Host.MarkNotificationInboxReadAsync(f.Host.CurrentContext!,
            BridgePayload.From(new { schemaVersion = 1, references = refs }), default));
        Check(!result.GetProperty("confirmed").GetBoolean() && f.Scm.Writes == 2, "partial write remains unconfirmed without retries");
        Check((long)revision.GetValue(f.Host)! == before + 1 &&
            events.Count(x => x.Name == "notificationInbox.changed") == 1 &&
            events.Count(x => x.Name == "marketplace.changed") == 1, "finally merges one cache and marketplace invalidation");
        Check(!f.Unread(a) && f.Unread(b) && f.Push(5) is null && f.Push(6) is not null, "receipts and pending/duplicate eligibility reflect successful prefix only");
        Check(!pendingA.IsCurrent() && pendingB.IsCurrent(), "partial success revokes only the confirmed native card");
        var reconciled = await f.Inbox();
        Check(f.Scm.Reads == 2, "next automatic read must hit authority despite healthy cache");
        var rows = reconciled.GetProperty("items").EnumerateArray().ToArray();
        Check(rows.Count(x => x.GetProperty("read").GetBoolean()) == 1 && reconciled.GetProperty("unreadCount").GetInt32() == 1, "authoritative readback retains partial success");
    }

    private static async Task MarketplaceReadBoundary(string mode, string? onlyOperation = null)
    {
        foreach (var operation in onlyOperation is null ? new[] { "read", "readAll" } : [onlyOperation])
        {
            using var f = new Fixture();
            using var cancellation = new CancellationTokenSource();
            f.Scm.Add(41, 1);
            var card = f.Push(41)!;
            f.Healthy();
            await f.Inbox();
            await f.Inbox();
            Check(f.Scm.Reads == 1, "marketplace boundary starts with healthy cache: " + operation);
            var events = new List<BridgeEnvelope>();
            using var runtime = new AccountBridgeRuntime(f.Host);
            runtime.EventReady += events.Add;
            var revision = typeof(ScmAccountBridgeHost).GetField("_inboxScmRevision", BindingFlags.Instance | BindingFlags.NonPublic)!;
            var before = (long)revision.GetValue(f.Host)!;
            f.Scm.HoldWrite = true;
            f.Scm.WriteFailure = mode;
            var continuation = new ConfirmedContinuation(() => !f.Unread(card), () =>
            {
                // This runs only once the real OAuth receipt is confirmed, before Host resumes.
                if (mode == "cancel") cancellation.Cancel();
                if (mode == "generation")
                {
                    typeof(ScmAccountBridgeHost).GetField("_businessStartupDeferred", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(f.Host, true);
                    var publish = typeof(ScmAccountBridgeHost).GetMethod("PublishSession", BindingFlags.Instance | BindingFlags.NonPublic)!;
                    publish.Invoke(f.Host, [null, false, null, false, null, null, null, null]);
                    publish.Invoke(f.Host, [f.Session, false, null, false, null, null, null, null]);
                    f.Scm.Add(41, 1);
                    f.Push(41);
                    f.Healthy();
                    before = (long)revision.GetValue(f.Host)!;
                    events.Clear();
                }
            });
            Task<BridgeDispatchBatch> write;
            var previous = SynchronizationContext.Current;
            try
            {
                SynchronizationContext.SetSynchronizationContext(continuation);
                write = runtime.DispatchAsync(BridgeEnvelope.Request("marketplace.notices", "l06d-" + operation,
                    f.Host.Generation, new { schemaVersion = 1, operation, id = 41 }, f.Host.CurrentContext), cancellation.Token).AsTask();
            }
            finally { SynchronizationContext.SetSynchronizationContext(previous); }
            // Force an asynchronous response so the Host continuation is captured above.
            f.Scm.ReleaseWrite.TrySetResult();
            var response = (await write.WaitAsync(TimeSpan.FromSeconds(5))).Response;
            var confirmed = mode is "cancel" or "success" or "generation";
            Check(continuation.Observed == confirmed, "hook observes actual OAuth confirmation only: " + mode);
            Check(f.Scm.Writes == 1, "marketplace writes exactly once without retries: " + operation);
            if (mode == "cancel" || mode == "timeout")
                Check(response.Status == "cancelled", "marketplace preserves cancellation response: " + mode);
            else if (mode == "generation")
                Check(response.Status != "ok", "old generation response is rejected");
            else
                Check(response.Status == "ok" && response.Payload.GetProperty("data").GetProperty("confirmed").GetBoolean() == confirmed,
                    "marketplace confirmation response: " + mode);
            var invalidations = mode is "cancel" or "success" ? 1 : 0;
            Check((long)revision.GetValue(f.Host)! == before + invalidations &&
                events.Count(x => x.Name == "notificationInbox.changed") == invalidations &&
                events.Count(x => x.Name == "marketplace.changed") == invalidations,
                "marketplace invalidates each reader exactly once only for current confirmed writes: " + mode);
            var reads = f.Scm.Reads;
            var inbox = await f.Inbox();
            Check(f.Scm.Reads == reads + (confirmed ? 1 : 0), "next background read bypasses invalidated healthy cache: " + mode);
            var expectedRead = mode is "cancel" or "success";
            Check(inbox.GetProperty("items")[0].GetProperty("read").GetBoolean() == expectedRead &&
                f.Unread(card) != expectedRead, "cache, SCM and receipts agree: " + mode);
        }
    }

    // Queue captured continuations without reinstalling this context. OAuth completes its receipt
    // commit on the pool; its completion then posts the awaiting Host continuation here.
    private sealed class ConfirmedContinuation(Func<bool> confirmed, Action beforeHost) : SynchronizationContext
    {
        private int _observed;
        internal bool Observed => Volatile.Read(ref _observed) != 0;
        public override void Post(SendOrPostCallback callback, object? state)
        {
            if (confirmed() && Interlocked.Exchange(ref _observed, 1) == 0) beforeHost();
            base.Post(callback, state);
        }
    }

    private static async Task AuthorityFailures()
    {
        foreach (var mode in new[] { "timeout", "missing-flag", "not-found" })
        {
            using var f = new Fixture();
            await f.All();
            f.Scm.Add(4, 1);
            f.Scm.ReadFailure = mode;
            Check(await f.PushAsync(4) is null && f.Push(4) is null, "unproven frame stays silent: " + mode);
            f.Scm.ReadFailure = null;
            var retry = await f.PushAsync(4);
            Check(retry is not null && f.Unread(retry), "failed probe never creates a permanent read tombstone: " + mode);
            Check(f.Scm.Writes == 1, "reconciliation never retries writes: " + mode);
        }
    }

    private sealed class Cards : IDisposable
    {
        private sealed class Sink : IDesktopNotificationSink
        {
            internal readonly List<DesktopNotification> Pending = [];
            public ValueTask<bool> TryPresentAsync(DesktopNotification card, CancellationToken token)
            { Pending.Add(card); return ValueTask.FromResult(true); }
            public void Clear() { }
            public void Dispose() { }
        }
        private readonly Fixture _fixture;
        private readonly Sink _sink = new();
        private readonly string _root = Directory.CreateTempSubdirectory("l06b-cards-").FullName;
        private readonly NotificationSettingsBridgeDispatcher _settings;
        internal int Activations;
        internal Cards(Fixture fixture)
        {
            _fixture = fixture;
            // Isolated notification preferences, never the real device store.
            File.WriteAllText(Path.Combine(_root, "notification-settings.v1.json"),
                """{"schemaVersion":1,"revision":0,"inAppEnabled":true,"position":"bottomRight","preview":"sourceOnly","windowsEnabled":true,"tradeWindowsEnabled":true}""");
            _settings = new(_root, () => fixture.Host.Generation, () => true, desktop: _sink,
                activationEvent: (g, payload) => BridgeEnvelope.Event("notificationSettings.activated", g, 1, payload));
            _settings.EventReady += _ => Activations++;
        }
        internal async Task<DesktopNotification> Queue(TradeNotificationEvent notice)
        {
            var generation = _fixture.Host.Generation;
            await _settings.PresentTradeAsync(_fixture.Host.CurrentContext!, generation, notice,
                () => generation == _fixture.Host.Generation && _fixture.Unread(notice));
            return _sink.Pending.Last();
        }
        public void Dispose() { _settings.Dispose(); Directory.Delete(_root, true); }
    }

    private static async Task Capacity()
    {
        using var f = new Fixture();
        var first = f.Push(1)!;
        var observer = new TradeNotificationObserver();
        Check(observer.Observe(f.Host.CurrentContext!, f.Host.Generation, first) is not null, "first alert recorded");
        for (var id = 2; id <= 8192; id++) Check(f.Push(id) is not null, "fill receipt " + id);
        Check(f.Push(8193) is null, "new key rejected at full capacity");
        Check(f.Unread(first) && f.Push(1) is not null, "old unread key not evicted");
        Check(observer.Observe(f.Host.CurrentContext!, f.Host.Generation, f.Push(1)!) is null, "capacity cannot restore duplicate alert");
        await f.Host.MarketplaceNoticesAsync(f.Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, operation = "read", id = 1 }), default);
        Check(!f.Unread(first) && f.Push(1) is null && f.Push(8193) is null, "existing key can confirm at capacity without opening a slot or restoring duplicates");
    }

    private sealed class Fixture : IDisposable
    {
        internal readonly Handler Scm = new();
        internal readonly OAuthPkceClient OAuth;
        internal readonly ScmOAuthSession Session = new("fixture", "boundary-owner", "Fixture", "synthetic", DateTimeOffset.UtcNow.AddHours(1), ["profile.read", "profile.write"]);
        internal readonly ScmAccountBridgeHost Host;
        private readonly AccountSafetyClient _relay;
        private readonly string _root = Directory.CreateTempSubdirectory("l06b-").FullName;
        internal Fixture()
        {
            var uri = new Uri("https://fixture.invalid/");
            OAuth = new(new ScmHttpClient(Scm), new Vault(), new("fixture", uri, uri, uri, "desktop", "api", "", "/callback"));
            _relay = new(uri, new Relay());
            Host = new(OAuth, new ScmProfileCacheStore(_root), "fixture", () => null, Session, 1, accountSafety: _relay);
        }
        internal static JsonElement Row(long id, int type = 1) => BridgePayload.From(new { id, type, subType = 4, title = type == 0 ? "收货提醒" : "Shipped", isRead = false });
        internal TradeNotificationEvent? Push(long id, int type = 1) => OAuth.ProjectTradeNotification(OAuthPkceClient.ChatOwner(Session), Row(id, type));
        internal async Task<TradeNotificationEvent?> PushAsync(long id, int type = 1)
        {
            // The fallback keeps the regression executable against the pre-fix implementation.
            var method = typeof(OAuthPkceClient).GetMethod("ReconcileStationPushAsync", BindingFlags.NonPublic | BindingFlags.Instance);
            if (method is null) return Push(id, type);
            var generation = Host.Generation;
            var gate = typeof(ScmAccountBridgeHost).GetField("_realtimeGate", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(Host)!;
            return await (Task<TradeNotificationEvent?>)method.Invoke(OAuth, [Session, Row(id, type), (Func<bool>)(() => Host.Generation == generation), gate, CancellationToken.None])!;
        }
        internal bool Unread(TradeNotificationEvent card) => OAuth.StationNotificationUnread(OAuthPkceClient.ChatOwner(Session), card);
        internal async Task<JsonElement> All(int? type = null) => BridgePayload.From(await Host.MarketplaceNoticesAsync(Host.CurrentContext!,
            type is null ? BridgePayload.From(new { schemaVersion = 1, operation = "readAll" }) : BridgePayload.From(new { schemaVersion = 1, operation = "readAll", type }), default));
        internal async Task<JsonElement> Page() => BridgePayload.From(await Host.MarketplaceNoticesAsync(Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, operation = "page" }), default));
        internal async Task<JsonElement> Inbox() => BridgePayload.From(await Host.ReadNotificationInboxAsync(Host.CurrentContext!, BridgePayload.From(new { schemaVersion = 1, allowScmCache = true }), default));
        internal void Healthy() => typeof(ScmAccountBridgeHost).GetMethod("ObserveInboxPush", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(Host, [true]);
        public void Dispose() { Host.Dispose(); _relay.Dispose(); Scm.Dispose(); Directory.Delete(_root, true); }
    }

    private static HttpResponseMessage Response(object data) => new(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) };
    private sealed class Handler : HttpMessageHandler
    {
        internal readonly Dictionary<long, (int Type, bool Read)> Rows = [];
        internal int Reads, Writes;
        internal bool HoldAll;
        internal bool HoldWrite;
        internal string? WriteFailure;
        internal readonly TaskCompletionSource ReleaseWrite = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal string? SecondFailure;
        internal string? ReadFailure;
        internal readonly TaskCompletionSource AllApplied = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal readonly TaskCompletionSource ReleaseAll = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal void Add(long id, int type) => Rows[id] = (type, false);
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            var path = request.RequestUri!.AbsolutePath;
            var query = System.Web.HttpUtility.ParseQueryString(request.RequestUri.Query);
            if (request.Method == HttpMethod.Put)
            {
                Writes++;
                if (HoldWrite) await ReleaseWrite.Task.WaitAsync(TimeSpan.FromSeconds(5), token);
                if (WriteFailure == "timeout") throw new TaskCanceledException("fixture unknown write outcome");
                if (WriteFailure == "false") return Response(false);
                if (path.EndsWith("/mark-all-read"))
                {
                    var type = int.TryParse(query["type"], out var only) ? (int?)only : null;
                    foreach (var id in Rows.Keys.ToArray()) if (type is null || Rows[id].Type == type) Rows[id] = (Rows[id].Type, true);
                    AllApplied.TrySetResult();
                    if (HoldAll) await ReleaseAll.Task.WaitAsync(TimeSpan.FromSeconds(5), token);
                }
                else
                {
                    Check(path.EndsWith("/mark-read"), "only existing write route");
                    if (Writes == 2 && SecondFailure == "timeout") throw new TaskCanceledException("fixture timeout");
                    if (Writes == 2 && SecondFailure == "false") return Response(false);
                    using var body = JsonDocument.Parse(await request.Content!.ReadAsStringAsync(token));
                    var id = body.RootElement.GetProperty("id").GetInt64();
                    if (Rows.TryGetValue(id, out var row)) Rows[id] = (row.Type, true);
                }
                return Response(true);
            }
            Check(path.EndsWith("/page"), "reconciliation uses only existing page route");
            Reads++;
            if (ReadFailure == "timeout") throw new TaskCanceledException("fixture read timeout");
            if (ReadFailure == "missing-flag") return Response(new { list = new[] { new { id = 4, type = 1 } }, total = 1 });
            if (ReadFailure == "not-found") return Response(new { list = Array.Empty<object>(), total = 0 });
            var page = int.Parse(query["pageNo"] ?? "1");
            var size = int.Parse(query["pageSize"] ?? "50");
            var filtered = Rows.Where(x => query["type"] is null || x.Value.Type == int.Parse(query["type"]!)).Reverse().ToArray();
            var list = filtered.Skip((page - 1) * size).Take(size).Select(x => new { id = x.Key, type = x.Value.Type,
                subType = 4, title = "Shipped", content = "Fixture", createTime = 1760000000000L, isRead = x.Value.Read }).ToArray();
            return Response(new { list, total = filtered.Length });
        }
    }
    private sealed class Relay : HttpMessageHandler
    {
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        {
            if (request.Method != HttpMethod.Get) throw new Exception("No relay writes in fixture");
            return Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK) { Content = new StringContent(JsonSerializer.Serialize(
                new NotificationInboxContract([], 0, 0, DateTimeOffset.UtcNow), new JsonSerializerOptions(JsonSerializerDefaults.Web))) });
        }
    }
    private sealed class Vault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string value) => throw new Exception("No credential persistence");
        public void DeleteRefreshToken(string key) => throw new Exception("No credential deletion");
    }
}
