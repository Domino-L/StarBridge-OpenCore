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
    private object _moduleAuthority = new();
    private (BridgeAccountContext Owner, long Generation, string? Room)? _confirmedMembership;
    internal event Action? ContentChanged;
    internal event Action<BridgeAccountContext, long, string?>? MembershipConfirmed;

    // A missing/expired display payload is not evidence of leaving a room.
    // This supplies switch intent only; it never extends display authority.
    internal (bool Known, string? Room) ReadPresetTrigger(BridgeAccountContext? owner, long generation)
    {
        lock (_gate)
        {
            if (owner is null || _confirmedMembership is not { } confirmed ||
                confirmed.Owner != owner || confirmed.Generation != generation) return (false, null);
            if (confirmed.Room is null) return (true, null);
            return _owner == owner && _generation == generation && _clock() < _validUntil &&
                _content?.RoomId == confirmed.Room ? (true, confirmed.Room) : (false, null);
        }
    }

    internal InformationOverlayRoomContent? Read(BridgeAccountContext? owner, long generation)
    {
        lock (_gate)
        {
            if (owner is null || owner != _owner || generation != _generation || _clock() >= _validUntil)
                ClearCore();
            return _content;
        }
    }

    internal InformationOverlaySourceSnapshot? ReadSource(BridgeAccountContext? owner, long generation)
    {
        lock (_gate)
        {
            var content = Read(owner, generation);
            return content is null || owner is null ? null : new(
                new(StarBridge.Core.Overlay.OverlaySourceMode.Room, content.RoomId,
                    OverlaySceneChoiceStore.Hash(owner), generation, _validUntil),
                _validUntil, room: content, authorityStamp: _moduleAuthority, clock: _clock);
        }
    }

    internal (StarBridge.Core.Overlay.OverlaySourceLease Lease, object Stamp)? PeekAuthority(BridgeAccountContext? owner, long generation)
    {
        lock (_gate)
        {
            if (owner is null || owner != _owner || generation != _generation || _clock() >= _validUntil || _content is null) return null;
            return (new(StarBridge.Core.Overlay.OverlaySourceMode.Room, _content.RoomId,
                OverlaySceneChoiceStore.Hash(owner), generation, _validUntil), _moduleAuthority);
        }
    }

    internal bool IsSourceCurrent(BridgeAccountContext? owner, long generation, InformationOverlaySourceSnapshot snapshot)
    {
        lock (_gate)
        {
            var content = Read(owner, generation);
            return content is not null && ReferenceEquals(snapshot.AuthorityStamp, _moduleAuthority) &&
                snapshot.Lease.Generation == generation && snapshot.Lease.OwnerKey == OverlaySceneChoiceStore.Hash(owner!) &&
                _clock() < snapshot.Lease.ValidUntil;
        }
    }

    internal void Clear()
    {
        lock (_gate)
        {
            _confirmedMembership = null;
            ClearCore();
        }
    }

    private void ClearCore()
    {
        var hadContent = _content is not null;
        _moduleAuthority = new();
        _content = null;
        _chatBaseline = null;
        _owner = null;
        if (hadContent) NotifyContentChanged();
    }

    private void NotifyContentChanged()
    {
        foreach (var handler in ContentChanged?.GetInvocationList() ?? [])
            try { ((Action)handler)(); } catch { }
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
                _confirmedMembership = (owner, generation, null);
                MembershipConfirmed?.Invoke(owner, generation, null);
                return;
            }
            if (_owner != owner || _generation != generation || _content?.RoomId != room.RoomId ||
                _clock() >= _validUntil) ClearCore();
            _owner = owner;
            _generation = generation;
            _confirmedMembership = (owner, generation, room.RoomId);
            // Bound stale visibility even if Flutter stops polling unexpectedly.
            var remaining = room.ExpiresAt - directory.ServerTime;
            _validUntil = _clock() + (remaining < TimeSpan.FromSeconds(30) ? remaining : TimeSpan.FromSeconds(30));
            _content = new(room.RoomId, room.Title, room.Goal, room.Capacity, localHandle,
                Array.AsReadOnly(room.Members.Select(member => new InformationOverlayRoomMember(
                    member.Callsign, member.GameId, member.IsHost, OverlayPresence(member.PresenceText),
                    member.LocationText, member.ShipText, member.ServerRegion)
                    { PreferenceKey = OverlayMemberIdentity.FromAccountId(member.AccountId), IsSelf = member.IsSelf,
                        LocationHiddenReason = member.LocationHiddenReason,
                        ArrivalPendingConfirmation = member.ArrivalPendingConfirmation,
                        ArrivalTargetCode = member.ArrivalTargetCode }).ToArray()),
                _content?.Messages ?? Array.Empty<InformationOverlayRoomMessage>())
                { ContinuityId = _content?.ContinuityId ?? Guid.NewGuid() };
            NotifyContentChanged();
            MembershipConfirmed?.Invoke(owner, generation, room.RoomId);
        }
    }

    private static string OverlayPresence(string value) => RoomAvatarProjection.PresenceKey(value) switch
    {
        "presence.inGame" => "InGame",
        "presence.online" => "AppOnline",
        "presence.away" => "Away",
        "presence.offline" => "Offline",
        _ => value
    };

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
                .Where(message => message.Sequence > baseline &&
                    (!string.IsNullOrWhiteSpace(message.Text) || message.Attachment is not null))
                .Select(message => new InformationOverlayRoomMessage(message.Sequence,
                    message.SenderCallsign, message.SenderGameId, message.Text, message.CreatedAt,
                    message.Kind.Equals("system", StringComparison.OrdinalIgnoreCase))
                    { IsSelf = message.IsSelf, AttachmentKind = message.Attachment?.Kind }))
                .GroupBy(message => message.Sequence).Select(group => group.First())
                .OrderBy(message => message.Sequence).TakeLast(50).ToArray();
            if (!_content.Messages.SequenceEqual(messages))
            {
                _content = _content with { Messages = Array.AsReadOnly(messages) };
                NotifyContentChanged();
            }
        }
    }
}
