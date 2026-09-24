namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Reminders;

public sealed partial class NativeInformationOverlayRuntime : IContinuousPlayReminderSink
{
    public async ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellation.ThrowIfCancellationRequested();
            if (_disposed || !notice.IsCurrent() || _window is not { IsVisible: true } window ||
                _workspace is not { } workspace || !workspace.Settings.ShowEventNotifications ||
                !workspace.Settings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder)) return false;
            var language = workspace.Language;
            var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            var traditional = language is "zh-TW" or "zh-Hant";
            var minutes = Math.Max(0, (long)notice.Duration.TotalMinutes);
            var copy = LocalPlayReminderCopyCatalog.Pick(zh);
            var title = traditional ? $"你已連續遊玩 {minutes} 分鐘" : zh ? $"你已连续游玩 {minutes} 分钟"
                : $"You have been playing for {minutes} minutes";
            var detail = traditional ? "休息一下，活動身體，也讓眼睛放鬆。" : copy.Detail;
            window.QueueGameEventNotification(OverlayEventNotificationTypes.LocalPlayReminder,
                title, detail, important: false, positive: true);
            return true; // Submitted to WPF's existing queue, not proof of a rendered frame.
        }, DispatcherPriority.Send, cancellation);
        return await operation.Task.WaitAsync(cancellation).ConfigureAwait(false);
    }
}
