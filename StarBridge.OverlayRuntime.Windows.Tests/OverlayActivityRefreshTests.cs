using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
namespace StarBridge.Desktop.Tests;

internal static class OverlayActivityRefreshTests
{
    internal static void RunAll()
    {
        var key = OverlayMemberIdentity.FromAccountId("synthetic-peer");
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Peer", "Peer", false, "InGame", "", "", "US") { PreferenceKey = key }], []);
        var source = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh");
        var notice = new SharedActivityNotice("Peer", new("fixture", "PlayerLocationChanged", DateTimeOffset.UtcNow), () => true)
            { PublisherKey = key };
        var settings = OverlayDisplaySettings.Default with { ShowEventNotifications = true,
            EventNotificationTypes = OverlayEventNotificationTypes.LocationChange, AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var model = new OverlayViewModel(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
            "zh", true, source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
        try
        {
            model.EventNotifications.Clear(); // Remove the separate startup connection notice.
            model.QueueGameEventNotification(OverlayEventNotificationTypes.LocationChange, "Peer",
                NativeInformationOverlayRuntime.LocationActivityDetail(notice, source.Scene.Players, "zh"), false, false,
                notice.IsCurrent, rows => NativeInformationOverlayRuntime.LocationActivityDetail(notice, rows, "zh"));
            var card = model.EventNotifications.Single();
            Check(card.Detail.Contains("待确认"), "Event arrives before the member location snapshot.");
            var expires = card.ExpiresAt;
            var known = source.Scene.Players.Select(p => p with { Location = "测试地点", SharedLocation = "测试地点" }).ToArray();
            model.Refresh(new(known), settings, OverlayRosterSelectionSettings.Default, "zh", true,
                source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            Check(model.Members.Single().Location == "测试地点", "The member pane already has the confirmed location.");
            Check(card.Detail.Contains("当前地点：测试地点"), "The existing event card must follow the same confirmed member snapshot.");
            Check(model.EventNotifications.Count == 1 && ReferenceEquals(card, model.EventNotifications[0]) && card.ExpiresAt == expires,
                "Supplementing detail does not replay the event or extend its lifetime.");
            model.QueueGameEventNotification(OverlayEventNotificationTypes.LocationChange, "Peer", "待确认", false, false,
                notice.IsCurrent, rows => NativeInformationOverlayRuntime.LocationActivityDetail(notice, rows, "zh"));
            Check(model.EventNotifications.Last().Detail.Contains("当前地点：测试地点"),
                "Presentation resolves against the already displayed roster instead of a stale enqueue-time string.");
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "zh", true,
                source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            Check(!card.Detail.Contains("测试地点"), "Revoked member location is removed from the existing card.");
        }
        finally { model.ClearAuthorizedContent(); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
