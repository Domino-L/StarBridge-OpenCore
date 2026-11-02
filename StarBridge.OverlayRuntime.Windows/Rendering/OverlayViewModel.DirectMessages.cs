namespace StarBridge.Desktop;

using System.Windows.Media;

public sealed partial class OverlayViewModel
{
    // Barrage rows of the chat channel are revoked by source; a direct message line is not
    // a chat-channel row, so it carries its own key and only its own reminder clears it.
    internal const string DirectMessageRowKey = "\u0001direct-message";
    private static readonly Brush DirectMessageAccent = CreateDirectMessageAccent();
    private (Guid Id, OverlayEventNotificationRow Row)? _directMessageRow;

    /// <summary>One purple barrage line for a new direct message, flying once.</summary>
    internal bool TryShowDirectMessageBarrage(Guid id, string title, string detail)
    {
        if (_chatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage) return false;
        if (_directMessageRow is { } previous) ClearDirectMessageBarrage(previous.Id);
        var now = DateTimeOffset.Now;
        var row = new OverlayEventNotificationRow(title, detail, "", DirectMessageAccent,
            now.AddSeconds(_chatDurationSeconds), OverlayEventNotificationTypes.None) { ChatSourceKey = DirectMessageRowKey };
        var lane = ResolveAvailableChatBarrageLane();
        if (_animationFrameRate == OverlayAnimationFrameRate.Off && !PreserveBarrageMotion) row.SetBarrageLane(lane);
        else row.BeginBarrage(now, ResolveChatBarrageDuration(row, _chatSettings), lane);
        ChatMessages.Add(row);
        _directMessageRow = (id, row);
        ChatPulse++;
        OnChanged(nameof(ChatVisibility));
        return true;
    }

    internal void ClearDirectMessageBarrage(Guid id)
    {
        if (_directMessageRow is not { } held || held.Id != id) return;
        _directMessageRow = null;
        if (!ChatMessages.Remove(held.Row)) return;
        ChatPulse++;
        OnChanged(nameof(ChatVisibility));
    }

    private static Brush CreateDirectMessageAccent()
    {
        var brush = new SolidColorBrush(Color.FromRgb(190, 150, 255));
        brush.Freeze();
        return brush;
    }
}
