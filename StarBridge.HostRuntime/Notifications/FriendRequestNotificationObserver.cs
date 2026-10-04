namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;

internal sealed class FriendRequestNotificationObserver
{
    private BridgeAccountContext? _owner;
    private long _generation;
    private DateTimeOffset? _updated;
    private HashSet<string> _seen = [];
    internal void Reset() { _owner = null; _updated = null; _seen.Clear(); }
    internal int Observe(BridgeEnvelope request, BridgeEnvelope response, long generation)
    {
        if (request.Name != "notificationInbox.read" || request.SessionGeneration != generation) return 0;
        if (response.Status != "ok" || response.SessionGeneration != generation || request.AccountContext is null || response.AccountContext != request.AccountContext) {
            Reset(); return 0;
        }
        try {
            var root = response.Payload;
            if (root.GetProperty("schemaVersion").GetInt32() != 1 || root.GetProperty("items").GetArrayLength() > 5000) throw new JsonException();
            var now = root.GetProperty("updatedAt").GetDateTimeOffset();
            var same = _owner == request.AccountContext && _generation == generation;
            if (same && now <= _updated) return 0;
            var continuous = same && _updated is {} previous && now - previous < TimeSpan.FromSeconds(90);
            var next = new HashSet<string>(); var fresh = 0;
            foreach (var row in root.GetProperty("items").EnumerateArray()) {
                if (row.GetProperty("actionTarget").GetString() != "friend_requests") continue;
                var key = row.GetProperty("eventKey").GetString();
                if (key is not { Length: 64 } || key.Any(c => !char.IsAsciiHexDigit(c)) || !next.Add(key)) throw new JsonException();
                var created = row.GetProperty("createdAt").GetDateTimeOffset();
                if (continuous && !_seen.Contains(key) && created > _updated && created <= now &&
                    !row.GetProperty("read").GetBoolean() && row.GetProperty("isAvailable").GetBoolean()) fresh++;
            }
            _owner = request.AccountContext; _generation = generation; _updated = now; _seen = next;
            return fresh;
        } catch (Exception e) when (e is JsonException or KeyNotFoundException or InvalidOperationException or FormatException) {
            Reset(); return 0;
        }
    }
}
