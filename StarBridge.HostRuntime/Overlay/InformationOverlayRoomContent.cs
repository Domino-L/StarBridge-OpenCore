namespace StarBridge.HostRuntime.Overlay;

// Host-owned authorized content, never accepted from a Flutter preview or persisted.
public sealed record InformationOverlayRoomMember(string Callsign, string GameId,
    bool IsHost, string Presence, string Location, string Ship, string ServerRegion)
{
    public string? PreferenceKey { get; init; }
    public bool? IsSelf { get; init; }
    public string? LocationHiddenReason { get; init; }
    public bool ArrivalPendingConfirmation { get; init; }
    public string? ArrivalTargetCode { get; init; }
}

public sealed record InformationOverlayRoomMessage(long Sequence, string SenderCallsign,
    string SenderGameId, string Text, DateTimeOffset CreatedAt, bool IsSystem)
{
    public bool? IsSelf { get; init; }
    // Only the kind crosses into the HUD; never attachment packages or invite tokens.
    public string? AttachmentKind { get; init; }
}

public sealed record InformationOverlayRoomContent(string RoomId, string Title, string Goal,
    int Capacity, string LocalHandle, IReadOnlyList<InformationOverlayRoomMember> Members,
    IReadOnlyList<InformationOverlayRoomMessage> Messages)
{
    // Opaque local continuity marker, not an account/remote room identifier.
    public Guid ContinuityId { get; init; } = Guid.NewGuid();
}
