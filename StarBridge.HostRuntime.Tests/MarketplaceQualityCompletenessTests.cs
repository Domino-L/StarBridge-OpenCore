using System.Collections;
using System.Collections.Concurrent;
using System.Net;
using System.Reflection;
using System.Text.Json;
using StarBridge.HostRuntime.Marketplace;
using StarBridge.NativeBridge;

internal static class MarketplaceQualityCompletenessTests
{
    private static int _checks;
    internal static async Task Run()
    {
        await Pagination("second", true, 21, 2, "101");
        await Pagination("cap", false, 60, 3, "100");
        await Pagination("proof", true, 20, 1, "100");
        await ComparisonCountsAndPrecision();
        await PartialBudget();
        await WorstCase();
        await PhysicalLifetime();
        await Capacity();
        await BudgetRetry();
        await FailureCache();
        await Top();
        Console.WriteLine($"PASS CX-T12 quality completeness: {_checks} assertions, fake transport only");
    }

    private static async Task Pagination(string mode, bool complete, int scanned, int pages, string price)
    {
        var handler = new Handler { Mode = mode };
        using var reader = Reader(handler, new MarketplaceTestTime());
        var tier = (await Read(reader)).GetProperty("tiers")[2];
        Check(tier.GetProperty("best").GetProperty("price").GetString() == price, mode + ": best across pages");
        Check(tier.GetProperty("bestComplete").GetBoolean() == complete, mode + ": completeness");
        Check(tier.GetProperty("bestScanned").GetInt32() == scanned, mode + ": compared count");
        Check(tier.GetProperty("bestRead").GetInt32() == scanned, mode + ": read prefix across pages");
        Check(handler.Queries.Count(q => q.GetValueOrDefault("minQuality") == "600") == pages, mode + ": page count");
        Check(tier.GetProperty("lowest").GetString() == "100", mode + ": lowest remains first page");
    }

    private static async Task ComparisonCountsAndPrecision()
    {
        var handler = new Handler { Mode = "mixed" };
        using var reader = Reader(handler, new MarketplaceTestTime());
        var tier = (await Read(reader)).GetProperty("tiers")[2];
        Check(tier.GetProperty("bestScanned").GetInt32() == 2, "CX-T16: only valid positive-quality quotes compared");
        Check(tier.GetProperty("bestRead").GetInt32() == 6, "CX-T16: zero/missing quality and invalid prices included in read prefix");
        var best = tier.GetProperty("best");
        Check(best.GetProperty("price").GetString() == "100" && best.GetProperty("quality").GetInt64() == 600,
            "CX-T16: exact ratio wins even when rounded ratios tie and competitor quality is higher");
        Check(best.GetProperty("perPoint").GetDecimal() == 0.1667m, "CX-T16: 100/600 retains four decimals instead of zero");
        Check(!tier.GetProperty("bestComplete").GetBoolean(), "CX-T16: malformed rows cannot prove completeness");
        var empty = (await Read(reader)).GetProperty("tiers")[0];
        Check(empty.GetProperty("bestRead").GetInt32() == 0 && empty.GetProperty("bestScanned").GetInt32() == 0,
            "CX-T16: empty tier has zero reads and comparisons");
        using var midpointReader = Reader(new Handler { Mode = "midpoint" }, new MarketplaceTestTime());
        var midpoint = (await Read(midpointReader)).GetProperty("tiers")[2].GetProperty("best");
        Check(midpoint.GetProperty("perPoint").GetDecimal() == 0.0313m, "CX-T16: midpoint rounds away from zero");
    }

    private static async Task PartialBudget()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler();
        using var reader = Reader(handler, time);
        var budget = Field<Queue<long>>(reader, "_userQualityRequests");
        for (var i = 0; i < 54; i++) budget.Enqueue(time.GetTimestamp());
        time.Advance(TimeSpan.FromSeconds(59));
        var tier = (await Read(reader)).GetProperty("tiers")[2];
        Check(tier.GetProperty("known").GetBoolean() && !tier.GetProperty("bestComplete").GetBoolean(), "pagination admission denial retains known first page");
        Check(tier.GetProperty("bestScanned").GetInt32() == 20 && handler.Sends == 6, "partial scan consumes only remaining budget");
        time.Advance(TimeSpan.FromSeconds(1));
        Check(tier.GetProperty("bestRead").GetInt32() == 20, "CX-T16: budget denial retains read prefix");
        tier = (await Read(reader)).GetProperty("tiers")[2];
        Check(tier.GetProperty("bestComplete").GetBoolean() && tier.GetProperty("best").GetProperty("price").GetString() == "101", "partial budget result not cached");
    }

    private static async Task WorstCase()
    {
        var handler = new Handler { Mode = "worst" };
        using var reader = Reader(handler, new MarketplaceTestTime());
        var data = await Read(reader);
        Check(handler.Sends == 21, "cold worst case: metadata + two summary quotes + eighteen tier pages");
        Check(data.GetProperty("tiers").EnumerateArray().All(t => !t.GetProperty("bestComplete").GetBoolean() &&
            t.GetProperty("bestScanned").GetInt32() == 60), "all six tiers capped at sixty comparisons");
        await Read(reader, 2);
        await Read(reader, 3);
        Check(handler.Sends == 60, "three worst-case cold items still bounded by sixty sends");
    }

    private static async Task PhysicalLifetime()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler { Hold = true };
        using var reader = Reader(handler, time);
        try
        {
            await Read(reader);
            var sent = handler.Sends;
            Check(Field<IDictionary>(reader, "_qualityReads").Count == 1, "physical requests retain in-flight entry after deadline");
            time.Advance(TimeSpan.FromSeconds(61));
            await Read(reader);
            Check(handler.Sends == sent, "expired result cannot duplicate unfinished physical work");
        }
        finally { handler.Release.TrySetResult(); }
        var limit = DateTime.UtcNow.AddSeconds(2);
        while (Field<IDictionary>(reader, "_qualityReads").Count != 0 && DateTime.UtcNow < limit)
            await Task.Delay(10);
        Check(Field<IDictionary>(reader, "_qualityReads").Count == 0, "physical completion releases in-flight registration");
    }
    private static async Task Capacity()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler { HasQuality = false };
        using var reader = Reader(handler, time);
        for (var id = 1; id <= 2001; id++)
        {
            // Isolate cache capacity from the independently tested sliding-window admission.
            Field<Queue<long>>(reader, "_userQualityRequests").Clear();
            await Read(reader, id);
        }
        var cache = Field<IDictionary>(reader, "_qualityCache");
        Check(cache.Count == 2000, "2001 completed IDs bounded to 2000");
        Check(!cache.Contains((1L, false)) && cache.Contains((2001L, false)), "oldest completion evicted");
        time.Advance(TimeSpan.FromSeconds(60));
        await Read(reader, 2002);
        Check(cache.Count == 1, "expired entries pruned on read/write");
        Check(Field<IDictionary>(reader, "_qualityReads").Count == 0, "completed work removed from in-flight registry");
    }

    private static async Task BudgetRetry()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler();
        using var reader = Reader(handler, time);
        var budget = Field<Queue<long>>(reader, "_userQualityRequests");
        for (var i = 0; i < 60; i++) budget.Enqueue(time.GetTimestamp());
        time.Advance(TimeSpan.FromSeconds(59));
        var denied = await Read(reader);
        Check(!denied.GetProperty("sell").GetProperty("known").GetBoolean() && handler.Sends == 0, "exhausted user budget sends nothing");
        time.Advance(TimeSpan.FromSeconds(1));
        var retry = await Read(reader);
        Check(retry.GetProperty("sell").GetProperty("known").GetBoolean() && handler.Sends > 0, "budget unknown retried before cache TTL");
    }

    private static async Task FailureCache()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler { Fail = true };
        using var reader = Reader(handler, time);
        await Read(reader);
        var sent = handler.Sends;
        await Read(reader);
        Check(handler.Sends == sent, "real failure remains short cached");
        time.Advance(TimeSpan.FromSeconds(60));
        await Read(reader);
        Check(handler.Sends > sent, "real failure cache expires");
    }

    private static async Task Top()
    {
        var time = new MarketplaceTestTime();
        var handler = new Handler { Mode = "top" };
        using var reader = Reader(handler, time);
        var row = (await Trending(reader)).GetProperty("rows")[0];
        Check(row.GetProperty("qualityTop").GetProperty("key").GetString() == "good", "highest stocked tier can be good");
        Check(handler.Queries.Count(q => q.ContainsKey("minQuality")) == 3, "descending search stops at good");
        var sent = handler.Sends;
        await Trending(reader);
        Check(handler.Sends == sent + 1, "trending completion cache used first");
        time.Advance(TimeSpan.FromSeconds(60));
        var passive = Field<Queue<long>>(reader, "_categoryRequests");
        for (var i = 0; i < 29; i++) passive.Enqueue(time.GetTimestamp());
        row = (await Trending(reader)).GetProperty("rows")[0];
        Check(!row.TryGetProperty("qualityTop", out _), "passive exhaustion omits top");
        Check(handler.Sends == sent + 3 && passive.Count == 30, "passive exhaustion never exceeds admission cap");
    }

    private static T Field<T>(object value, string name) =>
        (T)value.GetType().GetField(name, BindingFlags.NonPublic | BindingFlags.Instance)!.GetValue(value)!;
    private static ScmMarketplaceReader Reader(Handler handler, MarketplaceTestTime time) =>
        new(new("https://quality-completeness.invalid/"), handler) { Clock = time.GetUtcNow, MonotonicTime = time };
    private static async Task<JsonElement> Read(ScmMarketplaceReader reader, int id = 1) =>
        BridgePayload.From(await reader.ReadAsync("qualityTiers", 0, id.ToString(), 0, 1, 1, default)).GetProperty("data");
    private static async Task<JsonElement> Trending(ScmMarketplaceReader reader) =>
        BridgePayload.From(await reader.ReadAsync("trending", 0, "", 0, 1, 1, default)).GetProperty("data");
    private static void Check(bool value, string message)
    {
        _checks++;
        if (!value) throw new Exception("CX-T12: " + message);
    }

    private sealed class Handler : HttpMessageHandler
    {
        internal string Mode = "second";
        internal bool HasQuality = true, Fail, Hold;
        internal readonly TaskCompletionSource Release = new(TaskCreationOptions.RunContinuationsAsynchronously);
        internal int Sends;
        internal ConcurrentQueue<Dictionary<string, string>> Queries = new();
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken ct)
        {
            if (request.RequestUri!.Host != "quality-completeness.invalid") throw new Exception("Unexpected host");
            Interlocked.Increment(ref Sends);
            var q = request.RequestUri.Query.TrimStart('?').Split('&')
                .Select(x => x.Split('=', 2)).ToDictionary(x => x[0], x => x[1]);
            var path = request.RequestUri.AbsolutePath;
            if (path.EndsWith("items/get")) return Response(new { categoryId = 12, qualityInfo = HasQuality ? new { quality = true } : null });
            if (path.EndsWith("trending-items")) return Response(new[] { new { id = 1, thumbnailUrl = "https://image.invalid/fixture" } });
            if (!path.EndsWith("orders/page")) throw new Exception("Unexpected route");
            Queries.Enqueue(q);
            if (Hold) return Held();
            if (Fail) return Task.FromResult(new HttpResponseMessage(HttpStatusCode.InternalServerError));
            var min = q.GetValueOrDefault("minQuality");
            if (min is null) return Response(new { total = 1, list = new[] { Row(100, 600) } });
            if (Mode == "worst" && min is not null) return Response(new { total = 100, list = Enumerable.Range(0, 20).Select(_ => Row(100, Math.Max(1, int.Parse(min)))) });
            if (min != "600") return Response(new { total = 0, list = Array.Empty<object>() });
            if (Mode == "mixed") return Response(new { total = 6, list = new object[]
            {
                Row(1, 0), new { unitPrice = 2 }, new { unitPrice = "invalid" }, Row(-1, 700),
                Row(100, 600), new { unitPrice = 100.17m, itemDetails = new[] { new { qualityData = new { quality = 601 } } } },
            } });
            if (Mode == "midpoint") return Response(new { total = 1, list = new[] { Row(20, 640) } });
            var page = int.Parse(q["pageNo"]);
            if (Mode == "top") return Response(new { total = 1, list = new[] { Row(100, 600) } });
            if (Mode == "second" && page == 2) return Response(new { total = 21, list = new[] { Row(101, 799) } });
            var quality = Mode == "proof" ? 799 : 600;
            return Response(new { total = Mode == "second" ? 21 : 100, list = Enumerable.Range(0, 20).Select(_ => Row(100, quality)) });
        }
        private async Task<HttpResponseMessage> Held()
        {
            await Release.Task; // Deliberately ignores cancellation, never touches the network.
            return await Response(new { total = 0, list = Array.Empty<object>() });
        }
        private static object Row(int price, int quality) =>
            new { unitPrice = price, itemDetails = new[] { new { qualityData = new { quality } } } };
        private static Task<HttpResponseMessage> Response(object data) => Task.FromResult(new HttpResponseMessage(HttpStatusCode.OK)
            { Content = new StringContent(JsonSerializer.Serialize(new { code = 0, data })) });
    }
}
