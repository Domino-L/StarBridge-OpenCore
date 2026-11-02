using System.Diagnostics;
using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed partial class ScmMarketplaceReader
{
    private readonly object _categoryLock = new();
    private sealed record ItemMetadata(long? Category, bool HasQuality, DateTimeOffset Expires);
    private readonly Dictionary<long, ItemMetadata> _itemCategories = new();
    private readonly Dictionary<long, long> _categoryBackoff = new();
    private readonly Dictionary<long, Task<ItemMetadata?>> _categoryReads = new();
    private readonly Queue<long> _categoryRequests = new();
    private readonly Queue<long> _userQualityRequests = new();
    private const int CategoryCapacity = 2000;
    private readonly SemaphoreSlim _categoryGate = new(3);

    private async Task<object> QuotePage(JsonElement data, CancellationToken ct, Func<JsonElement, string?>? traderReference, bool markPending = false)
    {
        var total = Long(data, "total");
        if (total is null or < 0) throw new JsonException("Missing page total.");
        return new { rows = await WithImagelessCategories(Rows(At(data, "list"), p => Quote(p, traderReference)), true, ct, markPending), total };
    }

    // Only the first displayed item chooses the placeholder. Quote exposes no top-level item ID;
    // orderNumber and wantedItems identify different things and must never be used as a fallback.
    // A listing with a picture takes a category that is already known, for when the picture fails,
    // but only a listing without one spends a request on it.
    private async Task<object[]> WithImagelessCategories(object[] rows, bool quotes, CancellationToken ct, bool markPending = false)
    {
        lock (_categoryLock) PruneCategories();
        var candidates = new Dictionary<long, List<(Dictionary<string, object?> Row, Dictionary<string, object?>? Item)>>();
        foreach (var row in rows.Cast<Dictionary<string, object?>>())
        {
            var first = row.GetValueOrDefault("items") is object[] { Length: > 0 } items
                ? items[0] as Dictionary<string, object?> : null;
            if (quotes && ProjectedId(row.GetValueOrDefault("displayType")) == 2) continue;
            var id = ProjectedId(quotes ? first?.GetValueOrDefault("itemId") : row.GetValueOrDefault("id"));
            if (id is not > 0) continue;
            if (!candidates.TryGetValue(id.Value, out var targets))
            {
                candidates[id.Value] = targets = new();
            }
            targets.Add((row, first));
        }
        if (candidates.Count == 0) return rows;

        var started = Stopwatch.GetTimestamp();
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(ct);
        deadline.CancelAfter(TimeSpan.FromSeconds(2));
        static bool HasImage((Dictionary<string, object?> Row, Dictionary<string, object?>? Item) target) =>
            !string.IsNullOrWhiteSpace(target.Row.GetValueOrDefault("thumbnailUrl") as string) ||
            !string.IsNullOrWhiteSpace(target.Item?.GetValueOrDefault("thumbnailUrl") as string);
        bool Wanted(long id) => !quotes || candidates[id].Any(t => !HasImage(t));
        void Fill(long id, long category)
        {
            foreach (var (row, first) in candidates[id])
            {
                row["categoryId"] = category;
                if (quotes && first is not null) first["categoryId"] = category;
            }
        }
        long[] cold;
        lock (_categoryLock)
        {
            foreach (var id in candidates.Keys)
                if (_itemCategories.TryGetValue(id, out var entry) && entry.Category is long category) Fill(id, category);
            cold = candidates.Keys.Where(id => Wanted(id) && !_itemCategories.ContainsKey(id) && !_categoryBackoff.ContainsKey(id))
                .OrderBy(id => candidates[id].All(HasImage))
                .Take(10).ToArray();
        }
        var tasks = cold.Select(id => (Id: id, Read: ReadItemMetadata(id, started))).ToArray();
        // A misbehaving transport must not hold up the page. Workers only return values and cache
        // successes; they never mutate rows after the response has been returned.
        try { await Task.WhenAll(tasks.Select(t => t.Read)).WaitAsync(deadline.Token); }
        catch (OperationCanceledException) { }
        foreach (var (id, read) in tasks)
        {
            if (!read.IsCompletedSuccessfully || read.Result?.Category is not long category) continue;
            Fill(id, category);
        }
        // No answer yet is not "no category": the client reads these pages again a few times.
        if (!markPending) return rows;
        lock (_categoryLock)
        {
            if (CategoriesPaused(MonotonicTime.GetTimestamp())) return rows;
            foreach (var id in candidates.Keys.Where(id => Wanted(id) && !_itemCategories.ContainsKey(id) && !_categoryBackoff.ContainsKey(id)))
                foreach (var target in candidates[id].Where(t => !quotes || !HasImage(t)))
                    target.Row["categoryPending"] = true;
        }
        return rows;
    }

    private static long? ProjectedId(object? value) => value switch
    {
        JsonElement json => json.TryGetInt64Safe(),
        string text when long.TryParse(text, NumberStyles.None, CultureInfo.InvariantCulture, out var id) => id,
        _ => null,
    };

    // Every access is under _categoryLock, including eviction and admission.
    private void PruneCategories()
    {
        var now = Clock();
        var stamp = MonotonicTime.GetTimestamp();
        foreach (var id in _itemCategories.Where(p => p.Value.Expires <= now).Select(p => p.Key).ToArray())
            _itemCategories.Remove(id);
        foreach (var id in _categoryBackoff.Where(p => MonotonicTime.GetElapsedTime(p.Value, stamp) >= TimeSpan.FromMinutes(5)).Select(p => p.Key).ToArray())
            _categoryBackoff.Remove(id);
        while (_userQualityRequests.TryPeek(out var userSent) && MonotonicTime.GetElapsedTime(userSent, stamp) >= TimeSpan.FromMinutes(1)) _userQualityRequests.Dequeue();
        while (_categoryRequests.TryPeek(out var sent) && MonotonicTime.GetElapsedTime(sent, stamp) >= TimeSpan.FromMinutes(1)) _categoryRequests.Dequeue();
    }

    private void CategoryFailed(long id)
    {
        lock (_categoryLock)
        {
            PruneCategories();
            if (!_categoryBackoff.ContainsKey(id) && _categoryBackoff.Count >= CategoryCapacity)
                _categoryBackoff.Remove(_categoryBackoff.MaxBy(p => MonotonicTime.GetElapsedTime(p.Value)).Key);
            _categoryBackoff[id] = MonotonicTime.GetTimestamp();
        }
    }

    private bool AdmitCategoryRequest(bool userTriggered = false)
    {
        lock (_categoryLock)
        {
            PruneCategories();
            var now = MonotonicTime.GetTimestamp();
            var requests = userTriggered ? _userQualityRequests : _categoryRequests;
            if (CategoriesPaused(now) || requests.Count >= (userTriggered ? 60 : 30)) return false;
            requests.Enqueue(now);
            return true;
        }
    }

    private Task<ItemMetadata?> ReadItemMetadata(long id, long started, bool userTriggered = false)
    {
        lock (_categoryLock)
        {
            PruneCategories();
            var now = MonotonicTime.GetTimestamp();
            if (_itemCategories.TryGetValue(id, out var entry)) return Task.FromResult<ItemMetadata?>(entry);
            if (_categoryReads.TryGetValue(id, out var shared)) return shared;
            if (_categoryBackoff.ContainsKey(id) || CategoriesPaused(now) || (userTriggered ? _userQualityRequests.Count >= 60 : _categoryRequests.Count >= 30) ||
                _categoryReads.Count >= 30) return Task.FromResult<ItemMetadata?>(null);
            var completion = new TaskCompletionSource<ItemMetadata?>(TaskCreationOptions.RunContinuationsAsynchronously);
            _categoryReads[id] = completion.Task;
            _ = FetchItemCategory(id, completion, started, userTriggered);
            return completion.Task;
        }
    }

    private async Task FetchItemCategory(long id, TaskCompletionSource<ItemMetadata?> completion, long started, bool userTriggered)
    {
        // The shared request belongs to the reader, not the first page's cancellation token.
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
        var remaining = TimeSpan.FromSeconds(2) - Stopwatch.GetElapsedTime(started);
        deadline.CancelAfter(remaining > TimeSpan.Zero ? remaining : TimeSpan.Zero);
        var ct = deadline.Token;
        var entered = false;
        Task<JsonElement>? transport = null;
        ItemMetadata? result = null;
        try
        {
            await _categoryGate.WaitAsync(ct);
            entered = true;
            ct.ThrowIfCancellationRequested();
            // Admission runs inside Get, after its shared gate, immediately before sending.
            transport = Get("product/items/get?id=" + id.ToString(CultureInfo.InvariantCulture), ct, () =>
            {
                if (Stopwatch.GetElapsedTime(started) >= TimeSpan.FromSeconds(2)) throw new TimeoutException();
                return AdmitCategoryRequest(userTriggered);
            });
            var data = await transport.WaitAsync(ct);
            var category = Long(data, "categoryId");
            ct.ThrowIfCancellationRequested();
            if (Stopwatch.GetElapsedTime(started) >= TimeSpan.FromSeconds(2)) throw new TimeoutException();
            if (category is not > 0 && At(data, "qualityInfo").ValueKind == JsonValueKind.Undefined)
            { CategoryFailed(id); return; }
            result = new ItemMetadata(category is > 0 ? category : null, HasQuality(At(data, "qualityInfo")), Clock().AddHours(24));
            lock (_categoryLock)
            {
                PruneCategories();
                if (_itemCategories.Count >= CategoryCapacity)
                    _itemCategories.Remove(_itemCategories.MinBy(p => p.Value.Expires).Key);
                _itemCategories[id] = result;
            }
        }
        catch (CategoryBudgetUnavailableException) { }
        // Out of time, usually still queued behind the hall's first reads: that says nothing about
        // this item, so the next read asks again instead of waiting out the backoff.
        catch (OperationCanceledException) when (ct.IsCancellationRequested) { }
        catch (TimeoutException) { }
        // Optional artwork metadata never makes an otherwise usable market page fail.
        catch (Exception) { CategoryFailed(id); }
        finally
        {
            // Keep physical concurrency bounded if SendAsync ignores cancellation. Only three
            // such requests can remain; later pages time out their optional wait, leaving the
            // fourth Get slot for main reads. Observe late faults without caching late results.
            lock (_categoryLock)
            {
                completion.TrySetResult(result);
                if (entered && transport is { IsCompleted: false })
                    _ = transport.ContinueWith(t =>
                    {
                        _ = t.Exception;
                        lock (_categoryLock) _categoryReads.Remove(id);
                        _categoryGate.Release();
                    }, TaskScheduler.Default);
                else
                {
                    _categoryReads.Remove(id);
                    if (entered) _categoryGate.Release();
                }
            }
        }
    }

    private sealed class CategoryBudgetUnavailableException : Exception { }

    private static bool HasQuality(JsonElement value)
    {
        if (value.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return false;
        if (value.ValueKind == JsonValueKind.Object) return value.EnumerateObject().Any();
        if (value.ValueKind != JsonValueKind.String) return true;
        var text = value.GetString()?.Trim();
        if (string.IsNullOrEmpty(text)) return false;
        try { using var json = JsonDocument.Parse(text); return HasQuality(json.RootElement); }
        catch (JsonException) { return true; }
    }
}
