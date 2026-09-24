namespace StarBridge.Desktop;

using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    private InformationOverlayRoomContent? SafeReadRoom()
    {
        try { return _roomProvider(); }
        catch { return null; }
    }

    internal static (OverlaySceneSnapshot Scene, OverlayCommandState Command, OverlayChatMessage[] Chat)
        ProjectRoom(InformationOverlayRoomContent? room, OverlayScenePreference preference, string language)
    {
        var selection = InformationOverlayRuntimeProjection.ResolveScene(preference, room is not null);
        if (room is null || selection.Kind != InformationOverlaySceneKind.PartyRoom)
            return (new([], false, OverlaySceneContext.Local(preference) with { IsFallback = selection.IsFallback }),
                BuildCommandState(language), []);

        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language.Equals("zh-Hant", StringComparison.OrdinalIgnoreCase);
        var context = new OverlaySceneContext(preference, OverlaySceneKind.PartyRoom,
            traditional ? "目前房間" : zh ? "当前房间" : "Current room", false,
            RoomTitle: room.Title, RoomGoal: room.Goal, RoomMemberCount: room.Members.Count,
            RoomCapacity: room.Capacity, RoomId: room.RoomId, ChatChannelId: room.RoomId,
            ChatChannelTitle: room.Title);
        var players = room.Members.Select(member => OverlaySceneResolver.CreateRoomPlayer(
            new PartyLobbyMemberPreview(member.Callsign, member.GameId, IsHost: member.IsHost)
            {
                PresenceText = member.Presence,
                LocationText = member.Location,
                ShipText = member.Ship,
                ShardText = member.ServerRegion
            }, room.LocalHandle, null) with { SharedEventTypes = 0 }).ToArray();
        var scene = new OverlaySceneSnapshot(players, true, context);
        var command = BuildCommandState(language) with
        {
            NoticeTitle = traditional ? "房間接入" : zh ? "房间接入" : "PARTY LINK",
            NoticeText = traditional ? $"已接入 {room.Title} · {room.Members.Count}/{room.Capacity} 人"
                : zh ? $"已接入 {room.Title} · {room.Members.Count}/{room.Capacity} 人"
                : $"Linked to {room.Title} · {room.Members.Count}/{room.Capacity}"
        };
        var chat = room.Messages.Select(message => new OverlayChatMessage(message.Sequence,
            room.RoomId, message.SenderCallsign, message.SenderGameId, message.Text, message.CreatedAt,
            message.IsSystem, !string.IsNullOrEmpty(room.LocalHandle) &&
                message.SenderGameId.Equals(room.LocalHandle, StringComparison.OrdinalIgnoreCase), "")).ToArray();
        return (scene, command, chat);
    }
}
