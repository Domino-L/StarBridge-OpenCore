using System.Collections.Concurrent;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceSupplementBudgetTests
{
    private static int _checks;
    internal static async Task Run()
    {
        await PassivePages();
        await UserPages();
        await ConcurrentUsers();
        await MetadataPriority();
        foreach (var origin in new[] { "metadata", "passivePrice", "userPrice" }) await SharedPause(origin);
        foreach (var user in new[] { false, true })
        {
            await WallJumps(user);
            await MonotonicBackoff(user);
        }
        foreach (var origin in new[] { "metadata", "passivePrice", "userPrice" })
            foreach (var retry in new[] { "1800", "date", "invalid", "-5", "past", "86401", "huge" })
                await MonotonicPause(origin, retry);
        Console.WriteLine($"PASS CX-T06 supplement budgets: {_checks} assertions, fake transport only");
    }

    private static async Task PassivePages()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler();
        using var reader = Reader(handler, time);
        for (var page = 0; page < 20; page++)
        {
            handler.First = page * 10 + 1;
            var data = await Read(reader, page % 2 == 0 ? "trending" : "latest");
            Check(data.GetProperty("rows").GetArrayLength() == 10, "base page survives budget exhaustion");
        }
        Check(handler.Main == 20 && handler.Optional == 30, "twenty mixed pages share thirty metadata and price requests");
        Check(handler.Prices > 0 && handler.Details > 0, "both passive supplement kinds counted");
        time.Advance(TimeSpan.FromSeconds(59));
        await Read(reader, "latest");
        Check(handler.Optional == 30, "no reset at fifty-nine seconds");
        time.Advance(TimeSpan.FromSeconds(1));
        var resumed = await Read(reader, "latest");
        Check(handler.Optional == 40 && resumed.GetProperty("rows")[0].TryGetProperty("categoryId", out _), "passive window recovers");
    }

    private static async Task UserPages()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler();
        using var reader = Reader(handler, time);
        var responses = new List<JsonElement>();
        for (var id = 1; id <= 10; id++) responses.Add(await Read(reader, "qualityTiers", id));
        Check(handler.Optional == 60, "ten user items cannot exceed sixty HTTP sends");
        Check(responses[6].GetProperty("tiers").EnumerateArray().Any(t => !Known(t)), "partial last funded item exposes unknown tiers");
        Check(!Known(responses[9].GetProperty("sell")) && !Known(responses[9].GetProperty("buy")), "unfunded item returns unknown without throwing");
        var cached = await Read(reader, "qualityTiers", 1);
        Check(handler.Optional == 60 && cached.GetRawText() == responses[0].GetRawText(), "fresh cache returned even with exhausted budget");
        handler.First = 101;
        await Read(reader, "latest");
        Check(handler.Optional == 70, "user exhaustion does not consume passive budget");
        time.Advance(TimeSpan.FromSeconds(61));
        var recovered = await Read(reader, "qualityTiers", 10);
        Check(Known(recovered.GetProperty("sell")) && recovered.GetProperty("tiers").EnumerateArray().All(Known), "user budget and unknown cache recover");
        Check(handler.Optional == 79, "recovery sends one metadata and eight prices");
    }

    private static async Task ConcurrentUsers()
    {
        var handler = new Handler { Delay = true };
        using var reader = Reader(handler, new MarketplaceTestTime());
        await Task.WhenAll(Enumerable.Range(1, 10).Select(id => Read(reader, "qualityTiers", id)));
        Check(handler.Optional == 60, "concurrent user reads enforce the same hard bound");
        Check(handler.MaxOptional <= 3, "all supplement types share three physical slots");
    }

    private static async Task MetadataPriority()
    {
        var handler = new Handler { Priority = true };
        using var reader = Reader(handler, new MarketplaceTestTime());
        var rows = (await Read(reader, "trending")).GetProperty("rows");
        Check(handler.DetailIds.Order().SequenceEqual(Enumerable.Range(6, 10).Select(i => (long)i)), "ten imageless IDs precede earlier image IDs");
        Check(rows.EnumerateArray().Skip(5).All(r => r.TryGetProperty("categoryId", out _)), "category priority preserves all funded rows");
        var before = handler.Details;
        await Read(reader, "qualityTiers", 6);
        Check(handler.Details == before, "quality and category share metadata cache across budgets");
    }

    private static async Task SharedPause(string origin)
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler { Limit = origin, Count = 1 };
        using var reader = Reader(handler, time);
        await Read(reader, origin == "userPrice" ? "qualityTiers" : "trending");
        Check(handler.Limited, origin + " fixture produced a 429");
        var sent = handler.Optional;
        handler.Limit = null;
        handler.First = 100;
        await Read(reader, "latest");
        var unknown = await Read(reader, "qualityTiers", 100);
        Check(handler.Optional == sent && !Known(unknown.GetProperty("sell")), origin + " pauses both budgets while main reads work");
        time.Advance(TimeSpan.FromSeconds(119));
        handler.First = 101;
        await Read(reader, "trending");
        await Read(reader, "qualityTiers", 101);
        Check(handler.Optional == sent, origin + " respects Retry-After");
        time.Advance(TimeSpan.FromSeconds(1));
        handler.First = 102;
        await Read(reader, "latest");
        var resumed = await Read(reader, "qualityTiers", 102);
        Check(handler.Optional > sent && Known(resumed.GetProperty("sell")), origin + " resumes both budgets");
    }

    private static bool Known(JsonElement value) => value.GetProperty("known").GetBoolean();

    private static async Task WallJumps(bool user)
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler();
        using var reader = Reader(handler, time);
        async Task Page(int id)
        {
            handler.First = id * 10;
            await Read(reader, user ? "qualityTiers" : "latest", id);
        }
        for (var id = 1; id <= 10; id++) await Page(id);
        var limit = user ? 60 : 30;
        Check(handler.Optional == limit, $"{user}: exhaust exact budget");
        time.Wall = time.Wall.AddMinutes(1);
        await Page(11);
        Check(handler.Optional == limit, $"{user}: wall forward one minute cannot refill budget");
        time.Wall = time.Wall.AddDays(-2);
        await Page(12);
        Check(handler.Optional == limit, $"{user}: wall rollback cannot refill budget");
        time.AdvanceMonotonic(TimeSpan.FromSeconds(59));
        await Page(13);
        Check(handler.Optional == limit, $"{user}: monotonic window still closed at 59 seconds");
        time.AdvanceMonotonic(TimeSpan.FromSeconds(1));
        await Page(14);
        Check(handler.Optional > limit, $"{user}: monotonic minute recovers despite wall rollback");
    }

    private static async Task MonotonicBackoff(bool user)
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler { Count = 1, FailDetail = true };
        using var reader = Reader(handler, time);
        var operation = user ? "qualityTiers" : "latest";
        await Read(reader, operation);
        Check(handler.Details == 1, $"{user}: failure was sent");
        handler.FailDetail = false;
        time.Wall = time.Wall.AddHours(24);
        await Read(reader, operation);
        Check(handler.Details == 1, $"{user}: wall forward cannot end backoff");
        time.Wall = time.Wall.AddDays(-2);
        time.AdvanceMonotonic(TimeSpan.FromSeconds(299));
        await Read(reader, operation);
        Check(handler.Details == 1, $"{user}: backoff remains at 299 monotonic seconds");
        time.AdvanceMonotonic(TimeSpan.FromSeconds(1));
        // A partial quality result has its own 60-second cache. Use the other read surface
        // to inspect the same metadata backoff at the exact five-minute boundary.
        await Read(reader, user ? "latest" : "qualityTiers");
        Check(handler.Details == 2, $"{user}: exact monotonic five minutes ends backoff after rollback");
    }

    private static async Task MonotonicPause(string origin, string retry)
    {
        var time = new MarketplaceTestTime();
        var raw = retry switch
        {
            "date" => time.Wall.AddMinutes(30).ToString("R"),
            "past" => time.Wall.AddMinutes(-30).ToString("R"),
            "huge" => "999999999999999999999999999999999999",
            _ => retry,
        };
        var handler = new Handler { Count = 1, Limit = origin, RetryRaw = raw };
        using var reader = Reader(handler, time);
        await Read(reader, origin == "userPrice" ? "qualityTiers" : "trending");
        Check(handler.Limited, origin + ": 429 received for " + retry);
        handler.Limit = null;
        var sent = handler.Optional;
        var id = 100;
        async Task Both()
        {
            handler.First = ++id;
            await Read(reader, "latest");
            await Read(reader, "qualityTiers", id);
        }
        if (retry is "-5" or "past")
        {
            await Both();
            Check(handler.Optional > sent, origin + ": negative delay is zero");
            return;
        }
        time.Wall = time.Wall.AddDays(10);
        await Both();
        Check(handler.Optional == sent, origin + ": forward wall jump cannot end " + retry);
        time.Wall = time.Wall.AddDays(-20);
        await Both();
        Check(handler.Optional == sent, origin + ": backward wall jump cannot end " + retry);
        if (retry == "huge")
        {
            time.AdvanceMonotonic(TimeSpan.FromDays(100));
            await Both();
            Check(handler.Optional == sent, origin + ": unrepresentable delay fails closed");
            return;
        }
        var seconds = retry == "invalid" ? 120 : retry == "86401" ? 86401 : 1800;
        time.AdvanceMonotonic(TimeSpan.FromSeconds(seconds - 1));
        await Both();
        Check(handler.Optional == sent, origin + ": both budgets paused until final second for " + retry);
        time.AdvanceMonotonic(TimeSpan.FromSeconds(1));
        var details = handler.Details;
        var prices = handler.Prices;
        await Both();
        Check(handler.Details > details && handler.Prices > prices, origin + ": both budgets recover for " + retry);
    }
    private static ScmMarketplaceReader Reader(Handler handler, MarketplaceTestTime time) =>
        new(new("https://budget.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
    private static async Task<JsonElement> Read(ScmMarketplaceReader reader, string op, int id = 1) =>
        BridgePayload.From(await reader.ReadAsync(op, 0, id.ToString(), 0, 1, 1, default)).GetProperty("data");
    private static void Check(bool value, string message)
    {
        _checks++;
        if (!value) throw new Exception("CX-T06: " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal int First = 1, Count = 10, Main, Optional, Details, Prices, MaxOptional;
        internal bool Priority, Delay, Limited;
        internal string? Limit;
        internal string? RetryRaw;
        internal bool FailDetail;
        internal ConcurrentQueue<long> DetailIds = new();
        private int _active;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.RequestUri!.Host != "budget.invalid") throw new Exception("Unexpected host");
            var path = request.RequestUri.AbsolutePath;
            var query = request.RequestUri.Query.TrimStart('?').Split('&')
                .Select(x => x.Split('=', 2)).ToDictionary(x => x[0], x => x[1]);
            var detail = path.EndsWith("items/get");
            var price = path.EndsWith("orders/page") && query.ContainsKey("productId");
            if (!detail && !price)
            {
                Interlocked.Increment(ref Main);
                var ids = Enumerable.Range(First, Priority ? 15 : Count);
                if (path.EndsWith("trending-items")) return Response(ids.Select(id => new
                {
                    id, thumbnailUrl = Priority && id < 6 ? "https://image.invalid/fixture" : null
                }));
                if (!path.EndsWith("orders/page")) throw new Exception("Unexpected route");
                return Response(new { total = Count, list = ids.Select(id => new { itemDetails = new[] { new { itemId = id } } }) });
            }
            Interlocked.Increment(ref Optional);
            if (detail) { Interlocked.Increment(ref Details); DetailIds.Enqueue(long.Parse(query["id"])); }
            else Interlocked.Increment(ref Prices);
            var active = Interlocked.Increment(ref _active);
            lock (DetailIds) MaxOptional = Math.Max(MaxOptional, active);
            try
            {
                if (Delay) await Task.Delay(10, ct);
                if (!Limited && (Limit == "metadata" && detail || Limit is "passivePrice" or "userPrice" && price))
                {
                    Limited = true;
                    var response = new HttpResponseMessage(HttpStatusCode.TooManyRequests);
                    response.Headers.TryAddWithoutValidation("Retry-After", RetryRaw ?? "120");
                    return response;
                }
                if (detail && FailDetail) return new(HttpStatusCode.InternalServerError);
                return detail ? Response(new { categoryId = 12, qualityInfo = new { quality = true } }) :
                    Response(new { total = 1, list = new[] { new { unitPrice = 100, itemDetails = new[] { new { qualityData = new { quality = 980 } } } } } });
            }
            finally { Interlocked.Decrement(ref _active); }
        }
        private static HttpResponseMessage Response(object data) => new(HttpStatusCode.OK)
            { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) };
    }
}
