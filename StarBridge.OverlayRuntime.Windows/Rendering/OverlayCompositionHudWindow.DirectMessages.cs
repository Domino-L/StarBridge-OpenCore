using Vortice.Direct2D1;

namespace StarBridge.Desktop;

// Direct messages never take the top notice slot. A new one flies once as a purple
// barrage line in barrage mode; unread ones stay as a small mark: on the chat title
// when the chat list shows, otherwise beside the top slot (alone if the slot is hidden).
internal sealed partial class OverlayCompositionHudWindow
{
    private static readonly HudColor DirectMessageMarkColor = HudColor.FromRgb(190, 150, 255);
    private string? _directUnread;

    internal void SetDirectUnread(string? mark)
    {
        if (_disposed || _directUnread == mark) return;
        _directUnread = mark;
        PublishStateToRenderer(forceEventPulse: false);
    }

    // True when the overlay carries it: a barrage line now, or the unread mark in list mode.
    internal bool ShowDirectMessage(Guid id, string title, string detail)
    {
        if (_disposed) return false;
        if (_viewModel.ChatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage || !_settings.ShowChat) return true;
        if (!_viewModel.TryShowDirectMessageBarrage(id, title, detail)) return false;
        PublishStateToRenderer(forceEventPulse: false);
        return true;
    }

    internal void ClearDirectMessage(Guid id)
    {
        if (_disposed) return;
        _viewModel.ClearDirectMessageBarrage(id);
        PublishStateToRenderer(forceEventPulse: false);
    }

    private OverlayCompositionFrameState ApplyDirectMessages(OverlayCompositionFrameState state) =>
        ApplyDirectMessages(state, _directUnread);

    private static OverlayCompositionFrameState ApplyDirectMessages(OverlayCompositionFrameState state, string? mark) =>
        mark is null ? state
            : state.ShowChat && state.ChatDisplayMode == OverlayChatDisplayMode.MessageList
                ? state with { ChatUnread = mark }
                : state with { NoticeUnread = mark };

    private void DrawScene(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        DrawSceneModules(target, state);
        if (state.ChatUnread is { } chat)
        {
            var rect = state.ChatRect;
            var right = (float)rect.Right - 28;
            var top = (float)rect.Y + (state.NightShadowStyle ? 18 : 14);
            DrawDirectMessageMark(target, state, chat, right - DirectMessageMarkWidth(chat), top - 2);
        }
        if (state.NoticeUnread is { } notice)
        {
            var rect = state.NoticeRect;
            var width = DirectMessageMarkWidth(notice);
            var x = rect.Right + 10 + width <= state.Width ? (float)rect.Right + 10 : (float)rect.X - 10 - width;
            DrawDirectMessageMark(target, state, notice, x, (float)rect.Y + 12);
        }
    }

    private float DirectMessageMarkWidth(string mark) => MeasureTextWidth(mark, _eventTitleFormat, 40) + 16;

    private void DrawDirectMessageMark(ID2D1RenderTarget target, OverlayCompositionFrameState state, string mark, float x, float y)
    {
        var width = DirectMessageMarkWidth(mark);
        FillRect(target, x, y, width, 20, HudColor.FromRgb(8, 10, 18), state.Opacity * 0.62);
        DrawRectangle(target, x + 0.5f, y + 0.5f, width - 1, 19, DirectMessageMarkColor, state.Opacity * 0.7, 1);
        DrawText(target, mark, _eventTitleFormat, x + 8, y + 2, width - 12, 18, DirectMessageMarkColor, state.Opacity);
    }
}
