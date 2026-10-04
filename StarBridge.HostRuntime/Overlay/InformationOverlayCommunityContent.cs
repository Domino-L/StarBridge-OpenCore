namespace StarBridge.HostRuntime.Overlay;

/// <summary>Only already-authorized workspace fields cross into the renderer.</summary>
public sealed record InformationOverlayCommunityMember(
    string GameId, string Callsign, string Role, string Presence,
    string Ship, string Location, string ServerRegion, bool IsSelf)
{
    public string? PreferenceKey { get; init; }
    public string? LocationHiddenReason { get; init; }
    public bool ArrivalPendingConfirmation { get; init; }
    public string? ArrivalTargetCode { get; init; }
}

public sealed record InformationOverlayCommunityContent(
    string Code, string Name, IReadOnlyList<InformationOverlayCommunityMember> Members)
{
    public Guid ContinuityId { get; init; } = Guid.NewGuid();
    public string AnnouncementTitle { get; init; } = "";
    public string AnnouncementText { get; init; } = "";
    public long LatestChatSequence { get; init; }
    public IReadOnlyList<InformationOverlayRoomMessage> Messages { get; init; } = [];
}

internal sealed record OverlayCommunityTarget(string Code, string Name, string Reference);

internal interface IOverlayCommunityReader
{
    Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, CancellationToken token);
    Task<InformationOverlayCommunityContent> ReadContentAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token);
    // A complete, freshly authorized roster may be delivered before optional
    // communication reads. The callback never grants a lease to old chat data.
    Task<InformationOverlayCommunityContent> ReadContentAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, OverlayCommunityTarget target,
        Action<InformationOverlayCommunityContent> rosterReady, CancellationToken token) =>
        ReadContentAsync(owner, target, token);
    // Idle preparation needs the authorized roster, not chat history or notices.
    Task<InformationOverlayCommunityContent> ReadRosterAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token) =>
        ReadContentAsync(owner, target, token);
}

internal sealed record OverlayActivityCursor(string Instance = "", long Version = -1, bool PresenceEvents = false);

internal interface IOverlayCommunityChangeReader
{
    Task<OverlayActivityCursor> WaitForChangesAsync(StarBridge.NativeBridge.BridgeAccountContext owner,
        long generation, OverlayActivityCursor after, CancellationToken token);
}
