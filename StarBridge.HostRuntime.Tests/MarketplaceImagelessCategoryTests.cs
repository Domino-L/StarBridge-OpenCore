using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceImagelessCategoryTests
{
    internal static async Task Run()
    {
        await Trending();
        foreach (var operation in new[] { "latest", "offers", "marketOrders" }) await Quotes(operation);
        await Cache();
        foreach (var failure in new[] { "500", "json", "missing", "invalid", "timeout" }) await Failure(failure);
        await Limits();
        await Budget();
        await SharedRead();
        await RateLimited();
        await CacheCapacity();
        await BackoffCapacity();
        await PartialDeadline();
        await UncooperativeTransport();
        await Cancellation();
        await LatestSides();
        await Pending();
        Console.WriteLine("PASS CX-T05 imageless categories: 20 scenarios, fake transport only");
    }

    // User 10-29: the hall's latest-listings filter can be cleared; side 3 asks SCM for every type.
    private static async Task LatestSides()
    {
        var handler = new Handler();
        using var reader = Reader(handler);
        foreach (var (side, expected) in new[] { (1, "&creatorType=1&displayType=1"), (0, "&creatorType=0&displayType=1"),
            (2, "&displayType=3"), (3, "") })
        {
            await reader.ReadAsync("latest", 0, "", 0, side, 1, default);
            var query = handler.OrderQueries.Last();
            Check(query.EndsWith("&sortType=time&sortOrder=desc&language=CN" + expected, StringComparison.Ordinal) &&
                (side != 3 || !query.Contains("creatorType") && !query.Contains("displayType")),
                "latest side " + side + " maps to its SCM filter; all sends no type filter");
        }
    }

    private static async Task Trending()
    {
        var handler = new Handler
        {
            Trending = """[{"id":1,"thumbnailUrl":"https://catalog.invalid/a"},{"id":2,"thumbnailUrl":null},{"id":3,"thumbnailUrl":"https://catalog.invalid/b"}]"""
        };
        using var reader = Reader(handler);
        var rows = Rows(await Read(reader, "trending"));
        Check(handler.Ids.Order().SequenceEqual([1L, 2L, 3L]), "trending metadata includes image rows for quality detection");
        Check(Category(rows[0]) == 101 && Category(rows[1]) == 102 && Category(rows[2]) == 103, "trending category also on image rows, for when the picture fails");
        Check(rows[1].EnumerateObject().Count() == rows[0].EnumerateObject().Count() && !rows[1].TryGetProperty("unselected", out _), "only categoryId is added");
    }

    private static async Task Quotes(string operation)
    {
        var handler = new Handler
        {
            Orders = """
                [
                  {"orderNumber":"a","displayType":1,"thumbnailUrl":"https://catalog.invalid/a","itemDetails":[{"itemId":1}]},
                  {"orderNumber":"b","displayType":1,"itemDetails":[{"itemId":2,"thumbnailUrl":"https://catalog.invalid/b"}]},
                  {"orderNumber":"c","displayType":1,"itemDetails":[{"itemId":"3"},{"itemId":33}],"wantedItems":[{"itemId":93}]},
                  {"orderNumber":"d","displayType":1,"thumbnailUrl":"","itemDetails":[{"itemId":4,"thumbnailUrl":""}]},
                  {"orderNumber":"e","displayType":2,"itemDetails":[{"itemId":5}]},
                  {"orderNumber":"f","displayType":1,"itemDetails":[],"wantedItems":[{"itemId":6}]},
                  {"orderNumber":"g","displayType":1,"itemDetails":[{"itemId":"invalid"}]},
                  {"orderNumber":"h","displayType":3,"itemDetails":[{"itemId":7}]},
                  {"orderNumber":"i","displayType":1,"itemDetails":[{"itemId":3}]},
                  {"orderNumber":"j","displayType":1,"thumbnailUrl":"https://catalog.invalid/c","itemDetails":[{"itemId":3}]}
                ]
                """
        };
        using var reader = Reader(handler);
        var data = await Read(reader, operation);
        var rows = Rows(data);
        Check(data.GetProperty("total").GetInt32() == 10, operation + " preserves page total");
        Check(handler.Ids.Order().SequenceEqual([3L, 4L, 7L]), operation + " skips images/checklist/missing ID and deduplicates");
        foreach (var index in new[] { 2, 3, 7, 8, 9 })
            Check(Category(rows[index]) == Category(rows[index].GetProperty("items")[0]), operation + " row and first item category match");
        foreach (var index in new[] { 0, 1, 4, 5, 6 })
        {
            Check(!HasCategory(rows[index]), operation + " ineligible row untouched");
            foreach (var item in rows[index].GetProperty("items").EnumerateArray())
                Check(!HasCategory(item), operation + " ineligible nested item untouched");
        }
        Check(Category(rows[2]) == 103 && Category(rows[3]) == 104 && Category(rows[7]) == 107, "exact item identity");
        Check(!HasCategory(rows[2].GetProperty("items")[1]) && !HasCategory(rows[2].GetProperty("wantedItems")[0]), "other items and wantedItems unchanged");
    }

    private static async Task Cache()
    {
        var time = new MarketplaceTestTime { Wall = new DateTimeOffset(2026, 10, 23, 0, 0, 0, TimeSpan.Zero) };
        var handler = new Handler { Trending = """[{"id":1}]""", Orders = """[{"itemDetails":[{"itemId":1}]}]""" };
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        await Read(reader, "trending");
        time.Advance(TimeSpan.FromHours(23));
        Check(Category(Rows(await Read(reader, "latest"))[0]) == 101 && handler.Ids.Count == 1, "24-hour cache shared across operations");
        time.Advance(TimeSpan.FromHours(1) + TimeSpan.FromSeconds(1));
        await Read(reader, "trending");
        Check(handler.Ids.Count == 2, "expired entry fetched again");
        using var other = Reader(new Handler { Trending = """[{"id":1}]""", Detail = (_, _) => Task.FromResult(Envelope("{\"categoryId\":999}")) });
        Check(Category(Rows(await Read(other, "trending"))[0]) == 999, "cache belongs to reader instance");
        handler.Trending = """[{"id":1,"thumbnailUrl":"https://catalog.invalid/a"}]""";
        Check(Category(Rows(await Read(reader, "trending"))[0]) == 101 && handler.Ids.Count == 2, "cached category reaches an image row without a request");
        handler.Orders = """[{"thumbnailUrl":"https://catalog.invalid/a","itemDetails":[{"itemId":1}]},{"thumbnailUrl":"https://catalog.invalid/b","itemDetails":[{"itemId":9}]}]""";
        var quotes = Rows(await Read(reader, "latest"));
        Check(Category(quotes[0]) == 101 && !HasCategory(quotes[1]) && !quotes[1].TryGetProperty("categoryPending", out _) && handler.Ids.Count == 2,
            "listing with a picture never spends a request or waits on a category");
    }

    private static async Task Failure(string failure)
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler
        {
            Trending = """[{"id":1}]""",
            Detail = async (_, ct) =>
            {
                if (failure == "timeout") await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                return failure switch
                {
                    "500" => new(HttpStatusCode.InternalServerError),
                    "json" => new(HttpStatusCode.OK) { Content = new StringContent("{") },
                    "missing" => Envelope("{}"),
                    "invalid" => Envelope("{\"categoryId\":\"bad\"}"),
                    _ => throw new InvalidOperationException("Timeout should cancel")
                };
            }
        };
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        var timer = Stopwatch.StartNew();
        Check(!HasCategory(Rows(await Read(reader, "trending"))[0]), failure + " does not fail original read");
        if (failure == "timeout") Check(timer.Elapsed < TimeSpan.FromSeconds(3), "optional read has two-second budget");
        handler.Detail = (_, _) => Task.FromResult(Envelope("{\"categoryId\":222}"));
        await WaitForIdle(reader);
        await Read(reader, "trending");
        Check(handler.Ids.Count == (failure == "timeout" ? 2 : 1), failure == "timeout" ? "running out of time is not a failure, next read asks again" : failure + " backs off for five minutes");
        await WaitForIdle(reader);
        time.Advance(TimeSpan.FromMinutes(5) + TimeSpan.FromSeconds(1));
        Check(Category(Rows(await Read(reader, "trending"))[0]) == 222 && handler.Ids.Count == 2, failure + " not cached, next read retries");
        await Read(reader, "trending");
        Check(handler.Ids.Count == 2, "retry success is cached");
    }

    private static async Task Limits()
    {
        var list = JsonSerializer.Serialize(Enumerable.Range(1, 15).Select(id => new { id }));
        var handler = new Handler
        {
            Trending = list,
            Detail = async (id, ct) => { await Task.Delay(40, ct); return Envelope("{\"categoryId\":" + (id + 100) + "}"); }
        };
        using var reader = Reader(handler);
        var pages = await Task.WhenAll(Read(reader, "trending"), Read(reader, "trending"));
        Check(handler.MaxActive == 3, "three concurrent lookups maximum across reader calls");
        Check(handler.Ids.All(id => id <= 10) && handler.Ids.Count == 10, "concurrent pages share the ten selected IDs");
        foreach (var page in pages)
        {
            var rows = Rows(page);
            Check(rows.EnumerateArray().Take(10).All(HasCategory) && rows.EnumerateArray().Skip(10).All(r => !HasCategory(r)), "excess five rows remain untouched");
        }
        var singleHandler = new Handler { Trending = list };
        using var single = Reader(singleHandler);
        await Read(single, "trending");
        Check(singleHandler.Ids.Count == 10, "15 imageless items cause exactly ten requests");
        Check(Rows(await Read(single, "trending")).EnumerateArray().All(HasCategory) && singleHandler.Ids.Count == 15,
            "second page fills remaining five without refetching cached ten");
        var crossHandler = new Handler { Trending = """[{"id":11}]""" };
        using var cross = Reader(crossHandler);
        await Read(cross, "trending");
        crossHandler.Trending = list;
        Check(Category(Rows(await Read(cross, "trending"))[10]) == 111 && crossHandler.Ids.Count == 11,
            "cached eleventh row is filled before choosing ten cold ids");
    }

    private static string Items(int first, int count = 10) =>
        JsonSerializer.Serialize(Enumerable.Range(first, count).Select(id => new { id }));

    private static async Task Budget()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler();
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        for (var page = 0; page < 10; page++)
        {
            handler.Trending = Items(page * 10 + 1);
            await Read(reader, "trending");
        }
        Check(handler.Ids.Count == 30, "shared sliding minute budget is thirty requests");
        time.Advance(TimeSpan.FromSeconds(59));
        await Read(reader, "trending");
        Check(handler.Ids.Count == 30, "budget remains exhausted before minute boundary");
        time.Advance(TimeSpan.FromSeconds(1));
        Check(Rows(await Read(reader, "trending")).EnumerateArray().All(HasCategory) && handler.Ids.Count == 40,
            "budget recovers at one minute");
        var failing = new Handler { Detail = (_, _) => Task.FromResult(Envelope("{}")) };
        using var failedReader = new ScmMarketplaceReader(new("https://catalog.invalid/"), failing) { Clock = time.GetUtcNow, MonotonicTime = time };
        for (var page = 0; page < 10; page++)
        {
            failing.Trending = Items(page * 10 + 1);
            await Read(failedReader, "trending");
        }
        Check(failing.Ids.Count == 30, "failed lookups also consume the shared budget");
    }

    private static async Task SharedRead()
    {
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new Handler { Trending = Items(1, 1), Detail = async (_, _) =>
        {
            entered.TrySetResult();
            await release.Task;
            return Envelope("{\"categoryId\":123}");
        } };
        using var reader = Reader(handler);
        var first = Read(reader, "trending");
        await entered.Task;
        var second = Read(reader, "trending");
        release.TrySetResult();
        var pages = await Task.WhenAll(first, second);
        Check(handler.Ids.Count == 1 && pages.All(p => Category(Rows(p)[0]) == 123), "concurrent callers share one lookup");

        entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        handler.Trending = Items(2, 1);
        using var cancel = new CancellationTokenSource();
        var cancelled = reader.ReadAsync("trending", 0, "", 0, 1, 1, cancel.Token);
        await entered.Task;
        var survivor = Read(reader, "trending");
        cancel.Cancel();
        try { await cancelled; throw new Exception("Expected caller cancellation"); }
        catch (OperationCanceledException) { }
        release.TrySetResult();
        Check(Category(Rows(await survivor)[0]) == 123 && handler.Ids.Count == 2,
            "first caller cancellation does not cancel shared work for another page");
    }

    private static async Task RateLimited()
    {
        foreach (var retry in new[] { "120", "date", "1800", "none" })
        {
            var time = new MarketplaceTestTime { Wall = new DateTimeOffset(2026, 10, 23, 0, 0, 0, TimeSpan.Zero) };
            var handler = new Handler { Trending = Items(1, 1), Detail = (_, _) =>
            {
                var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                if (retry != "none") response.Headers.TryAddWithoutValidation("Retry-After",
                    retry == "date" ? time.Wall.AddSeconds(1800).ToString("R") : retry);
                return Task.FromResult(response);
            } };
            using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
            await Read(reader, "trending");
            handler.Trending = Items(2, 1);
            handler.Detail = (_, _) => Task.FromResult(Envelope("{\"categoryId\":123}"));
            var seconds = retry is "1800" or "date" ? 1800 : 120;
            time.Advance(TimeSpan.FromSeconds(seconds - 1));
            Check(!HasCategory(Rows(await Read(reader, "trending"))[0]) && handler.Ids.Count == 1, retry + " pauses reader");
            time.Advance(TimeSpan.FromSeconds(1));
            Check(Category(Rows(await Read(reader, "trending"))[0]) == 123 && handler.Ids.Count == 2, retry + " resumes reader");
        }
    }

    private static int Stored(ScmMarketplaceReader reader, string field)
    {
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        lock (typeof(ScmMarketplaceReader).GetField("_categoryLock", flags)!.GetValue(reader)!)
            return ((System.Collections.IDictionary)typeof(ScmMarketplaceReader).GetField(field, flags)!.GetValue(reader)!).Count;
    }

    private static async Task WaitForIdle(ScmMarketplaceReader reader)
    {
        var timer = Stopwatch.StartNew();
        while (Stored(reader, "_categoryReads") != 0 && timer.Elapsed < TimeSpan.FromSeconds(1)) await Task.Delay(10);
        Check(Stored(reader, "_categoryReads") == 0, "cooperative or released transport drains shared task registry");
    }

    private static async Task CacheCapacity()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler();
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        for (var page = 0; page < 210; page++)
        {
            handler.Trending = Items(page * 10 + 1);
            Check(Rows(await Read(reader, "trending")).EnumerateArray().All(HasCategory), "eviction preserves current response");
            time.Advance(TimeSpan.FromMinutes(1));
        }
        Check(Stored(reader, "_itemCategories") == 2000 && handler.Ids.Count == 2100, "cache bounded at 2000 ids");
        handler.Trending = Items(1, 1);
        await Read(reader, "trending");
        Check(handler.Ids.Count == 2101, "earliest expiry evicted first");
        time.Advance(TimeSpan.FromHours(24));
        handler.Trending = "[]";
        await Read(reader, "trending");
        Check(Stored(reader, "_itemCategories") == 0, "reads prune expired entries even on empty pages");
    }

    private static async Task BackoffCapacity()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler { Trending = Items(2001, 1), Detail = (_, _) => Task.FromResult(Envelope("{}")) };
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        // The normal 30/minute budget keeps a five-minute failure set much smaller. Seed only
        // this defensive capacity boundary; the actual failure still goes through ReadAsync.
        var entries = (Dictionary<long, long>)typeof(ScmMarketplaceReader).GetField("_categoryBackoff",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(reader)!;
        for (var id = 1; id <= 2000; id++) entries[id] = time.GetTimestamp() - TimeSpan.FromSeconds(id == 1 ? 240 : 0).Ticks;
        await Read(reader, "trending");
        Check(entries.Count == 2000 && !entries.ContainsKey(1) && entries.ContainsKey(2001), "backoff evicts earliest expiry");
        time.Advance(TimeSpan.FromMinutes(5));
        handler.Trending = "[]";
        await Read(reader, "trending");
        Check(entries.Count == 0, "reads prune expired backoff records");
    }

    private static async Task PartialDeadline()
    {
        var handler = new Handler
        {
            Trending = JsonSerializer.Serialize(Enumerable.Range(1, 15).Select(id => new { id })),
            Detail = async (id, ct) =>
            {
                if (id != 1) await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                return Envelope("{\"categoryId\":101}");
            }
        };
        using var reader = Reader(handler);
        var timer = Stopwatch.StartNew();
        var rows = Rows(await Read(reader, "trending"));
        Check(timer.Elapsed < TimeSpan.FromSeconds(3), "deadline covers queued work, not two seconds per wave");
        Check(Category(rows[0]) == 101 && rows.EnumerateArray().Skip(1).All(r => !HasCategory(r)), "deadline returns completed subset");
        Check(handler.Ids.Count <= 4 && handler.MaxActive <= 3, "cancelled queued lookups never reach handler");
        handler.Detail = (id, _) => Task.FromResult(Envelope("{\"categoryId\":" + (id + 100) + "}"));
        await WaitForIdle(reader);
        rows = Rows(await Read(reader, "trending"));
        Check(rows.EnumerateArray().Take(11).All(HasCategory), "lookups still queued at the deadline are asked again on the next read");
    }

    private static async Task UncooperativeTransport()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var release = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var exited = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new Handler
        {
            Trending = Items(1, 3),
            Detail = async (_, _) =>
            {
                await release.Task;
                exited.TrySetResult();
                return Envelope("{\"categoryId\":123}");
            }
        };
        using var reader = new ScmMarketplaceReader(new("https://catalog.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        object result;
        try
        {
            var timer = Stopwatch.StartNew();
            result = await reader.ReadAsync("trending", 0, "", 0, 1, 1, default);
            Check(timer.Elapsed < TimeSpan.FromSeconds(3) && !HasCategory(Rows(BridgePayload.From(result).GetProperty("data"))[0]), "uncooperative handler cannot delay page");
            handler.Trending = Items(20, 1);
            timer.Restart();
            Check(!HasCategory(Rows(await Read(reader, "trending"))[0]) && timer.Elapsed < TimeSpan.FromSeconds(3),
                "all occupied physical slots cause bounded skip, main read still succeeds");
            Check(handler.Ids.Count == 3, "hung transports do not multiply beyond physical slots");
            time.Advance(TimeSpan.FromMinutes(6));
            handler.Trending = Items(1, 3);
            await Read(reader, "trending");
            Check(handler.Ids.Count == 3, "same ids remain deduplicated after backoff expires while transport is still running");
        }
        finally { release.TrySetResult(); }
        await exited.Task;
        await WaitForIdle(reader);
        Check(Stored(reader, "_itemCategories") == 0, "late timeout result is not cached");
        handler.Detail = (_, _) => Task.FromResult(Envelope("{\"categoryId\":456}"));
        handler.Trending = Items(30, 1);
        Check(Category(Rows(await Read(reader, "trending"))[0]) == 456, "slots recover when transport eventually exits");
        Check(!HasCategory(Rows(BridgePayload.From(result).GetProperty("data"))[0]), "returned rows never mutate after deadline");
    }

    private static async Task Cancellation()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var handler = new Handler
        {
            Trending = """[{"id":1}]""",
            Detail = async (_, ct) => { started.TrySetResult(); await Task.Delay(Timeout.InfiniteTimeSpan, ct); return Envelope("{}"); }
        };
        using var reader = Reader(handler);
        using var cancel = new CancellationTokenSource();
        var read = reader.ReadAsync("trending", 0, "", 0, 1, 1, cancel.Token);
        await started.Task;
        cancel.Cancel();
        try { await read; throw new Exception("Caller cancellation must still propagate"); }
        catch (OperationCanceledException) { }
    }

    // The client reads again only where the Host has no answer yet.
    private static async Task Pending()
    {
        static bool Waiting(JsonElement row) => row.TryGetProperty("categoryPending", out var value) && value.GetBoolean();
        var slow = new Handler { Trending = Items(1, 2), Detail = async (id, ct) =>
        {
            if (id == 2) await Task.Delay(Timeout.InfiniteTimeSpan, ct);
            return Envelope("{\"categoryId\":101}");
        } };
        using var reader = Reader(slow);
        var rows = Rows(await Read(reader, "trending"));
        Check(!Waiting(rows[0]) && Waiting(rows[1]) && !HasCategory(rows[1]), "only the unanswered row waits");
        slow.Detail = (_, _) => Task.FromResult(Envelope("{\"categoryId\":102}"));
        await WaitForIdle(reader);
        rows = Rows(await Read(reader, "trending"));
        Check(rows.EnumerateArray().All(r => HasCategory(r) && !Waiting(r)), "answered rows stop waiting");

        var refused = new Handler { Trending = Items(1, 1), Detail = (_, _) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.InternalServerError)) };
        using var failed = Reader(refused);
        Check(!Waiting(Rows(await Read(failed, "trending"))[0]), "a real failure does not wait");
        // Only the pages the client reads again may wait; anything else would stay empty.
        foreach (var (operation, page) in new[] { ("offers", 1), ("marketOrders", 1), ("latest", 2) })
        {
            var quiet = new Handler { Orders = """[{"orderNumber":"a","displayType":1,"itemDetails":[{"itemId":1}]}]""", Detail = async (_, ct) =>
            {
                await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                return Envelope("{}");
            } };
            using var source = Reader(quiet);
            var data = BridgePayload.From(await source.ReadAsync(operation, 1, "", 0, 1, page, default)).GetProperty("data");
            Check(!Waiting(Rows(data)[0]), operation + " page " + page + " never waits");
        }
        var none = new Handler { Trending = Items(1, 1), Detail = (_, _) => Task.FromResult(Envelope("{\"qualityInfo\":null}")) };
        using var empty = Reader(none);
        Check(!Waiting(Rows(await Read(empty, "trending"))[0]), "an item SCM files nowhere does not wait");
    }

    private static ScmMarketplaceReader Reader(Handler handler) => new(new("https://catalog.invalid/"), handler);
    private static async Task<JsonElement> Read(ScmMarketplaceReader reader, string operation) =>
        BridgePayload.From(await reader.ReadAsync(operation, 1, "", 0, 1, 1, default)).GetProperty("data");
    private static JsonElement Rows(JsonElement data) => data.GetProperty("rows");
    private static bool HasCategory(JsonElement row) => row.TryGetProperty("categoryId", out _);
    private static long Category(JsonElement row) => row.GetProperty("categoryId").GetInt64();
    private static void Check(bool condition, string label) { if (!condition) throw new Exception("CX-50: " + label); }
    private static HttpResponseMessage Envelope(string data) => new(HttpStatusCode.OK)
        { Content = new StringContent("{\"code\":0,\"data\":" + data + "}") };

    private sealed class Handler : HttpMessageHandler
    {
        internal string Trending = "[]";
        internal string Orders = "[]";
        internal readonly ConcurrentQueue<long> Ids = new();
        internal readonly ConcurrentQueue<string> OrderQueries = new();
        internal Func<long, CancellationToken, Task<HttpResponseMessage>> Detail =
            (id, _) => Task.FromResult(Envelope("{\"categoryId\":" + (id + 100) + ",\"unselected\":true}"));
        private int _active;
        private int _maxActive;
        internal int MaxActive => _maxActive;

        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            Check(request.RequestUri!.Host == "catalog.invalid" && request.Method == HttpMethod.Get, "only fake public GETs");
            Check(request.Headers.Authorization is null && !request.Headers.Contains("Cookie"), "anonymous transport");
            var path = request.RequestUri.AbsolutePath;
            if (path == "/app-api/sc/orders/trending-items") return Envelope(Trending);
            if (path == "/app-api/sc/orders/page")
            {
                OrderQueries.Enqueue(request.RequestUri.Query);
                using var page = JsonDocument.Parse(Orders);
                return Envelope("{\"list\":" + Orders + ",\"total\":" + page.RootElement.GetArrayLength() + "}");
            }
            Check(path == "/app-api/product/items/get", "only category detail endpoint added");
            var id = long.Parse(request.RequestUri.Query[4..], CultureInfo.InvariantCulture);
            Ids.Enqueue(id);
            var active = Interlocked.Increment(ref _active);
            int previous;
            do { previous = _maxActive; }
            while (active > previous && Interlocked.CompareExchange(ref _maxActive, active, previous) != previous);
            try { return await Detail(id, ct); }
            finally { Interlocked.Decrement(ref _active); }
        }
    }
}
