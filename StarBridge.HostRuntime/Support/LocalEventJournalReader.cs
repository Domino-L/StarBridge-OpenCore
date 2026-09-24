namespace StarBridge.HostRuntime.Support;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

public sealed record LocalEventEntry(string Id, DateTimeOffset OccurredAt,
    string Category, string EventType, string Title, string Detail);

public sealed record LocalEventJournalSnapshot(string State, IReadOnlyList<LocalEventEntry> Entries,
    string? ContentRevision = null)
{
    public bool Available => State is "ready" or "missing" or "recovered";
}

/// <summary>Compatibility reader for the WPF normalized journal. Read never
/// creates, prunes, recovers or rewrites files, and never scans Game.log.</summary>
public sealed class LocalEventJournalReader
{
    public const int MaximumEntries = 3000;
    public const int MaximumFileBytes = 8 * 1024 * 1024;
    public static readonly TimeSpan Retention = TimeSpan.FromDays(30);
    private static readonly HashSet<string> Categories = new(StringComparer.Ordinal)
        { "session", "identity", "server", "ship", "location", "life", "other" };
    private static readonly JsonSerializerOptions JsonOptions = new(JsonSerializerDefaults.Web)
        { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow, MaxDepth = 8 };
    private readonly string _path;
    private readonly Func<DateTimeOffset> _now;

    public LocalEventJournalReader(string dataRoot, Func<DateTimeOffset>? now = null)
    {
        if (!Path.IsPathFullyQualified(dataRoot)) throw new ArgumentException("An absolute data root is required.");
        _path = Path.Combine(Path.GetFullPath(dataRoot), "local-event-log.json");
        _now = now ?? (() => DateTimeOffset.UtcNow);
    }

    public LocalEventJournalSnapshot Read()
    {
        var primary = ReadFile(_path);
        if (primary.State == "ready") return Present(primary, "ready");
        var backup = ReadFile(_path + ".bak");
        if (backup.State == "ready") return Present(backup, "recovered");
        return new(primary.State == "missing" && backup.State == "missing" ? "missing" : "unavailable", []);
    }

    private LocalEventJournalSnapshot Present(LocalEventJournalSnapshot loaded, string state)
    {
        var now = _now();
        // Retention is a view here, not an implicit destructive write.
        var entries = loaded.Entries.Where(e => e.OccurredAt <= now.AddMinutes(5) && now - e.OccurredAt <= Retention)
            .GroupBy(e => e.Id, StringComparer.OrdinalIgnoreCase)
            .Select(g => g.OrderByDescending(e => e.OccurredAt).First())
            .OrderBy(e => e.OccurredAt);
        var visible = new List<LocalEventEntry>();
        var identityStates = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        foreach (var original in entries)
        {
            var entry = original with { Category = NormalizeCategory(original.Category) };
            if (entry.Category == "identity" && !string.IsNullOrWhiteSpace(entry.Detail))
            {
                var identity = entry.Detail.Trim();
                if (identityStates.TryGetValue(identity, out var previous) && previous == entry.EventType) continue;
                identityStates[identity] = entry.EventType;
            }
            visible.Add(entry);
        }
        return new(state, visible.TakeLast(MaximumEntries).Reverse().ToArray(), loaded.ContentRevision);
    }

    private static LocalEventJournalSnapshot ReadFile(string path)
    {
        try
        {
            // Open rather than File.Exists: access denied must not become empty.
            // Allow atomic replacement but not an in-place writer to produce a
            // torn view. A writer already holding the file yields unavailable.
            using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
            if (stream.Length is < 2 or > MaximumFileBytes) return new("unavailable", []);
            var bytes = new byte[(int)stream.Length];
            stream.ReadExactly(bytes);
            if (stream.Position != stream.Length) return new("unavailable", []);
            var json = bytes.AsSpan();
            if (json.StartsWith(new byte[] { 0xEF, 0xBB, 0xBF })) json = json[3..];
            var entries = JsonSerializer.Deserialize<List<LocalEventEntry>>(json, JsonOptions);
            if (entries is null || entries.Count > 20000 || entries.Any(e => e is null || !Valid(e)))
                return new("unavailable", []);
            return new("ready", entries, Convert.ToHexString(SHA256.HashData(bytes)));
        }
        catch (FileNotFoundException) { return new("missing", []); }
        catch (DirectoryNotFoundException) { return new("missing", []); }
        catch { return new("unavailable", []); }
    }

    private static bool Valid(LocalEventEntry e) =>
        Text(e.Id, 128, false) && e.OccurredAt != default && Text(e.Category, 80, false) &&
        Text(e.EventType, 80, false) && Text(e.Title, 180, false) && Text(e.Detail, 500, true);
    private static bool Text(string? value, int limit, bool empty) => value is not null && value.Length <= limit &&
        (empty || !string.IsNullOrWhiteSpace(value)) && !value.Any(c => char.IsControl(c));
    private static string NormalizeCategory(string value) => Categories.Contains(value.Trim().ToLowerInvariant())
        ? value.Trim().ToLowerInvariant() : "other";

    public static IReadOnlyList<LocalEventEntry> Filter(LocalEventJournalSnapshot snapshot, string category)
    {
        if (!snapshot.Available) throw new InvalidOperationException("Event history is unavailable.");
        if (category == "all") return snapshot.Entries;
        if (!Categories.Contains(category)) throw new ArgumentException("Unknown event category.");
        return snapshot.Entries.Where(e => e.Category == category).ToArray();
    }

    /// <summary>WPF exports the complete retained history, not the active filter.
    /// This returns text only; file picking/writing belongs to a later slice.</summary>
    public static string FormatExport(LocalEventJournalSnapshot snapshot)
    {
        if (!snapshot.Available) throw new InvalidOperationException("Event history is unavailable.");
        var result = new StringBuilder("星海舰桥本地事件日志\n仅包含应用已经识别的标准化事件，不包含完整 Game.log 原文。\n\n");
        foreach (var e in snapshot.Entries.OrderBy(e => e.OccurredAt))
        {
            result.Append(e.OccurredAt.ToString("yyyy-MM-dd HH:mm:ss zzz"))
                .Append("  [").Append(e.Category).Append("] ").Append(e.Title);
            if (!string.IsNullOrWhiteSpace(e.Detail)) result.Append(" · ").Append(e.Detail);
            result.AppendLine();
        }
        return result.ToString();
    }
}
