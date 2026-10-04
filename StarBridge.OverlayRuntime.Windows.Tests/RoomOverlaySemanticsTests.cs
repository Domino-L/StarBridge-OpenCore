using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class RoomOverlaySemanticsTests
{
    internal static void RunAll()
    {
        var room = new InformationOverlayRoomContent("room-fixture", "Room fixture", "Room goal", 4, "Self",
            [new("Self", "Self", false, "InGame", "", "", "US"),
             new("Room host", "Host", true, "InGame", "", "", "US")], []);
        var organization = new InformationOverlayCommunityContent("org-fixture", "Organization fixture",
            [new("Outsider", "Outside room", "Member", "InGame", "", "", "US", false)]);
        var projected = NativeInformationOverlayRuntime.ProjectSource(room, organization, OverlayScenePreference.Auto, "zh");
        Check(projected.Scene.Players.Count == 2 && projected.Scene.Players.All(p => p.Name != "Outsider"),
            "Room roster must not include the simultaneously available organization.");
        var settings = OverlayDisplaySettings.Default with { ShowEventNotifications = true,
            EventNotificationTypes = OverlayEventNotificationTypes.SameServer,
            AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var model = new OverlayViewModel(new(projected.Scene.Players), settings,
            OverlayRosterSelectionSettings.Default, "zh", true, projected.Command,
            PlayerPresenceKind.AppOnline, "", projected.Scene.Context);
        try
        {
            model.Refresh(new(projected.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
                "zh", true, projected.Command, PlayerPresenceKind.InGame, "pub-use1-fixture-001", projected.Scene.Context);
            Check(model.EventNotifications.All(e => !e.Detail.Contains("组织成员") && !e.Detail.Contains("同服务器")),
                "Room with region-only data must not emit an organization or fabricated same-server count.");
            Check(model.SquadStatusPrimaryName == "成员 2 / 4", "Room overview must use room occupancy and capacity.");
            Check(model.SquadStatusFocusLine.Contains("同服务器人数待确认") && model.SquadStatusFocusLine.Contains("Room fixture") &&
                model.SquadStatusFocusLine.Contains("Room goal") && model.SquadStatusFocusLine.Contains("Room host"),
                "Room overview must carry room identity, host and goal without inventing a server count.");
            Check(projected.Scene.Context.RoomHostDisplay == "Room host", "Room context must carry the authorized host.");
        }
        finally { model.ClearAuthorizedContent(); }
        foreach (var language in new[] { "zh", "en" })
        {
            var exactPlayers = projected.Scene.Players.Select(p => p with { ServerShard = "pub-use1-fixture-001" }).ToArray();
            var events = settings with { EventNotificationTypes = OverlayEventNotificationTypes.SameServer | OverlayEventNotificationTypes.OnlineSummary };
            var exact = new OverlayViewModel(new(exactPlayers), events, OverlayRosterSelectionSettings.Default,
                language, true, projected.Command, PlayerPresenceKind.InGame, "", projected.Scene.Context);
            try
            {
                exact.Refresh(new(exactPlayers), events, OverlayRosterSelectionSettings.Default, language, true,
                    projected.Command, PlayerPresenceKind.InGame, "pub-use1-fixture-001", projected.Scene.Context);
                Check(exact.EventNotifications.Any(e => e.Detail == (language == "zh"
                    ? "当前有 1 名房间成员与你在同服务器" : "1 room members share your server")),
                    "Exact server evidence counts only the other room member, not self or organization outsiders.");
                var changed = exactPlayers.Select(p => p.IsSelf ? p : p with
                    { SharedLiveStatus = "AppOnline", LiveStatus = "AppOnline" }).ToArray();
                exact.Refresh(new(changed), events, OverlayRosterSelectionSettings.Default, language, true,
                    projected.Command, PlayerPresenceKind.InGame, "pub-use1-fixture-001", projected.Scene.Context);
                Check(exact.EventNotifications.Any(e => e.Detail == (language == "zh"
                    ? "房间游戏中 1 / 2" : "Room in game 1 / 2")), "Room in-game summary never labels the game count as fleet online.");
            }
            finally { exact.ClearAuthorizedContent(); }
        }
    }

    private static void Check(bool condition, string message)
    {
        if (!condition) throw new InvalidOperationException(message);
    }
}
