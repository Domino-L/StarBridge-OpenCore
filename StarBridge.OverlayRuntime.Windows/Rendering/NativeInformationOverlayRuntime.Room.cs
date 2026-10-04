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
        ProjectRoom(InformationOverlayRoomContent? room, OverlayScenePreference preference, string language, bool explicitSelf = false)
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
            RoomHostDisplay: room.Members.FirstOrDefault(member => member.IsHost)?.Callsign,
            RoomCapacity: room.Capacity, RoomId: room.RoomId, ChatChannelId: room.RoomId,
            ChatChannelTitle: room.Title);
        var players = room.Members.Select(member => OverlaySceneResolver.CreateRoomPlayer(
            new PartyLobbyMemberPreview(member.Callsign, member.GameId, IsHost: member.IsHost)
            {
                PresenceText = member.Presence,
                LocationText = member.Location,
                LocationHiddenReason = member.LocationHiddenReason,
                ShipText = member.Ship,
                ShardText = ""
            }, room.LocalHandle, null) with { SharedEventTypes = 0, RawShip = member.Ship, SharedShip = member.Ship,
                ServerRegion = member.ServerRegion, AccountId = member.PreferenceKey, RealtimeStateUnknown = member.Presence == "Unknown",
                ArrivalPendingConfirmation = member.ArrivalPendingConfirmation, ArrivalTargetCode = member.ArrivalTargetCode,
                IsSelf = member.IsSelf ?? (!string.IsNullOrWhiteSpace(room.LocalHandle) &&
                    member.GameId.Equals(room.LocalHandle, StringComparison.OrdinalIgnoreCase)) }).ToArray();
        var scene = new OverlaySceneSnapshot(players, true, context);
        var command = BuildCommandState(language) with
        {
            NoticeTitle = traditional ? "房間接入" : zh ? "房间接入" : "PARTY LINK",
            NoticeText = traditional ? $"已接入 {room.Title} · {room.Members.Count}/{room.Capacity} 人"
                : zh ? $"已接入 {room.Title} · {room.Members.Count}/{room.Capacity} 人"
                : $"Linked to {room.Title} · {room.Members.Count}/{room.Capacity}"
        };
        var chat = room.Messages.Select(message => new OverlayChatMessage(message.Sequence,
            room.RoomId, message.SenderCallsign, message.SenderGameId, OverlayMessageText(message, language), message.CreatedAt,
            message.IsSystem, explicitSelf ? message.IsSelf == true : !string.IsNullOrEmpty(room.LocalHandle) &&
                message.SenderGameId.Equals(room.LocalHandle, StringComparison.OrdinalIgnoreCase), "")).ToArray();
        return (scene, command, chat);
    }

    private static string OverlayMessageText(InformationOverlayRoomMessage message, string language)
    {
        if (string.IsNullOrWhiteSpace(message.AttachmentKind)) return message.Text;
        var traditional = language is "zh-Hant" or "zh-TW";
        var chinese = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var preset = message.AttachmentKind == StarBridge.Core.Chat.ChatAttachmentKinds.OverlayPreset;
        var hint = traditional ? (preset ? "[浮層預設] 請在客戶端查看" : "[附件] 請在客戶端查看")
            : chinese ? (preset ? "[浮层预设] 请在客户端查看" : "[附件] 请在客户端查看")
            : preset ? "[Overlay preset] View in the client" : "[Attachment] View in the client";
        return string.IsNullOrWhiteSpace(message.Text) ? hint : message.Text + "\n" + hint;
    }
}
