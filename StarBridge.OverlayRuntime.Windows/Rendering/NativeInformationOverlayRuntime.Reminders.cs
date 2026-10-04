namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    private InformationOverlayReminder? _activeReminder;
    private bool _activeReminderIncludesPreview;

    public async ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken cancellationToken)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            if (_disposed || _workspace is null || _window is not { IsVisible: true } window ||
                !CanPresentReminder(reminder, _workspace.Settings, StarCitizenProcessProbe.IsForeground(), true)) return false;
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
            if (reminder.DirectMessage != null)
            {
                (title, detail) = DirectMessageReminderCopy(reminder, language, _workspace.Settings.CommunicationMessagePreview);
            }
            if (!window.TryShowLiveCommunicationEvent(reminder.Id, title, detail)) return false;
            _activeReminder = reminder;
            _activeReminderIncludesPreview = reminder.DirectMessage is { Text.Length: > 0 } &&
                reminder.Preview == "fullContent" && _workspace.Settings.CommunicationMessagePreview;
            return true;
        }, DispatcherPriority.Send, cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    internal static bool CanPresentReminder(InformationOverlayReminder reminder,
        StarBridge.Core.Overlay.OverlayDisplaySettings settings, bool gameForeground, bool visible) =>
        reminder.IsCurrent() && gameForeground && visible && settings.ShowNotice &&
        (reminder.DirectMessage == null || settings.CommunicationFriendEvents);

    internal static (string Title, string Detail) DirectMessageReminderCopy(
        InformationOverlayReminder reminder, string language, bool includeMessagePreview)
    {
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        if (reminder.Preview == "hiddenDetails")
            return ("StarBridge", zh ? "你有新的提醒" : "You have a new notification");
        var message = reminder.DirectMessage!;
        var title = traditional ? "新的私訊" : zh ? "新的私信" : "New direct message";
        var detail = message.Conversations != 1 || string.IsNullOrWhiteSpace(message.Callsign)
            ? traditional ? $"{message.Conversations} 個對話有新私訊" : zh ? $"{message.Conversations} 个会话有新私信" : $"New messages in {message.Conversations} conversations"
            : traditional ? $"{message.Callsign} 發來新的私訊" : zh ? $"{message.Callsign} 发来新的私信" : $"New message from {message.Callsign}";
        if (includeMessagePreview && reminder.Preview == "fullContent" && !string.IsNullOrWhiteSpace(message.Text))
            detail += " · " + message.Text;
        return (title, detail);
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
        _activeReminderIncludesPreview = false;
        _window?.ClearLiveCommunicationEvent(reminder.Id);
    }

    private void ValidateReminder(bool gameForeground)
    {
        if (_activeReminder is { } reminder &&
            (!gameForeground || !reminder.IsCurrent() || _workspace?.Settings.ShowNotice != true))
            ClearReminderOnControlThread();
        else if (_activeReminder?.DirectMessage != null && _workspace?.Settings.CommunicationFriendEvents != true)
            ClearReminderOnControlThread();
        else if (_activeReminderIncludesPreview && _workspace?.Settings.CommunicationMessagePreview != true)
            ClearReminderOnControlThread();
    }
}
