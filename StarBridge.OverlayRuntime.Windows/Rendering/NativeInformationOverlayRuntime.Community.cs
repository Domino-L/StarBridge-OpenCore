using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime
{
    private string? SafeReadSourceMode() { try { return _sceneModeProvider(); } catch { return "unavailable"; } }
    private static OverlayScenePreference SourcePreference(string? mode, OverlayScenePreference legacy) => mode switch
    {
        null => legacy, "auto" or "community" => OverlayScenePreference.Auto,
        "room" => OverlayScenePreference.PartyRoom, _ => OverlayScenePreference.Fleet
    };
    private static Guid? SourceContinuity(OverlaySceneKind kind,
        InformationOverlayRoomContent? room, InformationOverlayCommunityContent? community) => kind switch
    {
        OverlaySceneKind.PartyRoom => room?.ContinuityId,
        OverlaySceneKind.Community => community?.ContinuityId,
        _ => null
    };
    private InformationOverlayCommunityContent? SafeReadCommunity()
    {
        try { return _communityProvider(); }
        catch { return null; }
    }

    internal static (OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat)
        ProjectSource(InformationOverlayRoomContent? room, InformationOverlayCommunityContent? community,
            OverlayScenePreference preference, string language, bool explicitCommunity = false)
    {
        var source = InformationOverlaySourcePolicy.Resolve(preference, room is not null,
            hasFleet: false, community is not null, explicitCommunity);
        if (source.Kind == InformationOverlaySourceKind.PartyRoom && source.IsAvailable)
            return ProjectRoom(room, preference, language);
        if (source.Kind != InformationOverlaySourceKind.Community || community is null)
            return ProjectRoom(null, preference, language);
        var players = community.Members.Select(member =>
            OverlaySceneResolver.CreateRoomPlayer(new(member.Callsign, member.GameId)
            {
                PresenceText = member.Presence, ShipText = member.Ship,
                LocationText = member.Location, ShardText = member.ServerRegion
            }, null, null) with
            {
                Role = member.Role,
                IsSelf = member.IsSelf,
                ShipConfidence = "Community",
                LocationConfidence = "Community",
                ShowMemberActions = false,
                SharedEventTypes = 0
            }).ToArray();
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        var scene = new OverlaySceneSnapshot(players, true,
            new(preference, OverlaySceneKind.Community, community.Name, false));
        var command = BuildCommandState(language) with
        {
            NoticeTitle = traditional ? "組織接入" : zh ? "组织接入" : "ORGANIZATION LINK",
            NoticeText = zh ? $"{community.Name} · {players.Length} 人" : $"{community.Name} · {players.Length} members"
        };
        // Organization history is not injected as new live chat. That channel
        // needs its own authorized subscription and baseline before enabling.
        return (scene, command, []);
    }
}
