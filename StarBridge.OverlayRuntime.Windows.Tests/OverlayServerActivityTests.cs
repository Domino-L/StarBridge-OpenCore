using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
namespace StarBridge.Desktop.Tests;

internal static class OverlayServerActivityTests
{
    internal static void RunAll()
    {
        var key = OverlayMemberIdentity.FromAccountId("synthetic-region-member");
        var notice = new SharedActivityNotice("Same name", new("region-fixture", "ServerJoined", DateTimeOffset.UtcNow), () => true)
            { PublisherKey = key };
        foreach (var (region, label) in new[] { ("US", "美服"), ("ASIA", "亚服"), ("EU", "欧服"), ("AU", "澳服") })
        foreach (var roomMode in new[] { true, false })
        {
            var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
                [new("Same name", "Fixture", false, "InGame", "", "", region) { PreferenceKey = key }], []);
            var community = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Same name", "Fixture", "Member", "InGame", "", "", region, false) { PreferenceKey = key }]);
            var source = NativeInformationOverlayRuntime.ProjectSource(roomMode ? room : null,
                roomMode ? null : community, OverlayScenePreference.Auto, "zh");
            var rows = source.Scene.Players;
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, rows, "zh") == "进入服务器 · 当前区域：" + label,
                "Authorized room/community server event must include the localized region.");
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice with { PublisherKey = "other" }, rows, "zh") == "进入服务器",
                "Same callsign cannot supply another member's region.");
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [rows[0], rows[0]], "zh") == "进入服务器",
                "Ambiguous identity cannot supply a region.");
            var shard = rows[0] with { ServerShard = "pub_use1_fixture_001", ServerRegion = "ASIA" };
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [shard], "zh") == "进入服务器 · 当前区域：美服",
                "Canonical shard evidence may resolve a region but its code must never appear.");
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [rows[0] with { SharedLiveStatus = "AppOnline" }], "zh") == "进入服务器",
                "Old region on a non-playing member is not presented.");
            Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [rows[0] with { ServerRegion = "unknown", ServerShard = null }], "zh") == "进入服务器",
                "Unknown values never appear as server codes or fabricated regions.");
        }
        Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [], "zh-Hant") == "進入伺服器", "Revoked source has no region.");
        Check(NativeInformationOverlayRuntime.ServerActivityDetail(notice, [], "en") == "Joined a server", "English fallback remains localized.");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
