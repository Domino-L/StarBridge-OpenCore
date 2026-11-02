namespace StarBridge.Desktop;

using System.Windows.Threading;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    // A room reminder holds the top slot; a direct message flies as its own barrage line.
    // Each keeps its own state so one never hides the other from preview revocation.
    private InformationOverlayReminder? _activeReminder;
    private InformationOverlayReminder? _activeDirectMessage;
    private bool _activeDirectMessageIncludesPreview;

    public async ValueTask<bool> TryPresentAsync(InformationOverlayReminder reminder, CancellationToken cancellationToken)
    {
        var dispatcher = _dispatcher;
        if (_disposed || dispatcher is null || dispatcher.HasShutdownStarted) return false;
        var operation = dispatcher.InvokeAsync(() =>
        {
            cancellationToken.ThrowIfCancellationRequested();
            // A rally holds the top slot until answered or over, open overlay or not.
            if (reminder.Rally != null) return PresentRallyOnControlThread(reminder);
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
            // Direct messages stay out of the top slot: a barrage line, or the unread mark.
            if (reminder.DirectMessage != null)
            {
                var (line, text) = DirectMessageBarrageCopy(reminder, language, _workspace.Settings.CommunicationMessagePreview);
                if (!window.ShowDirectMessage(reminder.Id, line, text)) return false;
                _activeDirectMessage = reminder;
                _activeDirectMessageIncludesPreview = reminder.DirectMessage is { Text.Length: > 0 } &&
                    reminder.Preview == "fullContent" && _workspace.Settings.CommunicationMessagePreview;
                return true;
            }
            if (!window.TryShowLiveCommunicationEvent(reminder.Id, title, detail)) return false;
            _activeReminder = reminder;
            return true;
        }, DispatcherPriority.Send, cancellationToken);
        return await operation.Task.WaitAsync(cancellationToken).ConfigureAwait(false);
    }

    internal static bool CanPresentReminder(InformationOverlayReminder reminder,
        StarBridge.Core.Overlay.OverlayDisplaySettings settings, bool gameForeground, bool visible) =>
        reminder.IsCurrent() && gameForeground && visible && (reminder.DirectMessage != null || settings.ShowNotice) &&
        (reminder.DirectMessage == null || settings.CommunicationFriendEvents);

    // The barrage line: the sender only, unless both preview switches allow the text.
    internal static (string Title, string Detail) DirectMessageBarrageCopy(
        InformationOverlayReminder reminder, string language, bool includeMessagePreview)
    {
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language is "zh-Hant" or "zh-TW";
        if (reminder.Preview == "hiddenDetails")
            return ("✉ StarBridge", zh ? "你有新的提醒" : "You have a new notification");
        var message = reminder.DirectMessage!;
        if (message.Conversations != 1 || string.IsNullOrWhiteSpace(message.Callsign))
            return (traditional ? "✉ 私訊" : zh ? "✉ 私信" : "✉ Direct messages",
                traditional ? $"{message.Conversations} 個對話有新私訊" : zh ? $"{message.Conversations} 个会话有新私信" : $"New messages in {message.Conversations} conversations");
        var detail = includeMessagePreview && reminder.Preview == "fullContent" && !string.IsNullOrWhiteSpace(message.Text)
            ? message.Text : traditional ? "發來新的私訊" : zh ? "发来新的私信" : "sent you a direct message";
        return ("✉ " + message.Callsign, detail);
    }

    public void ClearReminder()
    {
        var dispatcher = _dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished) return;
        // Never wait while the settings owner is holding its lock.
        dispatcher.BeginInvoke(ClearReminderOnControlThread, DispatcherPriority.Send);
    }

    // The Host's clear covers everything the overlay shows for it.
    private void ClearReminderOnControlThread()
    {
        ClearRoomReminder();
        ClearDirectMessageReminder();
    }

    private void ClearRoomReminder()
    {
        if (_activeReminder is not { } reminder) return;
        _activeReminder = null;
        _window?.ClearLiveCommunicationEvent(reminder.Id);
    }

    private void ClearDirectMessageReminder()
    {
        if (_activeDirectMessage is not { } reminder) return;
        _activeDirectMessage = null;
        _activeDirectMessageIncludesPreview = false;
        _window?.ClearDirectMessage(reminder.Id);
    }

    private void ValidateReminder(bool gameForeground)
    {
        if (_activeReminder is { } reminder && (!gameForeground || !reminder.IsCurrent() || _workspace?.Settings.ShowNotice != true))
            ClearRoomReminder();
        if (_activeDirectMessage is { } message && (!gameForeground || !message.IsCurrent()))
            ClearDirectMessageReminder();
        RevokeReminderPreview();
    }

    private void RevokeReminderPreview()
    {
        if (_activeDirectMessage is not null && (_workspace?.Settings.CommunicationFriendEvents != true ||
            _activeDirectMessageIncludesPreview && _workspace?.Settings.CommunicationMessagePreview != true))
            ClearDirectMessageReminder();
    }
}
