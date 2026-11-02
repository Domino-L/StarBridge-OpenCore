using StarBridge.HostRuntime.Tools;

namespace StarBridge.HostRuntime.Notifications;

public sealed partial class NotificationSettingsBridgeDispatcher
{
    public async ValueTask<string> PresentExecHangarAsync(ExecHangarDelivery delivery,
        Func<bool> environmentAllows, CancellationToken token)
    {
        DesktopNotification notice;
        lock (_gate) {
            if (_disposed || !delivery.IsCurrent()) return "expired";
            if (!environmentAllows()) return desktopSuppressionReason is null ? "suppressed" : HangarDeliveryState(DesktopSuppressionReason());
            var settings = Read();
            if (!settings.WindowsEnabled || desktop == null) return "windowsDisabled";
            var id = Guid.NewGuid(); var item = delivery.Notices[0];
            bool Current() {
                lock (_gate) {
                    try { return !_disposed && delivery.IsCurrent() && Read().WindowsEnabled && environmentAllows(); }
                    catch { return false; }
                }
            }
            notice = CreateDesktop(id, false, 0, 0, settings, Current) with {
                BackgroundOnly = false,
                PresentUntil = DateTimeOffset.UtcNow.AddSeconds(30),
                Activated = () => Activate(id, Current, "execHangar"),
                ExecHangar = new(item.Opening, delivery.Notices.Any(n => n.Kind is "open" or "close"), item.Boundary,
                    delivery.Config, delivery.MonitoringEndsAt, delivery.Mute,
                    delivery.Notices.Any(n => n.Kind == "leave"), delivery.Test)
            };
        }
        var result = await desktop.TryPresentDetailedAsync(notice, token);
        return result.Submitted ? "submitted" : HangarDeliveryState(result.Reason);
    }
    private static string HangarDeliveryState(string reason) => reason switch {
        "doNotDisturb" or "fullScreen" or "inactiveDesktop" or "quietTime" or "systemBusy" or "queueFull" or "expired" => reason,
        "environmentUnknown" or "gameActiveOrUnknown" or "appActiveOrUnknown" => "environmentUnknown",
        "unavailable" or "unsupported" => "desktopUnavailable",
        _ => "suppressed"
    };
}
