namespace StarBridge.HostRuntime.Notifications;

using System.Text.Json;
using StarBridge.NativeBridge;

// Observes only validated, successful domain reads. Never fetches data, keeps
// message content, changes room state or retries a sound after a quiet period.
internal sealed class RoomAudioObserver(TimeProvider? time = null)
{
    private readonly TimeProvider _time = time ?? TimeProvider.System;
    private string? _owner, _hostRoom;
    private long _generation, _received;
    private DateTimeOffset? _serverTime;
    private HashSet<string> _ids = [];
    internal int FreshInvitations { get; private set; }
    internal int FreshApplications { get; private set; }
    internal IReadOnlyList<string> FreshIds { get; private set; } = [];
    internal TimeSpan FreshLifetime { get; private set; } = TimeSpan.Zero;
    internal bool ContainsAll(IEnumerable<string> ids) => ids.All(_ids.Contains);
    internal void Reset() { _owner = null; _serverTime = null; _ids.Clear(); _hostRoom = null; FreshIds = []; }

    internal bool Observe(BridgeEnvelope request, BridgeEnvelope response, long generation)
    {
        FreshInvitations = FreshApplications = 0;
        FreshIds = [];
        if (request.Name != Account.AccountBridgeRequestNames.GetPartyRooms) return false;
        if (request.SessionGeneration != generation) return false; // A late old owner must not reset the new owner.
        if (response.Status != "ok" || response.AccountContext != request.AccountContext ||
            request.AccountContext is null || response.SessionGeneration != generation) { Reset(); return false; }
        try {
            var owner = JsonSerializer.Serialize(request.AccountContext);
            var root = response.Payload;
            var server = root.GetProperty("serverTime").GetDateTimeOffset();
            if (_owner == owner && _generation == generation && server <= _serverTime) return false;
            var current = root.GetProperty("currentRoomId").GetString();
            var candidates = new List<(string Id, DateTimeOffset? Created, bool Application, DateTimeOffset? Expires)>();
            foreach (var invite in root.GetProperty("receivedInvitations").EnumerateArray()) {
                var expires = invite.GetProperty("expiresAt").GetDateTimeOffset();
                if (expires > server) candidates.Add(("invite:" + invite.GetProperty("invitationId").GetString(), Created(invite), false, expires));
            }
            string? hostRoom = null;
            foreach (var room in root.GetProperty("rooms").EnumerateArray()) {
                var id = room.GetProperty("roomId").GetString();
                if (id != current || current is null || !room.GetProperty("viewerIsHost").GetBoolean()) continue;
                hostRoom = current;
                foreach (var application in room.GetProperty("pendingApplications").EnumerateArray())
                    candidates.Add(($"application:{current}:" + application.GetProperty("applicationId").GetString(), Created(application), true, null));
            }
            if (candidates.Count > 512 || candidates.Any(c => c.Id.EndsWith(':')) || candidates.Select(c => c.Id).Distinct().Count() != candidates.Count)
                throw new JsonException();
            var continuous = _owner == owner && _generation == generation && _serverTime is { } previous &&
                server > previous && server - previous <= TimeSpan.FromSeconds(30) &&
                _time.GetElapsedTime(_received) <= TimeSpan.FromSeconds(30);
            var fresh = candidates.Where(c => continuous && !_ids.Contains(c.Id) && c.Created > _serverTime && c.Created <= server &&
                (!c.Application || hostRoom == _hostRoom)).ToArray();
            FreshInvitations = fresh.Count(c => !c.Application);
            FreshApplications = fresh.Length - FreshInvitations;
            FreshIds = fresh.Select(c => c.Id).ToArray();
            FreshLifetime = fresh.Select(c => c.Expires is { } expiry ? expiry - server : TimeSpan.FromSeconds(10))
                .Append(TimeSpan.FromSeconds(10)).Min();
            // Consume even while muted, focused, cooling down or without an output device.
            _owner = owner; _generation = generation; _hostRoom = hostRoom;
            _serverTime = server; _received = _time.GetTimestamp();
            _ids = candidates.Select(c => c.Id).ToHashSet(StringComparer.Ordinal);
            return fresh.Length != 0;
        } catch (Exception e) when (e is JsonException or InvalidOperationException or KeyNotFoundException or FormatException) {
            Reset(); return false;
        }
    }
    private static DateTimeOffset? Created(JsonElement value) => value.TryGetProperty("createdAt", out var created) &&
        created.ValueKind == JsonValueKind.String && created.TryGetDateTimeOffset(out var instant) ? instant : null;
}
