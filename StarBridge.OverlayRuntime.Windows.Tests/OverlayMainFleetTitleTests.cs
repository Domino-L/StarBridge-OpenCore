using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

/// The main fleet is shown as one more organization: the organization wording,
/// its own name, and only its privacy-projected rows.
internal static class OverlayMainFleetTitleTests
{
    internal static void RunAll()
    {
        var tests = new (string Name, Action Run)[]
        {
            ("organization titles and shared self", Titles),
            ("events ignore the local server for a hidden self", () => PrimaryServerEvent(true, false)),
            ("ordinary community events keep the local server", () => PrimaryServerEvent(false, true)),
            ("hidden self server", () => Overview(true, "InGame", "", PlayerPresenceKind.InGame, "No server region data", "In game 1 / 1")),
            ("projected self server", () => Overview(true, "InGame", "EU", PlayerPresenceKind.InGame, "EU · 1", "In game 1 / 1")),
            ("projected app presence", () => Overview(true, "AppOnline", "", PlayerPresenceKind.InGame, "No one is in game", "In game 0 / 1")),
            ("projected offline presence", () => Overview(true, "Offline", "", PlayerPresenceKind.InGame, "No one is in game", "In game 0 / 0")),
            ("local app presence cannot override shared", () => Overview(true, "InGame", "EU", PlayerPresenceKind.AppOnline, "EU · 1", "In game 1 / 1")),
            ("ordinary community keeps local self", () => Overview(false, "AppOnline", "EU", PlayerPresenceKind.InGame, "US · 1", "In game 1 / 1"))
        };
        var failed = 0;
        foreach (var test in tests)
        {
            try { test.Run(); Console.WriteLine("PASS main fleet overview " + test.Name); }
            catch (Exception error) { failed++; Console.WriteLine("FAIL main fleet overview " + test.Name + ": " + error.Message); }
        }
        Console.WriteLine($"Main fleet overview: {tests.Length - failed} passed, {failed} failed");
        if (failed > 0) throw new Exception($"Main fleet overview: {failed} failed");
    }

    private static void Overview(bool sharedOnly, string presence, string region, PlayerPresenceKind localPresence,
        string expectedServer, string expectedSummary)
    {
        var local = new GameLogSessionSnapshot(new("connected", "US", "pub_use1_fixture_1"),
            new("confirmed", "Local fixture", "本机地点"), new("confirmed", "fixture", "Local ship", "本机舰船"));
        var community = new InformationOverlayCommunityContent("fleet", "Fixture fleet",
            [new("Self", "Self", "Member", presence, "", "", region, true)]) { SharedFieldsOnly = sharedOnly };
        var source = NativeInformationOverlayRuntime.ProjectSource(null, community, OverlayScenePreference.Auto, "en", true,
            localSession: local, localPresence: localPresence);
        var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default with { HideSelfMember = false },
            OverlayRosterSelectionSettings.Default, "en", true, source.Command, localPresence, local.Server.Shard!, source.Scene.Context);
        try
        {
            Check(model.SquadStatusServerSummary == expectedServer,
                $"Expected projected server {expectedServer}; actual {model.SquadStatusServerSummary}");
            Check(model.SquadStatusSummary == expectedSummary,
                $"Expected projected presence {expectedSummary}; actual {model.SquadStatusSummary}");
            if (sharedOnly && region.Length == 0 && presence == "InGame")
                Check(model.SquadStatusFocusLine == "Same shard as you 0", "Hidden self server cannot be inferred as the local shard.");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void PrimaryServerEvent(bool sharedOnly, bool expectEvent)
    {
        const string us = "pub_use1_fixture_1", eu = "pub_euw1_fixture_1";
        var community = new InformationOverlayCommunityContent("fleet", "Fixture fleet",
            [new("Self", "Self", "Member", "InGame", "", "", "", true)]) { SharedFieldsOnly = sharedOnly };
        var source = NativeInformationOverlayRuntime.ProjectSource(null, community, OverlayScenePreference.Auto, "en", true);
        var settings = OverlayDisplaySettings.Default with { HideSelfMember = false, ShowEventNotifications = true,
            EventNotificationTypes = OverlayEventNotificationTypes.PrimaryServer, AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var model = new OverlayViewModel(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default, "en", true,
            source.Command, PlayerPresenceKind.InGame, us, source.Scene.Context);
        try
        {
            model.Refresh(new(source.Scene.Players), settings, OverlayRosterSelectionSettings.Default, "en", true,
                source.Command, PlayerPresenceKind.InGame, eu, source.Scene.Context);
            Check(model.EventNotifications.Any(e => e.EventType == OverlayEventNotificationTypes.PrimaryServer) == expectEvent,
                $"Local server change with sharedOnly={sharedOnly}: " + string.Join(" | ", model.EventNotifications.Select(e => e.EventType + ":" + e.Detail)));
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void Titles()
    {
        var local = new GameLogSessionSnapshot(new("connected", "US", "pub_test_local_1"),
            new("confirmed", "Local fixture", "本机地点"), new("confirmed", "fixture", "Local ship", "本机舰船"));
        foreach (var (language, overview, members) in new[]
        {
            ("zh", "组织概况", "组织成员"),
            ("en", "ORGANIZATION OVERVIEW", "ORGANIZATION MEMBERS"),
        })
        {
            var fleet = new InformationOverlayCommunityContent("fleet", "Domino Pizza",
                [new("Self", "Self", "Member", "InGame", "Shared ship", "Shared place", "EU", true)]) { SharedFieldsOnly = true };
            var source = NativeInformationOverlayRuntime.ProjectSource(null, fleet, OverlayScenePreference.Auto, language, true,
                localSession: local, localPresence: PlayerPresenceKind.InGame);
            Check(source.Scene.Context.Kind == OverlaySceneKind.Community, "the main fleet uses the organization scene");
            Check(source.Scene.Context.ChatChannelTitle == "Domino Pizza", "the chat is titled with the fleet's own name");
            Check(source.Scene.Players.Single().SharedLocationText == "Shared place",
                "the main fleet self row keeps the privacy-projected value, never local Game.log detail");
            var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default with { HideSelfMember = false },
                OverlayRosterSelectionSettings.Default, language, true, source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            try
            {
                Check(model.SquadsTitle == overview, $"overview title {language}: {model.SquadsTitle}");
                Check(model.MembersTitle == members, $"members title {language}: {model.MembersTitle}");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine("PASS main fleet reads as an organization with a shared-only self row");
    }

    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
