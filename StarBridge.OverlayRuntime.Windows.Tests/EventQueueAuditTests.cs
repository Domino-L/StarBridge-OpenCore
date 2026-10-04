using StarBridge.Core.Events;
using StarBridge.Core.Presence;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop.Tests;

internal static class EventQueueAuditTests
{
    internal static void RunAll()
    {
        TypesAndDisabledQueue();
        LocalGameCards();
        LocalIdentityFallback();
        SelfEchoIdentity();
    }

    private static void LocalIdentityFallback()
    {
        foreach (var player in new string?[] { null, "", " ", "LocalPlayer" })
        {
            string? title = null;
            var notice = new LocalGameOverlayNotice(Guid.NewGuid().ToString("N"), "PlayerEnteredShip",
                LifeEventContext.Unknown, () => true, DisplayPlayer: player);
            Check(NativeInformationOverlayRuntime.TryQueueLocalGameEvent(notice, OverlayDisplaySettings.Default, true,
                "en", new(), (_, actualTitle, _, _, _, _, _) => title = actualTitle) && title == "Local player",
                "missing or placeholder local identity uses the original fallback without profile lookup");
        }
        Console.WriteLine("PASS local accepted identity and missing-identity fallback");
    }

    private static void TypesAndDisabledQueue()
    {
        foreach (var type in Enum.GetValues<OverlayEventNotificationTypes>().Where(t => t != 0 &&
                     ((int)t & ((int)t - 1)) == 0 && OverlayEventNotificationTypes.All.HasFlag(t)))
        {
            var settings = OverlayDisplaySettings.Default with { AnimationFrameRate = OverlayAnimationFrameRate.Off,
                EventNotificationMaxVisibleCount = 1 };
            var model = Model(settings);
            try
            {
                model.QueueGameEventNotification(type, "visible", "fixture", false, false);
                model.QueueGameEventNotification(type, "pending", "fixture", false, false);
                Check(model.EventNotifications.Count == 1 && model.PendingEventNotificationCount == 1, type + " reaches both queues");
                model.Refresh(new([]), settings with { EventNotificationTypes = OverlayEventNotificationTypes.All & ~type },
                    OverlayRosterSelectionSettings.Default, "en", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
                Check(!model.EventNotifications.Any(row => row.EventType == type) && model.PendingEventNotificationCount == 0,
                    type + " must clear visible and pending cards when that category is disabled");
                model.QueueGameEventNotification(type, "disabled", "fixture", false, false);
                Check(!model.EventNotifications.Any(row => row.EventType == type) && model.PendingEventNotificationCount == 0,
                    type + " stays disabled at the queue boundary");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine("PASS all nine active event categories clear both queues and reject disabled additions");
    }

    private static void LocalGameCards()
    {
        foreach (var language in new[] { "zh", "zh-Hant", "en" })
        foreach (var type in new[] { "PlayerDowned", "PlayerDied", "PlayerRevived", "PlayerRespawned",
                     "GameStarted", "GameStopped", "ServerJoined", "ServerLeft", "PlayerEnteredShip",
                     "PlayerExitedShip", "PlayerControllingShip", "PlayerStoppedDrivingShip" })
        {
            var settings = OverlayDisplaySettings.Default with { AnimationFrameRate = OverlayAnimationFrameRate.Off };
            var model = Model(settings);
            try
            {
                var gate = new OverlayLocalEventDeliveryGate();
                var valid = true;
                var notice = new LocalGameOverlayNotice(Guid.NewGuid().ToString("N"), type,
                    LifeEventContext.SafeZoneMedicalResponse, () => valid, type == "ServerJoined" ? "US" : "ANVL_Lightning_F8C",
                    "AcceptedFixturePilot");
                void Queue(OverlayEventNotificationTypes category, string title, string detail, bool important,
                    bool positive, Func<bool>? current, bool deviceLocal) =>
                    model.QueueGameEventNotification(category, title, detail, important, positive, current, isDeviceLocal: deviceLocal);
                Check(NativeInformationOverlayRuntime.TryQueueLocalGameEvent(notice, settings, true, language, gate, Queue), "local card accepted without a shared room");
                var card = model.EventNotifications.Single();
                Check((card.Title + " " + card.Detail).Contains("AcceptedFixturePilot"),
                    "accepted local identity reaches the actual queue in every language and event category: " + type + "/" + language + ": " + card.Title + " / " + card.Detail);
                Check(card.EventType == NativeInformationOverlayRuntime.ActivityNotificationType(type) && card.IsDeviceLocal, "correct local scope and category");
                if (type == "PlayerDowned") Check(card.Detail.Contains(language == "en" ? "safe zone" : language == "zh" ? "安全区" : "安全區"), "safe-zone parser context survives");
                if (type == "ServerJoined") Check(card.Detail.Contains(language == "en" ? "US" : "美服"), "localized region included");
                if (card.EventType == OverlayEventNotificationTypes.ShipChange) Check(card.Detail.Contains("F8C") && !card.Detail.Contains("ANVL_"), "ship uses shared translation vocabulary");
                Check(!gate.TryAcceptShared(notice.Id, "self", true), "shared echo cannot display the same journal ID again");
                Check(gate.TryAcceptShared(notice.Id, "peer-a", false) && gate.TryAcceptShared(notice.Id, "peer-b", false),
                    "different publishers with the same event ID remain distinct");
                Check(!gate.TryAcceptShared(notice.Id, "peer-a", false), "same publisher does not replay");
                model.ClearAuthorizedContent(preserveDeviceLocalEvents: true);
                Check(model.EventNotifications.Count == 1, "scene changes preserve local life events");
                valid = false;
                typeof(OverlayViewModel).GetMethod("TickEventNotifications", System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!
                    .Invoke(model, [DateTimeOffset.Now]);
                Check(model.EventNotifications.Count == 0, "account/lifetime invalidation clears local life card");
                Check(!NativeInformationOverlayRuntime.TryQueueLocalGameEvent(notice with { Id = "new", IsCurrent = () => true },
                    settings, false, language, gate, Queue), "closed overlay is not opened by a life event");
            }
            finally { model.ClearAuthorizedContent(); }
        }
        Console.WriteLine("PASS twelve local game event types in three languages, names, region, context, scope, expiry and shared echo");
    }

    private static OverlayViewModel Model(OverlayDisplaySettings settings)
    {
        var model = new OverlayViewModel(new([]), settings, OverlayRosterSelectionSettings.Default,
            "en", false, new("", "", null, null, null, null), PlayerPresenceKind.InGame, "");
        model.EventNotifications.Clear();
        return model;
    }

    private static void SelfEchoIdentity()
    {
        var member = new InformationOverlayRoomMember("same name", "same handle", false, "InGame", "", "", "")
            { PreferenceKey = "stable", IsSelf = true };
        var room = new InformationOverlayRoomContent("fixture", "room", "", 4, "same handle", [member], []);
        Check(NativeInformationOverlayRuntime.IsSelfActivityPublisher("stable", room, null, InformationOverlaySourceKind.PartyRoom), "explicit authenticated self suppresses echo");
        Check(!NativeInformationOverlayRuntime.IsSelfActivityPublisher("peer", room, null, InformationOverlaySourceKind.PartyRoom), "callsign cannot replace stable publisher identity");
        Check(!NativeInformationOverlayRuntime.IsSelfActivityPublisher("stable", room with { Members = [member with { IsSelf = null }] }, null,
            InformationOverlaySourceKind.PartyRoom), "legacy matching handle without self proof cannot suppress a peer event");
        Check(!NativeInformationOverlayRuntime.IsSelfActivityPublisher("stable", room with { Members = [member, member] }, null,
            InformationOverlaySourceKind.PartyRoom), "ambiguous self identity cannot suppress events");
        var row = NativeInformationOverlayRuntime.ProjectRoom(room, OverlayScenePreference.Auto, "en").Scene.Players.Single();
        Check(NativeInformationOverlayRuntime.IsModuleSelfPublisher("stable", [row]), "v2 self echo uses the events module's authorized identity");
        Check(!NativeInformationOverlayRuntime.IsModuleSelfPublisher("peer", [row]) &&
            !NativeInformationOverlayRuntime.IsModuleSelfPublisher(null, [row]) &&
            !NativeInformationOverlayRuntime.IsModuleSelfPublisher("stable", [row with { IsSelf = false }]) &&
            !NativeInformationOverlayRuntime.IsModuleSelfPublisher("stable", [row, row]),
            "v2 cannot guess self from a callsign, missing proof or ambiguous identity");
    }
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }
}
