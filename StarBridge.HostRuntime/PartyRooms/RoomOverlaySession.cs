namespace StarBridge.HostRuntime.PartyRooms;

using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;

/// <summary>
/// Only current membership obtained from the authenticated directory may supply
/// the native overlay. No additional HTTP, UI-selected room, or local game data.
/// </summary>
internal sealed class RoomOverlaySession(Func<DateTimeOffset>? clock = null)
{
    private readonly object _gate = new();
    private readonly Func<DateTimeOffset> _clock = clock ?? (() => DateTimeOffset.UtcNow);
    private BridgeAccountContext? _owner;
    private long _generation;
    private DateTimeOffset _validUntil;
    private InformationOverlayRoomContent? _content;
    private long? _chatBaseline;

    internal InformationOverlayRoomContent? Read(BridgeAccountContext? owner, long generation)
    {
        lock (_gate)
        {
            if (owner is null || owner != _owner || generation != _generation || _clock() >= _validUntil)
                ClearCore();
            return _content;
        }
    }

    internal void Clear()
    {
        lock (_gate) ClearCore();
    }

    private void ClearCore()
    {
        _content = null;
        _chatBaseline = null;
        _owner = null;
    }

    internal void ApplyDirectory(BridgeAccountContext owner, long generation,
        RoomDirectoryView directory, string localHandle)
    {
        lock (_gate)
        {
            var room = directory.Rooms.SingleOrDefault(item => item.RoomId == directory.CurrentRoomId);
            if (room is null || room.ExpiresAt <= directory.ServerTime)
            {
                ClearCore();
                return;
            }
            if (_owner != owner || _generation != generation || _content?.RoomId != room.RoomId ||
                _clock() >= _validUntil) ClearCore();
            _owner = owner;
            _generation = generation;
            // Bound stale visibility even if Flutter stops polling unexpectedly.
            var remaining = room.ExpiresAt - directory.ServerTime;
            _validUntil = _clock() + (remaining < TimeSpan.FromSeconds(30) ? remaining : TimeSpan.FromSeconds(30));
            _content = new(room.RoomId, room.Title, room.Goal, room.Capacity, localHandle,
                Array.AsReadOnly(room.Members.Select(member => new InformationOverlayRoomMember(
                    member.Callsign, member.GameId, member.IsHost, member.PresenceText,
                    member.LocationText, member.ShipText, member.ServerRegion)).ToArray()),
                _content?.Messages ?? Array.Empty<InformationOverlayRoomMessage>())
                { ContinuityId = _content?.ContinuityId ?? Guid.NewGuid() };
        }
    }

    internal void ApplyChat(string roomId, RoomChatPageView? page, RoomChatMessageView? sent,
        bool isHistory)
    {
        lock (_gate)
        {
            if (_content?.RoomId != roomId || isHistory) return;
            if (page is not null && _chatBaseline is null)
            {
                // WPF receive-session semantics: initial history is not live chat.
                _chatBaseline = page.LatestSequence;
                return;
            }
            if (_chatBaseline is not long baseline) return;
            var incoming = page?.Messages ?? (sent is null ? [] : new[] { sent });
            var messages = _content.Messages.Concat(incoming
                .Where(message => message.Sequence > baseline && !string.IsNullOrWhiteSpace(message.Text))
                .Select(message => new InformationOverlayRoomMessage(message.Sequence,
                    message.SenderCallsign, message.SenderGameId, message.Text, message.CreatedAt,
                    message.Kind.Equals("system", StringComparison.OrdinalIgnoreCase))))
                .GroupBy(message => message.Sequence).Select(group => group.First())
                .OrderBy(message => message.Sequence).TakeLast(50).ToArray();
            _content = _content with { Messages = Array.AsReadOnly(messages) };
        }
    }
}
