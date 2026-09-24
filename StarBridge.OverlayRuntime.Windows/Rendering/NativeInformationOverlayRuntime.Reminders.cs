namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    private InformationOverlayReminder? _activeReminder;

    public async ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken cancellationToken)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || !reminder.IsCurrent() || !StarCitizenProcessProbe.IsForeground() ||
                _window is not { IsVisible: true } window || _workspace?.Settings.ShowNotice != true) return false;
            var language = _workspace.Language;
            var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
            var traditional = language.Equals("zh-TW", StringComparison.OrdinalIgnoreCase) ||
                language.Equals("zh-Hant", StringComparison.OrdinalIgnoreCase);
            var hidden = reminder.Preview == "hiddenDetails";
            var title = hidden ? "StarBridge" : traditional ? "房間提醒" : zh ? "房间提醒" : "Room reminder";
            var detail = hidden ? (traditional ? "你有新的提醒" : zh ? "你有新的提醒" : "You have a new notification")
                : reminder.Preview != "fullContent" ? (traditional ? "有新的房間邀請或加入申請" : zh ? "有新的房间邀请或加入申请" : "New room invitations or join requests")
                : traditional ? $"新邀請 {reminder.Invitations} · 新加入申請 {reminder.Applications}"
                : zh ? $"新邀请 {reminder.Invitations} · 新加入申请 {reminder.Applications}"
                : $"New invitations: {reminder.Invitations} · Join requests: {reminder.Applications}";
            if (!window.TryShowLiveCommunicationEvent(reminder.Id, title, detail)) return false;
            _activeReminder = reminder;
            return true;
        }, DispatcherPriority.Send, cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    public void ClearReminder()
    {
        var dispatcher = _dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        // Never wait while the settings owner is holding its lock.
        dispatcher.BeginInvoke(ClearReminderOnControlThread, DispatcherPriority.Send);
    }

    private void ClearReminderOnControlThread()
    {
        if (_activeReminder is not { } reminder) return;
        _activeReminder = null;
        _window?.ClearLiveCommunicationEvent(reminder.Id);
    }

    private void ValidateReminder(bool gameForeground)
    {
        if (_activeReminder is { } reminder &&
            (!gameForeground || !reminder.IsCurrent() || _workspace?.Settings.ShowNotice != true))
            ClearReminderOnControlThread();
    }
}
