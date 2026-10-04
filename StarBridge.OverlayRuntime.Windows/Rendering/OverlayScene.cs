namespace StarBridge.Desktop;

using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;

public enum OverlaySceneKind
{
    Fleet,
    PartyRoom,
    Community
}

public sealed record OverlaySceneContext(
    OverlayScenePreference Preference,
    OverlaySceneKind Kind,
    string DisplayName,
    bool IsFallback,
    string? RoomTitle = null,
    string? RoomGoal = null,
    string? RoomActivity = null,
    string? RoomHostDisplay = null,
    int RoomMemberCount = 0,
    int RoomCapacity = 0,
    string? RoomId = null,
    string? ChatChannelId = null,
    string? ChatChannelTitle = null,
    bool IsLocalOnly = false)
{
    public static OverlaySceneContext Fleet(OverlayScenePreference preference, bool isFallback = false) =>
        new(preference, OverlaySceneKind.Fleet, "舰队", isFallback);

    public static OverlaySceneContext Local(OverlayScenePreference preference) =>
        Fleet(preference) with
        {
            DisplayName = "本地模式",
            ChatChannelId = null,
            ChatChannelTitle = null,
            IsLocalOnly = true
        };
}

public sealed record OverlaySceneSnapshot(
    IReadOnlyList<PlayerRow> Players,
    bool HasContent,
    OverlaySceneContext Context)
{
    public OverlayCommandState ApplySceneCommandState(OverlayCommandState commandState, bool zh)
    {
        if (Context.Kind != OverlaySceneKind.PartyRoom)
        {
            return commandState;
        }

        var title = zh ? "房间接入" : "PARTY LINK";
        var room = string.IsNullOrWhiteSpace(Context.RoomTitle)
            ? zh ? "当前房间" : "Current party"
            : Context.RoomTitle!;
        var capacity = Context.RoomCapacity > 0 ? Context.RoomCapacity : Context.RoomMemberCount;
        var text = zh
            ? $"已接入 {room} · {Context.RoomMemberCount}/{capacity} 人"
            : $"Linked to {room} · {Context.RoomMemberCount}/{capacity}";
        return commandState with { NoticeTitle = title, NoticeText = text };
    }
}

// Native presentation is independent for each module. A room member list must
// never become the input for an organization overview or announcement receipt.
internal sealed record OverlayModuleScene(OverlaySceneSnapshot Scene, OverlayCommandState Command,
    IReadOnlyList<OverlayChatMessage> Chat, string? SourceLabel, bool Available, string? Identity)
{
    internal string? ResourceKey { get; init; }
    internal string? EmptyMessage { get; init; }
    internal IReadOnlyList<string>? ChatSourceKeys { get; init; }
}

// Status is presentation metadata, never an announcement, event or chat row.
// In particular it cannot acquire a countdown, receipt or replay identity.
internal sealed record OverlayModuleEmptyStates(string? Notice = null, string? Overview = null,
    string? Members = null, string? Chat = null, string? Events = null)
{
    internal static readonly OverlayModuleEmptyStates Empty = new();
    internal static OverlayModuleEmptyStates From(OverlayModulePresentation? modules) => modules is null ? Empty :
        new(modules.Notice.EmptyMessage, modules.Overview.EmptyMessage, modules.Members.EmptyMessage,
            modules.Chat.EmptyMessage, modules.Events.EmptyMessage);
    internal static string? Message(OverlayResolvedSource source, string language)
    {
        if (source.Available || source.UnavailableReason == "module_hidden") return null;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        return source.Mode switch
        {
            OverlaySourceMode.Room => zh ? traditional ? "房間資訊暫不可用" : "房间信息暂不可用" : "Room information unavailable",
            OverlaySourceMode.Community => zh ? traditional ? "此組織暫不可用" : "该组织暂不可用" : "Organization unavailable",
            _ => zh ? traditional ? "資訊暫不可用" : "信息暂不可用" : "Information unavailable"
        };
    }
}

internal sealed record OverlayModuleSourceLabels(string? Notice = null, string? Overview = null,
    string? Members = null, string? Chat = null, string? Events = null)
{
    internal static readonly OverlayModuleSourceLabels Empty = new();
    internal static OverlayModuleSourceLabels From(OverlayModulePresentation? modules) => modules is null ? Empty :
        new(modules.Notice.SourceLabel, modules.Overview.SourceLabel, modules.Members.SourceLabel,
            modules.Chat.SourceLabel, modules.Events.SourceLabel);
    internal static string Prefix(string title, string? label, bool deviceLocal) =>
        deviceLocal || string.IsNullOrWhiteSpace(label) ? title : $"[{label}] {title}";
}

internal sealed record OverlayModulePresentation(OverlayModuleScene Notice, OverlayModuleScene Overview,
    OverlayModuleScene Members, OverlayModuleScene Chat, OverlayModuleScene Events, string ScopeKey)
{
    // Lease renewal alone is not a visual change. The runtime still reschedules
    // expiry even when it can avoid rebuilding the ViewModel and render state.
    internal DateTimeOffset? NextValidationAt { get; init; }
    internal bool HasSameContent(OverlayModulePresentation? other) => other is not null &&
        ScopeKey == other.ScopeKey && Same(Notice, other.Notice) && Same(Overview, other.Overview) &&
        Same(Members, other.Members) && Same(Chat, other.Chat) && Same(Events, other.Events);

    private static bool Same(OverlayModuleScene left, OverlayModuleScene right) =>
        left.Available == right.Available && left.Identity == right.Identity && left.ResourceKey == right.ResourceKey && left.SourceLabel == right.SourceLabel && left.EmptyMessage == right.EmptyMessage &&
        (left.ChatSourceKeys ?? []).SequenceEqual(right.ChatSourceKeys ?? []) &&
        left.Scene.HasContent == right.Scene.HasContent && left.Scene.Context == right.Scene.Context &&
        left.Scene.Players.SequenceEqual(right.Scene.Players) && left.Command == right.Command && left.Chat.SequenceEqual(right.Chat);
}

public static partial class OverlaySceneResolver
{

    internal static PlayerRow CreateRoomPlayer(
        PartyLobbyMemberPreview member,
        string? localPlayer,
        string? localCallsign)
    {
        var name = FirstNonEmpty(member.GameId, member.Callsign, "未知成员");
        var callsign = FirstNonEmpty(member.Callsign, member.GameId, name);
        var presence = ResolveRoomPresence(member.PresenceText);
        var online = PlayerPresence.IsOnline(presence);
        var liveStatus = PlayerPresence.ToWireValue(presence);
        var rawLocation = NormalizeRoomValue(member.LocationText, "等待位置同步");
        var location = FormatRoomLocation(rawLocation);
        var ship = ShipDisplayNamePresentation.ResolveChinese(
            member.ShipText,
            "等待舰船同步");
        var isSelf = MatchesIdentity(member.GameId, localPlayer, localCallsign) ||
                     MatchesIdentity(member.Callsign, localPlayer, localCallsign);
        return new PlayerRow(
            Name: name,
            Status: online ? "Online" : "Offline",
            Ship: ship,
            ShipInfo: PlayerSessionStatePresentation.IsSessionStateText(ship)
                ? ship
                : $"飞船：{ship}",
            Location: location,
            Callsign: callsign,
            AvatarPath: member.AvatarImageData,
            Initials: BuildInitials(callsign),
            Role: member.IsHost ? "房主" : "成员",
            RawShip: ship,
            ShipConfidence: "PartyRoom",
            LocationConfidence: "PartyRoom",
            RawLocation: rawLocation,
            IsSelf: isSelf,
            ShowMemberActions: false,
            ServerShard: member.ShardText,
            ServerRegion: ResolveRoomRegion(member.ShardText),
            LiveStatus: liveStatus,
            AccountId: member.AccountId,
            SharedOnlineStatus: online ? "Online" : "Offline",
            SharedLiveStatus: liveStatus,
            SharedShip: ship,
            SharedLocation: rawLocation) { LocationHiddenReason = member.LocationHiddenReason };
    }

    private static string FormatRoomLocation(string location)
    {
        if (PlayerSessionStatePresentation.IsSessionStateText(location) ||
            location.StartsWith("地点：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("可能在：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("可能离开：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("等待", StringComparison.OrdinalIgnoreCase))
        {
            return location;
        }

        return $"地点：{location}";
    }

    private static PlayerPresenceKind ResolveRoomPresence(string? value) =>
        string.IsNullOrWhiteSpace(value)
            ? PlayerPresenceKind.Offline
            : PlayerPresencePresentation.ResolveShared(value, "Online");

    private static bool MatchesIdentity(string? candidate, params string?[] identities) =>
        !string.IsNullOrWhiteSpace(candidate) &&
        identities.Any(identity => !string.IsNullOrWhiteSpace(identity) &&
                                   candidate.Equals(identity.Trim(), StringComparison.OrdinalIgnoreCase));

    private static string NormalizeRoomValue(string? value, string fallback)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return fallback;
        }

        return value.Trim()
            .Replace("飞船：", "", StringComparison.OrdinalIgnoreCase)
            .Replace("地点：", "", StringComparison.OrdinalIgnoreCase);
    }

    private static string? ResolveRoomRegion(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Contains("等待", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var resolved = GameServerRegionPresentation.ResolveRegion(value);
        if (!string.IsNullOrWhiteSpace(resolved))
        {
            return resolved;
        }

        var parts = value.Split('·', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 0 ? value.Trim() : parts[0];
    }

    private static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? "?";

    private static string BuildInitials(string value)
    {
        var parts = value.Split([' ', '_', '-'], StringSplitOptions.RemoveEmptyEntries);
        return parts.Length == 0
            ? "?"
            : string.Concat(parts.Take(2).Select(part => char.ToUpperInvariant(part[0])));
    }
}
