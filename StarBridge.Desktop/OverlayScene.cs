namespace StarBridge.Desktop;

using StarBridge.Core.Presence;

public enum OverlayScenePreference
{
    Auto,
    Fleet,
    PartyRoom
}

public enum OverlaySceneKind
{
    Fleet,
    PartyRoom
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
    IReadOnlyList<SquadRow> Squads,
    IReadOnlyList<PlayerRow> Players,
    bool HasContent,
    OverlaySceneContext Context)
{
    public OverlayDisplaySettings ApplySceneSettings(OverlayDisplaySettings settings) =>
        Context.Kind == OverlaySceneKind.PartyRoom
            ? settings with { MemberScopeMode = OverlayMemberScopeMode.AllFleet }
            : settings;

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

public static class OverlaySceneResolver
{
    public static OverlaySceneSnapshot Resolve(
        OverlayScenePreference preference,
        IEnumerable<SquadRow> fleetSquads,
        IEnumerable<PlayerRow> fleetPlayers,
        bool hasFleet,
        PartyLobbyRoomCard? currentRoom,
        string? localPlayer,
        string? localCallsign)
    {
        var usePartyRoom = preference == OverlayScenePreference.PartyRoom ||
                           preference == OverlayScenePreference.Auto && currentRoom is not null;
        if (!usePartyRoom || currentRoom is null)
        {
            return new OverlaySceneSnapshot(
                fleetSquads.ToArray(),
                fleetPlayers.ToArray(),
                hasFleet,
                OverlaySceneContext.Fleet(preference, preference == OverlayScenePreference.PartyRoom));
        }

        var roomPlayers = currentRoom.Members
            .Select(member => CreateRoomPlayer(member, currentRoom, localPlayer, localCallsign))
            .OrderByDescending(player => player.Status.Equals("Online", StringComparison.OrdinalIgnoreCase))
            .ThenByDescending(player => player.Role.Equals("房主", StringComparison.OrdinalIgnoreCase))
            .ThenBy(player => player.Name, StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var roomSquad = new SquadRow
        {
            Name = currentRoom.Title,
            Commander = currentRoom.HostDisplay,
            Mission = currentRoom.Activity,
            Description = currentRoom.Goal,
            Type = "PartyRoom",
            IsJoinedByCurrentUser = true,
            UpdatedAt = currentRoom.UpdatedAt
        };

        return new OverlaySceneSnapshot(
            [roomSquad],
            roomPlayers,
            true,
            new OverlaySceneContext(
                preference,
                OverlaySceneKind.PartyRoom,
                "当前房间",
                false,
                currentRoom.Title,
                currentRoom.Goal,
                currentRoom.Activity,
                currentRoom.HostDisplay,
                currentRoom.MemberCount,
                currentRoom.Capacity,
                currentRoom.RoomId));
    }

    private static PlayerRow CreateRoomPlayer(
        PartyLobbyMemberPreview member,
        PartyLobbyRoomCard room,
        string? localPlayer,
        string? localCallsign)
    {
        var name = FirstNonEmpty(member.GameId, member.Callsign, "未知成员");
        var callsign = FirstNonEmpty(member.Callsign, member.GameId, name);
        var online = IsInGame(member.PresenceText);
        var rawLocation = NormalizeRoomValue(member.LocationText, "等待位置同步");
        var location = FormatRoomLocation(rawLocation);
        var ship = NormalizeRoomValue(member.ShipText, "等待舰船同步");
        var isSelf = MatchesIdentity(member.GameId, localPlayer, localCallsign) ||
                     MatchesIdentity(member.Callsign, localPlayer, localCallsign);
        return new PlayerRow(
            Name: name,
            Status: online ? "Online" : "Offline",
            Ship: ship,
            ShipInfo: $"飞船：{ship}",
            Location: location,
            Callsign: callsign,
            AvatarPath: member.AvatarImageData,
            Initials: BuildInitials(callsign),
            SquadName: room.Title,
            Role: member.IsHost ? "房主" : "成员",
            RawShip: ship,
            ShipConfidence: "PartyRoom",
            LocationConfidence: "PartyRoom",
            RawLocation: rawLocation,
            IsSelf: isSelf,
            ShowMemberActions: false,
            ServerShard: ResolveRoomShard(member.ShardText),
            LiveStatus: member.PresenceText);
    }

    private static string FormatRoomLocation(string location)
    {
        if (location.StartsWith("地点：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("可能在：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("可能离开：", StringComparison.OrdinalIgnoreCase) ||
            location.StartsWith("等待", StringComparison.OrdinalIgnoreCase))
        {
            return location;
        }

        return $"地点：{location}";
    }

    private static bool IsInGame(string? value)
    {
        return PlayerPresencePresentation.Resolve(value, value) == PlayerPresenceKind.InGame;
    }

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

    private static string? ResolveRoomShard(string? value)
    {
        if (string.IsNullOrWhiteSpace(value) || value.Contains("等待", StringComparison.OrdinalIgnoreCase))
        {
            return null;
        }

        var parts = value.Split('·', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
        return parts.Length == 0 ? value.Trim() : parts[^1];
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
