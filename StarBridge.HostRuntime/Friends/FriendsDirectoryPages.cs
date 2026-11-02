using System.Text.Json;
using System.Text.Json.Nodes;
using StarBridge.HostRuntime.Account;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Friends;

internal static class FriendsDirectoryPages
{
    internal static readonly string[] Groups = ["friends", "incoming", "outgoing", "blocked", "results"];
    internal static JsonElement Page(JsonElement directory, string id, int offset)
    {
        var total = Groups.Sum(group => directory.GetProperty(group).GetArrayLength());
        if (offset < 0 || offset > total) throw new AccountBridgeHostException("friends.invalid_request");
        var count = Math.Min(100, total - offset);
        while (true)
        {
            var page = new JsonObject { ["schemaVersion"] = 1 };
            foreach (var name in new[] { "query", "refreshedAt" })
                if (directory.TryGetProperty(name, out var value)) page[name] = JsonNode.Parse(value.GetRawText());
            var baseOffset = 0;
            foreach (var group in Groups)
            {
                var source = directory.GetProperty(group);
                var first = Math.Max(0, offset - baseOffset);
                var end = Math.Min(source.GetArrayLength(), offset + count - baseOffset);
                var rows = new JsonArray();
                for (var index = first; index < end; index++) rows.Add(JsonNode.Parse(source[index].GetRawText()));
                page[group] = rows;
                baseOffset += source.GetArrayLength();
            }
            // JsonOptions omits null DTO properties. This metadata deliberately
            // includes nextOffset:null so the terminal-page contract is exact.
            page["page"] = new JsonObject {
                ["snapshotId"] = id, ["offset"] = offset,
                ["nextOffset"] = offset + count < total ? JsonValue.Create(offset + count) : null,
                ["total"] = total
            };
            var bytes = JsonSerializer.SerializeToUtf8Bytes(page, BridgeProtocol.JsonOptions);
            // Reserve room for the original account envelope. A single inline
            // avatar may exceed the preferred half-frame page but not 3/4.
            var limit = count <= 1 ? BridgeProtocol.MaximumFrameBytes * 3 / 4 : BridgeProtocol.MaximumFrameBytes / 2;
            if (bytes.Length <= limit) return JsonSerializer.SerializeToElement(page, BridgeProtocol.JsonOptions);
            if (count <= 1) throw new AccountBridgeHostException("friends.snapshot_too_large");
            count = Math.Max(1, count / 2);
        }
    }
}

/// Bounded immutable business snapshots, never account/root responses.
internal sealed class FriendsDirectoryPageStore(TimeProvider? clock = null)
{
    private readonly TimeProvider _clock = clock ?? TimeProvider.System;
    private readonly object _gate = new();
    private readonly Dictionary<string, Entry> _entries = new(StringComparer.Ordinal);
    private const int MaxEntries = 4, MaxBytes = 16 * 1024 * 1024;
    private sealed record Entry(JsonElement Directory, BridgeAccountContext Owner, long Generation,
        string Partition, Func<bool> Current, int Bytes, DateTimeOffset Expires, long Order, DateTimeOffset? CachedAtUtc);
    private long _order;

    internal JsonElement Open(JsonElement directory, BridgeAccountContext owner, long generation,
        string partition, Func<bool> current, DateTimeOffset? cachedAtUtc = null)
    {
        var bytes = JsonSerializer.SerializeToUtf8Bytes(directory, BridgeProtocol.JsonOptions).Length;
        if (bytes > MaxBytes) throw new AccountBridgeHostException("friends.snapshot_too_large");
        lock (_gate)
        {
            Prune();
            if (!current()) throw Changed();
            var id = Guid.NewGuid().ToString("N");
            var entry = new Entry(directory.Clone(), owner, generation, partition, current, bytes,
                _clock.GetUtcNow().AddMinutes(1), ++_order, cachedAtUtc);
            var page = FriendsDirectoryPages.Page(entry.Directory, id, 0);
            if (!current()) throw Changed();
            // An unpageable new directory must not evict an existing valid one.
            while (_entries.Count >= MaxEntries || _entries.Values.Sum(entry => entry.Bytes) + bytes > MaxBytes)
                _entries.Remove(_entries.MinBy(pair => pair.Value.Order).Key);
            _entries.Add(id, entry);
            return page;
        }
    }

    internal JsonElement Read(string id, int offset, BridgeAccountContext owner, long generation, string partition)
        => ReadCore(id, offset, owner, generation, partition).Page;

    internal (JsonElement Directory, DateTimeOffset CachedAtUtc) ReadCached(
        string id, int offset, BridgeAccountContext owner, long generation, string partition)
    {
        var result = ReadCore(id, offset, owner, generation, partition);
        return (result.Page, result.CachedAtUtc ?? throw Changed());
    }

    private (JsonElement Page, DateTimeOffset? CachedAtUtc) ReadCore(
        string id, int offset, BridgeAccountContext owner, long generation, string partition)
    {
        lock (_gate)
        {
            Prune();
            if (!_entries.TryGetValue(id, out var entry) || entry.Owner != owner || entry.Generation != generation ||
                entry.Partition != partition || !entry.Current()) throw Changed();
            var page = FriendsDirectoryPages.Page(entry.Directory, id, offset);
            if (!entry.Current()) { _entries.Remove(id); throw Changed(); }
            return (page, entry.CachedAtUtc);
        }
    }

    internal void Clear() { lock (_gate) _entries.Clear(); }
    private void Prune()
    {
        foreach (var id in _entries.Where(pair => pair.Value.Expires <= _clock.GetUtcNow() || !pair.Value.Current()).Select(pair => pair.Key).ToArray())
            _entries.Remove(id);
    }
    private static AccountBridgeHostException Changed() => new("friends.snapshot_changed", true);
}
