namespace StarBridge.HostRuntime.Overlay;

/// <summary>Only already-authorized workspace fields cross into the renderer.</summary>
public sealed record InformationOverlayCommunityMember(
    string GameId, string Callsign, string Role, string Presence,
    string Ship, string Location, string ServerRegion, bool IsSelf);

public sealed record InformationOverlayCommunityContent(
    string Code, string Name, IReadOnlyList<InformationOverlayCommunityMember> Members)
{
    public Guid ContinuityId { get; init; } = Guid.NewGuid();
}

internal sealed record OverlayCommunityTarget(string Code, string Name, string Reference);

internal interface IOverlayCommunityReader
{
    Task<IReadOnlyList<OverlayCommunityTarget>> ReadTargetsAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, CancellationToken token);
    Task<InformationOverlayCommunityContent> ReadContentAsync(
        StarBridge.NativeBridge.BridgeAccountContext owner, OverlayCommunityTarget target, CancellationToken token);
}
