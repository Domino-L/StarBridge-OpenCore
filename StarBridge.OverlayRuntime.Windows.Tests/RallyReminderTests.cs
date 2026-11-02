namespace StarBridge.Desktop.Tests;

using System.Reflection;
using StarBridge.Core.Overlay;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

internal static class RallyReminderTests
{
    private static void Check(bool value, string name)
    {
        if (!value) throw new Exception("FAIL rally copy: " + name);
        Console.WriteLine("PASS rally copy: " + name);
    }
    internal static void Run()
    {
        var now = DateTimeOffset.UtcNow;
        InformationOverlayReminder Reminder(string text = "集合", int seconds = 61, string preview = "sourceOnly", bool sample = false) =>
            new(Guid.NewGuid(), 0, 0, preview, () => true) { Rally = new(text, now.AddSeconds(seconds), sample) };
        foreach (var (language, title, hint, hidden, sample, label) in new[] {
            ("zh", "舰队召集", "Ctrl+Alt+Y 马上到 · Ctrl+Alt+N 来不了", "有新的召集，可在客户端回应", "（示例）这是一条示例召集", "召集中"),
            ("zh-TW", "艦隊召集", "Ctrl+Alt+Y 馬上到 · Ctrl+Alt+N 來不了", "有新的召集，可在客戶端回應", "（範例）這是一則範例召集", "召集中"),
            ("zh-Hant", "艦隊召集", "Ctrl+Alt+Y 馬上到 · Ctrl+Alt+N 來不了", "有新的召集，可在客戶端回應", "（範例）這是一則範例召集", "召集中"),
            ("en", "Fleet rally", "Ctrl+Alt+Y on my way · Ctrl+Alt+N can't make it", "New rally. Respond in the client.", "(sample) This is a sample rally", "Rally on") })
        {
            var reminder = Reminder();
            var slot = NativeInformationOverlayRuntime.RallySlotFor(reminder, language);
            var zh = language.StartsWith("zh");
            Check(slot.Id == reminder.Id && slot.ExpiresAt == reminder.Rally!.ExpiresAt && slot.Title == title &&
                slot.Hint == hint && slot.ActiveLabel == label && slot.Body == (zh ? "「集合」" : "“集合”"), language);
            Check(NativeInformationOverlayRuntime.RallySlotFor(Reminder(preview: "hiddenDetails"), language).Body == hidden, language + " hidden details");
            foreach (var text in new[] { "", " \t\r\n" })
                Check(NativeInformationOverlayRuntime.RallySlotFor(Reminder(text), language).Body == hidden, language + " empty body");
            foreach (var preview in new[] { "sourceOnly", "hiddenDetails" })
                Check(NativeInformationOverlayRuntime.RallySlotFor(Reminder("", preview: preview, sample: true), language).Body == sample,
                    language + " sample body: " + preview);
            var minutes = language switch { "en" => "2 min left", "zh" => "剩余 2 分钟", _ => "剩餘 2 分鐘" };
            Check(OverlayCompositionHudWindow.RallyRemaining(slot, now) == minutes, language + " minutes left");
        }
        foreach (var (input, expected) in new[] {
            (new string('a', 32), new string('a', 32)), (new string('a', 33), new string('a', 31) + "…"),
            (new string('舰', 16), new string('舰', 16)), (new string('舰', 16) + "a", new string('舰', 15) + "…"),
            (new string('a', 29) + "舰xy", new string('a', 29) + "舰…"),
            (new string('a', 30) + "😀xy", new string('a', 30) + "😀…"),
            (new string('a', 29) + "𠀀xy", new string('a', 29) + "𠀀…"),
            (new string('Ａ', 16) + "a", new string('Ａ', 15) + "…") })
            Check(NativeInformationOverlayRuntime.RallySlotFor(Reminder(input), "en").Body == $"“{expected}”",
                "width and scalar boundary: " + input);
        foreach (var seconds in new[] { 59, 1 })
            Check(OverlayCompositionHudWindow.RallyRemaining(NativeInformationOverlayRuntime.RallySlotFor(Reminder(seconds: seconds), "en"), now) ==
                "1 min left", "minute floor: " + seconds);
        NoticeSlotRules(now);
        NoticeQueueRules();
        foreach (var duration in new[] { 5, 10 })
        {
            var projected = NativeInformationOverlayRuntime.ProjectRoom(null, OverlayScenePreference.Auto, "en");
            var settings = OverlayDisplaySettings.Default with { ShowNotice = true, CommunicationEventDurationSeconds = duration };
            var model = new OverlayViewModel(new OverlayAuthorizedRoster([]), settings, OverlayRosterSelectionSettings.Default,
                "en", false, projected.Command, PlayerPresenceKind.AppOnline, "", projected.Scene.Context, []);
            try
            {
                model.ClearAuthorizedContent();
                Check(model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Rally", "Text", 8), "admitted");
                var remaining = typeof(OverlayViewModel).GetField("_noticeSecondsRemaining", BindingFlags.Instance | BindingFlags.NonPublic)!.GetValue(model);
                Check((int)remaining! == Math.Max(duration, 8), "minimum duration with setting " + duration);
            }
            finally { model.ClearAuthorizedContent(); }
        }
    }

    // The one top slot: a rally holds it, a notice borrows it with a side mark, "+N" for the
    // queue, closed once the countdown ends; nothing ever adds a second panel.
    private static void NoticeSlotRules(DateTimeOffset now)
    {
        const BindingFlags all = BindingFlags.Instance | BindingFlags.Static | BindingFlags.Public | BindingFlags.NonPublic;
        var settings = OverlayDisplaySettings.Default with { ShowNotice = true, EnableStartupTransition = false };
        using var window = new OverlayCompositionHudWindow(new OverlayAuthorizedRoster([]), [],
            OverlayLayoutItem.ParseMany(InformationOverlayDefaults.DefaultLayoutPayload), settings, new OverlayRosterSelectionSettings(), "zh", false,
            new OverlayCommandState(null, null, null, null, null, null), PlayerPresenceKind.AppOnline, "", new System.Windows.Rect(0, 0, 1920, 1080),
            OverlayStartupTransitionContext.ForLanguage("zh"), OverlaySceneContext.Local(settings.ScenePreference));
        var type = typeof(OverlayCompositionHudWindow);
        var built = type.GetMethod("BuildFrameState", all)!.Invoke(window, [])!;
        object Clone(object record) => record.GetType().GetMethod("<Clone>$", all)!.Invoke(record, [])!;
        object State(bool show, string? empty = null)
        {
            var copy = Clone(built);
            Put(copy, "ShowNotice", show); Put(copy, "FleetNoticeTitle", "房间邀请"); Put(copy, "FleetNotice", "Aster 邀请你");
            Put(copy, "NoticeTimerLabel", "4.0s");
            var empties = Clone(Read(copy, "EmptyStates")!);
            Put(empties, "Notice", empty is null ? null : new OverlayModuleEmptyState(empty));
            Put(copy, "EmptyStates", empties);
            return copy;
        }
        var apply = type.GetMethods(all).Single(m => m.Name == "ApplyNoticeSlot" && m.GetParameters().Length == 5);
        object Apply(object state, OverlayRallySlot? rally, bool item, int queued = 0) =>
            apply.Invoke(null, [state, rally, item, queued, now])!;
        var rally = new OverlayRallySlot(Guid.NewGuid(), "舰队召集", "「集合」", "Ctrl+Alt+Y 马上到", "召集中", now.AddMinutes(27.5), true, false);

        var pinned = Apply(State(show: false), rally, item: false);
        Check(Read(pinned, "ShowNotice") is true && Read(pinned, "FleetNoticeTitle") is "舰队召集" &&
            Read(pinned, "NoticeTimerLabel") is "剩余 28 分钟" && Read(pinned, "NoticeMeta") is "Ctrl+Alt+Y 马上到" &&
            Read(pinned, "NoticeAccent") is true, "slot: rally holds the slot even with the notice module off");
        Check(Read(Read(Apply(State(true, "暂无公告"), rally, item: false), "EmptyStates")!, "Notice") is null,
            "slot: rally replaces the empty notice state");
        var borrowed = Apply(State(true), rally, item: true, queued: 2);
        Check(Read(borrowed, "FleetNoticeTitle") is "房间邀请" && Read(borrowed, "NoticeMeta") is "+2 · ■ 召集中 · 剩余 28 分钟" &&
            Read(borrowed, "NoticeMetaAccent") is true && Read(borrowed, "NoticeAccent") is false,
            "slot: a notice borrows the slot and marks the rally");
        Check(Read(Apply(State(false), rally, item: false, queued: 1), "NoticeMeta") is "+1 · Ctrl+Alt+Y 马上到",
            "slot: queued notices still count while the rally holds the slot");
        Check(Read(Apply(State(false), rally, item: true), "FleetNoticeTitle") is "舰队召集",
            "slot: a notice hidden by its own switch never borrows the rally slot");
        Check(Read(Apply(State(true), rally with { ExpiresAt = now }, item: true, queued: 2), "NoticeMeta") is "+2",
            "slot: an expired rally is gone; the queue shows +N");
        Check(Read(Apply(State(true), null, item: true), "NoticeMeta") is null, "slot: no queue, no mark");
        Check(Read(Apply(State(false), null, item: false), "ShowNotice") is false, "slot: nothing showing, no slot");
        Check(Read(Apply(State(false), null, item: false, queued: 2), "NoticeMeta") is null, "slot: a closed slot shows no +N");

        static object? Read(object target, string name) => target.GetType().GetProperty(name, all)!.GetValue(target);
        static void Put(object target, string name, object? value) => target.GetType().GetProperty(name, all)!.SetValue(target, value);
    }

    // A room reminder outranks a plain communication event, which waits at the head of the
    // queue; one live reminder never displaces another. An announcement shows once per app run.
    private static void NoticeQueueRules()
    {
        var projected = NativeInformationOverlayRuntime.ProjectRoom(null, OverlayScenePreference.Auto, "en");
        var settings = OverlayDisplaySettings.Default with { ShowNotice = true, CommunicationEventDurationSeconds = 5 };
        var model = new OverlayViewModel(new OverlayAuthorizedRoster([]), settings, OverlayRosterSelectionSettings.Default,
            "en", false, projected.Command, PlayerPresenceKind.AppOnline, "", projected.Scene.Context, []);
        try
        {
            model.ClearAuthorizedContent();
            model.QueueCommunicationEvent("Comms", "Event");
            Check(model.NoticeItemActive && model.FleetNoticeTitle == "Comms", "queue: a communication event shows");
            Check(model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Room invite", "Aster"), "queue: a room reminder takes the slot");
            Check(model.FleetNoticeTitle == "Room invite" && model.NoticeQueueCount == 1, "queue: the communication event waits at the head");
            Check(!model.TryShowLiveCommunicationEvent(Guid.NewGuid(), "Another", "Vega"), "queue: one live reminder never displaces another");
        }
        finally { model.ClearAuthorizedContent(); }

        OverlayAnnouncementOnceTests.Run();
    }
}
