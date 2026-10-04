using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.Desktop.Tests;

internal static class OverlayArrivalSourceTests
{
    internal static void RunAll()
    {
        var failures = new List<string>();
        foreach (var test in new Action[] { NavigationTargetsUseActualStationNames, ArrivalUsesCurrentTarget, SharedArrivalFollowsAuthorizedTarget, LocalArrivalConfirmationMerges, LocalFirstLocationIsNotLost, SelectedSourceKeepsItsKind })
            try { test(); } catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        if (failures.Count > 0) throw new Exception(string.Join(Environment.NewLine, failures));
    }

    private static void NavigationTargetsUseActualStationNames()
    {
        if (!LocationNameLocalizer.IsCatalogLoaded)
        {
            Console.WriteLine("SKIP navigation station rendering: optional location catalog absent");
            return;
        }
        using var stream = typeof(StarBridge.Core.Locations.NavigationStationDisplay).Assembly
            .GetManifestResourceStream("StarBridge.NavigationStationDisplay.json")!;
        using var data = System.Text.Json.JsonDocument.Parse(stream);
        var cases = 0;
        foreach (var entry in data.RootElement.GetProperty("entries").EnumerateArray())
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        foreach (var roomScene in new[] { true, false })
        {
            var route = "LOC_" + entry.GetProperty("navigationCode").GetString()!.ToUpperInvariant() + " [12345]";
            var station = entry.GetProperty("stationCode").GetString()!;
            var name = LocationNameLocalizer.DisplayName(station, language);
            Check(name != station, "station catalog is actually loaded for rendering assertions");
            Check(LocationNameLocalizer.DisplayName(LocationNameLocalizer.DisplayName(station, "en"), language) == name,
                "station English shared values localize back to the same display name");
            var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
                [new("Peer", "Peer", false, "InGame", "Old place", "", "US")
                    { ArrivalPendingConfirmation = true, ArrivalTargetCode = route }], []);
            var community = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Peer", "Peer", "Member", "InGame", "", "Old place", "US", false)
                    { ArrivalPendingConfirmation = true, ArrivalTargetCode = route }]);
            var source = NativeInformationOverlayRuntime.ProjectSource(roomScene ? room : null, roomScene ? null : community,
                OverlayScenePreference.Auto, language);
            var model = new OverlayViewModel(new(source.Scene.Players), Settings(), OverlayRosterSelectionSettings.Default,
                language, true, source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            try
            {
                var expected = name + (language == "en" ? " · pending" : language == "zh-Hant" ? " · 待確認" : " · 待确认");
                Check(model.Members.Single().Location == expected, "receiving arrival uses station name and keeps pending: " + route + "/" + language);
                Check(source.Scene.Players.Single().ArrivalPendingConfirmation, "projection never confirms a pending navigation target");
                Check(LocationArrivalPresentation.ResolveCurrentLocation(PlayerPresenceKind.InGame, true, "Old place", true, route, language) == expected,
                    "local and remote arrival presentations use the same station display");
                cases++;
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine($"PASS navigation station native member rendering: {cases} route/scene/language combinations");
    }

    private static void ArrivalUsesCurrentTarget()
    {
        var local = new GameLogSessionSnapshot(new("connected", "US", "pub_test_local_1"),
            new("confirmed", "old place", "上次地点") { ArrivalPendingConfirmation = true, ArrivalTargetCode = "本次目标" },
            new("confirmed", "ANVL_Arrow", "Anvil Arrow", "箭矢"));
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Self", "Self", true, "InGame", "remote", "", "US") { IsSelf = true }], []);
        var community = new InformationOverlayCommunityContent("fixture", "Community",
            [new("Self", "Self", "Member", "InGame", "", "remote", "US", true)]);
        foreach (var roomScene in new[] { true, false })
        {
            var projection = NativeInformationOverlayRuntime.ProjectSource(roomScene ? room : null,
                roomScene ? null : community, OverlayScenePreference.Auto, "zh", localSession: local, localPresence: PlayerPresenceKind.InGame);
            var settings = OverlayDisplaySettings.Default with { HideSelfMember = false, AnimationFrameRate = OverlayAnimationFrameRate.Off,
                EventNotificationTypes = OverlayEventNotificationTypes.LocationChange };
            var model = new OverlayViewModel(new(projection.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
                "zh", true, projection.Command, PlayerPresenceKind.InGame, local.Server.Shard!, projection.Scene.Context);
            try
            {
                Check(model.Members.Single().Location.Contains("本次目标") && !model.Members.Single().Location.Contains("上次地点"),
                    "pending arrival must display this quantum target instead of the previous confirmed location");
                Check(model.Members.Single().Location.Contains("待确认"), "target is explicitly pending, never asserted as confirmed current location");
                Check(local.Location.ChineseName == "上次地点", "presentation does not rewrite the last confirmed snapshot");
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }

    private static void SelectedSourceKeepsItsKind()
    {
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "", [], []);
        var selectedCommunity = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh", true);
        var model = new OverlayViewModel(new(selectedCommunity.Scene.Players), OverlayDisplaySettings.Default,
            OverlayRosterSelectionSettings.Default, "zh", false, selectedCommunity.Command, PlayerPresenceKind.AppOnline, "", selectedCommunity.Scene.Context);
        try
        {
            Check(selectedCommunity.Scene.Context.Kind == OverlaySceneKind.Community && model.SquadsTitle == "组织概况",
                "selected organization with a pending/unavailable read must not flash fleet/local scene labels");
            Check(selectedCommunity.Scene.Players.Count == 0 && !selectedCommunity.Scene.HasContent &&
                model.Members.Single().DisplayName == "暂无可显示成员", "selection does not authorize retaining or substituting another roster");
            Check(!model.SquadStatusPrimaryName.Contains("无舰队"), "unavailable organization never becomes a no-fleet fact");
            var selectedRoom = NativeInformationOverlayRuntime.ProjectSource(null,
                new("fixture", "Community", []), OverlayScenePreference.PartyRoom, "en");
            model.Refresh(new(selectedRoom.Scene.Players), OverlayDisplaySettings.Default, OverlayRosterSelectionSettings.Default,
                "en", selectedRoom.Scene.HasContent, selectedRoom.Command, PlayerPresenceKind.AppOnline, "", selectedRoom.Scene.Context);
            Check(model.SquadsTitle == "PARTY OVERVIEW" && selectedRoom.Scene.Players.Count == 0 &&
                model.Members.Single().DisplayName == "No visible members" &&
                model.SquadStatusPrimaryName == "Room information unavailable", "an unavailable explicitly selected room keeps room semantics without substituting organization");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void SharedArrivalFollowsAuthorizedTarget()
    {
        var key = OverlayMemberIdentity.FromAccountId("synthetic-arrival-peer");
        var notice = new SharedActivityNotice("Peer", new("arrival-fixture", "PlayerLocationChanged", DateTimeOffset.UtcNow), () => true)
            { PublisherKey = key };
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        foreach (var roomScene in new[] { true, false })
        {
            var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
                [new("Peer", "Peer", false, "InGame", "Old place", "", "US")
                    { PreferenceKey = key, ArrivalPendingConfirmation = true, ArrivalTargetCode = "Current target" }], []);
            var community = new InformationOverlayCommunityContent("fixture", "Community",
                [new("Peer", "Peer", "Member", "InGame", "", "Old place", "US", false)
                    { PreferenceKey = key, ArrivalPendingConfirmation = true, ArrivalTargetCode = "Current target" }]);
            var source = NativeInformationOverlayRuntime.ProjectSource(roomScene ? room : null, roomScene ? null : community,
                OverlayScenePreference.Auto, language);
            var settings = Settings();
            var model = new OverlayViewModel(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
                language, true, source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            try
            {
                var row = model.Members.Single();
                Check(row.Location.Contains("Current target") && !row.Location.Contains("Old place"), "receiving member row displays this authorized pending target");
                model.EventNotifications.Clear();
                model.QueueGameEventNotification(OverlayEventNotificationTypes.LocationChange, "Peer", "", false, false,
                    notice.IsCurrent, rows => NativeInformationOverlayRuntime.LocationActivityDetail(notice, rows, language));
                var card = model.EventNotifications.Single();
                Check(card.Detail.Contains("Current target") && !card.Detail.Contains("Old place"), "receiving event must use the same current target as the member row");
                Check(card.Detail.Contains(language == "en" ? "pending" : language == "zh-Hant" ? "待確認" : "待确认"), "receiving card cannot assert a confirmed arrival");
                var expires = card.ExpiresAt;
                var known = source.Scene.Players.Select(p => p with { ArrivalPendingConfirmation = false,
                    ArrivalTargetCode = null, Location = "Current target", RawLocation = "Current target", SharedLocation = "Current target" }).ToArray();
                model.Refresh(new(known), settings, OverlayRosterSelectionSettings.Default, language, true,
                    source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
                Check(ReferenceEquals(card, model.EventNotifications.Single()) && card.ExpiresAt == expires &&
                    !card.Detail.Contains(language == "en" ? "pending" : language == "zh-Hant" ? "待確認" : "待确认"), "confirmed snapshot updates the existing card without replay or lifetime renewal");
                var hidden = known.Select(p => p with { Location = "Unknown", RawLocation = "Unknown", SharedLocation = "Unknown",
                    ArrivalTargetCode = null, LocationHiddenReason = SharedLocationVisibility.LowConfidence }).ToArray();
                model.Refresh(new(hidden), settings, OverlayRosterSelectionSettings.Default, language, true,
                    source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
                Check(!card.Detail.Contains("Current target"), "location privacy withdrawal removes old target from the live card");
                model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, language, true,
                    source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
                Check(!card.Detail.Contains("Current target"), "revoked roster cannot supplement the event");
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }

    private static void LocalArrivalConfirmationMerges()
    {
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Self", "Self", true, "InGame", "Old place", "", "US") { IsSelf = true }], []);
        var baseline = new GameLogSessionSnapshot(new("connected", "US", "pub_test_local_1"),
            new("confirmed", "Old place", "Old place"), new("unknown", null, null, null));
        var source = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
            localSession: baseline, localPresence: PlayerPresenceKind.InGame);
        var settings = Settings();
        var model = new OverlayViewModel(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
            "zh", true, source.Command, PlayerPresenceKind.InGame, baseline.Server.Shard!, source.Scene.Context);
        try
        {
            model.EventNotifications.Clear();
            void Refresh(GameLogSessionSnapshot session)
            {
                var next = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
                    localSession: session, localPresence: PlayerPresenceKind.InGame);
                model.Refresh(new(next.Scene.Players), settings, OverlayRosterSelectionSettings.Default, "zh", true,
                    next.Command, PlayerPresenceKind.InGame, baseline.Server.Shard!, next.Scene.Context);
            }
            Refresh(baseline with { Location = baseline.Location with { ArrivalPendingConfirmation = true, ArrivalTargetCode = "Current target" } });
            var card = model.EventNotifications.Single();
            Check(card.Detail.Contains("Current target") && !card.Detail.Contains("Old place") && card.Detail.Contains("待确认"), "local arrival event uses target, never retained history");
            Refresh(baseline with { Location = new("confirmed", "Current target", "Current target") });
            Check(model.EventNotifications.Count == 1 && ReferenceEquals(card, model.EventNotifications.Single()) &&
                card.Title == "地点已确认" && !card.Detail.Contains("待确认"), "same target confirmation merges even without a location string change");
            model.EventNotifications.Clear();
            Refresh(baseline with { Location = baseline.Location with { ArrivalPendingConfirmation = true, ArrivalTargetCode = null } });
            Check(model.Members.Single().Location == "地点待确认" && !model.EventNotifications.Single().Detail.Contains("Old place"), "arrival without a current target cannot substitute history");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static OverlayDisplaySettings Settings() => OverlayDisplaySettings.Default with { HideSelfMember = false,
        ShowEventNotifications = true, AnimationFrameRate = OverlayAnimationFrameRate.Off,
        EventNotificationTypes = OverlayEventNotificationTypes.LocationChange };

    private static void LocalFirstLocationIsNotLost()
    {
        var room = new InformationOverlayRoomContent("fixture", "Room", "", 4, "",
            [new("Self", "Self", true, "InGame", "", "", "US") { IsSelf = true }], []);
        var baseline = new GameLogSessionSnapshot(new("connected", "US", "pub_test_local_1"),
            new("unknown", null, null), new("unknown", null, null, null));
        var initial = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
            localSession: baseline, localPresence: PlayerPresenceKind.InGame);
        var settings = Settings();
        var model = new OverlayViewModel(new(initial.Scene.Players), settings, OverlayRosterSelectionSettings.Default,
            "zh", true, initial.Command, PlayerPresenceKind.InGame, baseline.Server.Shard!, initial.Scene.Context);
        try
        {
            model.EventNotifications.Clear();
            var known = NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "zh",
                localSession: baseline with { Location = new("confirmed", "First place", "First place") },
                localPresence: PlayerPresenceKind.InGame);
            model.Refresh(new(known.Scene.Players), settings, OverlayRosterSelectionSettings.Default, "zh", true,
                known.Command, PlayerPresenceKind.InGame, baseline.Server.Shard!, known.Scene.Context);
            Check(model.EventNotifications.Single().Detail.Contains("First place"), "the first live location after the unknown baseline is a new event, not discarded as missing history");
            model.Refresh(new(known.Scene.Players), settings, OverlayRosterSelectionSettings.Default, "zh", true,
                known.Command, PlayerPresenceKind.InGame, baseline.Server.Shard!, known.Scene.Context);
            Check(model.EventNotifications.Count == 1, "unchanged confirmed snapshot is not replayed");
        }
        finally { model.ClearAuthorizedContent(); }
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
