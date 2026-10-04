using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class OverlayModuleProjectionTests
{
    internal static void RunAll()
    {
        LiveUpdateDoesNotRebaseChat();
        MultiChatKeepsIndependentSequences();
        RealtimeExpiryRemainsUnknown();
        var now = DateTimeOffset.UtcNow;
        const string owner = "fixture-owner";
        var orgLease = new OverlaySourceLease(OverlaySourceMode.Community, "org", owner, 1, now.AddSeconds(40));
        var roomLease = new OverlaySourceLease(OverlaySourceMode.Room, "room", owner, 1, now.AddSeconds(30));
        var room = new InformationOverlayRoomContent("room", "Room fixture", "Goal", 6, "RoomHandle",
            [new("Room member", "RoomHandle", true, "InGame", "", "", "US") { PreferenceKey = "fixture-peer" }],
            [new(1, "Room member", "RoomHandle", "Room message", now, false)]);
        var community = new InformationOverlayCommunityContent("org", "Organization fixture",
            [new("OrgHandle", "Organization member", "Member", "AppOnline", "", "", "", false),
             new("OrgHandle2", "Other organization member", "Member", "AppOnline", "", "", "", false)])
        {
            AnnouncementTitle = "Organization notice", AnnouncementText = "Approved notice",
            Messages = [new(1, "Organization member", "OrgHandle", "Organization message", now, false)]
        };
        var roomSnapshot = new InformationOverlaySourceSnapshot(roomLease, roomLease.ValidUntil, room: room);
        var orgSnapshot = new InformationOverlaySourceSnapshot(orgLease, orgLease.ValidUntil, community: community);
        var policy = new OverlayPresetSources(new(OverlaySourceMode.Community, "org", owner), modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room), [OverlaySourceModule.Events] = new(OverlaySourceMode.Room) });
        var context = new OverlaySourceResolutionContext(owner, 1, now, OverlaySourceBinding.Automatic,
            roomLease, "org", new Dictionary<string, OverlaySourceLease> { ["org"] = orgLease });
        var current = true;
        var roomAuthorized = true;
        var orgAuthorized = true;
        var frame = InformationOverlayModuleFrame.Capture(policy, context,
            source => source.Mode == OverlaySourceMode.Room ? roomSnapshot : orgSnapshot, () => current,
            snapshot => snapshot.Room is null ? orgAuthorized : roomAuthorized);
        var projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
        Check(projection.Members.Scene.Context.Kind == OverlaySceneKind.PartyRoom && projection.Members.Scene.Players.Count == 1 &&
            projection.Overview.Scene.Context.Kind == OverlaySceneKind.Community && projection.Overview.Scene.Players.Count == 2,
            "Native projection keeps room roster and organization overview independent.");
        Check(projection.Chat.Chat.Single().Text == "Organization message" && projection.Notice.Command.NoticeText == "Approved notice" &&
            projection.Events.Scene.Context.Kind == OverlaySceneKind.PartyRoom,
            "Communication and event inputs carry their own source.");
        Check(projection.Members.SourceLabel == "Current room" && projection.Overview.SourceLabel is null,
            "Only overridden modules expose a source label.");
        Check(!NativeInformationOverlayRuntime.IsModuleSelfPublisher("fixture-peer", projection.Events.Scene.Players),
            "A matching local handle without explicit self proof cannot suppress a mixed-source peer event.");
        var activity = new StarBridge.HostRuntime.Privacy.SharedActivityNotice("Fixture",
            new("fixture-event", "PlayerDied", now), () => true) { SourceKey = "Community:org" };
        Check(!NativeInformationOverlayRuntime.ActivityMatchesModule(activity, projection.Events) &&
            NativeInformationOverlayRuntime.ActivityMatchesModule(activity with { SourceKey = "Room:room" }, projection.Events) &&
            !NativeInformationOverlayRuntime.ActivityMatchesModule(activity with { SourceKey = null }, projection.Events),
            "Mixed events reject the other module's source and unscoped legacy events.");
        var settings = OverlayDisplaySettings.Default with { ShowNotice = true, ShowChat = true,
            ChatDisplayMode = OverlayChatDisplayMode.MessageList, ShowEventNotifications = false,
            AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default,
            "en", false, projection.Notice.Command, PlayerPresenceKind.AppOnline, "");
        try
        {
            model.RefreshModules(projection, settings, OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
            Check(model.ModuleSourceLabels.Members == "Current room" && model.ModuleSourceLabels.Events == "Current room" &&
                model.ModuleSourceLabels.Overview is null && model.ModuleSourceLabels.Chat is null,
                "Native render headers carry only the independently overridden module labels.");
            Check(OverlayModuleSourceLabels.Prefix("Fixture event", model.ModuleSourceLabels.Events, false) == "[Current room] Fixture event" &&
                OverlayModuleSourceLabels.Prefix("Device event", model.ModuleSourceLabels.Events, true) == "Device event",
                "Barrage/toast source labels do not misattribute device-local events to a remote source.");
            Check(model.SquadsTitle == "ORGANIZATION OVERVIEW" && model.MembersTitle == "PARTY MEMBERS" && model.Members.Any(m => m.DisplayName.Contains("Room")) &&
                !model.Members.Any(m => m.DisplayName.Contains("Organization")), "Real native ViewModel no longer shares a single roster across modules.");
            Check(model.ChatMessages.Any(m => m.Detail.Contains("Organization message")) && model.FleetNotice == "Approved notice",
                "Real native chat and announcement use the organization, not room context.");
            roomAuthorized = false;
            projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
            model.RefreshModules(projection, settings, OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
            Check(!projection.Members.Available && projection.Members.Scene.Players.Count == 0 &&
                model.SquadsTitle == "ORGANIZATION OVERVIEW" && model.ChatMessages.Any(m => m.Detail.Contains("Organization message")) &&
                model.FleetNotice == "Approved notice", "Room withdrawal must not clear or replay the organization's notice/chat.");
            orgAuthorized = false;
            projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
            model.RefreshModules(projection, settings, OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
            Check(model.ChatMessages.Count == 0 && model.FleetNotice.Length == 0 && !projection.Overview.Available,
                "Organization withdrawal clears its visible communication immediately.");
            Check(model.NotificationVisibility == System.Windows.Visibility.Visible && model.ChatVisibility == System.Windows.Visibility.Visible,
                "Unavailable enabled modules keep their fixed empty-state panels visible, without queued content.");
            Check(model.ModuleEmptyStates.Notice == "Organization unavailable" && model.ModuleEmptyStates.Chat == "Organization unavailable" &&
                model.ModuleEmptyStates.Members == "Room information unavailable",
                "Empty states are specific to each source without exposing revoked names or old messages.");
            var hidden = InformationOverlayRuntimeProjection.ResolveVisibility(settings with { ShowNotice = false, ShowChat = false },
                new(true, true, true));
            Check(!hidden.ShowNotice && !hidden.ShowChat && !hidden.ShowEventNotifications,
                "An unavailable source never forces a user-disabled module on.");
            Check(OverlayModuleEmptyStates.Message(new(OverlaySourceMode.Room, null, false, "module_hidden"), "en") is null,
                "Inactive modules do not acquire unavailable-source messages.");
            current = false;
            projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
            Check(!projection.Notice.Available && !projection.Chat.Available && !projection.Members.Available,
                "Account change invalidates every projected module.");
        }
        finally { model.ClearAuthorizedContent(); }
        Check(model.ModuleSourceLabels == OverlayModuleSourceLabels.Empty, "Clearing authority removes source labels with the content.");
        Check(model.ModuleEmptyStates == OverlayModuleEmptyStates.Empty, "Clearing the window removes its presentation metadata as well.");
        Console.WriteLine("PASS mixed module projection and native ViewModel authorization isolation");
    }

    private static void RealtimeExpiryRemainsUnknown()
    {
        var now = DateTimeOffset.UtcNow;
        var lease = new OverlaySourceLease(OverlaySourceMode.Community, "org", "fixture", 1, now.AddSeconds(40));
        var snapshot = new InformationOverlaySourceSnapshot(lease, lease.ValidUntil,
            community: new("org", "Fixture", [new("Peer", "Peer", "Member", "InGame", "Ship", "Location", "US", false)]),
            clock: () => now, realtimeValidUntil: now.AddSeconds(30));
        var context = new OverlaySourceResolutionContext("fixture", 1, now, OverlaySourceBinding.Automatic, null,
            "org", new Dictionary<string, OverlaySourceLease> { ["org"] = lease });
        var frame = InformationOverlayModuleFrame.Capture(OverlayPresetSources.Default, context, _ => snapshot, () => true, _ => true);
        var projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
        Check(projection.NextValidationAt == now.AddSeconds(30), "Native deadline includes realtime freshness, not only the membership lease.");
        projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now.AddSeconds(30));
        var member = projection.Members.Scene.Players.Single();
        Check(projection.Members.Available && member.RealtimeStateUnknown && member.SharedShipDisplayText == "—" &&
            OverlayViewModel.LocalizeMemberLocation(member, "en") == "—",
            "Expired realtime fields are unknown, not offline or retained ship/location.");
        var overview = OverlayOverviewProjection.Project(projection.Overview.Scene.Players, projection.Overview.Scene.Context,
            true, PlayerPresenceKind.AppOnline, "", "en");
        Check(overview.Primary == "Realtime status unknown" && overview.Summary == "Members 1" && overview.TopLocations.Count == 0,
            "Stale realtime values never become an invented zero-online total or location grouping.");
        Check(projection.NextValidationAt == lease.ValidUntil, "After freshness expiry the native timer still schedules membership removal.");
        var room = new InformationOverlayRoomContent("room", "Fixture", "", 4, "SameHandle", [],
            [new(1, "Peer", "SameHandle", "Message", now, false)]);
        Check(!NativeInformationOverlayRuntime.ProjectRoom(room, OverlayScenePreference.PartyRoom, "en", explicitSelf: true).Chat.Single().IsSelf,
            "V2 room chat does not infer self from matching handles.");
    }

    private static void LiveUpdateDoesNotRebaseChat()
    {
        var now = DateTimeOffset.UtcNow;
        var lease = new OverlaySourceLease(OverlaySourceMode.Community, "org", "fixture", 1, now.AddSeconds(40));
        var authority = new object();
        var content = new InformationOverlayCommunityContent("org", "Fixture", [])
        { Messages = [new(1, "Member", "Member", "Old history", now, false)] };
        InformationOverlaySourceSnapshot Current() => new(lease, lease.ValidUntil, community: content, authorityStamp: authority);
        var context = new OverlaySourceResolutionContext("fixture", 1, now, OverlaySourceBinding.Automatic, null,
            "org", new Dictionary<string, OverlaySourceLease> { ["org"] = lease });
        var frame = InformationOverlayModuleFrame.Capture(OverlayPresetSources.Default, context, _ => Current(), () => true, _ => true);
        var settings = OverlayDisplaySettings.Default with { ShowChat = true, ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage,
            ShowEventNotifications = false, AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var first = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default, "en", false,
            first.Notice.Command, PlayerPresenceKind.AppOnline, "");
        try
        {
            model.RefreshModules(first, settings, OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
            Check(model.ChatMessages.Count == 0, "Initial history is not replayed as barrage.");
            content = content with { Messages = [.. content.Messages, new(2, "Member", "Member", "Live message", now, false)] };
            var next = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
            Check(next.Chat.Identity == first.Chat.Identity && next.Chat.Available, "Payload updates preserve source identity and availability.");
            model.RefreshModules(next, settings, OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
            Check(model.ChatMessages.Any(m => m.Detail.Contains("Live message")), "New payload neither flashes empty nor rebases away the new barrage message.");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void MultiChatKeepsIndependentSequences()
    {
        var now = DateTimeOffset.UtcNow;
        const string owner = "multi-fixture";
        var org = new OverlaySourceLease(OverlaySourceMode.Community, "org", owner, 1, now.AddSeconds(40));
        var room = new OverlaySourceLease(OverlaySourceMode.Room, "room", owner, 1, now.AddSeconds(40));
        long orgSequence = 100, roomSequence = 1;
        var orgContinuity = Guid.NewGuid();
        var roomContinuity = Guid.NewGuid();
        var orgAllowed = true;
        var accountAllowed = true;
        InformationOverlaySourceSnapshot Read(OverlayResolvedSource source) => source.Mode == OverlaySourceMode.Room
            ? new(room, room.ValidUntil, room: new("room", "Room fixture", "", 6, "", [],
                [new(roomSequence, "Peer", "peer", $"room-{roomSequence}", now, false)]) { ContinuityId = roomContinuity })
            : new(org, org.ValidUntil, community: new("org", "Organization fixture", [])
                { ContinuityId = orgContinuity, Messages = [new(orgSequence, "Peer", "peer", $"org-{orgSequence}", now, false)] });
        var policy = new OverlayPresetSources(new(OverlaySourceMode.Community, "org", owner),
            chatSources: [new(OverlaySourceMode.Room), new(OverlaySourceMode.Community, "org", owner)]);
        var context = new OverlaySourceResolutionContext(owner, 1, now, OverlaySourceBinding.Automatic, room, "org",
            new Dictionary<string, OverlaySourceLease> { ["org"] = org });
        var frame = InformationOverlayModuleFrame.Capture(policy, context, Read, () => accountAllowed,
            snapshot => snapshot.Lease.Mode == OverlaySourceMode.Room || orgAllowed);
        var settings = OverlayDisplaySettings.Default with { ShowChat = true, ChatShowSender = false,
            ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage, ShowEventNotifications = false,
            AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var initial = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default, "en", false,
            initial.Notice.Command, PlayerPresenceKind.AppOnline, "");
        void Refresh() => model.RefreshModules(NativeInformationOverlayRuntime.ProjectModules(frame, "en", now), settings,
            OverlayRosterSelectionSettings.Default, "en", PlayerPresenceKind.AppOnline, "");
        try
        {
            Refresh();
            Check(model.ChatMessages.Count == 0, "Multi-source barrage establishes separate silent history baselines.");
            roomSequence = 2;
            Refresh();
            Check(model.ChatMessages.Any(m => m.Detail.Contains("room-2")), "A lower room sequence is not swallowed by the organization's high watermark.");
            settings = settings with { ChatDisplayMode = OverlayChatDisplayMode.MessageList };
            roomSequence = orgSequence = 3;
            Refresh();
            Check(model.ChatMessages.Count == 2 && model.ChatMessages.Any(m => m.Detail.Contains("room-3")) &&
                model.ChatMessages.Any(m => m.Detail.Contains("org-3")), "Equal sequences from different sources are distinct messages.");
            var projection = NativeInformationOverlayRuntime.ProjectModules(frame, "en", now);
            Check(projection.Chat.Chat.All(m => m.SourceLabel?.Contains("fixture") == true) &&
                model.ChatMessages.All(m => m.Title.Contains("fixture")), "Source labels remain visible even when senders are hidden.");
            orgAllowed = false;
            Refresh();
            Check(model.ChatMessages.Count == 1 && model.ChatMessages[0].Detail.Contains("room-3"), "Partial revocation preserves only the still-authorized room.");
            settings = settings with { ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage };
            Refresh();
            orgAllowed = true;
            Refresh();
            Check(model.ChatMessages.Count == 0, "Readmission does not replay old organization history as live barrage.");
            accountAllowed = false;
            Refresh();
            Check(model.ChatMessages.Count == 0, "Account invalidation clears the whole aggregate.");
        }
        finally { model.ClearAuthorizedContent(); }
        Console.WriteLine("PASS multi-chat independent sequences, labels, mode switching and partial revocation");
    }

    private static void Check(bool value, string message)
    { if (!value) throw new InvalidOperationException(message); }
}
