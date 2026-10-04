using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
namespace StarBridge.Desktop.Tests;

internal static class OverlayLocalSelfTests
{
    internal static void RunAll()
    {
        var local = new GameLogSessionSnapshot(new("connected", "US", "pub_test_local_1"),
            new("confirmed", "Local fixture", "本机地点"), new("confirmed", "fixture", "Local ship", "本机舰船"));
        foreach (var status in new[] { "InGame", "AppOnline", "Offline", "InGame" })
        {
            var community = new InformationOverlayCommunityContent("fixture", "Fixture",
                [new("Self", "Self", "Member", status, "Remote ship", "Remote location", "US", true),
                 new("Peer", "Peer", "Member", "InGame", "Peer ship", "Peer location", "EU", false)]);
            var source = NativeInformationOverlayRuntime.ProjectSource(null, community, OverlayScenePreference.Auto, "zh",
                localSession: local, localPresence: PlayerPresenceKind.InGame);
            var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default with { HideSelfMember = false },
                OverlayRosterSelectionSettings.Default, "zh", true, source.Command, PlayerPresenceKind.InGame, local.Server.Shard!, source.Scene.Context);
            try
            {
                var self = model.Members.Single(row => row.DisplayName.Contains("Self"));
                Check(self.Location == "本机地点", $"Local self must ignore shared presence {status}; actual location: {self.Location}");
                Check(source.Scene.Players.Single(row => row.IsSelf).SharedPresence == PlayerPresenceKind.InGame, "Local display presence is authoritative.");
                Check(community.Members[0].Presence == status, "Display projection never rewrites shared source or outbound privacy.");
                Check(source.Scene.Players.Single(row => !row.IsSelf).SharedLocationText == "Peer location", "Peer keeps only authorized shared data.");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        var stale = new InformationOverlayCommunityContent("fixture", "Fixture",
            [new("Self", "Self", "Member", "AppOnline", "Remote ship", "Remote location", "US", true)]);
        var oldProjection = NativeInformationOverlayRuntime.ProjectSource(null, stale, OverlayScenePreference.Auto, "zh");
        Check(oldProjection.Scene.Players[0].SharedLocationCompactDisplayText.Contains("未进入游戏"),
            "Exact old-path repro: raw AppOnline overrides the still-running self row into not-in-game.");
        var room = new InformationOverlayRoomContent("room", "Room", "Goal", 4, "",
            [new("Self", "Self", true, "AppOnline", "Remote location", "Remote ship", "US") { IsSelf = true }], []);
        var localRoom = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
            localSession: local, localPresence: PlayerPresenceKind.InGame);
        Check(localRoom.Scene.Players.Single().SharedLocationText == "本机地点", "Room self uses same local projection.");
        Check(localRoom.Scene.Players.Single().SharedShipText == "本机舰船", "Authorized room self uses the local ship, not the remote placeholder.");
        var f8c = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
            localSession: local with { Ship = new("confirmed", "ANVL_F8C", "Anvil F8C Lightning", "F8C 闪电") },
            localPresence: PlayerPresenceKind.InGame);
        Check(f8c.Scene.Players[0].SharedShipDisplayText.Contains("F8C"), "The native room ship display consumes the confirmed local F8C.");
        var arriving = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
            localSession: local with { Location = local.Location with { ArrivalPendingConfirmation = true, ArrivalTargetCode = "fixture-target" } },
            localPresence: PlayerPresenceKind.InGame);
        Check(arriving.Scene.Players[0].ArrivalPendingConfirmation &&
            arriving.Scene.Players[0].LocationArrivalBadgeText.Length > 0,
            "Native member presentation must display the local arrival confirmation phase.");
        var eventSettings = OverlayDisplaySettings.Default with { HideSelfMember = false,
            ShowEventNotifications = true, EventNotificationTypes = OverlayEventNotificationTypes.LocationChange,
            AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var eventModel = new OverlayViewModel(new(localRoom.Scene.Players), eventSettings,
            OverlayRosterSelectionSettings.Default, "zh", true, localRoom.Command, PlayerPresenceKind.InGame,
            local.Server.Shard!, localRoom.Scene.Context);
        try
        {
            var moved = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
                localSession: local with { Location = new("confirmed", "Next fixture", "新地点") },
                localPresence: PlayerPresenceKind.InGame);
            eventModel.Refresh(new(moved.Scene.Players), eventSettings, OverlayRosterSelectionSettings.Default,
                "zh", true, moved.Command, PlayerPresenceKind.InGame, local.Server.Shard!, moved.Scene.Context);
            Check(eventModel.EventNotifications.Any(e => e.Detail.Contains("新地点")),
                "Confirmed local location changes must reach native event cards independently of shared event permissions.");
            var count = eventModel.EventNotifications.Count;
            eventModel.Refresh(new(moved.Scene.Players), eventSettings, OverlayRosterSelectionSettings.Default,
                "zh", true, moved.Command, PlayerPresenceKind.InGame, local.Server.Shard!, moved.Scene.Context);
            Check(eventModel.EventNotifications.Count == count, "Repeated identical refresh never repeats the location event.");
            var disabled = eventSettings with { ShowEventNotifications = false };
            eventModel.Refresh(new(localRoom.Scene.Players), disabled, OverlayRosterSelectionSettings.Default,
                "zh", true, localRoom.Command, PlayerPresenceKind.InGame, local.Server.Shard!, localRoom.Scene.Context);
            Check(eventModel.EventNotifications.Count == 0, "Local location events still honor the user's event switch.");
        }
        finally { eventModel.ClearAuthorizedContent(); }
        var notSelf = NativeInformationOverlayRuntime.ProjectSource(room with {
            LocalHandle = "Self", Members = [room.Members[0] with { IsSelf = false }]
        }, null, OverlayScenePreference.Auto, "zh", localSession: local, localPresence: PlayerPresenceKind.InGame);
        Check(!notSelf.Scene.Players[0].IsSelf && notSelf.Scene.Players[0].SharedLocationText == "Remote location",
            "An explicit non-self identity cannot obtain local detail through a matching display name/handle.");
        var english = NativeInformationOverlayRuntime.ProjectSource(null, stale, OverlayScenePreference.Auto, "en",
            localSession: local, localPresence: PlayerPresenceKind.InGame);
        Check(english.Scene.Players.Single().SharedLocationText == "Local fixture", "Local display preserves English mode.");
        var emptySession = NativeInformationOverlayRuntime.ProjectSource(null, stale, OverlayScenePreference.Auto, "zh",
            localSession: GameLogSessionSnapshot.Empty, localPresence: PlayerPresenceKind.InGame);
        Check(emptySession.Scene.Players.Single().SharedPresence == PlayerPresenceKind.InGame &&
            !emptySession.Scene.Players.Single().SharedLocationText.Contains("Remote"), "Unavailable local detail never falls back to stale remote self fields or invents exit.");
        var stopped = NativeInformationOverlayRuntime.ProjectSource(null, stale, OverlayScenePreference.Auto, "zh",
            localSession: local, localPresence: PlayerPresenceKind.AppOnline);
        Check(stopped.Scene.Players.Single().SharedPresence == PlayerPresenceKind.AppOnline &&
            stopped.Scene.Players.Single().ServerShard == null && !stopped.Scene.Players.Single().SharedLocationText.Contains("本机地点"),
            "Confirmed local stop clears local ship/location/server detail.");
        var revoked = NativeInformationOverlayRuntime.ProjectSource(null, null, OverlayScenePreference.Auto, "zh",
            localSession: local, localPresence: PlayerPresenceKind.InGame);
        Check(revoked.Scene.Players.Count == 0, "Local self is never inserted into a revoked source.");
        var ambiguous = oldProjection.Scene with { Players = [oldProjection.Scene.Players[0], oldProjection.Scene.Players[0]] };
        Check(ReferenceEquals(ambiguous, NativeInformationOverlayRuntime.ProjectLocalSelf(ambiguous, local, PlayerPresenceKind.InGame, "zh")),
            "Ambiguous self identity never receives local private data.");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
