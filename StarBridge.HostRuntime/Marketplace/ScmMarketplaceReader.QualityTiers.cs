using System.Collections.Concurrent;
using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed partial class ScmMarketplaceReader
{
    private static readonly (string Key, int Min, int Max)[] QualityBands =
    [ ("legendary", 950, 1000), ("excellent", 800, 949), ("good", 600, 799),
      ("normal", 400, 599), ("poor", 200, 399), ("inferior", 0, 199) ];
    private readonly object _qualityLock = new();
    private readonly Dictionary<(long Id, bool Trending), Task<object>> _qualityReads = new();
    private sealed record QualityCacheEntry(object Data, long Completed, long Sequence);
    private readonly Dictionary<(long Id, bool Trending), QualityCacheEntry> _qualityCache = new();
    private long _qualitySequence;
    private const int QualityCapacity = 2000;

    private sealed class QualityWork
    {
        internal readonly ConcurrentBag<Task> Transports = new();
        internal bool BudgetDenied;
    }

    // In-flight entries survive logical timeouts until every physical price request finishes.
    // One waiter's cancellation never cancels reader-owned shared work.
    private Task<object> CachedQuality(long id, bool trending, CancellationToken ct)
    {
        lock (_qualityLock)
        {
            PruneQualityCache();
            var key = (id, trending);
            if (_qualityReads.TryGetValue(key, out var pending)) return pending.WaitAsync(ct);
            if (_qualityCache.TryGetValue(key, out var cached)) return Task.FromResult(cached.Data).WaitAsync(ct);
            var completion = new TaskCompletionSource<object>(TaskCreationOptions.RunContinuationsAsynchronously);
            _qualityReads[key] = completion.Task;
            _ = CompleteQuality(key, completion);
            return completion.Task.WaitAsync(ct);
        }
    }

    private void PruneQualityCache()
    {
        var now = MonotonicTime.GetTimestamp();
        foreach (var key in _qualityCache.Where(p =>
            MonotonicTime.GetElapsedTime(p.Value.Completed, now) >= TimeSpan.FromMinutes(1)).Select(p => p.Key).ToArray())
            _qualityCache.Remove(key);
    }

    private async Task CompleteQuality((long Id, bool Trending) key, TaskCompletionSource<object> completion)
    {
        var work = new QualityWork();
        try
        {
            var result = key.Trending ? await ReadTrendingQuality(key.Id, work) : await ReadQualityTiers(key.Id, work);
            lock (_qualityLock)
            {
                PruneQualityCache();
                if (!work.BudgetDenied)
                {
                    if (_qualityCache.Count >= QualityCapacity)
                        _qualityCache.Remove(_qualityCache.MinBy(p => p.Value.Sequence).Key);
                    _qualityCache[key] = new(result, MonotonicTime.GetTimestamp(), ++_qualitySequence);
                }
                completion.TrySetResult(result);
            }
        }
        catch (Exception e) { completion.TrySetException(e); }
        finally
        {
            try { await Task.WhenAll(work.Transports); }
            catch (Exception) { /* Observe late transport failures; never replace the returned result. */ }
            lock (_qualityLock) _qualityReads.Remove(key);
        }
    }

    private Task<object> QualityTiers(long id, CancellationToken ct) => CachedQuality(id, false, ct);

    private async Task<object> ReadQualityTiers(long id, QualityWork work)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(6));
        var ct = deadline.Token;
        var metadata = await ReadItemMetadata(id, Stopwatch.GetTimestamp(), true);
        if (metadata is null)
        {
            // Real metadata failures have backoff; admission rejection must be retryable.
            lock (_categoryLock) work.BudgetDenied = !_categoryBackoff.ContainsKey(id);
        }
        var sell = ReadQualityPage(id, 1, null, 1, ct, work);
        var buy = ReadQualityPage(id, 0, null, 1, ct, work);
        var tiers = metadata?.HasQuality == true
            ? QualityBands.Select(b => ReadQualityPage(id, 1, b, 20, ct, work)).ToArray() : [];
        await Task.WhenAll(tiers.Concat([sell, buy]));
        return new
        {
            itemId = id, hasQuality = metadata?.HasQuality,
            sell = new { lowest = sell.Result.Price, quality = sell.Result.Quality, count = sell.Result.Count, known = sell.Result.Known },
            buy = new { highest = buy.Result.Price, count = buy.Result.Count, known = buy.Result.Known },
            tiers = tiers.Select((t, i) => new
            {
                key = QualityBands[i].Key, min = QualityBands[i].Min, max = QualityBands[i].Max,
                lowest = t.Result.Price, quality = t.Result.Quality, best = t.Result.Best,
                bestComplete = t.Result.BestComplete, bestScanned = t.Result.BestScanned, bestRead = t.Result.BestRead,
                count = t.Result.Count, known = t.Result.Known,
            }).ToArray(),
        };
    }

    // BestScanned counts compared quotes (valid nonnegative price and positive quality).
    // BestRead counts every row in the successfully read prefix, including invalid price/quality rows.
    private sealed record QualityPage(string? Price, long? Quality, long? Count, object? Best, bool Known,
        bool BestComplete = false, int BestScanned = 0, int BestRead = 0);
    private static readonly QualityPage UnknownQuality = new(null, null, null, null, false);

    private async Task<QualityPage> ReadQualityPage(long id, int side, (string Key, int Min, int Max)? band,
        int size, CancellationToken ct, QualityWork work, bool userTriggered = true)
    {
        var result = UnknownQuality;
        (string? Price, decimal? Value, long? Quality) best = default;
        var scanned = 0;
        var read = 0;
        var proofValid = true;
        decimal? previousLast = null;
        var maxPages = band is not null && size == 20 ? 3 : 1;
        try
        {
            for (var pageNo = 1; pageNo <= maxPages; pageNo++)
            {
                var route = "sc/orders/page?pageNo=" + pageNo + "&pageSize=" + size + "&displayType=1&productId=" + id +
                    "&creatorType=" + side + "&sortType=price&sortOrder=" + (side == 1 ? "asc" : "desc");
                if (band is { } b) route += "&minQuality=" + b.Min + "&maxQuality=" + b.Max;
                var page = await GetQualitySupplement(route, userTriggered, ct, work);
                var count = Long(page, "total");
                var list = At(page, "list");
                if (count is null or < 0 || list.ValueKind != JsonValueKind.Array || list.GetArrayLength() > size)
                    throw new JsonException("Invalid quality page.");
                var rows = list.EnumerateArray().Select(row =>
                {
                    string? price;
                    try { price = Number(row, "unitPrice"); }
                    catch (JsonException) { price = null; } // Count unreadable prices, but never compare them.
                    return (Price: price, Value: price is null ? (decimal?)null : decimal.Parse(price, CultureInfo.InvariantCulture), Quality: OrderQuality(row));
                }).ToArray();
                read += rows.Length;
                var candidates = rows.Where(row => row.Value is >= 0).ToArray();
                if (pageNo == 1)
                {
                    var lowest = (side == 1 ? candidates.OrderBy(r => r.Value) : candidates.OrderByDescending(r => r.Value))
                        .ThenByDescending(r => r.Quality).FirstOrDefault();
                    result = new(lowest.Price, lowest.Quality, count, null, true);
                }
                foreach (var row in candidates.Where(r => r.Quality is > 0))
                {
                    scanned++;
                    if (best.Price is null || row.Value / row.Quality < best.Value / best.Quality ||
                        row.Value / row.Quality == best.Value / best.Quality && row.Quality > best.Quality)
                        best = row;
                }
                // A malformed row or broken sorting cannot supply a completeness certificate.
                foreach (var row in rows)
                {
                    if (row.Value is null or < 0 || band is { } range &&
                        (row.Quality is null || row.Quality < range.Min || row.Quality > range.Max) ||
                        side == 1 && previousLast is not null && row.Value < previousLast)
                        proofValid = false;
                    previousLast = row.Value;
                }
                var end = (long)(pageNo - 1) * size + rows.Length >= count;
                // An empty/short page contradicting total is not proof of end-of-list.
                var bounded = band is { } tier && previousLast is not null && best.Value is not null &&
                    previousLast / tier.Max >= best.Value / best.Quality;
                var complete = proofValid && (end || bounded);
                object? bestValue = best.Price is null ? null : new
                {
                    price = best.Price, quality = best.Quality,
                    perPoint = decimal.Round(best.Value!.Value / best.Quality!.Value, 4, MidpointRounding.AwayFromZero),
                };
                result = result with { Best = bestValue, BestComplete = complete, BestScanned = scanned, BestRead = read };
                if (complete || rows.Length < size) break;
            }
        }
        catch (CategoryBudgetUnavailableException) { work.BudgetDenied = true; }
        catch (Exception e) when (e is HttpRequestException or JsonException or OperationCanceledException)
        { /* Retain first-page lowest and any comparison work; completeness stays false. */ }
        return result;
    }

    // SCM itemDetails[0].qualityData may be JSON text or an object. Do not project the raw item or seller.
    private static long? OrderQuality(JsonElement row)
    {
        var items = At(row, "itemDetails");
        var first = items.ValueKind == JsonValueKind.Array ? items.EnumerateArray().FirstOrDefault() : default;
        var data = At(first, "qualityData");
        if (data.ValueKind == JsonValueKind.String)
        {
            try { using var json = JsonDocument.Parse(data.GetString()!); return QualityValue(json.RootElement); }
            catch (JsonException) { return null; }
        }
        return QualityValue(data);
    }

    private static long? QualityValue(JsonElement data)
    {
        long? Read(string key) => long.TryParse(At(data, key).ToString(), NumberStyles.None,
            CultureInfo.InvariantCulture, out var value) && value is >= 0 and <= 1000 ? value : null;
        return Read("quality") ?? Read("qualityMin");
    }

    private async Task<object[]> TrendingQuality(object[] rows, CancellationToken ct)
    {
        // One pass, ten cold IDs maximum; image-less rows get first choice of passive budget.
        await WithImagelessCategories(rows, false, ct, markPending: true);
        var targets = rows.Cast<Dictionary<string, object?>>()
            .Where(r => ProjectedId(r.GetValueOrDefault("id")) is > 0)
            .GroupBy(r => ProjectedId(r["id"])!.Value).ToArray();
        Dictionary<long, ItemMetadata> metadata;
        lock (_categoryLock)
        {
            PruneCategories();
            metadata = targets.Where(g => _itemCategories.ContainsKey(g.Key))
                .ToDictionary(g => g.Key, g => _itemCategories[g.Key]);
        }
        var quality = targets.Where(g => metadata.GetValueOrDefault(g.Key)?.HasQuality == true).Take(6)
            .Select(async g => (Group: g, Data: (Dictionary<string, object?>)await CachedQuality(g.Key, true, ct))).ToArray();
        await Task.WhenAll(quality);
        foreach (var task in quality)
            foreach (var row in task.Result.Group)
                foreach (var field in task.Result.Data) row[field.Key] = field.Value;
        return rows;
    }

    private async Task<object> ReadTrendingQuality(long id, QualityWork work)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(6));
        var ct = deadline.Token;
        var any = ReadQualityPage(id, 1, null, 1, ct, work, false);
        var result = new Dictionary<string, object?>();
        foreach (var band in QualityBands)
        {
            var top = await ReadQualityPage(id, 1, band, 1, ct, work, false);
            if (!top.Known) break;
            if (top.Count == 0) continue;
            if (top.Price is not null)
                result["qualityTop"] = new { key = band.Key, min = band.Min, max = band.Max, lowest = top.Price };
            break;
        }
        var lowest = await any;
        if (lowest.Known) result["qualityAny"] = new { lowest = lowest.Price, quality = lowest.Quality };
        return result;
    }
}