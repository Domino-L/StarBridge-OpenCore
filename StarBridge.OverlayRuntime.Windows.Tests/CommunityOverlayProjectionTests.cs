// Same regression runs against both the internal client and the independent renderer.
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class CommunityOverlayProjectionTests
{
    internal static void RunAll()
    {
        SelfRemainsVisibleWhenSharedPresenceIsOffline();
        var organization = new InformationOverlayCommunityContent("synthetic-org", "Organization name",
            [new("Case_Handle", "Display", "Officer", "AppOnline", "", "", "", false)]);
        var room = new InformationOverlayRoomContent("room", "Room", "Goal", 4, "",
            [], [new(1, "Room sender", "Other_Handle", "Room-only chat", DateTimeOffset.UtcNow, false)]);
        var projected = NativeInformationOverlayRuntime.ProjectSource(null, organization, OverlayScenePreference.Auto, "en");
        Check(projected.Scene.HasContent && projected.Scene.Context.Kind == OverlaySceneKind.Community,
            "Automatic native source reaches real organization members when no room/main fleet exists.");
        var player = projected.Scene.Players.Single();
        Check(player.Name == "Case_Handle" && player.Role == "Officer" && !player.IsSelf,
            "Roster projection preserves authoritative identity, role and self flag.");
        Check(player.SharedEventTypes == 0 && !player.ShowMemberActions,
            "Displaying members does not grant event sharing or management actions.");
        Check(projected.Chat.Length == 0 && projected.Scene.Context.ChatChannelId is null,
            "Organization does not receive room chat or historical messages.");
        Check(NativeInformationOverlayRuntime.ProjectSource(room, organization, OverlayScenePreference.Auto, "en")
            .Scene.Context.Kind == OverlaySceneKind.PartyRoom, "Current room retains automatic priority.");
        Check(NativeInformationOverlayRuntime.ProjectSource(room, organization, OverlayScenePreference.Auto, "en", true)
            .Scene.Context.Kind == OverlaySceneKind.Community, "Explicit organization overrides automatic room priority.");
        Check(!NativeInformationOverlayRuntime.ProjectSource(room, null, OverlayScenePreference.Auto, "en", true)
            .Scene.HasContent, "Unavailable explicit organization never displays room data.");
        Check(!NativeInformationOverlayRuntime.ProjectSource(null, organization, OverlayScenePreference.Fleet, "en")
            .Scene.HasContent, "First-wave main fleet remains disabled and is not relabeled organization data.");
        Check(!NativeInformationOverlayRuntime.ProjectSource(null, organization, OverlayScenePreference.PartyRoom, "en")
            .Scene.HasContent, "Unavailable explicit room does not silently switch to an organization.");
        var settings = OverlayDisplaySettings.Default with { HideSelfMember = false };
        var model = new OverlayViewModel(new OverlayAuthorizedRoster(projected.Scene.Players), settings,
            OverlayRosterSelectionSettings.Default, "en", true, projected.Command,
            PlayerPresenceKind.AppOnline, "", projected.Scene.Context, projected.Chat);
        Check(model.SquadsTitle == "ORGANIZATION OVERVIEW" && model.MembersTitle == "ORGANIZATION MEMBERS",
            "Actual renderer labels organization content without enabling main fleet.");
        var overview = OverlayOverviewProjection.Project(projected.Scene.Players.ToArray(),
            projected.Scene.Context, true, PlayerPresenceKind.AppOnline, "", "en");
        Check(overview.Title == "ORGANIZATION OVERVIEW", "Overview uses organization label too.");
        model.ClearAuthorizedContent();
        Check(model.Members.Count == 0 && model.ChatMessages.Count == 0,
            "Revocation clears the actual renderer's authorized content.");
    }

    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }

    private static void SelfRemainsVisibleWhenSharedPresenceIsOffline()
    {
        var organization = new InformationOverlayCommunityContent("fixture", "Fixture",
            [new("Self_Handle", "Self", "Member", "Offline", "", "", "", true),
             new("Other_Handle", "Other", "Member", "Offline", "", "", "", false)]);
        var projected = NativeInformationOverlayRuntime.ProjectSource(null, organization, OverlayScenePreference.Auto, "en");
        foreach (var hideStatus in new[] { false, true })
        {
            var settings = OverlayDisplaySettings.Default with { HideSelfMember = false, HideMemberOnlineStatus = hideStatus };
            var model = new OverlayViewModel(new OverlayAuthorizedRoster(projected.Scene.Players), settings,
                OverlayRosterSelectionSettings.Default, "en", true, projected.Command,
                PlayerPresenceKind.AppOnline, "", projected.Scene.Context, projected.Chat);
            model.ApplyMemberViewport(180);
            Check(model.Members.Any(row => row.DisplayName.Contains("Self_Handle")),
                "Authorized self stays visible locally even when shared presence is offline; hiding status must not hide the member.");
            Check(!model.Members.Any(row => row.DisplayName.Contains("Other_Handle")), "Offline peers still follow the roster filter.");
            Check(projected.Scene.Players.Single(row => row.IsSelf).SharedPresence == PlayerPresenceKind.Offline,
                "Local display must not rewrite outbound privacy state.");
            model.Refresh(new OverlayAuthorizedRoster(projected.Scene.Players), settings with { HideSelfMember = true },
                OverlayRosterSelectionSettings.Default, "en", true, projected.Command,
                PlayerPresenceKind.AppOnline, "", projected.Scene.Context, projected.Chat);
            Check(!model.Members.Any(row => row.DisplayName.Contains("Self_Handle")), "Explicit hide-self still wins.");
            model.ClearAuthorizedContent();
        }
    }
}
