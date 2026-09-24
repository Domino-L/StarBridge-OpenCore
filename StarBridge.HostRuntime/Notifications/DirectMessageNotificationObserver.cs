namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;

// This is an event source, not a second inbox. It retains only opaque keys and
// high-water marks, never message text. Call before delivery-policy checks so
// muted/foreground messages cannot replay later.
internal sealed class DirectMessageNotificationObserver(TimeProvider? time = null)
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private string? _owner;
    private long _generation, _received;
    private DateTimeOffset? _server;
    private Dictionary<string, long> _sequences = new(StringComparer.Ordinal);
    internal IReadOnlyList<string> FreshKeys { get; private set; } = [];
    internal void Reset() { _owner = null; _server = null; _sequences.Clear(); FreshKeys = []; }

    internal bool Observe(BridgeEnvelope request, BridgeEnvelope response, long generation)
    {
        FreshKeys = [];
        if (request.Name != "directMessages.read" || request.Payload.TryGetProperty("targetRef", out _) ||
            request.SessionGeneration != generation) return false;
        if (response.Status != "ok" || request.AccountContext == null ||
            response.AccountContext != request.AccountContext || response.SessionGeneration != generation) {
            Reset(); return false;
        }
        try {
            var root = response.Payload;
            if (root.GetProperty("schemaVersion").GetInt32() != 1) throw new JsonException();
            var server = root.GetProperty("serverTime").GetDateTimeOffset();
            var owner = JsonSerializer.Serialize(request.AccountContext);
            var sameOwner = owner == _owner && generation == _generation;
            if (sameOwner && server <= _server) return false;
            var array = root.GetProperty("conversations");
            if (array.GetArrayLength() > 2000) throw new JsonException();
            var rows = new Dictionary<string, (long Sequence, bool Incoming, int Unread, DateTimeOffset Created)>(StringComparer.Ordinal);
            foreach (var row in array.EnumerateArray()) {
                var key = row.GetProperty("conversationKey").GetString();
                if (key is not { Length: 64 } || key.Any(c => !char.IsAsciiHexDigit(c))) throw new JsonException();
                // Older contracts are readable, but insufficient for notifications.
                if (!row.TryGetProperty("latestSequence", out var sequence) || sequence.ValueKind == JsonValueKind.Null ||
                    !row.TryGetProperty("lastMessageIncoming", out var incoming) || incoming.ValueKind == JsonValueKind.Null) {
                    Reset(); return false;
                }
                var number = sequence.GetInt64();
                var unread = row.GetProperty("unreadCount").GetInt32();
                var created = row.GetProperty("lastMessageAt").GetDateTimeOffset();
                if (number < 0 || unread < 0 || created > server ||
                    !rows.TryAdd(key, (number, incoming.GetBoolean(), unread, created))) throw new JsonException();
            }
            var continuous = sameOwner && _server is {} previous && server > previous &&
                server - previous <= TimeSpan.FromSeconds(30) && _time.GetElapsedTime(_received) <= TimeSpan.FromSeconds(30);
            var fresh = new List<string>();
            foreach (var (key, row) in rows) {
                var previousSequence = sameOwner ? _sequences.GetValueOrDefault(key) : 0;
                if (continuous && row.Sequence > previousSequence && row.Incoming && row.Unread > 0 &&
                    row.Created > _server && row.Created <= server) fresh.Add(key);
            }
            // A dropped row or rewound sequence must not reopen a consumed message.
            var next = sameOwner ? new Dictionary<string, long>(_sequences, StringComparer.Ordinal) : new(StringComparer.Ordinal);
            foreach (var (key, row) in rows) next[key] = Math.Max(next.GetValueOrDefault(key), row.Sequence);
            if (next.Count > 4000) { next = rows.ToDictionary(r => r.Key, r => r.Value.Sequence); fresh.Clear(); }
            _owner = owner; _generation = generation; _server = server;
            _received = _time.GetTimestamp(); _sequences = next; FreshKeys = fresh;
            return fresh.Count > 0;
        } catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException or OverflowException) {
            Reset(); return false;
        }
    }
}
