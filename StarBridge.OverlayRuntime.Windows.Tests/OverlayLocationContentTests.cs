using StarBridge.Core.Events;
using System.IO;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Privacy;
namespace StarBridge.Desktop.Tests;

internal static class OverlayLocationContentTests
{
    internal static void RunAll()
    {
        var path = Path.Combine(AppContext.BaseDirectory, "Data", "location-names-zh.txt");
        var previous = File.Exists(path) ? File.ReadAllBytes(path) : null;
        var catalogPath = Path.Combine(AppContext.BaseDirectory, "Data", "starbridge_location_catalog.json");
        var previousCatalog = File.Exists(catalogPath) ? File.ReadAllBytes(catalogPath) : null;
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        try
        {
            File.WriteAllText(path, "OverlayRoomTestPlace=测试地点\n");
            File.WriteAllText(catalogPath, """
                {"schemaVersion":1,"normalization":{"comparison":"ordinal-ignore-case","optionalQuantumPrefix":"QT_","instanceSuffixPattern":"_[0-9]+$"},
                 "statistics":{"entries":3,"reviewedChineseEntries":3},
                 "entries":[
                   {"canonicalCode":"RR_P3_LEO","nameEn":"Orbituary","nameZh":"轨道讣闻站"},
                   {"canonicalCode":"SyntheticA","nameEn":"Ambiguous fixture","nameZh":"测试甲"},
                   {"canonicalCode":"SyntheticB","nameEn":"Ambiguous fixture","nameZh":"测试乙"}]}
                """);
            OrganizationAndRoomDisplayNames();
            var key = OverlayMemberIdentity.FromAccountId("synthetic-local-member");
            var room = new InformationOverlayRoomContent("synthetic-room", "Room", "Goal", 4, "",
                [new("Same name", "Synthetic", true, "InGame", "OverlayRoomTestPlace", "", "US") { PreferenceKey = key }], []);
            var source = NativeInformationOverlayRuntime.ProjectRoom(room, OverlayScenePreference.Auto, "zh");
            var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default,
                OverlayRosterSelectionSettings.Default, "zh", true, source.Command,
                PlayerPresenceKind.AppOnline, "", source.Scene.Context);
            try
            {
                Check(model.Members.Single().Location == "测试地点", "Actual room member row must localize the authorized location.");
                var notice = new SharedActivityNotice("Same name", new("synthetic-event", "PlayerLocationChanged", DateTimeOffset.UtcNow), () => true)
                    { PublisherKey = key };
                Check(NativeInformationOverlayRuntime.LocationActivityDetail(notice, source.Scene.Players, "zh").Contains("当前地点：测试地点"),
                    "Location notice supplements authorized current location.");
                Check(!NativeInformationOverlayRuntime.LocationActivityDetail(notice with { PublisherKey = "other" }, source.Scene.Players, "zh").Contains("测试地点"),
                    "Same callsign is not an identity match.");
                Check(NativeInformationOverlayRuntime.LocationActivityDetail(notice,
                    [source.Scene.Players[0] with { ArrivalPendingConfirmation = true }], "zh").Contains("待确认"),
                    "Unconfirmed arrival is never promoted to confirmed location.");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        finally
        {
            if (previous is null) File.Delete(path); else File.WriteAllBytes(path, previous);
            if (previousCatalog is null) File.Delete(catalogPath); else File.WriteAllBytes(catalogPath, previousCatalog);
        }
    }

    private static void OrganizationAndRoomDisplayNames()
    {
        Check(LocationNameLocalizer.IsCatalogLoaded, LocationNameLocalizer.CatalogLoadError ?? "Fixture catalog must load.");
        foreach (var language in new[] { "zh", "zh-CN", "zh-Hant", "en", "en-US" })
        foreach (var raw in new[] { "RR_P3_LEO", "Orbituary" })
        foreach (var isRoom in new[] { false, true })
        {
            var expected = language.StartsWith("zh") ? "轨道讣闻站" : "Orbituary";
            var key = OverlayMemberIdentity.FromAccountId("synthetic-local-member");
            var room = new InformationOverlayRoomContent("fixture", "Room", "Goal", 4, "",
                [new("Fixture", "Fixture", true, "InGame", raw, "", "US") { PreferenceKey = key }], []);
            var community = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Fixture", "Fixture", "Member", "InGame", "", raw, "US", true) { PreferenceKey = key }]);
            var source = NativeInformationOverlayRuntime.ProjectSource(isRoom ? room : null,
                isRoom ? null : community, OverlayScenePreference.Auto, language);
            var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default,
                OverlayRosterSelectionSettings.Default, language, true, source.Command,
                PlayerPresenceKind.InGame, "", source.Scene.Context);
            try
            {
                Check(model.Members.Single().Location == expected,
                    $"{(isRoom ? "room" : "community")} member {language}/{raw}: expected {expected}, got {model.Members.Single().Location}");
                if (!isRoom)
                {
                    var overview = OverlayOverviewProjection.Project(source.Scene.Players.ToArray(), source.Scene.Context,
                        true, PlayerPresenceKind.InGame, "", language);
                    Check(overview.TopLocations.Single().DisplayName == expected,
                        $"community overview {language}/{raw}: expected {expected}, got {overview.TopLocations.Single().DisplayName}");
                }
                var notice = new SharedActivityNotice("Fixture", new("fixture", "PlayerLocationChanged", DateTimeOffset.UtcNow), () => true)
                    { PublisherKey = key };
                Check(NativeInformationOverlayRuntime.LocationActivityDetail(notice, source.Scene.Players, language).Contains(expected),
                    "Location event uses the same display localization.");
                Check(!NativeInformationOverlayRuntime.LocationActivityDetail(notice, [], language).Contains(expected),
                    "Revoked roster never supplies a location.");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Check(LocationNameLocalizer.DisplayName("Uncatalogued fixture", "zh-CN") == "Uncatalogued fixture", "Unknown input stays unchanged.");
        Check(LocationNameLocalizer.DisplayName("Ambiguous fixture", "zh-CN") == "Ambiguous fixture", "Ambiguous English names cannot pick a place.");
        Check(!LocationNameLocalizer.TryResolve("Orbituary", out _),
            "Display-name fallback must not turn a display string into a canonical identity or arrival target.");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
