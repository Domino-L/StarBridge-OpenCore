using System.Windows.Threading;
using StarBridge.Core.Events;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop;

public sealed partial class NativeInformationOverlayRuntime : ILocalGameOverlayEventSink
{
    private readonly OverlayLocalEventDeliveryGate _localEventDelivery = new();

    public async ValueTask<bool> TryPresentLocalGameEventAsync(LocalGameOverlayNotice notice, CancellationToken cancellation)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellation.ThrowIfCancellationRequested();
            if (_disposed || _window is not { } window || _workspace is not { } workspace) return false;
            return TryQueueLocalGameEvent(notice, workspace.Settings, window.IsVisible, workspace.Language,
                _localEventDelivery, (type, title, detail, important, positive, current, deviceLocal) =>
                    window.QueueGameEventNotification(type, title, detail, important, positive, current, isDeviceLocal: deviceLocal));
        }, DispatcherPriority.Send, cancellation);
        return await operation.Task.WaitAsync(cancellation).ConfigureAwait(false);
    }

    internal static bool TryQueueLocalGameEvent(LocalGameOverlayNotice notice, OverlayDisplaySettings settings,
        bool visible, string language, OverlayLocalEventDeliveryGate delivery,
        Action<OverlayEventNotificationTypes, string, string, bool, bool, Func<bool>?, bool> queue)
    {
        var category = ActivityNotificationType(notice.Type);
        if (!visible || !notice.IsCurrent() || !settings.ShowEventNotifications || category == 0 ||
            !settings.EventNotificationTypes.HasFlag(category)) return false;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-TW" or "zh-Hant" or "zh-HK";
        var words = ActivityCopy(notice.Type);
        var title = !string.IsNullOrWhiteSpace(notice.DisplayPlayer) &&
                    !notice.DisplayPlayer.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase)
            ? notice.DisplayPlayer.Trim()
            : traditional ? "本機玩家" : zh ? "本机玩家" : "Local player";
        var detail = traditional ? words.Item2 : zh ? words.Item1 : words.Item3;
        var important = false;
        var positive = false;
        if (category == OverlayEventNotificationTypes.DeathAndRespawn)
        {
            if (!Enum.TryParse<FleetEventType>(notice.Type, out var lifeType)) return false;
            var life = OverlayGameEventNotificationPolicy.Create(lifeType, title, zh, notice.Context);
            if (life is null) return false;
            title = life.Title; detail = life.Detail; important = life.Important; positive = life.Positive;
            if (traditional)
            {
                title = title.Replace("区", "區").Replace("获", "獲");
                detail = detail.Replace("机", "機").Replace("区", "區").Replace("应", "應").Replace("动", "動");
            }
        }
        else if (category == OverlayEventNotificationTypes.ShipChange && !string.IsNullOrWhiteSpace(notice.DisplayValue))
        {
            var ship = GameShipNames.Find(notice.DisplayValue);
            var value = traditional ? ship?.TraditionalChineseName ?? ship?.ChineseName : zh ? ship?.ChineseName : ship?.EnglishName;
            detail += " · " + (value ?? notice.DisplayValue);
        }
        else if (notice.Type == "ServerJoined")
        {
            var region = GameServerRegionPresentation.ResolvePreferredRegion(null, notice.DisplayValue, zh);
            if (traditional) region = region?.Replace("欧服", "歐服").Replace("亚服", "亞服");
            if (region is not null) detail += " · " + region;
        }
        if (!delivery.TryAcceptLocal(notice.Id)) return false;
        queue(category, title, detail, important, positive, notice.IsCurrent, true);
        return true;
    }
}

// Journal IDs survive their optional network round trip. One control-thread gate
// prevents a locally rendered event being shown again by the shared feed.
internal sealed class OverlayLocalEventDeliveryGate
{
    private readonly HashSet<string> _seen = new(StringComparer.Ordinal);
    private readonly Queue<string> _order = new();
    internal bool TryAcceptLocal(string id) => !_seen.Contains("self-shared:" + id) && Remember("local:" + id);
    internal bool TryAcceptShared(string id, string? publisherKey, bool isSelf)
    {
        // IDs belong to publishers; matching IDs from different peers are not echoes.
        if (isSelf && _seen.Contains("local:" + id)) return false;
        if (!Remember("shared:" + publisherKey + ":" + id)) return false;
        if (isSelf) Remember("self-shared:" + id);
        return true;
    }
    private bool Remember(string id)
    {
        if (!_seen.Add(id)) return false;
        _order.Enqueue(id);
        if (_order.Count > 256) _seen.Remove(_order.Dequeue());
        return true;
    }
}
