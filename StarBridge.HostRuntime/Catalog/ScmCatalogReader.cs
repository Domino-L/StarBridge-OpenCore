using System.Globalization;
using System.Text.Json;

namespace StarBridge.HostRuntime.Catalog;

/// <summary>Anonymous, demand-only catalogue reads. No account client, cookies or retries.</summary>
internal sealed class ScmCatalogReader : IDisposable
{
    private static readonly SemaphoreSlim GlobalSlots = new(2, 2);
    private static readonly CatalogRequestBudget SharedBudget = new(TimeProvider.System);
    private readonly HttpClient _http;
    private readonly Uri _base;
    private readonly TimeProvider _time;
    // Resolved per request: the runtime installs its device gate after composition.
    private readonly Func<Lifecycle.DeviceNetworkAdmission?>? _network;
    private readonly CancellationTokenSource _lifetime = new();
    private readonly object _sync = new();
    private readonly Dictionary<string, (JsonElement Value, long At, TimeSpan Ttl)> _cache = new();
    private readonly Dictionary<string, Task<JsonElement>> _pending = new();
    private readonly CatalogRequestBudget _budget;
    private bool _disposed;
    internal TimeSpan Timeout { get; init; } = TimeSpan.FromSeconds(18);

    internal ScmCatalogReader(Uri baseUri, HttpMessageHandler? handler = null, TimeProvider? time = null,
        Func<Lifecycle.DeviceNetworkAdmission?>? network = null, CatalogRequestBudget? budget = null)
    {
        if (baseUri.Scheme != "https" || !string.IsNullOrEmpty(baseUri.UserInfo) ||
            !string.IsNullOrEmpty(baseUri.Query) || !string.IsNullOrEmpty(baseUri.Fragment))
            throw new ArgumentException("HTTPS origin required.");
        _base = baseUri;
        _time = time ?? TimeProvider.System;
        _network = network;
        // Production runtimes in this process share one client budget, even after re-composition.
        _budget = budget ?? (time is null ? SharedBudget : new(_time));
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false })
            { Timeout = System.Threading.Timeout.InfiniteTimeSpan };
    }

    internal Task<JsonElement> ReadAsync(string operation, JsonElement input, CancellationToken token = default)
    {
        token.ThrowIfCancellationRequested();
        var (route, ttl, refresh) = Request(operation, input);
        Task<JsonElement> task;
        TaskCompletionSource<JsonElement>? source = null;
        Lifecycle.DeviceNetworkAdmission.Lease? lease = null;
        lock (_sync)
        {
            ObjectDisposedException.ThrowIf(_disposed, this);
            // Refresh invalidates exactly this query. It still joins an existing physical request.
            if (refresh) _cache.Remove(route);
            if (_pending.TryGetValue(route, out task!)) return task.WaitAsync(token);
            var now = _time.GetTimestamp();
            foreach (var key in _cache.Where(p => _time.GetElapsedTime(p.Value.At, now) >= p.Value.Ttl)
                         .Select(p => p.Key).ToArray()) _cache.Remove(key);
            if (_cache.TryGetValue(route, out var cached)) return Task.FromResult(cached.Value);
            // Admission first: a request the device gate refuses never spends quota.
            if (_network is not null)
            {
                lease = _network()?.Enter(_lifetime.Token);
                if (lease is null) throw new CatalogReadException("catalog.unavailable");
            }
            try { _budget.Admit(GlobalSlots); }
            catch { lease?.Dispose(); throw; }
            source = new(TaskCreationOptions.RunContinuationsAsynchronously);
            task = source.Task;
            _pending.Add(route, task);
        }
        _ = FetchAsync(operation, route, ttl, source, lease);
        // A caller abandoning a shared read never cancels the other callers.
        return task.WaitAsync(token);
    }

    private async Task FetchAsync(string operation, string route, TimeSpan ttl, TaskCompletionSource<JsonElement> source,
        Lifecycle.DeviceNetworkAdmission.Lease? lease)
    {
        JsonElement value = default;
        Exception? failure = null;
        try
        {
            using var work = lease;
            using var deadline = CancellationTokenSource.CreateLinkedTokenSource(_lifetime.Token, work?.Token ?? CancellationToken.None);
            deadline.CancelAfter(Timeout);
            work?.RequireCurrent();
            using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_base, "app-api/product/blueprint/" + route));
            using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, deadline.Token);
            if ((int)response.StatusCode == 429) throw new CatalogReadException("catalog.rate_limited");
            response.EnsureSuccessStatusCode();
            const int maximum = 1024 * 1024;
            if (response.Content.Headers.ContentLength > maximum) throw new JsonException();
            await using var input = await response.Content.ReadAsStreamAsync(deadline.Token);
            using var bytes = new MemoryStream();
            var buffer = new byte[16384];
            int count;
            while ((count = await input.ReadAsync(buffer, deadline.Token)) > 0)
            {
                if (bytes.Length + count > maximum) throw new JsonException();
                bytes.Write(buffer, 0, count);
            }
            using var document = JsonDocument.Parse(bytes.ToArray(), new JsonDocumentOptions { MaxDepth = 32 });
            var root = document.RootElement;
            if (CatalogProjection.At(root, "code").ValueKind != JsonValueKind.Number ||
                !CatalogProjection.At(root, "code").TryGetInt32(out var code) || code != 0)
                throw new JsonException();
            value = JsonSerializer.SerializeToElement(new
            {
                schemaVersion = 1, data = CatalogProjection.Project(operation, CatalogProjection.At(root, "data"))
            });
            lock (_sync)
            {
                if (!_disposed) _cache[route] = (value, _time.GetTimestamp(), ttl);
            }
        }
        catch (Exception error)
        {
            failure = error is CatalogReadException ? error : new CatalogReadException("catalog.unavailable");
        }
        finally { GlobalSlots.Release(); }
        lock (_sync) _pending.Remove(route);
        if (failure is null) source.TrySetResult(value);
        else source.TrySetException(failure);
    }

    internal static readonly IReadOnlySet<string> Operations = new HashSet<string>(StringComparer.Ordinal)
    {
        "missions.page", "missions.filters", "missions.detail", "blueprints.page", "blueprints.filters",
        "blueprints.detail", "blueprints.missions"
    };

    internal static (string Route, TimeSpan Ttl, bool Refresh) Request(string operation, JsonElement input)
    {
        if (!Operations.Contains(operation) || input.ValueKind != JsonValueKind.Object || input.GetRawText().Length > 4096)
            throw new ArgumentException("Invalid catalogue request.");
        var names = input.EnumerateObject().Select(p => p.Name).ToArray();
        if (names.Distinct(StringComparer.Ordinal).Count() != names.Length) throw new ArgumentException();
        var allowed = operation switch
        {
            "missions.page" => new[] { "keyword", "missionType", "system", "category", "faction", "issuer", "blueprintPoolGuid", "hasBlueprintRewards", "canBeShared", "illegal", "sortField", "sortOrder", "pageNo", "pageSize" },
            "blueprints.page" => ["keyword", "categoryName", "subcategory", "manufacturer", "itemClass", "grade", "isReward", "pageNo", "pageSize"],
            "blueprints.filters" => ["categoryName", "subcategory"],
            "missions.detail" => ["guid"],
            "blueprints.detail" or "blueprints.missions" => ["id"],
            _ => Array.Empty<string>()
        };
        if (names.Any(n => n is not ("schemaVersion" or "refresh") && !allowed.Contains(n))) throw new ArgumentException();
        var values = new SortedDictionary<string, string>(StringComparer.Ordinal);
        foreach (var property in input.EnumerateObject())
        {
            var name = property.Name;
            var value = property.Value;
            if (name == "schemaVersion")
            {
                if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt32(out var version) || version != 1) throw new ArgumentException();
                continue;
            }
            if (name == "refresh")
            {
                if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException();
                continue;
            }
            if (name is "hasBlueprintRewards" or "canBeShared" or "illegal" or "isReward")
            {
                if (value.ValueKind is not (JsonValueKind.True or JsonValueKind.False)) throw new ArgumentException();
                values[name] = value.GetBoolean() ? "true" : "false";
            }
            else if (name is "id" or "pageNo" or "pageSize")
            {
                if (value.ValueKind != JsonValueKind.Number || !value.TryGetInt64(out var number) || number < 1 ||
                    name == "pageNo" && number > 10000 || name == "pageSize" && number != 20)
                    throw new ArgumentException();
                values[name] = number.ToString(CultureInfo.InvariantCulture);
            }
            else
            {
                if (value.ValueKind != JsonValueKind.String) throw new ArgumentException();
                var text = value.GetString()!.Trim();
                if (text.Length > 200 || text.Any(char.IsControl)) throw new ArgumentException();
                if (name == "category" && text.Length > 64 ||
                    name == "blueprintPoolGuid" && !Guid.TryParseExact(text, "D", out _)) throw new ArgumentException();
                if (name == "subcategory" && text.Length == 0) continue;
                values[name] = text;
            }
        }
        if (operation == "missions.detail" && (!values.TryGetValue("guid", out var guid) || !Guid.TryParse(guid, out _))) throw new ArgumentException();
        if (operation is "blueprints.detail" or "blueprints.missions" && !values.ContainsKey("id")) throw new ArgumentException();
        if (operation.EndsWith(".page", StringComparison.Ordinal)) { values.TryAdd("pageNo", "1"); values["pageSize"] = "20"; }
        if (operation == "missions.page")
        {
            values.TryAdd("sortField", "rewardUec"); values.TryAdd("sortOrder", "desc");
            if (values["sortField"] is not ("rewardUec" or "title") || values["sortOrder"] is not ("asc" or "desc")) throw new ArgumentException();
        }
        // The controller requires categoryName even for the all-category filter query.
        if (operation == "blueprints.filters") values.TryAdd("categoryName", "");
        var path = operation switch
        {
            "missions.page" => "mission-page", "missions.filters" => "mission-filters", "missions.detail" => "mission-by-guid",
            "blueprints.page" => "page", "blueprints.filters" => "filter-options", "blueprints.detail" => "get-detail", _ => "reward-mission-details"
        };
        var query = string.Join("&", values.Select(p => Uri.EscapeDataString(p.Key) + "=" + Uri.EscapeDataString(p.Value)));
        var ttl = operation.EndsWith(".filters", StringComparison.Ordinal) ? TimeSpan.FromHours(1) :
            operation.EndsWith(".page", StringComparison.Ordinal) ? TimeSpan.FromMinutes(10) : TimeSpan.FromMinutes(30);
        return (path + (query.Length == 0 ? "" : "?" + query), ttl, CatalogProjection.At(input, "refresh").ValueKind == JsonValueKind.True);
    }

    public void Dispose()
    {
        lock (_sync) { if (_disposed) return; _disposed = true; _cache.Clear(); }
        _lifetime.Cancel();
        _http.Dispose();
    }
}

internal sealed class CatalogReadException(string code) : Exception("Catalogue read unavailable.")
{
    internal string Code { get; } = code;
}

/// <summary>Rolling monotonic per-client quota; injectable only for isolated regression clocks.</summary>
internal sealed class CatalogRequestBudget(TimeProvider time)
{
    private readonly object _sync = new();
    private readonly Queue<long> _sent = new();
    private long? _last;
    internal void Admit(SemaphoreSlim slots)
    {
        lock (_sync)
        {
            var now = time.GetTimestamp();
            while (_sent.TryPeek(out var at) && time.GetElapsedTime(at, now) >= TimeSpan.FromHours(1)) _sent.Dequeue();
            if (_last is { } last && time.GetElapsedTime(last, now) < TimeSpan.FromSeconds(1) || _sent.Count >= 120)
                throw new CatalogReadException("catalog.rate_limited");
            // No queue or delayed refill, including global concurrency exhaustion.
            if (!slots.Wait(0)) throw new CatalogReadException("catalog.rate_limited");
            _sent.Enqueue(now);
            _last = now;
        }
    }
}
