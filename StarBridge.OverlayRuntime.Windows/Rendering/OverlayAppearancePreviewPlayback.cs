using System.Diagnostics;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    internal void PrepareQuietPreviewExamples()
    {
        // A moving barrage is the content's reading mode, not an ornament.
        // Preview reduction still makes notice/event/decorative motion static.
        // This session-only policy never changes normal Open or saved settings.
        _viewModel.PreserveBarrageMotion = true;
        _viewModel.ClearAuthorizedContent();
    }
    internal void UpdatePreviewBarrageFrameRate(OverlayAnimationFrameRate frameRate) =>
        _viewModel.PreviewBarrageFrameRate = frameRate;
    internal IReadOnlyList<OverlayAppearancePlacementState> ReadPreviewPlacementStates()
    {
        List<OverlayAppearancePlacementState> states = [];
        CollectExtendedPreviewPlacementStates(BuildFrameState(), states);
        return states.ToArray();
    }
    partial void CollectExtendedPreviewPlacementStates(OverlayCompositionFrameState state, List<OverlayAppearancePlacementState> states);
    // Called only by the temporary appearance-preview surface. All content is owned
    // finite examples; the same real ViewModel handles entrance, retention,
    // upward departure, restacking and Off/reduced-motion completion.
    internal (int Count, bool Moving) PreviewEventState =>
        (_viewModel.EventNotifications.Count, _viewModel.HasActiveEventNotificationMotion);
    internal void RetainPreviewExamplesForSequence() =>
        _viewModel.HoldEventNotificationsForStartupReveal(8000);
}

internal sealed partial class OverlayAppearancePreviewSurface
{
    private sealed class ExampleLease { internal bool Current = true; }
    private readonly List<ExampleLease> _events = [];
    private Guid? _notice;
    private DispatcherTimer? _exampleSequence;
    private int _examplePhase;
    private long _exampleWaitUntil;
    private long _exampleDeadline;

    internal bool Play(OverlayAppearancePreviewPlayback action)
    {
        VerifyAlive();
        if (!Enum.IsDefined(action)) throw new ArgumentOutOfRangeException(nameof(action));
        // A direct action interrupts the finite automatic demonstration, never
        // queues another sequence or a future pet pose behind the current one.
        StopExampleSequence();
        if (action != OverlayAppearancePreviewPlayback.Transition) StopPreviewTransition();
        switch (action)
        {
            case OverlayAppearancePreviewPlayback.Transition:
                return StartPreviewTransition();
            case OverlayAppearancePreviewPlayback.NoticeShow:
                if (!_frame.Settings.ShowNotice) return false;
                if (_notice is { } old) _hud.ClearLiveCommunicationEvent(old);
                var id = Guid.NewGuid();
                var zh = _frame.Language.StartsWith("zh", StringComparison.Ordinal);
                if (!_hud.TryShowLiveCommunicationEvent(id, zh ? "公告 · 预览示例" : "Notice · preview example",
                    zh ? "这是一条示例公告，不是实际舰队消息。" : "Example announcement, not a real fleet message.")) return false;
                _notice = id;
                return true;
            case OverlayAppearancePreviewPlayback.NoticeHide:
                if (_notice is { } notice) _hud.ClearLiveCommunicationEvent(notice);
                _notice = null;
                return true;
            case OverlayAppearancePreviewPlayback.EventAdd:
                return AddPreviewEvent();
            case OverlayAppearancePreviewPlayback.EventHide:
                InvalidatePreviewEvents();
                return true;
            case OverlayAppearancePreviewPlayback.EventSequence:
                if (!_frame.Settings.ShowEventNotifications || _frame.Settings.EventNotificationMaxVisibleCount < 2 ||
                    _frame.Settings.EventNotificationTypes == OverlayEventNotificationTypes.None ||
                    _frame.Settings.AnimationFrameRate == OverlayAnimationFrameRate.Off) return false;
                InvalidatePreviewEvents();
                _examplePhase = 0;
                _exampleDeadline = Stopwatch.GetTimestamp() + 30 * Stopwatch.Frequency;
                _exampleSequence = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
                _exampleSequence.Tick += (_, _) => AdvanceExampleSequence();
                _exampleSequence.Start();
                return true;
            case OverlayAppearancePreviewPlayback.Barrage:
                if (!_frame.Settings.ShowChat || _frame.Settings.ChatDisplayMode != OverlayChatDisplayMode.FullScreenBarrage) return false;
                PublishExample(OverlayAppearancePreviewExample.Barrage);
                return true;
            case OverlayAppearancePreviewPlayback.Stop:
                InvalidatePreviewEvents();
                if (_notice is { } active) _hud.ClearLiveCommunicationEvent(active);
                _notice = null;
                return true;
            default: return false;
        }
    }

    private bool AddPreviewEvent(bool retain = false)
    {
        if (!_frame.Settings.ShowEventNotifications || _frame.Settings.EventNotificationTypes == OverlayEventNotificationTypes.None || _events.Count >= 64) return false;
        var type = Enum.GetValues<OverlayEventNotificationTypes>().First(value =>
            value != OverlayEventNotificationTypes.None && value != OverlayEventNotificationTypes.All &&
            _frame.Settings.EventNotificationTypes.HasFlag(value));
        var lease = new ExampleLease();
        _events.Add(lease);
        var number = ++_sequence;
        var zh = _frame.Language.StartsWith("zh", StringComparison.Ordinal);
        _hud.QueueGameEventNotification(type, zh ? $"事件 {number} · 预览示例" : $"Event {number} · preview example",
            zh ? "示例状态变化；使用正常进场与退场顺序。" : "Example state change; normal entrance and departure order.",
            false, number % 2 != 0, () => lease.Current && !_disposed);
        if (retain) _hud.RetainPreviewExamplesForSequence(); // Finite example readability, not a pet-clock override.
        return true;
    }
    private void InvalidatePreviewEvents()
    {
        foreach (var lease in _events) lease.Current = false;
        _events.Clear();
    }
    private void StopExampleSequence()
    {
        _exampleSequence?.Stop(); _exampleSequence = null;
        _exampleWaitUntil = 0;
    }
    private void AdvanceExampleSequence()
    {
        if (_disposed || Stopwatch.GetTimestamp() >= _exampleDeadline) { StopExampleSequence(); InvalidatePreviewEvents(); return; }
        var (count, moving) = _hud.PreviewEventState;
        var expected = _examplePhase switch { 0 => 0, 1 or 3 or 5 => 1, _ => 2 };
        if (moving || count != expected) { _exampleWaitUntil = 0; return; }
        if (_exampleWaitUntil == 0)
        {
            _exampleWaitUntil = Stopwatch.GetTimestamp() + (long)(.65 * Stopwatch.Frequency);
            return;
        }
        if (Stopwatch.GetTimestamp() < _exampleWaitUntil) return;
        _exampleWaitUntil = 0;
        switch (_examplePhase++)
        {
            case 0: case 1: case 3:
                AddPreviewEvent(retain: true);
                break;
            case 2: case 4:
                // Invalidate only the oldest example; the normal VM animates
                // its exit upward and returns the surviving new row to slot 1.
                _events[0].Current = false; _events.RemoveAt(0);
                break;
            default: StopExampleSequence(); break;
        }
    }
}
