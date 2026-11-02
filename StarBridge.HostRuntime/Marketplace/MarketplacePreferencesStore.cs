using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Marketplace;

internal sealed record MarketplaceView(string Keyword = "", long? Category = null, string Relation = "", long RelatedId = 0, string Layout = "cards", int Side = 1, string ItemLayout = "cards", string OrderLayout = "rows");
/// <summary>What a watched item looked like when it was followed (watch tab, G3 0.7.2): the lowest
/// ask and the number of live sell listings then, and when. Local only; compared with fresh reads.</summary>
internal sealed record MarketplaceWatch(long Id, string? Price, long? Count, long At);
internal sealed record MarketplacePreferences(long Revision, long[] Favorites, long[] RecentItems, string[] RecentSearches, MarketplaceView? View = null, string PriceFormat = "auto", MarketplaceWatch[]? Watched = null)
{
    /// <summary>How prices are written, after the SCM site's 价格显示格式: auto follows the UI language.</summary>
    internal static readonly string[] PriceFormats = ["auto", "comma", "intl", "chinese"];
    internal static MarketplacePreferences Empty => new(0, [], [], []);
}

/// <summary>One scoped local file. No legacy import, remote synchronization, media or credentials.</summary>
internal sealed class MarketplacePreferencesStore(string root)
{
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "marketplace-local-v1");
    private readonly object _gate = new();
    private string PathFor(BridgeAccountContext? owner)
    {
        var scope = owner is null ? "anonymous-device" : JsonSerializer.Serialize(owner);
        return Path.Combine(_directory, Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(scope))) + ".json");
    }
    private static void Safe(string path)
    {
        for (string? candidate = Path.GetFullPath(path); candidate is not null; candidate = Path.GetDirectoryName(candidate))
            if ((File.Exists(candidate) || Directory.Exists(candidate)) && File.GetAttributes(candidate).HasFlag(FileAttributes.ReparsePoint))
                throw new IOException("Unsafe local preference path.");
    }
    internal MarketplacePreferences Read(BridgeAccountContext? owner)
    {
        lock (_gate) return ReadCore(owner);
    }
    private MarketplacePreferences ReadCore(BridgeAccountContext? owner)
    {
        Safe(_directory);
        var path = PathFor(owner);
        Safe(path);
        if (!File.Exists(path)) return MarketplacePreferences.Empty;
        if (new FileInfo(path).Length > 65536) return MarketplacePreferences.Empty;
        try
        {
            using var document = JsonDocument.Parse(File.ReadAllText(path));
            return Recover(document.RootElement);
        }
        catch (JsonException) { return MarketplacePreferences.Empty; }
    }
    /// <summary>Reading never fails on content: another version's file or a bad value falls back for that
    /// value alone and everything still valid survives. Bridge writes stay strict (Parse, Validate). Saves
    /// are atomic, so a file nothing can be read from is not expected; it is replaced by the next save.</summary>
    private static MarketplacePreferences Recover(JsonElement body)
    {
        if (body.ValueKind != JsonValueKind.Object) return MarketplacePreferences.Empty;
        var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
        var fields = new Dictionary<string, JsonElement>(StringComparer.OrdinalIgnoreCase);
        foreach (var property in body.EnumerateObject()) fields[property.Name] = property.Value;
        T? Field<T>(string name)
        {
            try { return fields.TryGetValue(name, out var value) ? value.Deserialize<T>(options) : default; }
            catch (JsonException) { return default; }
        }
        long[] Ids(string name, int limit) => fields.TryGetValue(name, out var list) && list.ValueKind == JsonValueKind.Array
            ? list.EnumerateArray().Select(e => e.ValueKind == JsonValueKind.Number && e.TryGetInt64(out var id) ? id : 0)
                .Where(id => id > 0).Distinct().Take(limit).ToArray()
            : [];
        var result = MarketplacePreferences.Empty with
        {
            Revision = Math.Max(Field<long>("revision"), 0),
            Favorites = Ids("favorites", 100),
            RecentItems = Ids("recentItems", 20),
            RecentSearches = fields.TryGetValue("recentSearches", out var searches) && searches.ValueKind == JsonValueKind.Array
                ? searches.EnumerateArray().Where(e => e.ValueKind == JsonValueKind.String).Select(e => e.GetString()!)
                    .Where(s => s.Length <= 100 && !s.Any(char.IsControl)).Distinct().Take(20).ToArray()
                : []
        };
        MarketplacePreferences? Valid(MarketplacePreferences candidate)
        {
            try { Validate(candidate); return candidate; }
            catch (Exception error) when (error is InvalidDataException or ArgumentException) { return null; }
        }
        if (Field<string>("priceFormat") is { } format) result = Valid(result with { PriceFormat = format }) ?? result;
        if (Field<MarketplaceView>("view") is { } view)
            result = Valid(result with { View = view }) ?? Valid(result with { View = view with { Side = 1 } }) ?? result;
        if (fields.TryGetValue("watched", out var watched) && watched.ValueKind == JsonValueKind.Array)
            foreach (var snapshot in watched.EnumerateArray())
            {
                MarketplaceWatch? entry;
                try { entry = snapshot.Deserialize<MarketplaceWatch>(options); }
                catch (JsonException) { continue; }
                if (entry is not null) result = Valid(result with { Watched = [.. result.Watched ?? [], entry] }) ?? result;
            }
        return result;
    }
    internal static MarketplacePreferences Parse(JsonElement body)
    {
        var names = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        if (body.ValueKind != JsonValueKind.Object) throw new InvalidDataException("Invalid preferences.");
        foreach (var property in body.EnumerateObject())
            if (!names.Add(property.Name) || property.Name.ToLowerInvariant() is not ("revision" or "favorites" or "recentitems" or "recentsearches" or "view" or "priceformat" or "watched"))
                throw new InvalidDataException("Invalid preference fields.");
        if (!new[] { "revision", "favorites", "recentitems", "recentsearches" }.All(names.Contains)) throw new InvalidDataException("Missing preference fields.");
        if (body.TryGetProperty("view", out var view) && view.ValueKind != JsonValueKind.Null &&
            (view.ValueKind != JsonValueKind.Object || view.EnumerateObject().Any(p => p.Name.ToLowerInvariant() is not ("keyword" or "category" or "relation" or "relatedid" or "layout" or "side" or "itemlayout" or "orderlayout"))))
            throw new InvalidDataException("Invalid view fields.");
        var value = body.Deserialize<MarketplacePreferences>(new JsonSerializerOptions { PropertyNameCaseInsensitive = true }) ??
            throw new InvalidDataException("Invalid preferences.");
        Validate(value);
        return value;
    }
    internal MarketplacePreferences Save(BridgeAccountContext? owner, MarketplacePreferences value, Func<bool> canCommit)
    {
        Validate(value);
        lock (_gate)
        {
            Safe(_directory);
            Directory.CreateDirectory(_directory);
            var path = PathFor(owner);
            Safe(path); Safe(path + ".lock"); Safe(path + ".tmp");
            using var lease = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None);
            var current = ReadCore(owner);
            if (current.Revision != value.Revision) throw new InvalidDataException("Preference revision changed.");
            var next = value with { Revision = checked(current.Revision + 1) };
            var bytes = JsonSerializer.SerializeToUtf8Bytes(next);
            using (var stream = new FileStream(path + ".tmp", FileMode.Create, FileAccess.Write, FileShare.None))
            { stream.Write(bytes); stream.Flush(true); }
            if (!canCommit()) throw new OperationCanceledException();
            File.Move(path + ".tmp", path, true);
            return next;
        }
    }
    private static void Validate(MarketplacePreferences p)
    {
        if (p.View is { } view && (view.Keyword is null || view.Keyword.Length > 100 || view.Keyword.Any(char.IsControl) ||
            view.Category <= 0 || view.RelatedId < 0 || view.Relation is not ("" or "attachments" or "blueprints") ||
            view.Relation != "" && view.RelatedId <= 0 || view.Layout is not ("cards" or "rows") || view.Side is < 0 or > 2 || view.ItemLayout is not ("cards" or "rows") || view.OrderLayout is not ("cards" or "rows")))
            throw new InvalidDataException("Invalid view preferences.");
        if (p.Watched is { } watched && (watched.Length > 100 || watched.Any(w => w is null || w.Id <= 0 || w.At < 0 ||
                w.Count is < 0 || w.Price is { } price && (price.Length > 32 ||
                    !decimal.TryParse(price, System.Globalization.NumberStyles.Number, System.Globalization.CultureInfo.InvariantCulture, out var value) || value < 0)) ||
            watched.Select(w => w.Id).Distinct().Count() != watched.Length ||
            watched.Any(w => !p.Favorites.Contains(w.Id))))
            throw new InvalidDataException("Invalid watch snapshots.");
        if (p.PriceFormat is null || !MarketplacePreferences.PriceFormats.Contains(p.PriceFormat))
            throw new InvalidDataException("Invalid price format.");
        if (p.Revision < 0 || p.Favorites is null || p.RecentItems is null || p.RecentSearches is null ||
            p.Favorites.Length > 100 || p.RecentItems.Length > 20 || p.RecentSearches.Length > 20 ||
            p.Favorites.Concat(p.RecentItems).Any(id => id <= 0) ||
            p.Favorites.Distinct().Count() != p.Favorites.Length ||
            p.RecentItems.Distinct().Count() != p.RecentItems.Length ||
            p.RecentSearches.Distinct().Count() != p.RecentSearches.Length ||
            p.RecentSearches.Any(s => s is null || s.Length > 100 || s.Any(char.IsControl)))
            throw new InvalidDataException("Invalid preferences.");
    }
}
