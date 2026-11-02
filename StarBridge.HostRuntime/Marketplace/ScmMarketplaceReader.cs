using StarBridge.HostRuntime.Account;
using System.Globalization;
using System.Net;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Marketplace;

/// <summary>Anonymous, bounded public SCM reads. Identity references are supplied only by the account owner.</summary>
internal sealed partial class ScmMarketplaceReader : IDisposable
{
    private readonly HttpClient _http;
    private readonly Uri _base;
    private readonly SemaphoreSlim _gate = new(4);
    private readonly CancellationTokenSource _lifetime = new();
    internal ScmMarketplaceReader(Uri baseUri, HttpMessageHandler? handler = null)
    {
        if (baseUri.Scheme != "https" && !baseUri.IsLoopback) throw new ArgumentException("HTTPS required.");
        _base = baseUri;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
        { Timeout = Timeout.InfiniteTimeSpan };
    }

    internal async Task<object> ReadAsync(string operation, long id, string keyword, long category, int side, int page,
        CancellationToken token, string language = "CN", JsonElement options = default,
        Func<JsonElement, string?>? traderReference = null)
    {
        using var deadline = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
        deadline.CancelAfter(TimeSpan.FromSeconds(18));
        var ct = deadline.Token;
        object value;
        switch (operation)
        {
            case "marketItems":
            case "marketOrders":
                value = await Browse(operation, keyword, category, page, language, options, ct, traderReference);
                break;
            case "locations":
                value = Page(await Get("sc/address/simple-page?pageNo=" + page + "&pageSize=50&tradeEnabled=true&keyword=" + Uri.EscapeDataString(keyword), ct), p => Pick(p, "id", "name", "nameEn", "fullPath"));
                break;
            case "categories":
                // The tree and the catalogue total are independent: read them side by side, so the
                // hall's slowest first-screen read is one round trip, not two.
                var treeRead = CategoryTree(ct);
                var totalRead = CatalogTotal(ct);
                await Task.WhenAll(treeRead, totalRead);
                value = new { rows = Rows(await treeRead, Category), total = await totalRead };
                break;
            case "qualityTiers":
                if (!Regex.IsMatch(keyword, @"\A[0-9]{1,9}\z")) throw new ArgumentException("Invalid quality tier request.");
                value = await QualityTiers(long.Parse(keyword, CultureInfo.InvariantCulture), ct);
                break;
            case "bestPrices":
                // "itemId:side,…" (side 1 sell → lowest ask, 0 buy → highest bid); one 1-row page each.
                if (!System.Text.RegularExpressions.Regex.IsMatch(keyword, @"^\d{1,9}:[01](,\d{1,9}:[01]){0,9}$"))
                    throw new ArgumentException("Invalid best price request.");
                var pairs = keyword.Split(',').Select(p => p.Split(':')).Select(p => (id: long.Parse(p[0]), side: int.Parse(p[1]))).Distinct().ToArray();
                var bests = await Task.WhenAll(pairs.Select(async pair =>
                {
                    try
                    {
                        var page = await Get("sc/orders/page?pageNo=1&pageSize=1&displayType=1&productId=" + pair.id + "&creatorType=" + pair.side +
                            "&sortType=price&sortOrder=" + (pair.side == 0 ? "desc" : "asc") + "&language=" + language, ct);
                        var first = At(page, "list").ValueKind == JsonValueKind.Array ? At(page, "list").EnumerateArray().FirstOrDefault() : default;
                        return (pair.id, pair.side, price: first.ValueKind == JsonValueKind.Object ? Number(first, "unitPrice") : null, known: true);
                    }
                    catch (Exception e) when (e is HttpRequestException or JsonException) { return (pair.id, pair.side, price: (string?)null, known: false); }
                }));
                value = new { rows = bests.Where(b => b.known).Select(b => new { id = b.id, side = b.side, price = b.price }).ToArray() };
                break;
            case "categoryListings":
                // Active listings per top-level category: SCM expands a category to its children and the
                // public page lists only live orders, so one 1-row page per root gives the on-sale count.
                var tree = await CategoryTree(ct);
                var roots = tree.EnumerateArray().Where(c => (Long(c, "parentId") ?? 0) == 0)
                    .Select(c => Long(c, "id")).OfType<long>().Take(30).ToArray();
                var counts = await Task.WhenAll(roots.Select(async root =>
                {
                    try { return (id: root, count: Long(await Get("sc/orders/page?pageNo=1&pageSize=1&categoryId=" + root, ct), "total")); }
                    catch (Exception e) when (e is HttpRequestException or JsonException) { return (id: root, count: (long?)null); }
                }));
                value = new { rows = counts.Select(c => new { id = c.id, count = c.count }).ToArray() };
                break;
            case "trending":
                value = new { rows = await TrendingQuality(
                    Rows(await Get("sc/orders/trending-items?pageSize=15&language=" + language, ct), Trending), ct) };
                break;
            case "latest":
                // side 3: no type filter, so SCM returns every type (single, checklist, barter, sell and buy);
                // each card already reads its own creatorType/displayType.
                var filter = side == 3 ? "" : side == 2 ? "&displayType=3" : "&creatorType=" + side + "&displayType=1";
                value = await QuotePage(await Get("sc/orders/page?pageNo=" + page + "&pageSize=20&sortType=time&sortOrder=desc&language=" + language + filter, ct), ct, traderReference, markPending: page == 1);
                break;
            case "timezones":
                value = new { rows = Rows(await Get("member/timezone/list", ct), TimeZone) };
                break;
            case "hotWords":
                value = new { rows = Rows(await Get("product/items/hot-words", ct), p => Pick(p, "itemId", "itemName", "itemNameEn")).Take(10).ToArray() };
                break;
            case "search":
                value = Page(await Get("product/items/search-list?pageNo=" + page + "&pageSize=20&keyword=" +
                    Uri.EscapeDataString(keyword) + (category > 0 ? "&categoryId=" + category : ""), ct), Item);
                break;
            case "item":
                value = Item(await Get("product/items/get?id=" + id, ct));
                break;
            case "offers":
                value = await QuotePage(await Get("sc/orders/page?" + OfferQuery(id, side, page, language, options), ct), ct, traderReference);
                break;
            case "trend":
                var trend = await Get("sc/orders/price-trend-v2?productId=" + id, ct);
                value = new { overallPrice = Number(trend, "overallPrice"), sellVWAP = Number(trend, "sellVWAP"),
                    buyVWAP = Number(trend, "buyVWAP"), rows = Rows(At(trend, "trendData"), p => Pick(p, "date", "sellPrice", "buyPrice", "transactionVolume")) };
                break;
            case "acquisition":
                value = new { rows = Rows(await Get("member/item/acquisition/list?itemId=" + id, ct),
                    p => Pick(p, "id", "title", "description", "source", "difficulty", "updateTime")) };
                break;
            case "blueprints":
                var item = await Get("product/items/get?id=" + id, ct);
                var uuid = Text(item, "uuid");
                if (!Guid.TryParse(uuid, out _)) { value = new { rows = Array.Empty<object>(), missing = "materialIdentity" }; break; }
                value = Page(await Get("product/blueprint/page?pageNo=" + page + "&pageSize=20&materialGuid=" +
                    Uri.EscapeDataString(uuid!), ct), p => Pick(p, "id", "blueprintName", "blueprintNameCn", "thumbnailUrl"));
                break;
            case "attachments":
                value = await Attachments(id, language, ct);
                break;
            default: throw new ArgumentException("Unsupported public read.");
        }
        ct.ThrowIfCancellationRequested();
        return new { schemaVersion = 1, readAt = DateTimeOffset.UtcNow, data = value };
    }

    /// <summary>Per-item offer page. Only presence, location, minimum quality and price direction may vary; everything else is fixed.</summary>
    internal static string OfferQuery(long id, int side, int page, string language, JsonElement options)
    {
        var values = BrowseOptions(options);
        if (values.Keys.Any(k => k is not ("creatorStatus" or "locationId" or "minQuality" or "maxQuality" or "sortOrder")))
            throw new ArgumentException("Filter is not available for offers.");
        if (values.TryGetValue("minQuality", out var min) && values.TryGetValue("maxQuality", out var max) &&
            int.Parse(min) > int.Parse(max)) throw new ArgumentException("Invalid quality interval.");
        var fields = new Dictionary<string, string>
        {
            ["pageNo"] = page.ToString(), ["pageSize"] = "20", ["displayType"] = "1", ["productId"] = id.ToString(),
            ["creatorType"] = side.ToString(), ["language"] = language, ["sortType"] = "price",
            ["sortOrder"] = values.GetValueOrDefault("sortOrder", side == 0 ? "desc" : "asc"),
        };
        foreach (var (key, value) in values) fields[key] = value;
        return string.Join("&", fields.Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));
    }

    private async Task<object> Attachments(long id, string language, CancellationToken ct)
    {
        var item = await Get("product/items/get?id=" + id, ct);
        var ports = At(At(item, "extendedAttrs"), "ports");
        if (ports.ValueKind != JsonValueKind.Array || ports.GetArrayLength() > 32)
            return new { rows = Array.Empty<object>(), missing = "attachmentPorts" };
        var rows = new Dictionary<long, object>();
        var filters = new List<object>();
        foreach (var port in ports.EnumerateArray())
        {
            var types = At(port, "types");
            foreach (var (type, name) in new[] { ("Barrel", "barrel"), ("IronSight", "optics"), ("BottomAttachment", "underbarrel") })
            {
                if (Text(port, "name") != name && !(types.ValueKind == JsonValueKind.Array && types.EnumerateArray().Any(t => t.ValueKind == JsonValueKind.String && t.GetString() == type))) continue;
                var min = Long(port, "minSize"); var max = Long(port, "maxSize");
                if (min is null or < 0 or > 100 || max is null or > 100 || max < min)
                    return new { rows = Array.Empty<object>(), missing = "attachmentSizes" };
                var tags = At(port, "requiredTags");
                if (tags.ValueKind is not (JsonValueKind.Array or JsonValueKind.Undefined or JsonValueKind.Null) ||
                    tags.ValueKind == JsonValueKind.Array && (tags.GetArrayLength() > 20 || tags.EnumerateArray().Any(t => t.ValueKind != JsonValueKind.String || t.GetString()!.Length > 100 || t.GetString()!.Contains(','))))
                    return new { rows = Array.Empty<object>(), missing = "attachmentTags" };
                var required = tags.ValueKind == JsonValueKind.Array ? string.Join(",", tags.EnumerateArray().Select(t => t.GetString())) : "";
                var data = await Get("product/items/weapon-attachments?subType=" + type + "&minSize=" + min + "&maxSize=" + max + "&requiredTags=" + Uri.EscapeDataString(required) + "&language=" + language, ct);
                filters.Add(new { subType = type, minSize = min, maxSize = max, requiredTags = required });
                if (data.ValueKind != JsonValueKind.Array || data.GetArrayLength() > 1000) throw new JsonException("Invalid attachments.");
                foreach (var candidate in data.EnumerateArray())
                    if (Long(candidate, "id") is > 0 and var candidateId) rows[candidateId] = Item(candidate);
            }
        }
        return new { rows = rows.Values.ToArray(), total = rows.Count, filters, missing = filters.Count == 0 ? "attachmentPorts" : null };
    }

    private static object Page(JsonElement data, Func<JsonElement, object> project)
    {
        var total = Long(data, "total");
        if (total is null or < 0) throw new JsonException("Missing page total.");
        return new { rows = Rows(At(data, "list"), project), total };
    }
    private static object[] Rows(JsonElement value, Func<JsonElement, object> project)
    {
        if (value.ValueKind != JsonValueKind.Array || value.GetArrayLength() > 1000) throw new JsonException("Invalid public list.");
        return value.EnumerateArray().Select(project).ToArray();
    }
    private static object Item(JsonElement p)
    {
        var result = Pick(p, "id", "categoryId", "uuid", "itemName", "itemNameEn", "description", "descriptionEn",
            "thumbnailUrl", "thumbnailUrlHd", "sellOrderCount", "buyOrderCount", "checklistSellCount", "checklistBuyCount",
            "dataVersion", "itemType", "variantGroupId", "baseItemKey", "variantType", "qualityInfo");
        if (At(p, "variants").ValueKind == JsonValueKind.Array)
            result["variants"] = Rows(At(p, "variants"), x => Pick(x, "id", "itemName", "itemNameEn", "thumbnailUrl", "variantType"));
        return result;
    }
    /// <summary>SCM time zones with the offset in force now, so DST is applied the way the SCM website does.</summary>
    internal static object TimeZone(JsonElement p)
    {
        var result = Pick(p, "id", "value", "label", "offset", "offsetMinutes");
        var current = Long(p, "offsetMinutes");
        var zone = Text(p, "value");
        if (zone is { Length: > 0 and <= 64 } && TimeZoneInfo.TryFindSystemTimeZoneById(zone, out var info))
            current = (long)info.GetUtcOffset(DateTimeOffset.UtcNow).TotalMinutes;
        result["currentOffsetMinutes"] = current is >= -14 * 60 and <= 14 * 60 ? current : null;
        return result;
    }
    private static object Category(JsonElement p) => Pick(p, "id", "parentId", "name", "nameEn", "picUrl", "icon", "sort", "filterConfig");
    private static object Trending(JsonElement p) => Pick(p, "id", "itemName", "itemNameEn", "thumbnailUrl", "price", "changePercent", "sellPrice", "buyPrice", "orderCount");
    private static object Quote(JsonElement p, Func<JsonElement, string?>? traderReference)
    {
        // Never send contact details, account IDs or private warehouse fields to Flutter.
        // Only validated RSI avatar URLs may be sent; the Host does not download these images.
        var result = Pick(p, "orderNumber", "creatorType", "remainingQuantity", "availableQuantity", "unitPrice",
            "createTime", "itemName", "thumbnailUrl", "locationId", "locationName", "tradeStartTime", "tradeEndTime", "displayType", "timezoneId",
            "hasOngoingTransactions");
        // The order's public note, as SCM's market list shows it; bounded for the detail sheet.
        var remark = Pick(p, "remark")["remark"] as string;
        result["remark"] = string.IsNullOrWhiteSpace(remark) ? null : remark.Trim() is { Length: > 500 } trimmed ? trimmed[..500] : remark.Trim();
        var tradeTime = At(p, "tradeTime");
        // SCM exposes seven weekday flags either as JSON text or as an array.
        result["tradeTime"] = tradeTime.ValueKind is JsonValueKind.Array or JsonValueKind.String
            ? tradeTime.ValueKind == JsonValueKind.String ? tradeTime.GetString() : tradeTime.GetRawText()
            : null;
        result["avatar"] = RsiAvatarImage.Validate(Text(p, "avatar"))?.AbsoluteUri;
        result["seller"] = Mask(Text(p, "nickname"));
        if (traderReference?.Invoke(p) is { } reference) result["traderRef"] = reference;
        result["point"] = Number(p, "point");
        var status = Long(p, "creatorStatus");
        result["presence"] = status == 1 ? "online" : status == 2 ? "game" : status is null ? "unknown" : "offline";
        if (At(p, "itemDetails").ValueKind == JsonValueKind.Array)
            result["items"] = Rows(At(p, "itemDetails"), x => Pick(x, "itemId", "itemName", "thumbnailUrl", "quantity", "unitPrice", "qualityData", "qualityInfo"));
        if (At(p, "wantedItems").ValueKind == JsonValueKind.Array)
            result["wantedItems"] = Rows(At(p, "wantedItems"), x => Pick(x, "itemId", "itemName", "thumbnailUrl", "quantity", "unitPrice", "qualityData"));
        return result;
    }
    private static string? Mask(string? name)
    {
        if (string.IsNullOrEmpty(name)) return null;
        if (name.Contains('*')) return name;
        return name.Length < 2 ? "*" : name[..1] + "*****" + name[^1..];
    }
    private static readonly HashSet<string> Numbers = new(StringComparer.Ordinal)
    { "price", "unitPrice", "changePercent", "sellPrice", "buyPrice", "point" };
    private static Dictionary<string, object?> Pick(JsonElement p, params string[] keys)
    {
        if (p.ValueKind != JsonValueKind.Object) throw new JsonException("Invalid public object.");
        var result = new Dictionary<string, object?>();
        foreach (var key in keys)
        {
            var v = At(p, key);
            if (v.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) { result[key] = null; continue; }
            if (Numbers.Contains(key)) { result[key] = Number(p, key); continue; }
            if (v.ValueKind == JsonValueKind.String)
            {
                var text = v.GetString()!;
                if (text.Length > 16000) throw new JsonException("Oversized public text.");
                text = Regex.Replace(text, @"<[^>]*>", "", RegexOptions.None, TimeSpan.FromMilliseconds(100));
                text = WebUtility.HtmlDecode(text);
                result[key] = text;
                if (key is "itemName" or "name" or "description" or "title" or "content" or "locationName" or "blueprintNameCn")
                    result[key + "Hant"] = Traditional(text);
            }
            else if (v.ValueKind is JsonValueKind.Number or JsonValueKind.True or JsonValueKind.False)
                result[key] = v.Clone();
            else throw new JsonException("Unexpected public field.");
        }
        return result;
    }
    internal static JsonElement At(JsonElement p, string key) =>
        p.ValueKind == JsonValueKind.Object && p.TryGetProperty(key, out var v) ? v : default;
    private static string? Text(JsonElement p, string key) => At(p, key).ValueKind == JsonValueKind.String ? At(p, key).GetString() : null;
    private static long? Long(JsonElement p, string key) => At(p, key).TryGetInt64Safe();
    private static string? Number(JsonElement p, string key)
    {
        var v = At(p, key);
        if (v.ValueKind is JsonValueKind.Null or JsonValueKind.Undefined) return null;
        if (decimal.TryParse(v.ToString(), NumberStyles.Float, CultureInfo.InvariantCulture, out var number) &&
            Math.Abs(number) <= 9007199254740991m) return number.ToString(CultureInfo.InvariantCulture);
        throw new JsonException("Invalid public number.");
    }

    // Windows supplies the conversion data; no downloaded dictionary or destructive ID/name rewrite.
    internal static string Traditional(string value)
    {
        if (!OperatingSystem.IsWindows() || value.Length == 0) return value;
        var buffer = new StringBuilder(value.Length * 2 + 2);
        // Include the terminator: StringBuilder marshalling requires a terminated
        // output; explicit source lengths otherwise leave trailing native bytes.
        var length = LCMapStringEx("zh-TW", 0x04000000, value, -1, buffer, buffer.Capacity, IntPtr.Zero, IntPtr.Zero, 0);
        return length > 0 ? buffer.ToString() : value;
    }
    [DllImport("kernel32.dll", CharSet = CharSet.Unicode)]
    private static extern int LCMapStringEx(string locale, uint flags, string source, int sourceLength,
        StringBuilder destination, int destinationLength, IntPtr version, IntPtr reserved, nint sortHandle);

    private async Task<long?> CatalogTotal(CancellationToken ct)
    {
        try { return Long(await Get("product/items/search-list?pageNo=1&pageSize=1", ct), "total"); }
        catch (Exception e) when (e is HttpRequestException or JsonException) { return null; }
    }

    // The category tree changes rarely and feeds the hall tiles, the per-category counts and the market
    // filters. One shared read serves concurrent callers; a good copy is reused for ten minutes, a failed
    // or cancelled read is never cached.
    private static readonly TimeSpan CategoryTreeLifetime = TimeSpan.FromMinutes(10);
    private readonly object _treeLock = new();
    private Task<JsonElement>? _tree;
    private DateTimeOffset _treeStarted;
    internal Func<DateTimeOffset> Clock { get; init; } = () => DateTimeOffset.UtcNow;

    private Task<JsonElement> CategoryTree(CancellationToken ct)
    {
        lock (_treeLock)
        {
            var current = _tree;
            var reusable = current is not null && !current.IsFaulted && !current.IsCanceled &&
                (!current.IsCompleted || Clock() - _treeStarted < CategoryTreeLifetime);
            if (!reusable)
            {
                // Owned by the reader, not by the first caller: one caller giving up must not cancel the
                // read the others are waiting on. The usual per-read deadline still applies.
                var deadline = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token);
                deadline.CancelAfter(TimeSpan.FromSeconds(18));
                current = Get("product/items/category-list", deadline.Token);
                _ = current.ContinueWith(_ => deadline.Dispose(), TaskScheduler.Default);
                _tree = current;
                _treeStarted = Clock();
            }
            return current!.WaitAsync(ct);
        }
    }

    private async Task<JsonElement> Get(string route, CancellationToken ct, Func<bool>? admitCategory = null)
    {
        await _gate.WaitAsync(ct);
        try
        {
            ct.ThrowIfCancellationRequested();
            if (admitCategory is not null && !admitCategory()) throw new CategoryBudgetUnavailableException();
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_base, "app-api/" + route));
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, ct);
            if (admitCategory is not null && response.StatusCode == HttpStatusCode.TooManyRequests)
                PauseCategories(response);
            response.EnsureSuccessStatusCode();
            const int max = 1024 * 1024;
            if (response.Content.Headers.ContentLength > max) throw new JsonException("Public response too large.");
            await using var input = await response.Content.ReadAsStreamAsync(ct);
            using var bytes = new MemoryStream();
            var buffer = new byte[16384];
            int count;
            while ((count = await input.ReadAsync(buffer, ct)) > 0)
            {
                if (bytes.Length + count > max) throw new JsonException("Public response too large.");
                bytes.Write(buffer, 0, count);
            }
            using var json = JsonDocument.Parse(bytes.ToArray(), new JsonDocumentOptions { MaxDepth = 32 });
            if (Long(json.RootElement, "code") != 0) throw new HttpRequestException("Public read rejected.");
            var data = At(json.RootElement, "data");
            if (data.ValueKind is not (JsonValueKind.Array or JsonValueKind.Object)) throw new JsonException("Invalid public data.");
            return data.Clone();
        }
        finally { _gate.Release(); }
    }
    public void Dispose() { _lifetime.Cancel(); _http.Dispose(); }
}
internal static class MarketplaceJson
{
    internal static long? TryGetInt64Safe(this JsonElement value) =>
        value.ValueKind == JsonValueKind.Number && value.TryGetInt64(out var result) ? result : null;
}
