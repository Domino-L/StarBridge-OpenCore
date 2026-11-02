using System.Windows.Threading;

namespace StarBridge.Desktop;

/// <summary>A main-fleet rally held in the top notice slot. Copy is localized by the
/// runtime; only the minutes left are computed per frame.</summary>
internal sealed record OverlayRallySlot(Guid Id, string Title, string Body, string Hint,
    string ActiveLabel, DateTimeOffset ExpiresAt, bool Chinese, bool Traditional);

internal sealed partial class OverlayCompositionHudWindow
{
    private static readonly HudColor NoticeRallyAccent = HudColor.FromRgb(242, 179, 91);
    private OverlayRallySlot? _rally;
    private DispatcherTimer? _rallyClock;

    internal bool ShowRally(OverlayRallySlot rally)
    {
        if (_disposed) return false;
        _rally = rally;
        // Only the "minutes left" text changes while a rally holds the slot.
        _rallyClock ??= new DispatcherTimer(TimeSpan.FromSeconds(20), DispatcherPriority.Background,
            (_, _) => RefreshRally(), Dispatcher.CurrentDispatcher);
        _rallyClock.Start();
        PublishStateToRenderer(forceEventPulse: false);
        return true;
    }

    internal void ClearRally(Guid id)
    {
        if (_rally?.Id != id) return;
        _rally = null;
        _rallyClock?.Stop();
        if (!_disposed) PublishStateToRenderer(forceEventPulse: false);
    }

    private void RefreshRally()
    {
        if (_disposed || _rally is null || DateTimeOffset.UtcNow >= _rally.ExpiresAt)
        {
            _rally = null;
            _rallyClock?.Stop();
        }
        if (!_disposed) PublishStateToRenderer(forceEventPulse: false);
    }

    // Render thread only: the announcement in the frame being drawn that still waits to reach
    // the screen. A frame drawn and committed in full view confirms it; a window that never
    // draws never does. While the content is still fading in, or calm display dims the slot,
    // it keeps waiting and a later frame (the countdown redraws every second) confirms it.
    private (string Key, string Receipt)? _announcementOnScreen;

    private void ConfirmAnnouncementOnScreen()
    {
        if (_announcementOnScreen is not { } shown || _state is not { } state) return;
        if (IsContentRevealActive() || ReadAppearanceAnimationState().StartupActive || CalmFactor(state.NoticeRect) < 0.5) return;
        _announcementOnScreen = null;
        OverlayViewModel.ConfirmAnnouncementShown(shown.Key, shown.Receipt);
    }

    // One slot that never grows. A running rally holds it; a newer notice may borrow it
    // for its few seconds and shows the rally as a side mark. Otherwise queued notices
    // show "+N". When the countdown ends the slot closes; nothing stays behind.
    private OverlayCompositionFrameState ApplyNoticeSlot(OverlayCompositionFrameState state) =>
        ApplyNoticeSlot(state, _rally, _viewModel.NoticeItemActive, _viewModel.NoticeQueueCount, DateTimeOffset.UtcNow);

    private static OverlayCompositionFrameState ApplyNoticeSlot(OverlayCompositionFrameState state,
        OverlayRallySlot? rally, bool itemActive, int queued, DateTimeOffset now)
    {
        if (rally is not null && now >= rally.ExpiresAt) rally = null;
        var item = state.ShowNotice && itemActive;
        if (rally is not null)
        {
            var left = RallyRemaining(rally, now);
            var more = queued > 0 ? $"+{queued} · " : "";
            if (item) return state with { NoticeMeta = $"{more}■ {rally.ActiveLabel} · {left}", NoticeMetaAccent = true };
            // The rally has its own switch: it shows even with the notice module off.
            return state with
            {
                ShowNotice = true, FleetNoticeTitle = rally.Title, FleetNotice = rally.Body,
                NoticeTimerLabel = left, NoticeAccent = true, NoticeMeta = more + rally.Hint,
                EmptyStates = state.EmptyStates with { Notice = null },
                SourceLabels = state.SourceLabels with { Notice = null }
            };
        }
        return item && queued > 0 ? state with { NoticeMeta = $"+{queued}" } : state;
    }

    internal static string RallyRemaining(OverlayRallySlot rally, DateTimeOffset now)
    {
        var minutes = Math.Max(1, (int)Math.Ceiling((rally.ExpiresAt - now).TotalMinutes));
        return rally.Traditional ? $"剩餘 {minutes} 分鐘" : rally.Chinese ? $"剩余 {minutes} 分钟" : $"{minutes} min left";
    }
}
