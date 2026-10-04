using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class OverlayRegionSummaryTests
{
    internal static void RunAll()
    {
        foreach (var language in new[] { "zh", "en" })
        foreach (var roomMode in new[] { true, false })
        foreach (var localShard in new[] { "", "pub_use1_fixture_001" })
        {
            var initialRoom = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
                [new("Peer", "Peer", false, "InGame", "", "", "EU")], []);
            var initialCommunity = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Peer", "Peer", "Member", "InGame", "", "", "EU", false)]);
            var source = NativeInformationOverlayRuntime.ProjectSource(roomMode ? initialRoom : null,
                roomMode ? null : initialCommunity, OverlayScenePreference.Auto, language);
            var settings = OverlayDisplaySettings.Default with { ShowEventNotifications = true,
                EventNotificationTypes = OverlayEventNotificationTypes.PrimaryServer, AnimationFrameRate = OverlayAnimationFrameRate.Off };
            var model = new OverlayViewModel(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
                language, true, source.Command, PlayerPresenceKind.InGame, localShard, source.Scene.Context);
            try
            {
                model.EventNotifications.Clear();
                var next = source.Scene.Players.Select(p => p with { ServerRegion = "US", ServerShard = null }).ToArray();
                model.Refresh(new(next), settings, OverlayRosterSelectionSettings.Default, language, true,
                    source.Command, PlayerPresenceKind.InGame, localShard, source.Scene.Context);
                var expected = language == "zh"
                    ? (roomMode ? "房间人数最多区域：美服" : "当前主服务器：美服")
                    : (roomMode ? "Busiest room region: US" : "Primary server: US");
                Check(model.EventNotifications.Any(card => card.Detail == expected),
                    $"Raw shared US and sender-local shard must use the same event vocabulary: {roomMode}/{language}/{localShard}");
                var count = model.EventNotifications.Count;
                model.Refresh(new(next.Select(p => p with { ServerRegion = "美服" }).ToArray()), settings,
                    OverlayRosterSelectionSettings.Default, language, true, source.Command,
                    PlayerPresenceKind.InGame, localShard, source.Scene.Context);
                Check(model.EventNotifications.Count == count, "Equivalent code/label must not create a second primary-region event.");
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }
    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
