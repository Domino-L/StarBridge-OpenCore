// Same regression runs against both the internal client and the independent renderer.
namespace StarBridge.Desktop.Tests;

using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

internal static class RoomOverlayProjectionTests
{
    internal static void RunAll()
    {
        var content = new InformationOverlayRoomContent("room", "Room title", "Goal", 4, "Case_Handle",
            [new("Callsign", "Case_Handle", true, "InGame", "", "", "US")],
            [new(2, "Callsign", "Case_Handle", "Chat text", DateTimeOffset.UtcNow, false)]);
        var projected = NativeInformationOverlayRuntime.ProjectRoom(content, OverlayScenePreference.Auto, "zh");
        Check(projected.Scene.HasContent && projected.Scene.Context.Kind == OverlaySceneKind.PartyRoom,
            "Auto selects authoritative room.");
        var player = projected.Scene.Players.Single();
        Check(player.Name == "Case_Handle" && player.Callsign == "Callsign" && player.IsSelf,
            "Shared WPF row projection preserves identity and self rules.");
        Check(player.ServerShard == "US", "No concrete shard in room overlay.");
        Check(projected.Chat.Single().IsSelf && projected.Chat.Single().ChannelId == "room",
            "Chat is scoped to current room and authoritative local handle.");
        Check(projected.Command.NoticeText!.Contains("Room title"), "Notice uses real room title.");
        Check(NativeInformationOverlayRuntime.ProjectRoom(content, OverlayScenePreference.Auto, "zh-Hant")
            .Command.NoticeTitle == "房間接入", "Traditional notice.");
        Check(NativeInformationOverlayRuntime.ProjectRoom(content, OverlayScenePreference.Auto, "en")
            .Command.NoticeTitle == "PARTY LINK", "English notice.");
        var fleet = NativeInformationOverlayRuntime.ProjectRoom(content, OverlayScenePreference.Fleet, "en");
        Check(fleet.Scene.Context.IsLocalOnly && fleet.Chat.Length == 0 && fleet.Scene.Players.Count == 0,
            "Explicit fleet never leaks room data into another scene.");
        var empty = NativeInformationOverlayRuntime.ProjectRoom(null, OverlayScenePreference.PartyRoom, "en");
        Check(empty.Scene.Context.IsLocalOnly && empty.Scene.Context.IsFallback, "Missing room falls back locally.");

        var settings = OverlayDisplaySettings.Default with { ChatDisplayMode = OverlayChatDisplayMode.MessageList };
        var model = new OverlayViewModel(new OverlayAuthorizedRoster(projected.Scene.Players), settings,
            OverlayRosterSelectionSettings.Default, "zh", true, projected.Command,
            PlayerPresenceKind.AppOnline, "", projected.Scene.Context, projected.Chat);
        Check(model.ChatMessages.Count == 1, "Real view model consumes the projected room chat.");
        model.QueueCommunicationEvent("Old notice", "Old room detail");
        for (var i = 0; i < 10; i++)
            model.QueueGameEventNotification(OverlayEventNotificationTypes.All,
                $"Old event {i}", "Old room detail", false, true);
        Check(model.EventNotifications.Count > 0 && model.PendingEventNotificationCount > 0,
            "Test includes visible and queued old-room events before revocation.");
        model.ClearAuthorizedContent();
        Check(model.ChatMessages.Count == 0 && model.Members.Count == 0 && model.EventNotifications.Count == 0 &&
            model.PendingEventNotificationCount == 0 && model.FleetNotice == "",
            "Revocation clears visible content and pending event queues.");
        model.Refresh(new OverlayAuthorizedRoster([]), settings, OverlayRosterSelectionSettings.Default,
            "en", false, empty.Command, PlayerPresenceKind.AppOnline, "", empty.Scene.Context, []);
        Check(model.ChatMessages.Count == 0 && model.Members.All(member =>
            !member.DisplayName.Contains("Callsign") && !member.DisplayName.Contains("Case_Handle")),
            "Local fallback may show an empty-state row but never restores room data.");
        model.ClearAuthorizedContent();
        var liveId = Guid.NewGuid();
        Check(model.TryShowLiveCommunicationEvent(liveId, "Room reminder", "New invitation"), "Idle notice accepts a real-time reminder");
        Check(!model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Another", "No delayed queue"), "Busy notice does not queue a late reminder");
        model.ClearLiveCommunicationEvent(Guid.NewGuid());
        Check(model.FleetNotice == "New invitation", "Unrelated cleanup cannot clear another reminder");
        model.ClearLiveCommunicationEvent(liveId);
        Check(model.FleetNotice == "", "Target revocation clears live text");
        model.QueueCommunicationEvent("Other channel", "Preserve this notice");
        model.ClearLiveCommunicationEvent(liveId);
        Check(model.FleetNotice == "Preserve this notice", "Reminder cleanup preserves other communication content");
        model.ClearAuthorizedContent();
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}
