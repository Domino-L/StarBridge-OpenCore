namespace StarBridge.Core.Presence;

/// <summary>
/// A policy-derived view of what one representative audience can receive.
/// Shared events are deliberately exposed separately because they are push
/// notifications, not part of the state a viewer reads later.
/// </summary>
public readonly record struct PlayerSharedStateAudienceView(
    PlayerSharedStateFields VisibleFields)
{
    public const PlayerSharedStateFields StatusFieldMask =
        PlayerSharedStateFields.Presence |
        PlayerSharedStateFields.Ship |
        PlayerSharedStateFields.Location |
        PlayerSharedStateFields.Server |
        PlayerSharedStateFields.PersonalHangar;

    public PlayerSharedStateFields StatusFields => VisibleFields & StatusFieldMask;

    public bool ReceivesSharedEvents =>
        VisibleFields.HasFlag(PlayerSharedStateFields.SharedEvents);
}

/// <summary>
/// Typed policy facts used by the compact privacy summary and the future
/// "what others see" preview. Every value is resolved by the production
/// audience policy; presentation code only formats these results.
/// </summary>
public readonly record struct PlayerSharedStateAudienceProjection(
    PlayerSharedStateAudienceView FleetAdministrators,
    PlayerSharedStateAudienceView FleetMembers,
    PlayerSharedStateAudienceView SelectedFleetGroupMembers,
    PlayerSharedStateAudienceView RoomMembers,
    PlayerSharedStateAudienceView SelectedRoomGroupMembers,
    PlayerSharedStateAudienceView AcceptedFriends)
{
    public PlayerSharedStateFields FleetStatusFields =>
        FleetAdministrators.StatusFields |
        FleetMembers.StatusFields |
        SelectedFleetGroupMembers.StatusFields;

    public PlayerSharedStateFields RoomStatusFields =>
        RoomMembers.StatusFields |
        SelectedRoomGroupMembers.StatusFields;
}

public static class PlayerSharedStateAudienceProjectionPolicy
{
    public static PlayerSharedStateAudienceProjection Project(
        PlayerSharedStatePublicationPolicy publication,
        bool hasSelectedFleetGroups = false,
        bool hasSelectedRoomGroups = false) =>
        new(
            Resolve(publication, new PlayerSharedStateViewerFacts(
                IsFleetMember: true,
                IsFleetPrivacyAdmin: true)),
            Resolve(publication, new PlayerSharedStateViewerFacts(
                IsFleetMember: true)),
            hasSelectedFleetGroups
                ? Resolve(publication, new PlayerSharedStateViewerFacts(
                    IsFleetMember: true,
                    IsSelectedFleetVisibilityGroupMember: true))
                : default,
            Resolve(publication, new PlayerSharedStateViewerFacts(
                IsRoomMember: true)),
            hasSelectedRoomGroups
                ? Resolve(publication, new PlayerSharedStateViewerFacts(
                    IsRoomMember: true,
                    IsSelectedRoomVisibilityGroupMember: true))
                : default,
            Resolve(publication, new PlayerSharedStateViewerFacts(
                IsAcceptedFriend: true)));

    private static PlayerSharedStateAudienceView Resolve(
        PlayerSharedStatePublicationPolicy publication,
        PlayerSharedStateViewerFacts viewer) =>
        new(PlayerSharedStateAudiencePolicy.Resolve(publication, viewer));
}
