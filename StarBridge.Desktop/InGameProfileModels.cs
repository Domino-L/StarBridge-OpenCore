using StarBridge.Core.Friends;
using StarBridge.Core.Presence;
using MediaBrush = System.Windows.Media.Brush;

namespace StarBridge.Desktop;

internal sealed record InGameProfileTarget(
    string Key,
    bool IsOwner,
    string Callsign,
    string GameId,
    string? AvatarSource,
    string AvatarFallbackText,
    string PresenceText,
    MediaBrush PresenceBrush,
    FriendUserContract? User = null,
    PlayerPresenceVisibilityMode VisibilityMode = PlayerPresenceVisibilityMode.Online);

internal sealed record InGameProfileShipRow(
    string Name,
    string Detail,
    string? ImagePath = null,
    string? ValueText = null,
    string? RoleText = null,
    string? SizeText = null,
    string? ImportedText = null);

internal sealed record InGameProfileHangarSegment(
    string Name,
    int Count,
    string AccentHex);

internal sealed record InGameProfileSnapshot(
    InGameProfileTarget Target,
    bool IsLoading,
    bool IsAvailable,
    string Introduction,
    string Availability,
    string AvailabilityTimeZone,
    string GameplayDuration,
    string GameplayStatisticsVisibility,
    string ActivityRhythm,
    string? PresenceIntent,
    bool IsPublic,
    string[] SkilledRoleIds,
    string[] SkilledRoles,
    string[] SupportCapabilities,
    string[] ParticipationInterests,
    string FleetName,
    string FleetCode,
    string FleetRole,
    string? FleetLogoSource,
    InGameProfileShipRow[] Ships,
    InGameProfileHangarSegment[] HangarSegments,
    string StatusText,
    InGameProfileShipRow[]? FavoriteShips = null,
    string HangarTotalValue = "未公布",
    string HangarCategorySummary = "未公开",
    string HangarPrimaryType = "未公开",
    string HangarComposition = "暂无舰船构成",
    double HangarPrimaryShare = 0d,
    InGameProfileShipRow? RecentShip = null);

internal sealed record InGameProfileEditDraft(
    string Callsign,
    string Introduction,
    string ActivityRhythm,
    string? PresenceIntent,
    bool IsPublic);

internal sealed class InGameProfileRequestedEventArgs(
    InGameProfileTarget target) : EventArgs
{
    internal InGameProfileTarget Target { get; } = target;
}

internal sealed class InGameProfileOwnerSaveRequestedEventArgs(
    string profileKey,
    InGameProfileEditDraft draft) : EventArgs
{
    internal string ProfileKey { get; } = profileKey;
    internal InGameProfileEditDraft Draft { get; } = draft;
}

internal sealed class InGameProfileAvatarChangeRequestedEventArgs(
    string profileKey) : EventArgs
{
    internal string ProfileKey { get; } = profileKey;
}

internal sealed class InGameProfileScanHangarRequestedEventArgs(
    string profileKey) : EventArgs
{
    internal string ProfileKey { get; } = profileKey;
}

internal sealed class InGameProfileVisibilityModeChangedEventArgs(
    string profileKey,
    PlayerPresenceVisibilityMode mode) : EventArgs
{
    internal string ProfileKey { get; } = profileKey;
    internal PlayerPresenceVisibilityMode Mode { get; } = mode;
}
