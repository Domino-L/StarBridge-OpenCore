using System.Reflection;
using System.IO;
using StarBridge.HostRuntime.Reminders;
using StarBridge.Core.Presence;

namespace StarBridge.Desktop.Tests;

internal static class ContinuousPlayOverlayTests
{
    private static readonly DateTimeOffset Noon = new(2026, 9, 30, 15, 0, 0, TimeSpan.Zero);
    private static readonly OverlayDisplaySettings Settings = OverlayDisplaySettings.Default with
    { AnimationFrameRate = OverlayAnimationFrameRate.Off, EventNotificationTypes = OverlayEventNotificationTypes.LocalPlayReminder };

    internal static void RunAll()
    {
        var failures = new List<string>();
        foreach (var test in new Action[] { Copy, LongSession, SourceChange, PendingAndLanguages, Invalidation, Gates, TimerToCard })
        {
            try { test(); Console.WriteLine("PASS continuous play overlay " + test.Method.Name); }
            catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        }
        if (failures.Count > 0) throw new Exception(string.Join(Environment.NewLine, failures));
    }

    private static OverlayViewModel Model()
    {
        var model = new OverlayViewModel(new([]), Settings, OverlayRosterSelectionSettings.Default,
            "zh", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
        model.EventNotifications.Clear(); // Exclude the independent receiver-connected startup card.
        return model;
    }

    private static bool Queue(OverlayViewModel model, ContinuousPlayNotice notice, OverlayDisplaySettings? settings = null,
        bool visible = true) => NativeInformationOverlayRuntime.TryQueueContinuousPlay(notice, settings ?? Settings,
            visible, "zh", (type, title, detail, important, positive, current, deviceLocal) =>
                model.QueueGameEventNotification(type, title, detail, important, positive, current, isDeviceLocal: deviceLocal), Noon, new Random(2));

    private static void Copy()
    {
        var model = Model();
        try
        {
            var duration = TimeSpan.FromMinutes(120);
            var expected = LocalPlayReminderCopyCatalog.Pick(true, Noon, duration, random: new Random(2));
            Check(Queue(model, new(duration, () => true)), "due reminder accepted");
            Check(model.EventNotifications.Single().Title.Contains(expected.Title), "selected hydration/rest title must be retained");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void LongSession()
    {
        var model = Model();
        try
        {
            Queue(model, new(TimeSpan.FromHours(10), () => true));
            Check(model.EventNotifications.Single().Detail.Contains("10 个小时"), "ten-hour reminder must use actual continuous duration");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void SourceChange()
    {
        var model = Model();
        try
        {
            model.Refresh(new([]), Settings with { EventNotificationTypes = OverlayEventNotificationTypes.All },
                OverlayRosterSelectionSettings.Default, "zh", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
            Queue(model, new(TimeSpan.FromHours(2), () => true));
            model.QueueGameEventNotification(OverlayEventNotificationTypes.ShipChange, "Peer", "Old scene ship", false, false);
            Check(model.EventNotifications.Count == 2, "source reset includes an actual peer card");
            model.ClearAuthorizedContent(preserveDeviceLocalEvents: true); // Actual room/community continuity boundary.
            Check(model.EventNotifications.Count == 1 && model.EventNotifications[0].EventType == OverlayEventNotificationTypes.LocalPlayReminder,
                "changing the authorized source must clear shared events while retaining device-local rest reminder");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void PendingAndLanguages()
    {
        var model = Model();
        try
        {
            model.Refresh(new([]), Settings with { EventNotificationMaxVisibleCount = 1 },
                OverlayRosterSelectionSettings.Default, "zh", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
            model.QueueGameEventNotification(OverlayEventNotificationTypes.LocalPlayReminder, "Old scene", "fixture", false, false);
            Queue(model, new(TimeSpan.FromHours(2), () => true));
            Check(model.PendingEventNotificationCount == 1, "due reminder can be pending");
            model.ClearAuthorizedContent(preserveDeviceLocalEvents: true);
            model.Refresh(new([]), Settings, OverlayRosterSelectionSettings.Default, "zh", false,
                new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
            Check(model.EventNotifications.Single().IsDeviceLocal && model.PendingEventNotificationCount == 0,
                "queued local reminder survives source reset and promotes normally");
        }
        finally { model.ClearAuthorizedContent(); }
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        {
            var selected = -1;
            string title = "", detail = "";
            NativeInformationOverlayRuntime.TryQueueContinuousPlay(new(TimeSpan.FromHours(10), () => true), Settings,
                true, language, (_, t, d, _, _, _, _) => { title = t; detail = d; }, Noon, new Random(2), selected: index => selected = index);
            Check(title.Contains(language == "en" ? "superhuman" : language == "zh" ? "超人" : "超人") &&
                detail.Contains(language == "en" ? "10 hours" : language == "zh" ? "10 个小时" : "10 個小時"), "duration-aware three-language copy");
            var next = -1;
            NativeInformationOverlayRuntime.TryQueueContinuousPlay(new(TimeSpan.FromHours(10), () => true), Settings,
                true, language, (_, _, _, _, _, _, _) => { }, Noon, new Random(2), selected, index => next = index);
            Check(selected != next, "successive reminders preserve non-repeating copy selection");
        }
    }

    private static void Invalidation()
    {
        var model = Model();
        var current = true;
        try
        {
            Queue(model, new(TimeSpan.FromHours(2), () => current));
            current = false;
            Tick(model);
            Check(model.EventNotifications.Count == 0, "disabled/stale reminder must clear from the actual card queue");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void Gates()
    {
        var model = Model();
        try
        {
            var notice = new ContinuousPlayNotice(TimeSpan.FromHours(2), () => true);
            Check(!Queue(model, notice, visible: false), "hidden overlay rejected");
            Check(!Queue(model, notice, Settings with { ShowEventNotifications = false }), "event module disabled");
            Check(!Queue(model, notice, Settings with { EventNotificationTypes = OverlayEventNotificationTypes.None }), "type disabled");
            Check(!Queue(model, notice with { IsCurrent = () => false }), "stale notice rejected");
            Check(model.EventNotifications.Count == 0, "suppression does not insert a card");
        }
        finally { model.ClearAuthorizedContent(); }
    }

    private static void TimerToCard()
    {
        var root = Path.Combine(Path.GetTempPath(), "starbridge-overlay-play-" + Guid.NewGuid().ToString("N"));
        var model = Model();
        var clock = new Clock { Now = Noon.AddMinutes(-120) };
        using var runtime = new ContinuousPlayReminderRuntime(root,
            () => new("running", Noon.AddMinutes(-120)), new Sink(model), clock);
        try
        {
            runtime.TickAsync().GetAwaiter().GetResult();
            clock.Now = Noon.AddSeconds(-1); runtime.TickAsync().GetAwaiter().GetResult();
            Check(model.EventNotifications.Count == 0, "timer does not notify early");
            clock.Now = Noon; runtime.TickAsync().GetAwaiter().GetResult();
            Check(model.EventNotifications.Single().EventType == OverlayEventNotificationTypes.LocalPlayReminder,
                "actual timer and storage reach the native dispatch boundary and card model");
            runtime.SaveAsync(new(false), 0).GetAwaiter().GetResult();
            Tick(model);
            Check(model.EventNotifications.Count == 0, "actual saved disable invalidates already queued reminder");
        }
        finally { model.ClearAuthorizedContent(); if (Directory.Exists(root)) Directory.Delete(root, true); }
    }

    private static void Tick(OverlayViewModel model) => typeof(OverlayViewModel)
        .GetMethod("TickEventNotifications", BindingFlags.Instance | BindingFlags.NonPublic)!
        .Invoke(model, [DateTimeOffset.Now]);
    private sealed class Clock : TimeProvider { internal DateTimeOffset Now; public override DateTimeOffset GetUtcNow() => Now; }
    private sealed class Sink(OverlayViewModel model) : IContinuousPlayReminderSink
    { public ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation) => new(Queue(model, notice)); }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
