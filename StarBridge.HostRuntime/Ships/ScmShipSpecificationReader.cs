using System.Net;
using System.Text.Json;
using StarBridge.Core.Ships;

namespace StarBridge.HostRuntime.Ships;

/// <summary>Anonymous SCM model lookup, bounded transport and model cache. No credentials or media.</summary>
internal sealed class ScmShipSpecificationReader : IDisposable
{
    private readonly HttpClient _http;
    private readonly Uri _base;
    private readonly TimeProvider _time;
    private readonly SemaphoreSlim _gate = new(1, 1);
    private readonly Dictionary<string, ShipSpecifications> _cache = new(StringComparer.OrdinalIgnoreCase);
    private readonly CancellationTokenSource _lifetime = new();
    private Catalogue? _catalogue;
    private readonly ShipNameIndex _names;
    private static readonly Lazy<ShipNameIndex> ClientNames = new(() => ShipNameIndex.Parse(
        Hangar.HangarShipNames.Resource("StarBridge.ShipNamePack.json"),
        Hangar.HangarShipNames.Resource("StarBridge.ShipDisplayCatalog.tsv")));
    // Verified against SCM's public 4.10.2 identity catalogue (2026-10-16).
    // These are exact naming differences, not suffix stripping. Replica, GS,
    // TSG, display and loadout-specific runtime IDs must remain distinct.
    private static readonly IReadOnlyDictionary<string, string> RuntimeAliases =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase) {
            ["CRUS_Spirit_A1"] = "CRUS_A1_Spirit",
            ["CRUS_Spirit_C1"] = "CRUS_C1_Spirit",
            ["ANVL_C8R_Pisces"] = "ANVL_C8R_Pisces_Rescue",
            ["ARGO_MPUV_1T"] = "ARGO_MPUV_Tractor",
            ["ORIG_600i_BIS2951"] = "ORIG_600i_2951_BIS",
            ["ARGO_ATLS_IKTI_ARGOS"] = "ARGO_ATLS_IKTI_Rad"
        };

    internal ScmShipSpecificationReader(Uri apiBase, HttpMessageHandler? handler = null, TimeProvider? time = null,
        ShipNameIndex? names = null)
    {
        if (apiBase.Scheme != Uri.UriSchemeHttps && !apiBase.IsLoopback)
            throw new ArgumentException("An HTTPS SCM API is required.", nameof(apiBase));
        _base = apiBase;
        _time = time ?? TimeProvider.System;
        _names = names ?? ClientNames.Value;
        _http = new(handler ?? new HttpClientHandler { AllowAutoRedirect = false, UseCookies = false }) {
            Timeout = Timeout.InfiniteTimeSpan
        };
    }

    internal async Task<ShipSpecifications> ReadAsync(string model, bool refresh, CancellationToken token)
    {
        // Resolve only established catalog aliases; never fuzzy-match an edition or runtime replica.
        var presentation = Hangar.HangarShipNames.Lookup(model);
        var name = _names.Find(model) ?? _names.Find(presentation.EnglishName);
        var english = name?.EnglishName ?? presentation.EnglishName ?? model;
        var mapping = ScmShipSpecificationMappings.Find(model, name?.RuntimeId, english);
        var query = new ModelQuery(mapping?.ParameterModel ?? english, name?.RuntimeId, mapping);
        // Exact module/source choices and cosmetic provenance must not be collapsed
        // by a shared legacy alias in the local catalogue.
        var runtimeId = (query.RuntimeId ?? "name:" + query.EnglishName.Trim()) + "|source:" +
            query.Mapping?.SourceRuntime + "|paint:" + query.Mapping?.PaintBaseModel +
            "|bundle:" + query.Mapping?.BundleBaseModel;
        await _gate.WaitAsync(token).ConfigureAwait(false);
        try
        {
            var now = _time.GetUtcNow();
            _cache.TryGetValue(runtimeId, out var cached);
            if (!refresh && cached?.FetchedAt is { } fetched && now - fetched <
                (cached.State == "ready" ? TimeSpan.FromHours(6) : TimeSpan.FromMinutes(5))) return cached;
            using var timeout = CancellationTokenSource.CreateLinkedTokenSource(token, _lifetime.Token);
            timeout.CancelAfter(TimeSpan.FromSeconds(18));
            try
            {
                var result = await FetchAsync(query, now, refresh, timeout.Token).ConfigureAwait(false);
                if (_cache.Count >= 128) _cache.Remove(_cache.MinBy(p => p.Value.FetchedAt).Key);
                _cache[runtimeId] = result;
                return result;
            }
            catch (Exception error) when (error is HttpRequestException or JsonException or OperationCanceledException or
                InvalidOperationException or FormatException or KeyNotFoundException or OverflowException)
            {
                token.ThrowIfCancellationRequested();
                _lifetime.Token.ThrowIfCancellationRequested();
                if (cached is { State: "ready", FetchedAt: { } at } && now - at < TimeSpan.FromDays(1))
                    return cached with { Stale = true };
                throw new HttpRequestException("Ship specifications are temporarily unavailable.", error);
            }
        }
        finally { _gate.Release(); }
    }

    private sealed record ModelQuery(string EnglishName, string? RuntimeId, ScmShipSpecificationMapping? Mapping);
    private sealed record CatalogueEntry(long Id, string Name, string? RuntimeId);
    private sealed record Catalogue(DateTimeOffset FetchedAt, IReadOnlyList<CatalogueEntry> Entries);
    private static string NameKey(string value) => string.Concat(value.Where(char.IsLetterOrDigit)).ToUpperInvariant();
    private bool RuntimeMatches(string? keyword, string runtime) =>
        string.Equals(keyword, runtime, StringComparison.OrdinalIgnoreCase) ||
        _names.Find(keyword)?.RuntimeId == runtime ||
        keyword is not null && RuntimeAliases.TryGetValue(keyword, out var alias) && alias == runtime;

    private async Task<ShipSpecifications> FetchAsync(ModelQuery model, DateTimeOffset now, bool refresh, CancellationToken token)
    {
        // SCM substring search is sensitive to spaces/hyphens, word order and renamed
        // display labels. Build a bounded, shared identity index instead. It contains
        // only public vehicle IDs/names/keywords; detailed facts remain lazy per model.
        var catalogue = await ReadCatalogueAsync(now, refresh, token).ConfigureAwait(false);
        var candidates = catalogue.Entries.Where(row => model.Mapping is { } mapping
            ? string.Equals(row.RuntimeId, mapping.SourceRuntime, StringComparison.OrdinalIgnoreCase)
            : model.RuntimeId is { } runtime
            ? RuntimeMatches(row.RuntimeId, runtime) || row.RuntimeId is null &&
                _names.Find(row.Name)?.RuntimeId == runtime
            : NameKey(row.Name) == NameKey(model.EnglishName) ||
                _names.Find(row.Name) is { RuntimeId: null } display &&
                    NameKey(display.EnglishName) == NameKey(model.EnglishName)).ToArray();
        if (candidates.Length == 0 || candidates.Length > 8)
            return new(candidates.Length == 0 ? "notFound" : "ambiguous", model.EnglishName, FetchedAt: now);
        if (candidates.Length != 1) return new("ambiguous", model.EnglishName, FetchedAt: now);
        var selected = candidates[0];
        using var detail = await GetAsync("product/items/get?language=EN&id=" + selected.Id, token).ConfigureAwait(false);
        var item = Data(detail);
        var keyword = ShipSpecificationProjection.Text(item, "keyWord");
        // Recheck identity at the detail boundary: never merge replicas, limited
        // editions or a record changed since the index was read via baseItemKey.
        if (ShipSpecificationProjection.At(item, "id").GetInt64() != selected.Id ||
            !string.Equals(keyword, selected.RuntimeId, StringComparison.OrdinalIgnoreCase) ||
            (model.Mapping is { } selectedMapping
                ? !string.Equals(keyword, selectedMapping.SourceRuntime, StringComparison.OrdinalIgnoreCase)
                : model.RuntimeId is { } known && keyword is not null
                ? !RuntimeMatches(keyword, known)
                : NameKey(ShipSpecificationProjection.Text(item, "itemNameEn") ?? "") != NameKey(selected.Name)))
            throw new JsonException("Catalogue model changed.");
        if (model.Mapping?.RequiredRole is { } role &&
            !string.Equals(ShipSpecificationProjection.Text(ShipSpecificationProjection.At(item, "extendedAttrs"), "role"),
                role, StringComparison.OrdinalIgnoreCase))
            throw new JsonException("Catalogue module changed.");
        if (model.Mapping?.RequiredOriginalName is { } originalName &&
            !string.Equals(ShipSpecificationProjection.Text(ShipSpecificationProjection.At(item, "extendedAttrs"), "originalName"),
                originalName, StringComparison.OrdinalIgnoreCase))
            throw new JsonException("Catalogue reproduction identity changed.");
        return ShipSpecificationProjection.Project(item, model.EnglishName, now) with {
            PaintBaseModel = model.Mapping?.PaintBaseModel,
            BundleBaseModel = model.Mapping?.BundleBaseModel
        };
    }

    private async Task<Catalogue> ReadCatalogueAsync(DateTimeOffset now, bool refresh, CancellationToken token)
    {
        if (!refresh && _catalogue is { } cached && now - cached.FetchedAt < TimeSpan.FromHours(6)) return cached;
        const int pageSize = 100, maximum = 1000;
        var ids = new HashSet<long>();
        int? expected = null;
        for (var page = 1; page <= maximum / pageSize; page++)
        {
            using var search = await GetAsync($"product/items/search-list?pageNo={page}&pageSize={pageSize}&itemType=1&language=EN", token).ConfigureAwait(false);
            var data = Data(search);
            var rows = ShipSpecificationProjection.At(data, "list");
            if (!ShipSpecificationProjection.At(data, "total").TryGetInt32(out var count) || count < 0 || count > maximum ||
                expected.HasValue && expected != count || rows.ValueKind != JsonValueKind.Array ||
                rows.GetArrayLength() != Math.Min(pageSize, count - (page - 1) * pageSize))
                throw new JsonException("Incomplete vehicle catalogue.");
            expected = count;
            foreach (var row in rows.EnumerateArray())
                if (!ShipSpecificationProjection.At(row, "id").TryGetInt64(out var id) || id <= 0 || !ids.Add(id))
                    throw new JsonException("Invalid catalogue identity.");
            if (ids.Count == count) break;
        }
        var entries = new List<CatalogueEntry>();
        foreach (var batch in ids.Chunk(100))
        {
            using var profiles = await GetAsync("product/items/warehouse-profiles?language=EN&ids=" + string.Join(',', batch), token).ConfigureAwait(false);
            var rows = Data(profiles, JsonValueKind.Array);
            if (rows.GetArrayLength() != batch.Length) throw new JsonException("Incomplete catalogue identities.");
            var remaining = batch.ToHashSet();
            foreach (var row in rows.EnumerateArray())
            {
                var name = ShipSpecificationProjection.Text(row, "itemNameEn");
                var keyword = ShipSpecificationProjection.Text(row, "keyWord");
                if (!ShipSpecificationProjection.At(row, "id").TryGetInt64(out var id) || !remaining.Remove(id) ||
                    string.IsNullOrWhiteSpace(name) || name.Length > 240 || keyword?.Length > 240)
                    throw new JsonException("Invalid catalogue identity.");
                entries.Add(new(id, name, keyword));
            }
        }
        return _catalogue = new(now, entries);
    }

    private async Task<JsonDocument> GetAsync(string route, CancellationToken token)
    {
        using var request = new HttpRequestMessage(HttpMethod.Get, new Uri(_base, "app-api/" + route));
        using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, token).ConfigureAwait(false);
        response.EnsureSuccessStatusCode();
        const int maximum = 2 * 1024 * 1024;
        if (response.Content.Headers.ContentLength > maximum) throw new JsonException("Catalogue response too large.");
        await using var stream = await response.Content.ReadAsStreamAsync(token).ConfigureAwait(false);
        using var buffer = new MemoryStream();
        var chunk = new byte[16384];
        int read;
        while ((read = await stream.ReadAsync(chunk, token).ConfigureAwait(false)) > 0)
        {
            if (buffer.Length + read > maximum) throw new JsonException("Catalogue response too large.");
            buffer.Write(chunk, 0, read);
        }
        return JsonDocument.Parse(buffer.ToArray(), new JsonDocumentOptions { MaxDepth = 32 });
    }
    private static JsonElement Data(JsonDocument document, JsonValueKind kind = JsonValueKind.Object)
    {
        var root = document.RootElement;
        if (ShipSpecificationProjection.At(root, "code").GetInt32() != 0 ||
            ShipSpecificationProjection.At(root, "data").ValueKind != kind)
            throw new JsonException("Catalogue request failed.");
        return root.GetProperty("data");
    }
    public void Dispose() { _lifetime.Cancel(); _http.Dispose(); }
}
