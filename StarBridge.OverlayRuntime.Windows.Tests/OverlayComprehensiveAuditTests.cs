using System.Reflection;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class OverlayComprehensiveAuditTests
{
    internal static void RunAll()
    {
        var failures = new List<string>();
        foreach (var test in new Action[] { PinnedCardsStillObserveValidity, InvalidPendingCardsDoNotRemainBehindPins, EventBurstIsBounded, LegacySettingsCannotBreakRendering, ChatBurstIsBounded, SelfRegionSurvivesMissingShard, ClosingWindowStopsModelTimers, NativeRefreshSignalsCoalesce })
        {
            try { test(); Console.WriteLine("PASS full overlay audit " + test.Method.Name); }
            catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        }
        if (failures.Count != 0) throw new InvalidOperationException(string.Join(Environment.NewLine, failures));
    }

    private static OverlayViewModel Model() => new(new([]), OverlayDisplaySettings.Default with
    {
        AnimationFrameRate = OverlayAnimationFrameRate.Off, EventNotificationMaxVisibleCount = 1,
        EventNotificationPinImportant = true
    }, OverlayRosterSelectionSettings.Default, "en", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");

    private static void PinnedCardsStillObserveValidity()
    {
        var model = Model();
        try
        {
            model.EventNotifications.Clear();
            var valid = true;
            model.QueueGameEventNotification(OverlayEventNotificationTypes.DeathAndRespawn, "pinned", "fixture", true, false, () => valid);
            Check(model.EventNotifications.Single().ExpiresAt == DateTimeOffset.MaxValue, "fixture is pinned");
            var timer = (DispatcherTimer)typeof(OverlayViewModel).GetField("_eventNotificationTimer", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(model)!;
            Check(timer.IsEnabled, "a pinned card with a validity callback must keep observing expiry/account withdrawal when animation is off");
            valid = false;
            Tick(model, DateTimeOffset.Now);
            Check(model.EventNotifications.Count == 0 && !timer.IsEnabled, "withdrawn pin is cleared and idle timer stops");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void InvalidPendingCardsDoNotRemainBehindPins()
    {
        var model = Model();
        try
        {
            model.EventNotifications.Clear();
            model.QueueGameEventNotification(OverlayEventNotificationTypes.DeathAndRespawn, "pin", "fixture", true, false);
            var valid = true;
            model.QueueGameEventNotification(OverlayEventNotificationTypes.MemberServer, "queued", "fixture", false, false, () => valid);
            Check(model.PendingEventNotificationCount == 1, "fixture has a blocked live event");
            valid = false;
            Tick(model, DateTimeOffset.Now);
            Check(model.PendingEventNotificationCount == 0 && model.EventNotifications.Single().Title == "pin",
                "expired/withdrawn queued notices must be reaped even while pinned visible cards never leave");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void EventBurstIsBounded()
    {
        var model = Model();
        try
        {
            model.EventNotifications.Clear();
            model.QueueGameEventNotification(OverlayEventNotificationTypes.DeathAndRespawn, "pin", "fixture", true, false);
            model.QueueGameEventNotification(OverlayEventNotificationTypes.DeathAndRespawn, "important waiting", "fixture", true, false);
            for (var i = 0; i < 2000; i++)
                model.QueueGameEventNotification(OverlayEventNotificationTypes.ShipChange, "event " + i, "fixture", false, false);
            Check(model.PendingEventNotificationCount <= 128, "a sustained burst behind pinned cards must have a bounded pending queue");
            var pending = (System.Collections.IEnumerable)typeof(OverlayViewModel).GetField("_pendingEventNotifications", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(model)!;
            Check(pending.Cast<object>().Any(row => (string?)row.GetType().GetProperty("Title")!.GetValue(row) == "important waiting"),
                "ordinary overflow preserves an already queued important event");
            Tick(model, DateTimeOffset.Now.AddMinutes(3));
            Check(model.PendingEventNotificationCount == 0 && model.EventNotifications.Count == 1,
                "old pending state transitions must expire without evicting a valid pin");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void LegacySettingsCannotBreakRendering()
    {
        var parts = OverlayDisplaySettings.Default.Serialize().Split(',');
        parts[33] = "NaN";
        OverlayViewModel? model = null;
        try
        {
            var settings = OverlayDisplaySettings.Parse(string.Join(',', parts));
            model = new(new([]), settings, OverlayRosterSelectionSettings.Default, "en", false,
                new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
            Check(double.IsFinite(model.MemberNameColumnWidth.Value), "legacy settings reach valid native member columns");
        }
        finally { model?.ClearAuthorizedContent(); }
    }

    private static void ChatBurstIsBounded()
    {
        var settings = OverlayDisplaySettings.Default with { ShowChat = true, ChatDisplayMode = OverlayChatDisplayMode.FullScreenBarrage, AnimationFrameRate = OverlayAnimationFrameRate.Off };
        var context = new OverlaySceneContext(OverlayScenePreference.PartyRoom, OverlaySceneKind.PartyRoom, "Room", false, RoomId: "fixture", ChatChannelId: "fixture");
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
            new("", "", null, null, null, null), PlayerPresenceKind.InGame, "", context);
        try
        {
            var now = DateTimeOffset.Now;
            // The sender's timestamp is deliberately ahead: backlog freshness
            // must use local reception time rather than the peer's clock.
            var messages = Enumerable.Range(1, 2000).Select(i => new OverlayChatMessage(i, "fixture", "Peer", "Peer", "message " + i, now.AddDays(1), false, false, "#FFFFFF")).ToArray();
            model.Refresh(new([]), settings, OverlayRosterSelectionSettings.Default, "en", true,
                new("", "", null, null, null, null), PlayerPresenceKind.InGame, "", context, messages);
            var pending = (System.Collections.ICollection)typeof(OverlayViewModel).GetField("_pendingChatMessages", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(model)!;
            Check(pending.Count <= 128, "live barrage bursts must not accumulate an unbounded backlog");
            typeof(OverlayViewModel).GetMethod("TickChatMessages", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(model, [now.AddMinutes(3)]);
            Check(pending.Count == 0 && model.ChatMessages.Count == 0, "expired chat backlog must not replay stale conversations");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void SelfRegionSurvivesMissingShard()
    {
        foreach (var room in new[] { true, false })
        {
            var roomContent = new InformationOverlayRoomContent("fixture", "Room", "", 4, "Self", [new("Self", "Self", true, "InGame", "", "", "US") { IsSelf = true }], []);
            var orgContent = new InformationOverlayCommunityContent("fixture", "Community", [new("Self", "Self", "Member", "InGame", "", "", "US", true)]);
            var source = NativeInformationOverlayRuntime.ProjectSource(room ? roomContent : null, room ? null : orgContent, OverlayScenePreference.Auto, "zh");
            var model = new OverlayViewModel(new(source.Scene.Players), OverlayDisplaySettings.Default, OverlayRosterSelectionSettings.Default,
                "zh", true, source.Command, PlayerPresenceKind.InGame, "", source.Scene.Context);
            try { Check(model.SquadStatusServerSummary == "美服 · 1 人", "authorized self region still counts when the local shard is not yet known: " + room); }
            finally { model.ClearAuthorizedContent(); }
        }
    }

    private static void ClosingWindowStopsModelTimers()
    {
        var model = Model();
        var timers = new[] { "_timer", "_rosterRotationTimer", "_eventNotificationTimer" }.Select(name =>
            (DispatcherTimer)typeof(OverlayViewModel).GetField(name, BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(model)!).ToArray();
        // Exercise the real owner's Dispose without creating an HWND/render thread.
        var window = (OverlayCompositionHudWindow)System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(OverlayCompositionHudWindow));
        typeof(OverlayCompositionHudWindow).GetField("_disposeLock", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, new object());
        typeof(OverlayCompositionHudWindow).GetField("_viewModel", BindingFlags.Instance | BindingFlags.NonPublic)!.SetValue(window, model);
        try
        {
            model.QueueGameEventNotification(OverlayEventNotificationTypes.DeathAndRespawn, "pin", "fixture", true, false, () => true);
            foreach (var timer in timers) timer.Start();
            window.Dispose();
            Check(timers.All(timer => !timer.IsEnabled), "closing the native owner must stop every model timer instead of retaining hidden windows and event callbacks");
            Check(model.EventNotifications.Count == 0 && model.ChatMessages.Count == 0 && model.PendingEventNotificationCount == 0, "closed window releases live content");
        }
        finally { foreach (var timer in timers) timer.Stop(); model.ClearAuthorizedContent(); }
    }

    private static void NativeRefreshSignalsCoalesce()
    {
        var runtime = (NativeInformationOverlayRuntime)System.Runtime.CompilerServices.RuntimeHelpers.GetUninitializedObject(typeof(NativeInformationOverlayRuntime));
        var type = typeof(NativeInformationOverlayRuntime);
        var flags = BindingFlags.Instance | BindingFlags.NonPublic;
        type.GetField("_dispatcher", flags)!.SetValue(runtime, Dispatcher.CurrentDispatcher);
        type.GetField("_snapshot", flags)!.SetValue(runtime, InformationOverlayRuntimeSnapshot.Unavailable with { IsVisible = true });
        for (var i = 0; i < 2000; i++) runtime.RequestContentRefresh();
        Check((int)type.GetField("_contentRefreshQueued", flags)!.GetValue(runtime)! == 1, "a burst schedules only one native content refresh");
        var frame = new DispatcherFrame();
        Dispatcher.CurrentDispatcher.BeginInvoke(() => frame.Continue = false, DispatcherPriority.Background);
        Dispatcher.PushFrame(frame);
        Check((int)type.GetField("_contentRefreshQueued", flags)!.GetValue(runtime)! == 0, "the scheduled refresh drains without creating an HWND");
        type.GetField("_snapshot", flags)!.SetValue(runtime, InformationOverlayRuntimeSnapshot.Unavailable);
        runtime.RequestContentRefresh();
        Check((int)type.GetField("_contentRefreshQueued", flags)!.GetValue(runtime)! == 0, "closed overlays do not schedule live refresh work");
    }

    private static void Tick(OverlayViewModel model, DateTimeOffset now) =>
        typeof(OverlayViewModel).GetMethod("TickEventNotifications", BindingFlags.Instance | BindingFlags.NonPublic)!.Invoke(model, [now]);
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
