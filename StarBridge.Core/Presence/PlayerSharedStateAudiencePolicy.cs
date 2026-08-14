namespace StarBridge.Core.Presence;

[Flags]
public enum PlayerSharedStateFields
{
    None = 0,
    Presence = 1 << 0,
    Ship = 1 << 1,
    Location = 1 << 2,
    Server = 1 << 3,
    SharedEvents = 1 << 4,
    PersonalHangar = 1 << 5,
    All = Presence | Ship | Location | Server | SharedEvents | PersonalHangar
}

public readonly record struct PlayerSharedStatePublicationPolicy(
    string? FleetScope,
    PlayerSharedStateFields? FleetFields,
    string? RoomScope,
    PlayerSharedStateFields? RoomFields,
    bool FriendsCanViewPresence,
    bool PersonalHangarSharedWithFleet = false,
    bool UsesFleetAudienceSources = false,
    bool FleetAdministratorsCanView = false,
    bool FleetMembersCanView = false,
    bool UsesRoomAudienceSources = false,
    bool RoomMembersCanView = false);

public readonly record struct PlayerSharedStateViewerFacts(
    bool IsSelf = false,
    bool IsFleetMember = false,
    bool IsFleetPrivacyAdmin = false,
    bool IsSpecifiedFleetMember = false,
    bool IsSelectedFleetVisibilityGroupMember = false,
    bool IsRoomMember = false,
    bool IsSelectedRoomVisibilityGroupMember = false,
    bool IsAcceptedFriend = false);

public static class PlayerSharedStateAudiencePolicy
{
    public const string RoomMembersScope = "RoomMembers";
    public const PlayerSharedStateFields PartyRoomLiveStateFields =
        PlayerSharedStateFields.Presence |
        PlayerSharedStateFields.Ship |
        PlayerSharedStateFields.Location |
        PlayerSharedStateFields.Server;

    public static PlayerSharedStateFields Resolve(
        PlayerSharedStatePublicationPolicy publication,
        PlayerSharedStateViewerFacts viewer)
    {
        if (viewer.IsSelf)
        {
            return PlayerSharedStateFields.All;
        }

        var visible = PlayerSharedStateFields.None;
        if (viewer.IsFleetMember && FleetAxisAllows(publication, viewer))
        {
            var legacyFleetFields = publication.PersonalHangarSharedWithFleet
                ? PlayerSharedStateFields.All
                : PlayerSharedStateFields.All & ~PlayerSharedStateFields.PersonalHangar;
            visible |= NormalizeFields(publication.FleetFields, legacyFleetFields);
        }

        if (viewer.IsRoomMember && RoomAxisAllows(publication, viewer))
        {
            visible |= NormalizeFields(publication.RoomFields, PlayerSharedStateFields.None);
        }

        if (viewer.IsAcceptedFriend && publication.FriendsCanViewPresence)
        {
            visible |= PlayerSharedStateFields.Presence;
        }

        return visible;
    }

    public static string NormalizeRoomScope(string? scope)
    {
        var normalized = (scope ?? "")
            .Trim()
            .Replace(" ", "", StringComparison.Ordinal)
            .Replace("-", "", StringComparison.Ordinal)
            .Replace("_", "", StringComparison.Ordinal)
            .ToUpperInvariant();
        return normalized switch
        {
            "ROOMMEMBERS" => RoomMembersScope,
            _ => PlayerSharedStateVisibility.PrivateScope
        };
    }

    private static bool FleetScopeAllows(
        string? scope,
        PlayerSharedStateViewerFacts viewer) =>
        PlayerSharedStateVisibility.NormalizeScope(scope) switch
        {
            PlayerSharedStateVisibility.PrivateScope => false,
            PlayerSharedStateVisibility.AdminOnlyScope => viewer.IsFleetPrivacyAdmin,
            PlayerSharedStateVisibility.SpecifiedMembersScope =>
                viewer.IsFleetPrivacyAdmin || viewer.IsSpecifiedFleetMember,
            PlayerSharedStateVisibility.FleetScope => true,
            _ => false
        };

    private static bool FleetAxisAllows(
        PlayerSharedStatePublicationPolicy publication,
        PlayerSharedStateViewerFacts viewer) =>
        publication.UsesFleetAudienceSources
            ? publication.FleetMembersCanView ||
              publication.FleetAdministratorsCanView && viewer.IsFleetPrivacyAdmin ||
              viewer.IsSelectedFleetVisibilityGroupMember
            : FleetScopeAllows(publication.FleetScope, viewer);

    private static bool RoomAxisAllows(
        PlayerSharedStatePublicationPolicy publication,
        PlayerSharedStateViewerFacts viewer) =>
        publication.UsesRoomAudienceSources
            ? publication.RoomMembersCanView || viewer.IsSelectedRoomVisibilityGroupMember
            : string.Equals(
                NormalizeRoomScope(publication.RoomScope),
                RoomMembersScope,
                StringComparison.Ordinal);

    private static PlayerSharedStateFields NormalizeFields(
        PlayerSharedStateFields? fields,
        PlayerSharedStateFields missingValue) =>
        (fields ?? missingValue) & PlayerSharedStateFields.All;
}
