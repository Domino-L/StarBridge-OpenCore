using System.Diagnostics;
using System.Windows.Threading;
using StarBridge.Core.Overlay;
using Vortice.DirectComposition;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private bool _previewContentHidden;
    internal bool PreviewContentHidden => PreviewRender(() => _previewContentHidden);
    private void SetPreviewContentVisible(bool visible) => PreviewRender(() =>
    {
        if (visible) _rootVisual!.SetEffect(null).CheckError();
        else
        {
            _compositionDevice!.CreateEffectGroup(out var effect).CheckError();
            using (effect)
            {
                effect.SetOpacity(0).CheckError();
                _rootVisual!.SetEffect(effect).CheckError();
            } // Visual retains its COM reference until detached, including HUD dispose.
        }
        _compositionDevice!.Commit().CheckError();
        _previewContentHidden = !visible;
    });
    // Preview replays the SAME installed startup entry points on the existing
    // real surface. No new skin timeline, normalized miniature or pet reset.
    // All renderer mutations/fences below run on its owning render dispatcher.
    internal double BeginPreviewStartup()
    {
        if (_disposed || _settings.AnimationFrameRate == OverlayAnimationFrameRate.Off || !UiMotion.IsEnabled)
            return 0;
        StopPreviewStartup();
        SetPreviewContentVisible(false);
        var settings = _settings;
        try
        {
            _settings = settings with { EnableStartupTransition = true, AutoFocusGameWindowOnOpen = false };
            BeginAppearanceStartup(out var installed, out var duration);
            _deferEventNotificationsUntilContentRevealCompletes = true;
            if (installed)
            {
                _viewModel.HoldEventNotificationsForStartupReveal(duration + 1000);
                PublishStateToRenderer(forceEventPulse: false);
                // Publish and first installed draw must commit before exposing
                // the HUD region: never show the old modules before startup.
                SetPreviewContentVisible(true);
                ScheduleEventRevealAfter(duration + 90);
                return duration + 120;
            }
            if (!TryStartStartupTransition()) { StopPreviewStartup(); return 0; }
            duration = Math.Max(OverlayStartupTransitionLayer.DurationMs + 90,
                OverlayCompositionStartupTransitionWindow.ProgressCompleteFadeStartMs + ContentRevealMs + ContentRevealMaxDelayMs + 90);
            _viewModel.HoldEventNotificationsForStartupReveal(duration + 1000);
            PublishStateToRenderer(forceEventPulse: false);
            // The normal terminal cover is an internal, input-transparent HWND,
            // NOT a second user-operated preview carrier. Until its normal
            // handoff all module drawing (including installed pet) stays hidden.
            var timer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(OverlayCompositionStartupTransitionWindow.ProgressCompleteFadeStartMs) };
            _initialRevealTimer = timer;
            timer.Tick += (_, _) =>
            {
                timer.Stop();
                if (_disposed || !ReferenceEquals(_initialRevealTimer, timer)) return;
                _initialRevealTimer = null;
                BeginContentReveal(delayEventReveal: true);
                SetPreviewContentVisible(true);
            };
            timer.Start();
            return duration;
        }
        catch { StopPreviewStartup(); throw; }
        finally { _settings = settings; } // Presentation only; frame/settings/save never enable startup.
    }

    internal bool PreviewStartupActive => PreviewRender(() => ReadAppearanceAnimationState().StartupActive);
    internal void StopPreviewStartup()
    {
        _initialRevealTimer?.Stop(); _initialRevealTimer = null;
        _delayedEventRevealTimer?.Stop(); _delayedEventRevealTimer = null;
        StopStartupCover();
        _deferEventNotificationsUntilContentRevealCompletes = false;
        if (_disposed) return;
        PreviewRender(() =>
        {
            _contentRevealStartedAtUtc = DateTimeOffset.MinValue;
#if STARBRIDGE_VERDICT_NEXT
            _verdictNextStartupPending = false;
            _verdictNextStartupAt = DateTimeOffset.MinValue;
            Interlocked.Exchange(ref _verdictNextStartupUtcTicks, 0);
#endif
        });
        PublishStateToRenderer(forceEventPulse: false);
        PreviewRender(() => { }); // Final frame before the owner can release protection.
        SetPreviewContentVisible(true);
    }
    private void PreviewRender(Action action) => PreviewRender(() => { action(); return true; });
    private T PreviewRender<T>(Func<T> action)
    {
        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
            throw new InvalidOperationException("Preview renderer unavailable.");
        return dispatcher.Invoke(action, DispatcherPriority.Render);
    }
}

internal sealed partial class OverlayAppearancePreviewSurface
{
    private DispatcherTimer? _previewTransition;
    private long _previewTransitionEnd;
    private long _previewTransitionLimit;
    internal bool TransitionPlaying => _previewTransition is not null;
    internal event Action? TransitionStateChanged;

    private bool StartPreviewTransition()
    {
        if (_frame.Settings.AnimationFrameRate == OverlayAnimationFrameRate.Off || !UiMotion.IsEnabled) return false;
        StopPreviewTransition();
        var duration = _hud.BeginPreviewStartup();
        if (duration <= 0) return false;
        _previewTransitionEnd = Stopwatch.GetTimestamp() + (long)(duration / 1000 * Stopwatch.Frequency);
        _previewTransitionLimit = Stopwatch.GetTimestamp() + 12 * Stopwatch.Frequency;
        _previewTransition = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(40) };
        _previewTransition.Tick += (_, _) =>
        {
            // An installed renderer starts on its first committed frame; don't
            // clip its tail if a slow render delays that first frame.
            if (!UiMotion.IsEnabled || Stopwatch.GetTimestamp() >= _previewTransitionLimit ||
                Stopwatch.GetTimestamp() >= _previewTransitionEnd && !_hud.PreviewStartupActive)
                StopPreviewTransition();
        };
        _previewTransition.Start();
        try { TransitionStateChanged?.Invoke(); }
        catch { StopPreviewTransition(); throw; }
        return true;
    }
    private void StopPreviewTransition()
    {
        if (_previewTransition is null) return;
        _previewTransition.Stop(); _previewTransition = null;
        // Restore current inspector protection BEFORE ordinary content returns.
        try { TransitionStateChanged?.Invoke(); }
        finally { _hud.StopPreviewStartup(); }
    }
}
