namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Events;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Privacy;

public sealed partial class NativeInformationOverlayRuntime : ISharedActivitySink
{
    public async ValueTask<bool> TryPresentActivityAsync(SharedActivityNotice notice, CancellationToken token)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            token.ThrowIfCancellationRequested();
            if (_disposed || !notice.IsCurrent() || _window is not { IsVisible: true } window ||
                _workspace is not { } workspace || !workspace.Settings.ShowEventNotifications) return false;
            var type = SharedActivityEvent.Category(notice.Event.Type) switch
            {
                SharedActivityEventTypes.Presence => OverlayEventNotificationTypes.MemberPresence,
                SharedActivityEventTypes.Server => OverlayEventNotificationTypes.MemberServer,
                SharedActivityEventTypes.Ship => OverlayEventNotificationTypes.ShipChange,
                SharedActivityEventTypes.Location => OverlayEventNotificationTypes.LocationChange,
                SharedActivityEventTypes.Life => OverlayEventNotificationTypes.DeathAndRespawn,
                _ => OverlayEventNotificationTypes.None
            };
            if (type == 0 || !workspace.Settings.EventNotificationTypes.HasFlag(type)) return false;
            var zh = workspace.Language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            var traditional = workspace.Language is "zh-TW" or "zh-Hant";
            var copy = notice.Event.Type switch
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
            window.QueueGameEventNotification(type, notice.Callsign, traditional ? copy.Item2 : zh ? copy.Item1 : copy.Item3,
                important: false, positive: notice.Event.Type is "PlayerRevived" or "PlayerRespawned", isCurrent: notice.IsCurrent);
            return true;
        }, DispatcherPriority.Send, token);
        return await operation.Task.WaitAsync(token).ConfigureAwait(false);
    }
}
