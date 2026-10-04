namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Reminders;

public sealed partial class NativeInformationOverlayRuntime : IContinuousPlayReminderSink
{
    private int _lastContinuousPlayCopyIndex = -1;
    public async ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellation.ThrowIfCancellationRequested();
            if (_disposed || _window is not { } window || _workspace is not { } workspace) return false;
            return TryQueueContinuousPlay(notice, workspace.Settings, window.IsVisible, workspace.Language,
                (type, title, detail, important, positive, current, deviceLocal) =>
                    window.QueueGameEventNotification(type, title, detail, important, positive, current, isDeviceLocal: deviceLocal),
                previousIndex: _lastContinuousPlayCopyIndex, selected: index => _lastContinuousPlayCopyIndex = index);
        }, DispatcherPriority.Send, cancellation);
        return await operation.Task.WaitAsync(cancellation).ConfigureAwait(false);
    }

    // The same dispatch boundary can be exercised without opening a native window.
    internal static bool TryQueueContinuousPlay(ContinuousPlayNotice notice, OverlayDisplaySettings settings,
        bool visible, string language,
        Action<OverlayEventNotificationTypes, string, string, bool, bool, Func<bool>?, bool> queue,
        DateTimeOffset? localNow = null, Random? random = null, int previousIndex = -1, Action<int>? selected = null)
    {
        if (!notice.IsCurrent() || !visible || !settings.ShowEventNotifications ||
            !settings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder)) return false;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-TW" or "zh-Hant" or "zh-HK";
        var minutes = Math.Max(0, (long)notice.Duration.TotalMinutes);
        var copy = LocalPlayReminderCopyCatalog.Pick(zh, localNow ?? DateTimeOffset.Now, notice.Duration, previousIndex, random);
        if (traditional) copy = LocalPlayReminderCopyCatalog.ToTraditional(copy, localNow ?? DateTimeOffset.Now);
        var title = traditional ? $"你已連續遊玩 {minutes} 分鐘，{copy.Title}" : zh ? $"你已连续游玩 {minutes} 分钟，{copy.Title}"
            : $"You have been playing for {minutes} minutes — {copy.Title}";
        queue(OverlayEventNotificationTypes.LocalPlayReminder, title, copy.Detail, false, true, notice.IsCurrent, true);
        selected?.Invoke(copy.Index);
        return true; // Submitted to WPF's existing queue, not proof of a rendered frame.
    }
}
