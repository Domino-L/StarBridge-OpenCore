using System.Collections.Concurrent;
using System.Diagnostics;
using System.Windows;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Privacy;

namespace StarBridge.Desktop.Tests;

// Real HWND / DirectComposition / model, entirely outside desktop bounds. All
// data is synthetic, no account files, network, hotkeys or game focus changes.
internal static class OverlayModuleLifecycleTests
{
    internal static async Task Run()
    {
        var fixture = new Sources();
        var legacyReads = 0;
        var observations = new ConcurrentQueue<(OverlayModulePresentation Frame, OverlayModuleWindowObservation Window)>();
        var deadlines = new ConcurrentQueue<(DateTimeOffset Deadline, DateTimeOffset ScheduledAt)>();
        using var runtime = new NativeInformationOverlayRuntime(
            roomProvider: () => { Interlocked.Increment(ref legacyReads); return null; },
            communityProvider: () => { Interlocked.Increment(ref legacyReads); return null; },
            moduleProvider: fixture.Read);
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        runtime.ModulesPresented = (frame, window) => observations.Enqueue((frame, window));
        runtime.ModuleValidationScheduled = deadline => deadlines.Enqueue((deadline, DateTimeOffset.UtcNow));
        var workspace = new InformationOverlayRuntimeWorkspace(1, InformationOverlayDefaults.DefaultSettings with
        {
            ShowNotice = true, ShowChat = true, ShowMembers = true, ShowSquads = true,
            ShowEventNotifications = true, ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage,
            AnimationFrameRate = OverlayAnimationFrameRate.Off,
            EnableStartupTransition = false,
            AutoFocusGameWindowOnOpen = false, AutoOpenOverlayOnGameStart = false,
            AutoOpenOverlayOnGameForeground = false, AutoCloseOverlayOnGameBackground = false
        }, InformationOverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload).ToArray(),
            "Alt+O", false, GameLogSessionSnapshot.Empty, "en", fixture.Policy);
        var result = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace);
        Check(result is { IsVisible: true, WindowState: "open", FailureCode: null }, "Module data opens the real window without legacy preparation.");
        Check(runtime.ModuleDemand is { } demand && ReferenceEquals(demand.Sources, fixture.Policy) && demand.ActiveModules.Count == 5,
            "Actual HWND publishes immutable visible module intent independently of its data leases.");
        var first = await WaitFor(observations, item => item.Window.Notice == "Notice fixture");
        Check(first.Window.OverviewTitle == "ORGANIZATION OVERVIEW" && first.Window.MembersTitle == "PARTY MEMBERS" &&
            first.Window.Members.Any(member => member.Contains("Room member")) && first.Window.Chat.Count == 0,
            "First HWND model uses mixed sources and does not replay chat history.");
        Check(legacyReads == 0, "Mixed mode must never read or demand the legacy source.");
        Check(first.Window.SourceLabels.Members == "Current room" && first.Window.SourceLabels.Events == "Current room" &&
            first.Window.SourceLabels.Overview is null,
            "Real HWND consumes independent module labels without changing the semantic skin titles.");

        var activity = new SharedActivityNotice("Room member", new("module-event", "PlayerDied", DateTimeOffset.UtcNow), () => true)
            { SourceKey = "Room:room", PublisherKey = "member-key" };
        Check(!await runtime.TryPresentActivityAsync(activity with { SourceKey = "Community:org" }, CancellationToken.None),
            "A notification from another authorized module source must not enter the events module.");
        Check(await runtime.TryPresentActivityAsync(activity, CancellationToken.None),
            "The events module accepts a live notification from its own source.");
        Check(legacyReads == 0, "Mixed-source events must not read or demand the legacy source for self-echo detection.");

        // Let the periodic invalidation check run. New immutable snapshots with
        // identical data and renewed leases do not trigger a render/model reset.
        await Task.Delay(1600);
        Check(observations.IsEmpty, "Equivalent payloads are not republished every timer tick.");
        fixture.AddMessage();
        runtime.RequestContentRefresh();
        var updated = await WaitFor(observations, item => item.Window.Chat.Any(text => text.Contains("Live fixture")));
        Check(updated.Window.Notice == "Notice fixture" && updated.Window.ChatPulse > first.Window.ChatPulse,
            "A real window update shows the new barrage without resetting the notice.");

        // Change modes on the already-open HWND, as in the reported acceptance
        // case. A settings sync must not require close/reopen or another message.
        for (var switchIndex = 0; switchIndex < 3; switchIndex++)
        {
            workspace = workspace with { Settings = workspace.Settings with { ChatDisplayMode = OverlayChatDisplayMode.MessageList } };
            await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
            var list = await WaitFor(observations, item => item.Window.Chat.Any(text => text.Contains("Live fixture")));
            Check(list.Window.Visibility.ShowChat, "Switching to message list restores its actual native module immediately.");
            workspace = workspace with { Settings = workspace.Settings with { ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage } };
            await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
            await WaitFor(observations, item => item.Window.Chat.Count == 0);
        }
        workspace = workspace with { Settings = workspace.Settings with { ChatDisplayMode = OverlayChatDisplayMode.MessageList } };
        await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
        await WaitFor(observations, item => item.Window.Chat.Any(text => text.Contains("Live fixture")));
        fixture.AddMessage(3, "Message-list delta fixture");
        runtime.RequestContentRefresh();
        var listDelta = await WaitFor(observations, item => item.Window.Chat.Any(text => text.Contains("Message-list delta fixture")));
        Check(listDelta.Window.Visibility.ShowChat && listDelta.Window.Chat.Any(text => text.Contains("Live fixture")),
            "A new message appears in the open message list without erasing the previous message.");

        // A passing expiry assertion must come from the deadline timer, not the
        // 750 ms game-window poll or a subsequent explicit refresh.
        await runtime.PausePeriodicRefreshForTestAsync();
        var realtimeDeadline = fixture.ExpireRealtimeSoon();
        runtime.RequestContentRefresh();
        await RequireScheduledBeforeExpiry(deadlines, realtimeDeadline);
        var stale = await WaitFor(observations, item => item.Window.OverviewPrimary == "Realtime status unknown");
        Check(stale.Frame.Overview.Available && stale.Window.Notice == "Notice fixture",
            "Realtime expiry updates the actual HWND without discarding authorized identity or announcement data.");
        var roomDeadline = fixture.ExpireRoomSoon();
        runtime.RequestContentRefresh();
        await RequireScheduledBeforeExpiry(deadlines, roomDeadline);
        var expired = await WaitFor(observations, item => !item.Frame.Members.Available);
        Check(expired.Window.Members.SequenceEqual(["No visible members"]) && expired.Window.Notice == "Notice fixture" && expired.Frame.Overview.Available,
            "A room lease expiring without another input clears only its modules.");
        Check(expired.Window.EmptyStates.Members == "Room information unavailable" && expired.Window.EmptyStates.Events == "Room information unavailable" &&
            expired.Window.Visibility.ShowMembers && expired.Window.Visibility.ShowEventNotifications,
            "Actual HWND retains fixed member/event empty panels after the lease expires.");
        var communicationDeadline = fixture.ExpireCommunicationSoon();
        runtime.RequestContentRefresh();
        await RequireScheduledBeforeExpiry(deadlines, communicationDeadline);
        var communicationExpired = await WaitFor(observations, item => !item.Frame.Notice.Available && item.Frame.Overview.Available);
        Check(communicationExpired.Window.Notice.Length == 0 && communicationExpired.Window.Chat.Count == 0,
            "Communication expires on its own deadline while the authorized organization overview remains.");
        Check(communicationExpired.Window.Visibility.ShowNotice && communicationExpired.Window.Visibility.ShowChat &&
            communicationExpired.Window.EmptyStates.Notice == "Organization unavailable" && communicationExpired.Window.EmptyStates.Chat == "Organization unavailable",
            "Actual HWND keeps notice and barrage source failure visible without fake messages or countdowns.");
        fixture.DenyOrganization();
        runtime.RequestContentRefresh();
        var revoked = await WaitFor(observations, item => !item.Frame.Overview.Available);
        Check(revoked.Window.Notice.Length == 0 && revoked.Window.Chat.Count == 0,
            "Revocation clears the actual window's communication and pending barrage.");

        fixture.FailRead("overlay.sources_limit_exceeded");
        runtime.RequestContentRefresh();
        await WaitFor(observations, item => item.Frame.ScopeKey == "unavailable");
        var failedContent = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace);
        Check(failedContent.IsVisible && failedContent.FailureCode == "overlay.sources_limit_exceeded" && !failedContent.Retryable,
            "Content failure is reported, without showing unrelated legacy data or closing the layout.");
        fixture.ChangeAccount();
        runtime.RequestContentRefresh();
        var recovered = await WaitFor(observations, item => item.Window.Notice == "New account notice");
        Check(!recovered.Window.Chat.Any(text => text.Contains("Live fixture")) && recovered.Frame.ScopeKey != first.Frame.ScopeKey,
            "Account change recovers only the new scope, without old conversation content.");
        Check(recovered.Window.EmptyStates.Notice is null && recovered.Window.EmptyStates.Chat is null,
            "New authorized content removes old empty-state warnings.");
        Check(legacyReads == 0, "No error or recovery path falls back to the legacy provider.");
        var invalidWorkspace = workspace with { Sources = null, SourcePresetsEnabled = true };
        var closed = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, invalidWorkspace);
        Check(!closed.IsVisible, "Closing releases the native module window.");
        Check(runtime.ModuleDemand is { Sources: null }, "Damaged v2 retains its mode instead of advertising legacy demand.");
        Check(legacyReads == 0, "Closing an invalid v2 workspace must not briefly refresh the visible window with legacy data.");
        var reopen = await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, invalidWorkspace);
        Check(!reopen.IsVisible && reopen.FailureCode == "overlay.workspace_invalid_preset" && !reopen.Retryable && legacyReads == 0,
            "All native reopen paths reject the invalid v2 workspace instead of silently choosing legacy data.");
        var count = observations.Count;
        fixture.AddMessage();
        runtime.RequestContentRefresh();
        await Task.Delay(900);
        Check(observations.Count == count, "Closed runtime neither publishes content nor runs a pending expiry refresh.");
        await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Close, workspace with { Sources = null, SourcePresetsEnabled = false });
        Check(runtime.ModuleDemand is null && !runtime.IsVisible, "Explicit v1 workspace restores the legacy contract without opening a window.");
        Console.WriteLine("PASS real offscreen module HWND: first frame, delta updates, timed expiry, revoke, failure, account recovery and close");
    }

    private sealed class Sources
    {
        private readonly object _sync = new();
        private string _owner = "fixture-owner";
        private long _generation = 1;
        private bool _organizationAuthorized = true;
        private DateTimeOffset _roomUntil = DateTimeOffset.UtcNow.AddMinutes(1);
        private DateTimeOffset _communicationUntil = DateTimeOffset.UtcNow.AddMinutes(1);
        private DateTimeOffset _realtimeUntil = DateTimeOffset.UtcNow.AddMinutes(1);
        private string? _failure;
        private object _authority = new();
        private readonly Guid _roomContinuity = Guid.NewGuid();
        private InformationOverlayCommunityContent _organization = new("org", "Organization fixture",
            [new("Organization member", "OrganizationFixture", "Member", "InGame", "Ship", "Location", "US", false)])
        {
            AnnouncementTitle = "Notice", AnnouncementText = "Notice fixture",
            Messages = [new(1, "Member", "Fixture", "History fixture", DateTimeOffset.UtcNow, false)]
        };
        internal OverlayPresetSources Policy { get; } = new(OverlaySourceBinding.Follow, modules:
            new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Members] = new(OverlaySourceMode.Room), [OverlaySourceModule.Events] = new(OverlaySourceMode.Room) });
        internal void AddMessage() { lock (_sync) _organization = _organization with
            { Messages = [.. _organization.Messages, new(2, "Member", "Fixture", "Live fixture", DateTimeOffset.UtcNow, false)] }; }
        internal void AddMessage(long sequence, string text) { lock (_sync) _organization = _organization with
            { Messages = [.. _organization.Messages, new(sequence, "Member", "Fixture", text, DateTimeOffset.UtcNow, false)] }; }
        internal DateTimeOffset ExpireRoomSoon() { lock (_sync) return _roomUntil = DateTimeOffset.UtcNow.AddSeconds(1); }
        internal DateTimeOffset ExpireCommunicationSoon() { lock (_sync) return _communicationUntil = DateTimeOffset.UtcNow.AddSeconds(1); }
        internal DateTimeOffset ExpireRealtimeSoon() { lock (_sync) return _realtimeUntil = DateTimeOffset.UtcNow.AddSeconds(1); }
        internal void DenyOrganization() { lock (_sync) _organizationAuthorized = false; }
        internal void FailRead(string failure) { lock (_sync) _failure = failure; }
        internal void ChangeAccount()
        {
            lock (_sync)
            {
                _owner = "another-fixture"; _generation++; _authority = new();
                _organizationAuthorized = true; _failure = null;
                _communicationUntil = DateTimeOffset.UtcNow.AddSeconds(40);
                _organization = _organization with { ContinuityId = Guid.NewGuid(), AnnouncementText = "New account notice", Messages = [] };
            }
        }
        internal InformationOverlayModuleReadResult Read(InformationOverlayRuntimeWorkspace workspace)
        {
            lock (_sync)
            {
                if (_failure is not null) return new(null, _failure);
                var owner = _owner; var generation = _generation;
                var now = DateTimeOffset.UtcNow;
                var orgLease = new OverlaySourceLease(OverlaySourceMode.Community, "org", owner, generation, now.AddSeconds(40));
                var roomLease = new OverlaySourceLease(OverlaySourceMode.Room, "room", owner, generation, _roomUntil);
                var context = new OverlaySourceResolutionContext(owner, generation, now,
                    new(OverlaySourceMode.Community, "org", owner), roomLease, "org",
                    new Dictionary<string, OverlaySourceLease> { ["org"] = orgLease });
                InformationOverlaySourceSnapshot? Source(OverlayResolvedSource source)
                {
                    lock (_sync)
                    {
                        if (_owner != owner || _generation != generation) return null;
                        if (source.Mode == OverlaySourceMode.Room)
                            return new(roomLease, roomLease.ValidUntil, room: new("room", "Room fixture", "", 6, "",
                                [new("Room member", "RoomFixture", true, "AppOnline", "", "", "")], [])
                                { ContinuityId = _roomContinuity }, authorityStamp: _authority);
                        return _organizationAuthorized ? new(orgLease, _communicationUntil, community: _organization,
                            authorityStamp: _authority, realtimeValidUntil: _realtimeUntil) : null;
                    }
                }
                bool Current() { lock (_sync) return _owner == owner && _generation == generation; }
                bool Authorized(InformationOverlaySourceSnapshot snapshot)
                { lock (_sync) return Current() && ReferenceEquals(snapshot.AuthorityStamp, _authority) &&
                    (snapshot.Room is null ? _organizationAuthorized : DateTimeOffset.UtcNow < _roomUntil); }
                return InformationOverlayModuleFrame.TryCapture(workspace.Sources!, context, Source, Current, Authorized,
                    activeModules: OverlayModuleSourceResolver.VisibleModules(workspace.Settings));
            }
        }
    }

    private static async Task RequireScheduledBeforeExpiry(
        ConcurrentQueue<(DateTimeOffset Deadline, DateTimeOffset ScheduledAt)> queue, DateTimeOffset expected)
    {
        var watch = Stopwatch.StartNew();
        while (watch.Elapsed < TimeSpan.FromSeconds(5))
        {
            while (queue.TryDequeue(out var item))
                if (item.Deadline == expected)
                {
                    Check(item.ScheduledAt < expected, "The explicit refresh must arm the deadline before expiration, not perform the expiration itself.");
                    return;
                }
            await Task.Delay(10);
        }
        throw new InvalidOperationException("The intended expiry was not scheduled before expiration.");
    }

    private static async Task<(OverlayModulePresentation Frame, OverlayModuleWindowObservation Window)> WaitFor(
        ConcurrentQueue<(OverlayModulePresentation Frame, OverlayModuleWindowObservation Window)> queue,
        Func<(OverlayModulePresentation Frame, OverlayModuleWindowObservation Window), bool> predicate)
    {
        var watch = Stopwatch.StartNew();
        while (watch.Elapsed < TimeSpan.FromSeconds(5))
        {
            while (queue.TryDequeue(out var item)) if (predicate(item)) return item;
            await Task.Delay(10);
        }
        throw new InvalidOperationException("Expected real window state did not arrive.");
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
