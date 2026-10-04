namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Events;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Privacy;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime : ISharedActivitySink
{
    public async ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || _window is not { IsVisible: true } window || _workspace is not { } workspace) return false;
            var type = ActivityNotificationType(notice.Event.Type);
            IReadOnlyList<PlayerRow> players = [];
            bool isSelf;
            if (workspace.UsesModuleSources)
            {
                var modules = ReadModules(workspace, SafeReadSession(), ReadLocalDisplayPresence());
                if (modules is null || !ActivityMatchesModule(notice, modules.Events)) return false;
                players = modules.Events.Scene.Players;
                isSelf = IsModuleSelfPublisher(notice.PublisherKey, players);
                var originalNotice = notice;
                var identity = modules.Events.Identity;
                notice = notice with { IsCurrent = () => originalNotice.IsCurrent() &&
                    _lastRenderedModules?.Events is { } displayed && displayed.Identity == identity && ActivityMatchesModule(originalNotice, displayed) };
            }
            else
            {
                if (notice.Event.Type is "PlayerLocationChanged" or "ServerJoined" || type == OverlayEventNotificationTypes.ShipChange)
                {
                    var mode = SafeReadSourceMode();
                    var room = SafeReadRoom();
                    var preference = SourcePreference(mode, workspace.Settings.ScenePreference);
                    var community = mode == "community" || preference == OverlayScenePreference.Auto && room is null ? SafeReadCommunity() : null;
                    var content = ProjectSource(room, community, preference, workspace.Language, mode == "community",
                        SafeReadSession(), ReadLocalDisplayPresence());
                    players = content.Scene.Players;
                }
                isSelf = IsCurrentSelfPublisher(notice.PublisherKey, workspace);
            }
            return TryQueueSharedActivity(notice, workspace.Settings, true, workspace.Language, _localEventDelivery,
                isSelf, players,
                (category, title, detail, positive, current, currentDetail) => window.QueueGameEventNotification(
                    category, title, detail, false, positive, current, currentDetail));
        }, DispatcherPriority.Send, token);
        return await operation.Task.WaitAsync(token).ConfigureAwait(false);
    }

    internal static bool ActivityMatchesModule(SharedActivityNotice notice, OverlayModuleScene events) =>
        events.Available && events.Identity is not null && notice.SourceKey is not null && notice.SourceKey == events.ResourceKey;

    internal static bool IsModuleSelfPublisher(string? publisherKey, IReadOnlyList<PlayerRow> players)
    {
        if (publisherKey is null) return false;
        var matches = players.Where(player => player.AccountId == publisherKey).Take(2).ToArray();
        return matches.Length == 1 && matches[0].IsSelf;
    }

    // The actual control-thread queue path, also exercised without creating a HWND.
    internal static bool TryQueueSharedActivity(SharedActivityNotice notice, OverlayDisplaySettings settings,
        bool visible, string language, OverlayLocalEventDeliveryGate delivery, bool isSelf,
        IReadOnlyList<PlayerRow> players,
        Action<OverlayEventNotificationTypes, string, string, bool, Func<bool>?, Func<IReadOnlyList<PlayerRow>, string>?> queue)
    {
        var type = ActivityNotificationType(notice.Event.Type);
        if (!visible || !notice.IsCurrent() || !settings.ShowEventNotifications || type == 0 ||
            !settings.EventNotificationTypes.HasFlag(type)) return false;
        if (!delivery.TryAcceptShared(notice.Event.Id, notice.PublisherKey, isSelf)) return false;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-TW" or "zh-Hant" or "zh-HK";
        var copy = ActivityCopy(notice.Event.Type);
        Func<IReadOnlyList<PlayerRow>, string>? currentDetail = notice.Event.Type == "PlayerLocationChanged"
            ? rows => LocationActivityDetail(notice, rows, language)
            : notice.Event.Type == "ServerJoined" ? rows => ServerActivityDetail(notice, rows, language)
            : type == OverlayEventNotificationTypes.ShipChange ? rows => ShipActivityDetail(notice, rows, language) : null;
        var detail = currentDetail?.Invoke(players) ?? (traditional ? copy.Item2 : zh ? copy.Item1 : copy.Item3);
        queue(type, notice.Callsign, detail, notice.Event.Type is "PlayerRevived" or "PlayerRespawned", notice.IsCurrent, currentDetail);
        return true;
    }

    internal static string ShipActivityDetail(SharedActivityNotice notice, IReadOnlyList<PlayerRow> authorizedPlayers, string language)
    {
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-TW" or "zh-Hant" or "zh-HK";
        var copy = ActivityCopy(notice.Event.Type);
        var title = traditional ? copy.Item2 : zh ? copy.Item1 : copy.Item3;
        var rows = notice.PublisherKey is null ? [] : authorizedPlayers.Where(row => row.AccountId == notice.PublisherKey).ToArray();
        // The minimal event has no historical ship payload. Only show explicitly
        // current, independently authorized information; later refreshes cannot
        // claim that a new ship was the object of the earlier enter/seat event.
        if (rows.Length != 1 || rows[0].SharedPresence != StarBridge.Core.Presence.PlayerPresenceKind.InGame ||
            rows[0].SharedHasServerSession == false) return title;
        var raw = rows[0].SharedShipText;
        if (!PlayerSessionStatePresentation.HasRecognizedValue(raw) || PlayerSessionStatePresentation.IsSessionStateText(raw) ||
            raw.Length > 256 || raw.Any(char.IsControl)) return title;
        var ship = StarBridge.HostRuntime.Presence.GameShipNames.Find(raw);
        var value = ship is null ? raw.Contains('_') ? null : raw :
            traditional ? ship.TraditionalChineseName ?? ship.ChineseName : zh ? ship.ChineseName : ship.EnglishName;
        return string.IsNullOrWhiteSpace(value) ? title : title +
            (traditional ? " · 目前艦船：" : zh ? " · 当前舰船：" : " · Current ship: ") + value;
    }

    internal static OverlayEventNotificationTypes ActivityNotificationType(string type) => SharedActivityEvent.Category(type) switch
            {
                SharedActivityEventTypes.Presence => OverlayEventNotificationTypes.MemberPresence,
                SharedActivityEventTypes.Server => OverlayEventNotificationTypes.MemberServer,
                SharedActivityEventTypes.Ship => OverlayEventNotificationTypes.ShipChange,
                SharedActivityEventTypes.Location => OverlayEventNotificationTypes.LocationChange,
                SharedActivityEventTypes.Life => OverlayEventNotificationTypes.DeathAndRespawn,
                _ => OverlayEventNotificationTypes.None
            };

    internal static (string, string, string) ActivityCopy(string type) => type switch
            {
                "GameStarted" => ("开始游戏", "開始遊戲", "Started playing"),
                "GameStopped" => ("结束游戏", "結束遊戲", "Stopped playing"),
                "ServerJoined" => ("进入服务器", "進入伺服器", "Joined a server"),
                "ServerLeft" => ("离开服务器", "離開伺服器", "Left a server"),
                "PlayerEnteredShip" => ("进入飞船", "進入飛船", "Entered a ship"),
                "PlayerExitedShip" => ("离开飞船", "離開飛船", "Left a ship"),
                "PlayerControllingShip" => ("进入驾驶位", "進入駕駛位", "Took the pilot seat"),
                "PlayerStoppedDrivingShip" => ("离开驾驶位", "離開駕駛位", "Left the pilot seat"),
                "PlayerLocationChanged" => ("位置已更新", "位置已更新", "Location changed"),
                "PlayerDowned" => ("已倒地", "已倒地", "Incapacitated"),
                "PlayerDied" => ("已死亡", "已死亡", "Died"),
                "PlayerRevived" => ("已被救起", "已被救起", "Revived"),
                "PlayerRespawned" => ("已重生", "已重生", "Respawned"),
                _ => ("", "", "")
            };
    internal static string ServerActivityDetail(SharedActivityNotice notice, IReadOnlyList<PlayerRow> authorizedPlayers, string language)
    {
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-TW" or "zh-Hant";
        var title = traditional ? "進入伺服器" : zh ? "进入服务器" : "Joined a server";
        var rows = notice.PublisherKey is null ? [] : authorizedPlayers.Where(row => row.AccountId == notice.PublisherKey).ToArray();
        // Events carry no historical region. Only supplement an independently
        // authorized current member; the presentation mapper never returns IDs.
        var region = rows.Length == 1 && rows[0].SharedPresence == StarBridge.Core.Presence.PlayerPresenceKind.InGame &&
            rows[0].SharedHasServerSession != false
            ? GameServerRegionPresentation.ResolvePreferredRegion(rows[0].ServerShard, rows[0].ServerRegion, zh)
            : null;
        if (region is null) return title;
        if (traditional) region = region.Replace("欧服", "歐服").Replace("亚服", "亞服");
        return title + (traditional ? " · 目前區域：" : zh ? " · 当前区域：" : " · Current region: ") + region;
    }

    private bool IsCurrentSelfPublisher(string? publisherKey, InformationOverlayRuntimeWorkspace workspace)
    {
        if (publisherKey is null) return false;
        var mode = SafeReadSourceMode();
        var room = SafeReadRoom();
        var preference = SourcePreference(mode, workspace.Settings.ScenePreference);
        var community = mode == "community" || preference == OverlayScenePreference.Auto && room is null ? SafeReadCommunity() : null;
        var source = InformationOverlaySourcePolicy.Resolve(preference, room is not null,
            hasFleet: false, community is not null, mode == "community");
        return IsSelfActivityPublisher(publisherKey, room, community, source.Kind);
    }

    internal static bool IsSelfActivityPublisher(string publisherKey, InformationOverlayRoomContent? room,
        InformationOverlayCommunityContent? community, InformationOverlaySourceKind kind)
    {
        if (kind == InformationOverlaySourceKind.PartyRoom && room is not null)
        {
            var matches = room.Members.Where(row => row.PreferenceKey == publisherKey).ToArray();
            return matches.Length == 1 && matches[0].IsSelf == true;
        }
        if (kind == InformationOverlaySourceKind.Community && community is not null)
        {
            var matches = community.Members.Where(row => row.PreferenceKey == publisherKey).ToArray();
            return matches.Length == 1 && matches[0].IsSelf;
        }
        return false;
    }

    internal static string LocationActivityDetail(SharedActivityNotice notice, IReadOnlyList<PlayerRow> authorizedPlayers, string language)
    {
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        var rows = notice.PublisherKey is null ? [] : authorizedPlayers.Where(row => row.AccountId == notice.PublisherKey).ToArray();
        // The event contract has no historical location. Supplement only current,
        // independently authorized location; never claim it was the event destination.
        var member = rows.Length == 1 && rows[0].SharedPresence == StarBridge.Core.Presence.PlayerPresenceKind.InGame &&
            rows[0].SharedHasServerSession != false && !rows[0].IsLowConfidenceLocationHidden ? rows[0] : null;
        if (member?.ArrivalPendingConfirmation == true)
        {
            var target = LocationArrivalPresentation.ResolveCurrentLocation(member.SharedPresence,
                member.SharedHasServerSession, member.SharedLocationText, true, member.ArrivalTargetCode, language);
            return (traditional ? "位置已更新 · 目前到達目標：" : zh ? "位置已更新 · 当前到达目标：" : "Location changed · current arrival target: ") + target;
        }
        var location = member is not null && !PlayerSessionStatePresentation.IsSessionStateText(member.SharedLocationText) &&
            PlayerSessionStatePresentation.HasRecognizedValue(member.SharedLocationText)
                ? LocationNameLocalizer.DisplayName(member.SharedLocationText, zh ? "zh" : "en") : null;
        return string.IsNullOrWhiteSpace(location)
            ? traditional ? "位置已更新 · 目前地點待確認" : zh ? "位置已更新 · 当前地点待确认" : "Location changed · current location unavailable"
            : traditional ? $"位置已更新 · 目前地點：{location}" : zh ? $"位置已更新 · 当前地点：{location}" : $"Location changed · current location: {location}";
    }
}
