using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Globalization;
using System.Windows;
using StarBridge.Core.Presence;
using MediaBrush = System.Windows.Media.Brush;
using MediaColor = System.Windows.Media.Color;
using MediaSolidBrush = System.Windows.Media.SolidColorBrush;

namespace StarBridge.Desktop;

public sealed record PlayerRow(
    string Name,
    string Status,
    string Ship,
    string ShipInfo,
    string Location,
    string? Callsign = null,
    string? AvatarPath = null,
    string Initials = "?",
    string Role = "Member",
    MediaBrush? NameBrush = null,
    string RawShip = "Unknown",
    string ShipConfidence = "None",
    string LocationConfidence = "None",
    string RawLocation = "Unknown",
    bool IsSelf = false,
    bool ShowMemberActions = true,
    string? ServerShard = null,
    string? ServerRegion = null,
    string? LiveStatus = null,
    MediaBrush? RoleBrush = null,
    string? AccountId = null,
    string? SharedOnlineStatus = null,
    string? SharedLiveStatus = null,
    string? SharedShip = null,
    string? SharedLocation = null,
    int SharedEventTypes = (int)PlayerSharedEventTypes.All,
    bool? SharedHasServerSession = null,
    bool IsFleetCommander = false,
    MediaBrush? RoleColorBrush = null,
    bool HasFleetPosition = false,
    bool ArrivalPendingConfirmation = false,
    string? ArrivalTargetCode = null)
{
    // Callsign 在无呼号时回落为游戏 ID（DisplayCallsign），此时两行会重复，故留空。
    public string GameId => string.Equals(Name, Callsign, StringComparison.OrdinalIgnoreCase)
        ? ""
        : Name;
    public PlayerPresenceKind Presence => PlayerPresencePresentation.Resolve(LiveStatus, Status);
    public string PresenceText => PlayerPresencePresentation.Format(Presence);
    public MediaBrush StatusBrush => PlayerPresencePresentation.Brush(Presence);
    public string SharedOnlineStatusValue => SharedOnlineStatus ?? Status;
    public string? SharedLiveStatusValue => SharedLiveStatus ?? LiveStatus;
    public PlayerPresenceKind SharedPresence => PlayerPresencePresentation.ResolveShared(SharedLiveStatusValue, SharedOnlineStatusValue);
    public string SharedPresenceText => PlayerPresencePresentation.Format(SharedPresence);
    public MediaBrush SharedStatusBrush => PlayerPresencePresentation.Brush(SharedPresence);
    public string SharedShipText => SharedShip ?? Ship;
    public string SharedLocationText => SharedLocation ?? Location;
    public string SharedShipDisplayText => ShipDisplayNamePresentation.ResolveChinese(
        PlayerSessionStatePresentation.ResolveShip(
            SharedPresence,
            ResolveSharedServerSession(),
            SharedShipText),
        ShipDisplayNamePresentation.UnknownShip);
    public string SharedLocationDisplayText => LocationArrivalPresentation.ResolveLocation(
        SharedPresence,
        ResolveSharedServerSession(),
        SharedLocationText,
        ArrivalPendingConfirmation);
    public string SharedLocationCompactDisplayText => LocationArrivalPresentation.ResolveCompactLocation(
        SharedPresence,
        ResolveSharedServerSession(),
        SharedLocationText,
        ArrivalPendingConfirmation);
    public string LocationArrivalBadgeText => LocationArrivalPresentation.ResolveBadge(
        ArrivalPendingConfirmation,
        SharedPresence,
        ResolveSharedServerSession());
    public Visibility LocationArrivalBadgeVisibility => string.IsNullOrWhiteSpace(LocationArrivalBadgeText)
        ? Visibility.Collapsed
        : Visibility.Visible;
    public string SharedLocationToolTip => LocationArrivalPresentation.ResolveDetail(
        ArrivalPendingConfirmation,
        SharedPresence,
        ResolveSharedServerSession(),
        SharedLocationText,
        ArrivalTargetCode);
    internal FleetServerRelationshipKind? ResolvedServerRelationship { get; init; }
    // The legacy property name is retained for XAML compatibility. The member
    // table now presents a localized region, never a relationship label or a
    // concrete shard identifier.
    public string ServerRelationshipText => GameServerRegionPresentation.Resolve(
        SharedPresence,
        ServerRegion,
        ServerShard,
        zh: true);
    public string ServerShardDisplayText =>
        SharedPresence == PlayerPresenceKind.InGame &&
        PlayerSessionStatePresentation.HasRecognizedValue(ServerShard)
            ? ServerShard!.Trim()
            : "未进入游戏";
    internal bool MatchesFleetSearch(string? searchText) =>
        FleetRosterSearchPolicy.Matches(
            searchText,
            Name,
            Callsign,
            Role,
            ServerRelationshipText,
            SharedPresenceText,
            SharedShipDisplayText,
            SharedLocationDisplayText);
    internal bool AllowsSharedEvent(PlayerSharedEventTypes eventType) =>
        PlayerEventSharingSettings.FromWireValue(SharedEventTypes).HasFlag(eventType);
    public Visibility MemberActionVisibility => ShowMemberActions && !IsSelf ? Visibility.Visible : Visibility.Collapsed;

    private bool? ResolveSharedServerSession()
    {
        if (SharedPresence != PlayerPresenceKind.InGame)
        {
            return false;
        }

        if (SharedHasServerSession.HasValue)
        {
            return SharedHasServerSession.Value;
        }

        return PlayerSessionStatePresentation.HasRecognizedValue(ServerShard) ||
               PlayerSessionStatePresentation.HasRecognizedValue(ServerRegion)
            ? true
            : null;
    }
}

