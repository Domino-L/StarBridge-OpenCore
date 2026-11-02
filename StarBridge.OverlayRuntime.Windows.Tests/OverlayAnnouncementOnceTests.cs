namespace StarBridge.Desktop.Tests;

using System.Reflection;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;

// The top slot closes when the countdown ends, and an announcement shows once per app run
// for each account and channel. Reopening the overlay builds a new model every time. The
// model never records an announcement itself; the window confirms it after a committed frame.
internal static class OverlayAnnouncementOnceTests
{
    private const BindingFlags Instance = BindingFlags.Instance | BindingFlags.NonPublic;
    private static readonly OverlayDisplaySettings Settings = OverlayDisplaySettings.Default with
        { ShowNotice = true, EnableStartupTransition = false, CommunicationEventDurationSeconds = 5 };
    private static readonly OverlayCommandState Empty = new(null, null, null, null, null, null);

    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL announce once: " + name);
        Console.WriteLine("PASS announce once: " + name);
    }

    internal static void Run()
    {
        Countdown();
        var scene = Scene();
        Check(Shows(scene, "Drill on Saturday", "owner-a:1"), "a new announcement shows");
        Check(!Shows(scene, "Drill on Saturday", "owner-a:1"), "reopening does not show it again");
        Check(!Shows(scene, "Drill on Saturday", "owner-a:2"), "signing in again with the same account does not show it again");
        Check(Shows(scene, "Drill on Saturday", "owner-b:1"), "another account sees it once");
        Check(Shows(scene, "Drill moved to Sunday", "owner-a:2"), "a changed announcement shows");
        Check(Shows(scene with { ChatChannelId = scene.ChatChannelId + "-b" }, "Drill moved to Sunday", "owner-a:2"),
            "another organization's channel is separate");
        UnshownWindow();
        Queued();
        QueuedThenDisabled();
        BumpedByReminder();
        TwoModels();
        Capacity();
    }

    private static void Countdown()
    {
        using var window = new OverlayCompositionHudWindow(new([]), [], OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload),
            Settings, OverlayRosterSelectionSettings.Default, "en", true, Notice("Countdown fixture"), PlayerPresenceKind.AppOnline, "",
            new System.Windows.Rect(0, 0, 1920, 1080), OverlayStartupTransitionContext.ForLanguage("en"), Scene());
        var model = (OverlayViewModel)typeof(OverlayCompositionHudWindow).GetField("_viewModel", Instance)!.GetValue(window)!;
        Check(FrameShowsNotice(window), "countdown: the announcement shows");
        Tick(model, 5);
        Check(!FrameShowsNotice(window), "countdown: the slot closes when the countdown ends");
        model.ClearAuthorizedContent();
    }

    // A window that never drew a frame has not shown its announcement to anyone.
    private static void UnshownWindow()
    {
        var scene = Scene();
        using (var window = new OverlayCompositionHudWindow(new([]), [], OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload),
            Settings, OverlayRosterSelectionSettings.Default, "en", true, Empty, PlayerPresenceKind.AppOnline, "",
            new System.Windows.Rect(0, 0, 1920, 1080), OverlayStartupTransitionContext.ForLanguage("en"), scene))
        {
            var model = (OverlayViewModel)typeof(OverlayCompositionHudWindow).GetField("_viewModel", Instance)!.GetValue(window)!;
            Refresh(model, scene, "Never drawn", "owner-a:1");
            typeof(OverlayCompositionHudWindow).GetMethod("PublishStateToRenderer", Instance)!.Invoke(window, [false]);
            Check(model.NoticeItemActive && !window.FirstFrameCommitted, "unshown window: the announcement is in the slot, no frame drawn");
            model.ClearAuthorizedContent();
        }
        Check(Shows(scene, "Never drawn", "owner-a:1"), "unshown window: it shows when the overlay really opens");
    }

    // An announcement waiting behind a reminder is not shown yet: closing the overlay keeps it unseen.
    // The first module refresh resets the slot, so the modules are in place before the reminder.
    private static void Queued()
    {
        var scene = Scene();
        var model = New(scene);
        try
        {
            Refresh(model, scene, "", "owner-a:1");
            Check(model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster"), "queued: a reminder holds the slot");
            Refresh(model, scene, "Waiting announcement", "owner-a:1");
            Check(model.FleetNoticeTitle == "Room invite" && model.NoticeQueueCount == 1, "queued: the announcement waits");
        }
        finally { model.ClearAuthorizedContent(); }
        Check(Shows(scene, "Waiting announcement", "owner-a:1"), "queued: closed before it showed, it shows on reopen");

        scene = Scene();
        model = New(scene);
        try
        {
            Refresh(model, scene, "", "owner-a:1");
            model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster");
            Refresh(model, scene, "Promoted announcement", "owner-a:1");
            Tick(model, 5);
            Check(model.FleetNotice == "Promoted announcement", "queued: it reaches the slot after the reminder");
            ConfirmOnScreen(model);
        }
        finally { model.ClearAuthorizedContent(); }
        Check(!Shows(scene, "Promoted announcement", "owner-a:1"), "queued: once shown, reopening does not show it again");
    }

    // Turning notices off drops the queue; an announcement dropped before it showed comes back.
    private static void QueuedThenDisabled()
    {
        var scene = Scene();
        var model = New(scene);
        try
        {
            Refresh(model, scene, "", "owner-a:1");
            model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster");
            Refresh(model, scene, "Dropped announcement", "owner-a:1");
            Refresh(model, scene, "Dropped announcement", "owner-a:1", Settings with { ShowNotice = false });
            Refresh(model, scene, "Dropped announcement", "owner-a:1");
            Check(model.FleetNotice == "Dropped announcement" || model.NoticeQueueCount == 1,
                "notices off then on: an announcement that never showed comes back");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    // A reminder bumps the announcement and gives the slot back afterwards.
    private static void BumpedByReminder()
    {
        foreach (var confirmedFirst in new[] { false, true })
        {
            var scene = Scene();
            var model = New(scene);
            var name = confirmedFirst ? "bumped after it showed" : "bumped before it reached the screen";
            try
            {
                Refresh(model, scene, "", "owner-a:1");
                Refresh(model, scene, "Bumped announcement", "owner-a:1");
                if (confirmedFirst) ConfirmOnScreen(model);
                model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster");
                Tick(model, 5);
                Check(model.FleetNotice == "Bumped announcement", name + ": it comes back after the reminder");
                ConfirmOnScreen(model);
            }
            finally { model.ClearAuthorizedContent(); }
            Check(!Shows(scene, "Bumped announcement", "owner-a:1"), name + ": reopening does not show it again");
        }
    }

    private static void TwoModels()
    {
        var scene = Scene();
        var first = New(scene);
        var second = New(scene);
        try
        {
            Refresh(first, scene, "Shared announcement", "owner-a:1");
            ConfirmOnScreen(first);
            Refresh(second, scene, "Shared announcement", "owner-a:1");
            Check(first.NoticeItemActive && !second.NoticeItemActive, "two models: only the first shows it");
        }
        finally { first.ClearAuthorizedContent(); second.ClearAuthorizedContent(); }

        // Both wait behind a reminder; the second checks again when its turn comes.
        scene = Scene();
        first = New(scene);
        second = New(scene);
        try
        {
            foreach (var model in new[] { first, second })
            {
                Refresh(model, scene, "", "owner-a:1");
                model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster");
                Refresh(model, scene, "Queued twice", "owner-a:1");
            }
            Tick(first, 5);
            ConfirmOnScreen(first);
            Tick(second, 5);
            Check(first.FleetNotice == "Queued twice" && second.FleetNotice != "Queued twice",
                "two models: queued in both, only the first shows it");
        }
        finally { first.ClearAuthorizedContent(); second.ClearAuthorizedContent(); }
    }

    // The record holds 64 channels; a 65th drops only the oldest one.
    private static void Capacity()
    {
        var table = (System.Collections.IDictionary)typeof(OverlayViewModel)
            .GetField("s_shownAnnouncements", BindingFlags.Static | BindingFlags.NonPublic)!.GetValue(null)!;
        lock (table) table.Clear();
        var oldest = Scene();
        var second = Scene();
        Shows(oldest, "Capacity fixture", "owner-a:1");
        Shows(second, "Capacity fixture", "owner-a:1");
        for (var i = 2; i < 64; i++) Shows(Scene(), "Capacity fixture", "owner-a:1");
        Check(table.Count == 64 && !Shows(oldest, "Capacity fixture", "owner-a:1"), "capacity: 64 channels are all kept");
        Shows(Scene(), "Capacity fixture", "owner-a:1");
        Check(table.Count == 64 && !Shows(second, "Capacity fixture", "owner-a:1") && Shows(oldest, "Capacity fixture", "owner-a:1"),
            "capacity: the 65th channel drops only the oldest");
    }

    private static OverlaySceneContext Scene() => new(OverlayScenePreference.Auto, OverlaySceneKind.Community, "Fixture organization", false,
        ChatChannelId: "organization:once-" + Guid.NewGuid().ToString("N"));

    private static OverlayCommandState Notice(string text) => Empty with { NoticeTitle = "Announcement", NoticeText = text };

    private static OverlayViewModel New(OverlaySceneContext scene) =>
        new(new([]), Settings, OverlayRosterSelectionSettings.Default, "en", true, Empty, PlayerPresenceKind.AppOnline, "", scene);

    private static void Refresh(OverlayViewModel model, OverlaySceneContext scene, string text, string scopeKey,
        OverlayDisplaySettings? settings = null)
    {
        var module = new OverlayModuleScene(new([], true, scene), Notice(text), [], null, true, "notice-fixture");
        model.Refresh(new([]), settings ?? Settings, OverlayRosterSelectionSettings.Default, "en", true, Notice(text), PlayerPresenceKind.AppOnline, "",
            scene, modules: new OverlayModulePresentation(module, module, module, module, module, scopeKey));
    }

    private static bool Shows(OverlaySceneContext scene, string text, string scopeKey)
    {
        var model = New(scene);
        try
        {
            Refresh(model, scene, text, scopeKey);
            var shown = model.NoticeItemActive && model.FleetNotice == text;
            if (shown) ConfirmOnScreen(model);
            return shown;
        }
        finally { model.ClearAuthorizedContent(); }
    }

    // What the window does after it commits a frame that shows the announcement.
    private static void ConfirmOnScreen(OverlayViewModel model)
    {
        if (model.AnnouncementAwaitingScreen(model.FleetNoticeTitle, model.FleetNotice) is { } shown)
            OverlayViewModel.ConfirmAnnouncementShown(shown.Key, shown.Receipt);
    }

    private static void Tick(OverlayViewModel model, int times)
    {
        var timer = (DispatcherTimer)typeof(OverlayViewModel).GetField("_timer", Instance)!.GetValue(model)!;
        var fire = typeof(DispatcherTimer).GetMethod("FireTick", Instance)!;
        for (var i = 0; i < times; i++) fire.Invoke(timer, null);
    }

    private static bool FrameShowsNotice(OverlayCompositionHudWindow window)
    {
        var frame = typeof(OverlayCompositionHudWindow).GetMethod("BuildFrameState", Instance)!.Invoke(window, null)!;
        return frame.GetType().GetProperty("ShowNotice")!.GetValue(frame) is true;
    }
}
