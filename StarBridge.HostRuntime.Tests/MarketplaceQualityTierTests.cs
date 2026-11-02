using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Net;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceQualityTierTests
{
    private static int _checks;
    internal static async Task Run()
    {
        await MarketplaceQualityCompletenessTests.Run();
        await TiersAndCache();
        foreach (var info in new object?[] { null, "", "{}", new { } }) await NoQuality(info);
        await PartialFailure(false);
        await PartialFailure(true);
        await Trending();
        await TrendingLimit();
        await Cancellation();
        await SelectionEdges();
        await EmptyTop();
        Offers();
        Console.WriteLine($"PASS CX-T02 quality tiers: {_checks} assertions, fake transport only");
    }

    private static async Task TiersAndCache()
    {
        var time = new MarketplaceTestTime { Wall = DateTimeOffset.UtcNow };
        var handler = new Handler();
        using var reader = new ScmMarketplaceReader(new("https://quality.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
        var pair = await Task.WhenAll(Read(reader), Read(reader));
        Check(pair[0].GetRawText() == pair[1].GetRawText(), "concurrent callers share result");
        Check(handler.Requests.Count == 9 && handler.Details == 1, "one detail plus eight order pages");
        Check(handler.MaxActive <= 3, "maximum three requests");
        var data = pair[0];
        Check(data.GetProperty("itemId").GetInt64() == 1 && data.GetProperty("hasQuality").GetBoolean(), "item identity and quality");
        Check(data.GetProperty("sell").GetProperty("lowest").GetString() == "100" &&
            data.GetProperty("sell").GetProperty("quality").GetInt32() == 612, "any quality uses qualityMin fallback");
        Check(data.GetProperty("buy").GetProperty("highest").GetString() == "100" &&
            data.GetProperty("buy").GetProperty("count").GetInt32() == 17, "buy price and total");
        var bands = new[] { ("legendary", 950, 1000), ("excellent", 800, 949), ("good", 600, 799),
            ("normal", 400, 599), ("poor", 200, 399), ("inferior", 0, 199) };
        for (var i = 0; i < bands.Length; i++)
        {
            var (key, min, max) = bands[i];
            var tier = data.GetProperty("tiers")[i];
            Check(tier.GetProperty("key").GetString() == key && tier.GetProperty("known").GetBoolean(), "ordered known tier " + key);
            Check(handler.Requests.Any(q => q.GetValueOrDefault("minQuality") == min.ToString() &&
                q.GetValueOrDefault("maxQuality") == max.ToString() && q["pageSize"] == "20" &&
                q["creatorType"] == "1" && q["sortOrder"] == "asc"), "exact bounded tier query " + key);
            Check(tier.GetProperty("quality").GetInt32() == min + 10, "equal price prefers higher quality " + key);
            var best = tier.GetProperty("best");
            Check(best.GetProperty("quality").GetInt32() == max && best.GetProperty("price").GetString() == "101", "higher priced best value " + key);
            Check(best.GetProperty("perPoint").GetDecimal() == decimal.Round(101m / max, 4, MidpointRounding.AwayFromZero), "rounded per point " + key);
            Check(tier.GetProperty("count").GetInt32() == 17, "count uses total, not page length");
        }
        Check(!data.GetRawText().Contains("creatorId") && !data.GetRawText().Contains("contact") &&
            !data.GetRawText().Contains("memberId"), "no identities or contact projection");
        await Read(reader);
        Check(handler.Requests.Count == 9, "60-second cache");
        time.Advance(TimeSpan.FromSeconds(61));
        await Read(reader);
        Check(handler.Requests.Count == 17 && handler.Details == 1, "price cache expires, metadata remains");
        time.Advance(TimeSpan.FromHours(24));
        await Read(reader);
        Check(handler.Details == 2, "metadata expires at 24 hours");
        foreach (var invalid in new[] { "", "1:1", "1234567890", "1\n", "-1" })
        {
            try { await Read(reader, invalid); throw new Exception("accepted invalid item ID"); }
            catch (ArgumentException) { _checks++; }
        }
    }

    private static async Task NoQuality(object? info)
    {
        var handler = new Handler { Info = _ => info };
        using var reader = Reader(handler);
        var data = await Read(reader);
        Check(!data.GetProperty("hasQuality").GetBoolean() && data.GetProperty("tiers").GetArrayLength() == 0, "empty quality info");
        Check(handler.Requests.Count == 3, "non-quality only detail and required quotes");
    }

    private static async Task PartialFailure(bool timeout)
    {
        var handler = new Handler { FailMin = 600, TimeoutFailure = timeout };
        using var reader = Reader(handler);
        var timer = Stopwatch.StartNew();
        var data = await Read(reader);
        Check(!data.GetProperty("tiers")[2].GetProperty("known").GetBoolean(), "failed tier unknown");
        Check(data.GetProperty("tiers").EnumerateArray().Where((_, i) => i != 2).All(t => t.GetProperty("known").GetBoolean()), "other tiers survive");
        Check(data.GetProperty("sell").GetProperty("known").GetBoolean(), "required sell survives");
        Check(timer.Elapsed < TimeSpan.FromSeconds(7), "six-second total deadline");
    }

    private static async Task Trending()
    {
        var handler = new Handler { TrendingCount = 3, Info = id => id == 3 ? null : "{\"quality\":true}" };
        using var reader = Reader(handler);
        var rows = (await ReadTrending(reader)).GetProperty("rows");
        Check(rows[0].GetProperty("qualityTop").GetProperty("key").GetString() == "legendary", "legendary top");
        Check(rows[1].GetProperty("qualityTop").GetProperty("key").GetString() == "excellent", "excellent fallback");
        Check(rows[0].GetProperty("qualityAny").GetProperty("quality").GetInt32() == 612, "any quality card");
        Check(!rows[2].TryGetProperty("qualityAny", out _) && !rows[2].TryGetProperty("qualityTop", out _), "non-quality card unchanged");
        Check(handler.Details == 3 && handler.Requests.Count == 9, "trending exact request budget");
        await ReadTrending(reader);
        Check(handler.Requests.Count == 10, "trending quotes cached, only base page refreshed");
        await Read(reader);
        Check(handler.Details == 3, "metadata shared with qualityTiers");
        var failure = new Handler { TrendingCount = 1, FailMin = 950 };
        using var failing = Reader(failure);
        var failedRow = (await ReadTrending(failing)).GetProperty("rows")[0];
        Check(failedRow.TryGetProperty("qualityAny", out _) && !failedRow.TryGetProperty("qualityTop", out _), "optional failure leaves other field");
        Check(failure.Requests.All(q => q.GetValueOrDefault("minQuality") != "800"), "failure is not an empty legendary tier");
    }

    private static async Task TrendingLimit()
    {
        var handler = new Handler { TrendingCount = 15 };
        using var reader = Reader(handler);
        var rows = (await ReadTrending(reader)).GetProperty("rows");
        Check(handler.Details == 10, "ten new metadata reads maximum");
        Check(rows.EnumerateArray().Take(6).All(r => r.TryGetProperty("qualityAny", out _)) &&
            rows.EnumerateArray().Skip(6).All(r => !r.TryGetProperty("qualityAny", out _)), "only first six quality items");
        Check(handler.MaxActive <= 3, "trending concurrency bounded");
    }

    private static async Task Cancellation()
    {
        var handler = new Handler();
        using var reader = Reader(handler);
        using var cancel = new CancellationTokenSource();
        var cancelled = reader.ReadAsync("qualityTiers", 0, "1", 0, 1, 1, cancel.Token);
        var other = Read(reader);
        cancel.Cancel();
        try { await cancelled; throw new Exception("cancellation ignored"); }
        catch (OperationCanceledException) { _checks++; }
        await other;
        Check(handler.Requests.Count == 9, "one waiter cancellation does not cancel shared work");
    }

    private static void Offers()
    {
        var valid = ScmMarketplaceReader.OfferQuery(1, 1, 1, "CN", BridgePayload.From(new { minQuality = "800", maxQuality = "949" }));
        Check(valid.Contains("minQuality=800") && valid.Contains("maxQuality=949"), "offer interval accepted");
        foreach (var max in new[] { "1001", "-1", "abc", "1.5" })
        {
            try { ScmMarketplaceReader.OfferQuery(1, 1, 1, "CN", BridgePayload.From(new { maxQuality = max })); throw new Exception("invalid max accepted"); }
            catch (ArgumentException) { _checks++; }
        }
        try { ScmMarketplaceReader.OfferQuery(1, 1, 1, "CN", BridgePayload.From(new { minQuality = "950", maxQuality = "949" })); throw new Exception("reversed interval accepted"); }
        catch (ArgumentException) { _checks++; }
    }

    private static async Task SelectionEdges()
    {
        var handler = new Handler { EdgeRows = true };
        using var reader = Reader(handler);
        var tier = (await Read(reader)).GetProperty("tiers")[5];
        Check((!tier.TryGetProperty("quality", out var quality) || quality.ValueKind == JsonValueKind.Null), "missing quality remains null");
        Check(tier.GetProperty("best").GetProperty("quality").GetInt32() == 180, "equal exact per-point value prefers higher quality");
        Check(tier.GetProperty("best").GetProperty("price").GetString() == "180", "zero and missing quality excluded from best");
    }

    private static async Task EmptyTop()
    {
        var handler = new Handler { TrendingCount = 1, EmptyBands = true };
        using var reader = Reader(handler);
        var row = (await ReadTrending(reader)).GetProperty("rows")[0];
        Check(row.TryGetProperty("qualityAny", out _) && !row.TryGetProperty("qualityTop", out _), "no top field when all six bands empty");
        Check(handler.Requests.Count == 9, "all six empty top tiers checked");
    }

    private static ScmMarketplaceReader Reader(Handler handler) => new(new("https://quality.invalid/"), handler);
    private static async Task<JsonElement> Read(ScmMarketplaceReader reader, string id = "1") =>
        BridgePayload.From(await reader.ReadAsync("qualityTiers", 0, id, 0, 1, 1, default)).GetProperty("data");
    private static async Task<JsonElement> ReadTrending(ScmMarketplaceReader reader) =>
        BridgePayload.From(await reader.ReadAsync("trending", 0, "", 0, 1, 1, default)).GetProperty("data");
    private static void Check(bool value, string message) { _checks++; if (!value) throw new Exception("CX-T02: " + message); }

    private sealed class Handler : HttpMessageHandler
    {
        internal ConcurrentQueue<Dictionary<string, string>> Requests = new();
        internal Func<long, object?> Info = _ => "{\"quality\":true}";
        internal int Details, TrendingCount, MaxActive;
        internal int? FailMin;
        internal bool TimeoutFailure;
        internal bool EdgeRows, EmptyBands;
        private int _active;
        protected override async Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.RequestUri!.Host != "quality.invalid") throw new Exception("Unexpected host");
            var q = request.RequestUri.Query.TrimStart('?').Split('&').Select(x => x.Split('=', 2)).ToDictionary(x => x[0], x => x[1]);
            Requests.Enqueue(q);
            var active = Interlocked.Increment(ref _active);
            lock (Requests) MaxActive = Math.Max(MaxActive, active);
            try
            {
                await Task.Delay(15, ct);
                var path = request.RequestUri.AbsolutePath;
                if (path.EndsWith("items/get"))
                {
                    Interlocked.Increment(ref Details);
                    return Response(new { categoryId = 12, qualityInfo = Info(long.Parse(q["id"])) });
                }
                if (path.EndsWith("trending-items")) return Response(Enumerable.Range(1, TrendingCount).Select(id => new { id, thumbnailUrl = "https://image.invalid/test" }));
                if (!path.EndsWith("orders/page")) throw new Exception("Unexpected route");
                var min = q.TryGetValue("minQuality", out var raw) ? int.Parse(raw) : -1;
                if (min == FailMin)
                {
                    if (TimeoutFailure) await Task.Delay(Timeout.InfiniteTimeSpan, ct);
                    return new(HttpStatusCode.InternalServerError);
                }
                if (TrendingCount > 0 && q["productId"] == "2" && min == 950) return Response(new { total = 0, list = Array.Empty<object>() });
                if (EmptyBands && min >= 0) return Response(new { total = 0, list = Array.Empty<object>() });
                object Row(int price, int quality) => new { unitPrice = price, itemDetails = new[] { new { qualityData = JsonSerializer.Serialize(new { quality }) } }, creatorId = 999, memberId = 888, contact = "fixture" };
                if (q["pageSize"] == "20")
                {
                    if (EdgeRows && min == 0) return Response(new { total = 4, list = new[] { new { unitPrice = 0 } as object, Row(1, 0), Row(100, 100), Row(180, 180) } });
                    var max = int.Parse(q["maxQuality"]);
                    return Response(new { total = 17, list = new[] { Row(100, min), Row(100, min + 10), Row(101, max) } });
                }
                return Response(new { total = 17, list = new[] { new { unitPrice = 100, itemDetails = new[] { new { qualityData = new { qualityMin = 612 } } } } } });
            }
            finally { Interlocked.Decrement(ref _active); }
        }
        private static HttpResponseMessage Response(object data) => new(HttpStatusCode.OK)
            { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) };
    }
}
