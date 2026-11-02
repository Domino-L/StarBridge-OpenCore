using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using StarBridge.Core.Presence;
using SharpGen.Runtime;
using Vortice;
using Vortice.DCommon;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectComposition;
using Vortice.DirectWrite;
using Vortice.DXGI;
using Vortice.Mathematics;
using D2DFactoryType = Vortice.Direct2D1.FactoryType;
using D2DTextAntialiasMode = Vortice.Direct2D1.TextAntialiasMode;
using D3DFeatureLevel = Vortice.Direct3D.FeatureLevel;
using D3D11Api = Vortice.Direct3D11.D3D11;
using DCompApi = Vortice.DirectComposition.DComp;
using DWriteFontStretch = Vortice.DirectWrite.FontStretch;
using DWriteFontStyle = Vortice.DirectWrite.FontStyle;
using DWriteFontWeight = Vortice.DirectWrite.FontWeight;
using DWriteFactoryType = Vortice.DirectWrite.FactoryType;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using DxgiAlphaMode = Vortice.DXGI.AlphaMode;
using DxgiFormat = Vortice.DXGI.Format;
using WpfRect = System.Windows.Rect;
using WpfVisibility = System.Windows.Visibility;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow : IOverlayHost, IDisposable
{
    private const int WsPopup = unchecked((int)0x80000000);
    private const int WsVisible = 0x10000000;
    private const int SwHide = 0;
    private const int SwShowna = 8;
    private const int WmNcHitTest = 0x0084;
    private const int WmMouseActivate = 0x0021;
    private const int WmMouseMove = 0x0200;
    private const int WmLButtonDown = 0x0201;
    private const int WmLButtonUp = 0x0202;
    private const int WmRButtonDown = 0x0204;
    private const int WmRButtonUp = 0x0205;
    private const int WmMButtonDown = 0x0207;
    private const int WmMButtonUp = 0x0208;
    private const int WmMouseWheel = 0x020A;
    private const int WmXButtonDown = 0x020B;
    private const int WmXButtonUp = 0x020C;
    private const int HtTransparent = -1;
    private const int MaNoActivate = 3;
    private const double EventSlideMs = 260;
    private const double EventFlowFrameMs = 1000.0 / 30.0;
    private const double EventFlowCycleMs = 1600.0;
    private const double EventSteadyFlowMs = 420.0;
    private const double NightShadowAmbientFlowBaseCycleMs = 16000.0;
    private const double ContentRevealMs = 360;
    private const double ContentRevealMaxDelayMs = 150;
    private const float ContentRevealOffsetY = 10.0f;
    private const float FleetNoticeAnchorAppearEnd = 0.22f;
    private const float FleetNoticeAnchorTravelStart = 0.16f;
    private const float FleetNoticeAnchorTravelEnd = 0.72f;
    private const float FleetNoticeBannerRevealStart = 0.20f;
    private const float FleetNoticeBannerRevealEnd = 0.82f;
    private const float FleetNoticeContentRevealStart = 0.42f;
    private const float FleetNoticeContentRevealEnd = 0.94f;
    private const float FleetNoticeAnchorStartRadius = 36.0f;
    private const float FleetNoticeAnchorRestRadius = 27.0f;
    private const float FleetNoticeBladeTipFlatHalf = 2.0f;
    private const double FleetNoticeExitDurationMs = 480.0;
    private const double FleetNoticeAnchorTrailCycleMs = 3200.0;
    private const int FleetNoticeAnchorTrailSamples = 15;
    private const float FleetNoticeAnchorTrailLength = 22.0f;
    private const float FleetNoticeAnchorTrailWaveAmplitude = 2.7f;
    private const double NightShadowStartupDurationMs = 0;
    private const double NightShadowModuleRevealMs = 360;
    private const double NightShadowSourceChargeMs = 420;
    private const double NightShadowRouteLeadMs = 650;
    private const double NightShadowSilentStartupDurationMs = 2700;
    private const double NightShadowSilentModuleRevealMs = 520;
    private const double NightShadowBlackCurtainStartupDurationMs = 3400;
    private const double NightShadowBlackCurtainModuleRevealMs = 620;
    private const double NightShadowBladeCurtainStartupDurationMs = 3000;
    private const double NightShadowBladeCurtainModuleRevealMs = 600;
    private const float PanelFrameInset = 0.0f;
    private const float PanelChromeInset = 11.0f;
    private const float PanelCornerDiagonalOpacity = 0.82f;
    private const float PanelCornerDiagonalStrokeWidth = 1.32f;
    private const float PanelCornerLineOpacity = 0.66f;
    private const float PanelCornerLineStrokeWidth = 1.0f;
    private const float NightShadowSlashLength = 38.0f;
    private const float NightShadowBottomSlashLength = 32.0f;
    private const int SlowOperationThresholdMs = 80;
    // Local diagnostics have observed otherwise-successful DirectComposition
    // cold starts taking just over three seconds under GPU contention.
    internal const int StartupReadyTimeoutMilliseconds = 5000;
    private static readonly string[] NightShadowJoinableModuleKeys = ["Squads", "Members", "Chat"];
    private readonly Dispatcher _ownerDispatcher;
    private readonly ManualResetEventSlim _started = new(false);
    private readonly object _disposeLock = new();
    private readonly OverlayViewModel _viewModel;
    private readonly OverlayAdaptiveFramePacer _adaptiveFramePacer = new();
    private readonly DateTimeOffset _frameClockStartedAtUtc = DateTimeOffset.UtcNow;
    private readonly Stopwatch _frameClock = Stopwatch.StartNew();

    private IEnumerable<OverlayLayoutItem> _layout;
    private OverlayDisplaySettings _settings;
    private string _language;
    private WpfRect _surfaceBounds;
    private OverlayStartupTransitionContext _startupTransitionContext;
    private double _dpiScaleX;
    private double _dpiScaleY;
    private double _renderDpiScaleX;
    private double _renderDpiScaleY;
    private double? _targetDpiScale;
    private Thread? _thread;
    private Dispatcher? _renderDispatcher;
    private Exception? _startupException;
    private bool _disposed;
    private bool _renderThreadDisposed;
    private bool _isVisible;
    private int _firstFrameCommitted;
    private OverlayCompositionStartupTransitionWindow? _compositionStartupTransition;
    private DispatcherTimer? _initialRevealTimer;
    private DispatcherTimer? _delayedEventRevealTimer;
    private DispatcherTimer? _hitTraceTimer;
    private DispatcherTimer? _topmostGuardTimer;

    private HwndSource? _source;
    private OverlayFrameScheduler? _frameScheduler;
    private ID3D11Device? _d3dDevice;
    private IDXGIDevice? _dxgiDevice;
    private ID2D1Device? _d2dDevice;
    private ID2D1DeviceContext? _d2dDeviceContext;
    private ID2D1Effect? _outerGlowEffect;
    private ID2D1Effect? _innerGlowEffect;
    private IDCompositionDevice? _compositionDevice;
    private IDCompositionTarget? _target;
    private IDCompositionVisual? _rootVisual;
    private IDCompositionSurface? _surface;
    private ID2D1Factory1? _d2dFactory;
    private IDWriteFactory? _writeFactory;
    private IDWriteTextFormat? _titleFormat;
    private IDWriteTextFormat? _textFormat;
    private IDWriteTextFormat? _textRightFormat;
    private IDWriteTextFormat? _mutedFormat;
    private IDWriteTextFormat? _overviewValueFormat;
    private IDWriteTextFormat? _overviewNumberFormat;
    private IDWriteTextFormat? _mutedRightFormat;
    private IDWriteTextFormat? _sourceLabelFormat;
    private IDWriteTextFormat? _tinyFormat;
    private IDWriteTextFormat? _tinyCenterFormat;
    private IDWriteTextFormat? _centerFormat;
    private IDWriteTextFormat? _eventTitleFormat;
    private IDWriteTextFormat? _eventDetailFormat;
    private IDWriteTextFormat? _chatBarrageTitleFormat;
    private IDWriteTextFormat? _chatBarrageTextFormat;
    private IDWriteTextFormat? _chatBarrageTimestampFormat;
    private float _chatBarrageFormatSize;
    private readonly OverlayBarrageTextMeasurementCache _chatBarrageTextMeasurementCache = new();
    private readonly Dictionary<(string Text, IDWriteTextFormat Format), float> _textWidthCache = [];
    private ID2D1StrokeStyle? _cornerStrokeStyle;
    private Dictionary<BrushKey, ID2D1SolidColorBrush>? _frameBrushes;
    private OverlayCompositionFrameState? _state;
    private readonly OverlayAppearanceFrameInvalidator _appearanceMotionInvalidator = new();
    private bool _glowDevicePathDisabled;
    private DateTimeOffset _frameNowUtc;
    private DateTimeOffset _eventSlideStartedAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastEventFlowFrameAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _contentRevealStartedAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _fleetNoticeExitStartedAtUtc = DateTimeOffset.MinValue;
    private OverlayCompositionFrameState? _fleetNoticeExitState;
    private int _lastEventPulse;
    private bool _deferEventNotificationsUntilContentRevealCompletes;
    private int _left;
    private int _top;
    private int _pixelWidth;
    private int _pixelHeight;
    private int _hitTestDiagnosticsCount;
    private int _mouseActivateDiagnosticsCount;
    private int _hitTraceDiagnosticsCount;
    private int _mouseInputDiagnosticsCount;

    public OverlayCompositionHudWindow(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        IEnumerable<OverlayLayoutItem> layout,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        WpfRect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext,
        double? targetDpiScale = null,
        OverlayModulePresentation? modules = null)
    {
        _ownerDispatcher = Dispatcher.CurrentDispatcher;
        _layout = layout;
        _settings = settings;
        _language = language;
        _surfaceBounds = NormalizeSurfaceBounds(surfaceBounds);
        _targetDpiScale = targetDpiScale;
        _startupTransitionContext = startupTransitionContext;
        ResolveDpiScale();
        _viewModel = new OverlayViewModel(
            roster,
            settings,
            rosterSelectionSettings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            sceneContext,
            chatMessages,
            modules);
        _viewModel.PropertyChanged += OverlayViewModel_PropertyChanged;
        UpdateExtendedAppearanceScope(settings.Skin, sceneContext, modules);
        if (settings.ShowEventNotifications)
        {
            _viewModel.QueueEventReceiverConnectionIfNeeded(language);
        }
        ApplyLayoutDependentViewModelState();
    }

    public event EventHandler? Closed;

    public bool IsVisible => _isVisible;
    private readonly OverlayMenuZOrder _menuZOrder = new();
    internal IntPtr NativeHandle => _source?.Handle ?? IntPtr.Zero;
    internal bool FirstFrameCommitted => Volatile.Read(ref _firstFrameCommitted) == 1;
    internal bool NativeWindowIsVisible => NativeHandle is var handle && handle != IntPtr.Zero && IsWindowVisible(handle);
    internal bool StartupTransitionEnabled => _settings.EnableStartupTransition;
    internal void StopStartupCover()
    {
        _compositionStartupTransition?.Dispose();
        _compositionStartupTransition = null;
    }
    internal void SetMenuAbove(IntPtr menu)
    {
        _menuZOrder.Set(menu);
        var dispatcher = _renderDispatcher;
        if (dispatcher is { HasShutdownStarted: false, HasShutdownFinished: false })
            dispatcher.BeginInvoke(() => _menuZOrder.Apply(_source?.Handle ?? IntPtr.Zero), DispatcherPriority.Send);
    }

    public void Show()
    {
        if (_isVisible)
        {
            return;
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            _isVisible = true;
            BeginAppearanceStartup(out var playAppearanceStartup, out var startupDurationMs);

            StartRenderThread();
            if (playAppearanceStartup)
            {
                _viewModel.HoldEventNotificationsForStartupReveal(startupDurationMs + 1000);
                _deferEventNotificationsUntilContentRevealCompletes = true;
                PublishStateToRenderer(forceEventPulse: false);
                ScheduleEventRevealAfter(startupDurationMs + 90);
            }
            else if (TryStartStartupTransition())
            {
                _viewModel.HoldEventNotificationsForStartupReveal(
                    OverlayCompositionStartupTransitionWindow.ProgressCompleteFadeStartMs +
                    ContentRevealMs +
                    ContentRevealMaxDelayMs +
                    1000);
                _initialRevealTimer = new DispatcherTimer { Interval = TimeSpan.FromMilliseconds(OverlayCompositionStartupTransitionWindow.ProgressCompleteFadeStartMs) };
                _initialRevealTimer.Tick += (_, _) =>
                {
                    _initialRevealTimer?.Stop();
                    _initialRevealTimer = null;
                    if (!_disposed)
                    {
                        BeginContentReveal(delayEventReveal: true);
                    }
                };
                _initialRevealTimer.Start();
            }
            else
            {
                PublishStateToRenderer(forceEventPulse: true);
            }
        }
        finally
        {
            LogPerformance("dcomp-hud-show", stopwatch);
        }
    }

    public void BeginStartupTransition(int settleDelayMs = 0)
    {
        BeginExtendedStartupTransition(settleDelayMs);
    }

    private void BeginContentReveal(bool delayEventReveal)
    {
        _contentRevealStartedAtUtc = DateTimeOffset.UtcNow;
        _deferEventNotificationsUntilContentRevealCompletes = delayEventReveal;
        PublishStateToRenderer(forceEventPulse: false);
        if (delayEventReveal)
        {
            ScheduleEventRevealAfterContentReveal();
        }
    }

    private void ScheduleEventRevealAfterContentReveal()
    {
        ScheduleEventRevealAfter(ContentRevealMs + ContentRevealMaxDelayMs + 90);
    }

    private void ScheduleEventRevealAfter(double delayMs)
    {
        _delayedEventRevealTimer?.Stop();
        var timer = new DispatcherTimer
        {
            Interval = TimeSpan.FromMilliseconds(Math.Max(1, delayMs))
        };
        _delayedEventRevealTimer = timer;
        timer.Tick += (_, _) =>
        {
            timer.Stop();
            if (!ReferenceEquals(_delayedEventRevealTimer, timer) || _disposed)
            {
                return;
            }

            _delayedEventRevealTimer = null;
            _deferEventNotificationsUntilContentRevealCompletes = false;
            _viewModel.ReplayEventNotificationsEnter();
            PublishStateToRenderer(forceEventPulse: true);
        };
        timer.Start();
    }

    public void Close()
    {
        Dispose();
    }

    public void SetVisible(bool visible)
    {
        lock (_disposeLock)
        {
            if (_disposed || _isVisible == visible)
            {
                return;
            }

            _isVisible = visible;
        }

        if (!visible)
        {
            // The optional startup cover owns a separate HWND; hiding only
            // the HUD must not leave that cover above the menu.
            _compositionStartupTransition?.Dispose();
            _compositionStartupTransition = null;
        }

        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            return;
        }

        dispatcher.BeginInvoke(() =>
        {
            if (_disposed || _isVisible != visible) return;
            if (_source?.Handle is not { } handle || handle == IntPtr.Zero)
            {
                return;
            }

            ObserveCalmVisibility(visible);
            if (visible)
            {
                // Owner publishes refreshed authorized state at Render priority
                // before this reveal. Draw it while hidden, then show the HWND.
                DrawFrame();
            }
            ShowWindow(handle, visible ? SwShowna : SwHide);
            if (!visible) ResetExtendedAppearanceLifecycle();
            if (visible)
            {
                OverlayHwndDiagnostics.EnsureTopmost(handle, "experimental-hud-show", force: true);
            }
        }, visible ? DispatcherPriority.Render : DispatcherPriority.Send);
    }

    public void QueueGameEventNotification(OverlayEventNotificationTypes eventType, string title, string detail,
        bool important, bool positive) => QueueGameEventNotification(eventType, title, detail, important, positive, null);

    public void QueueGameEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        bool important,
        bool positive,
        Func<bool>? isCurrent,
        Func<IReadOnlyList<PlayerRow>, string>? currentDetail = null,
        bool isDeviceLocal = false)
    {
        if (_disposed || !_settings.ShowEventNotifications)
        {
            return;
        }

        _viewModel.QueueGameEventNotification(eventType, title, detail, important, positive, isCurrent, currentDetail, isDeviceLocal);
        PublishStateToRenderer(forceEventPulse: true);
    }

    public void QueueCommunicationEvent(string title, string detail)
    {
        if (_disposed || !_settings.ShowNotice)
        {
            return;
        }

        _viewModel.QueueCommunicationEvent(title, detail);
        PublishStateToRenderer(forceEventPulse: false);
    }

    internal bool TryShowLiveCommunicationEvent(Guid id, string title, string detail, int minimumSeconds = 0)
    {
        if (_disposed || !_settings.ShowNotice || !_viewModel.TryShowLiveCommunicationEvent(id, title, detail, minimumSeconds)) return false;
        PublishStateToRenderer(forceEventPulse: false);
        return true;
    }

    internal void ClearLiveCommunicationEvent(Guid id)
    {
        if (_disposed) return;
        _viewModel.ClearLiveCommunicationEvent(id);
        PublishStateToRenderer(forceEventPulse: false);
    }

    public void Dispose()
    {
        var notifyClosed = false;
        lock (_disposeLock)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
            notifyClosed = _isVisible;
            _isVisible = false;
        }

        _viewModel.PropertyChanged -= OverlayViewModel_PropertyChanged;
        _viewModel.ClearAuthorizedContent();
        _initialRevealTimer?.Stop();
        _initialRevealTimer = null;
        _delayedEventRevealTimer?.Stop();
        _delayedEventRevealTimer = null;
        _compositionStartupTransition?.Dispose();
        _compositionStartupTransition = null;
        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            NotifyClosedIfNeeded(notifyClosed);
            return;
        }

        if (dispatcher.CheckAccess())
        {
            DisposeOnRenderThread();
            NotifyClosedIfNeeded(notifyClosed);
        }
        else
        {
            dispatcher.BeginInvoke(() =>
            {
                DisposeOnRenderThread();
                NotifyClosedIfNeeded(notifyClosed);
            }, DispatcherPriority.Send);
        }
    }

    public void Refresh(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        IEnumerable<OverlayLayoutItem> layout,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language, bool hasFleet, OverlayCommandState commandState,
        PlayerPresenceKind localPresence, string localShard, WpfRect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext, OverlaySceneContext sceneContext) =>
        RefreshWithDpi(roster, chatMessages, layout, settings, rosterSelectionSettings, language,
            hasFleet, commandState, localPresence, localShard, surfaceBounds, startupTransitionContext, sceneContext);

    public void RefreshWithDpi(
        OverlayAuthorizedRoster roster,
        IEnumerable<OverlayChatMessage> chatMessages,
        IEnumerable<OverlayLayoutItem> layout,
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        WpfRect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext,
        double? targetDpiScale = null,
        OverlayModulePresentation? modules = null)
    {
        if (_disposed)
        {
            return;
        }

        UpdateExtendedAppearanceScope(settings.Skin, sceneContext, modules);
        _layout = layout.ToArray();
        _settings = settings;
        _language = language;
        _surfaceBounds = NormalizeSurfaceBounds(surfaceBounds);
        _targetDpiScale = targetDpiScale;
        _startupTransitionContext = startupTransitionContext;
        ResolveDpiScale();
        _viewModel.Refresh(
            roster,
            settings,
            rosterSelectionSettings,
            language,
            hasFleet,
            commandState,
            localPresence,
            localShard,
            sceneContext,
            chatMessages,
            modules);
        ApplyLayoutDependentViewModelState();
        PublishStateToRenderer(forceEventPulse: false);
    }

    private void OverlayViewModel_PropertyChanged(object? sender, PropertyChangedEventArgs e)
    {
        if (!_isVisible || _disposed)
        {
            return;
        }

        _ownerDispatcher.BeginInvoke(() =>
        {
            ApplyLayoutDependentViewModelState();
            PublishStateToRenderer(forceEventPulse: false);
        }, DispatcherPriority.Render);
    }

    internal void ClearAuthorizedContent(bool preserveDeviceLocalEvents = false, bool preserveAnnouncementReceipt = false) =>
        _viewModel.ClearAuthorizedContent(preserveDeviceLocalEvents, preserveAnnouncementReceipt);

    internal OverlayModuleWindowObservation ObserveModules() => new(_viewModel.FleetNotice,
        _viewModel.SquadsTitle, _viewModel.MembersTitle, _viewModel.Members.Select(row => row.DisplayName).ToArray(),
        _viewModel.ChatMessages.Select(row => row.Detail).ToArray(), _viewModel.ChatPulse, _viewModel.SquadStatusPrimaryName)
        { SourceLabels = _viewModel.ModuleSourceLabels, EmptyStates = _viewModel.ModuleEmptyStates,
          Visibility = InformationOverlayRuntimeProjection.ResolveVisibility(_settings, new(
              _viewModel.NotificationVisibility == WpfVisibility.Visible, _viewModel.ChatVisibility == WpfVisibility.Visible,
              _viewModel.EventNotificationVisibility == WpfVisibility.Visible)) };

    private void StartRenderThread()
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            ResolveDeviceBounds();
            if (_pixelWidth <= 1 || _pixelHeight <= 1)
            {
                throw new InvalidOperationException("Overlay composition bounds are empty.");
            }

            _thread = new Thread(RenderThreadMain)
            {
                IsBackground = true,
                Name = "StarBridge Overlay DirectComposition HUD"
            };
            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();

            if (!_started.Wait(TimeSpan.FromMilliseconds(StartupReadyTimeoutMilliseconds)))
            {
                throw new TimeoutException("DirectComposition overlay startup timed out.");
            }

            if (_startupException is not null)
            {
                throw new InvalidOperationException("DirectComposition overlay startup failed.", _startupException);
            }
        }
        finally
        {
            LogPerformance("dcomp-hud-start-render-thread", stopwatch);
        }
    }

    private bool TryStartStartupTransition()
    {
        if (IsNightShadowStyle(_settings))
        {
            return false;
        }

        var stopwatch = Stopwatch.StartNew();
        try
        {
            return OverlayCompositionStartupTransitionWindow.TryStart(
                _surfaceBounds,
                _dpiScaleX,
                _dpiScaleY,
                _settings,
                _language,
                _startupTransitionContext,
                BuildStartupRevealTargets(),
                out _compositionStartupTransition);
        }
        finally
        {
            LogPerformance("dcomp-hud-startup-transition", stopwatch);
        }
    }

    private bool ShouldPlayNightShadowStartup()
    {
        return _settings.EnableStartupTransition &&
               IsNightShadowStyle(_settings);
    }

    private bool ShouldPlayVerdictStartup()
    {
        return _settings.EnableStartupTransition &&
               UiMotion.IsEnabled &&
               _settings.Skin == OverlaySkin.Verdict &&
               _settings.StartupTransitionStyle == OverlayStartupTransitionStyle.VerdictProtocol;
    }

    private IReadOnlyList<WpfRect> BuildStartupRevealTargets()
    {
        var width = Math.Max(1, _surfaceBounds.Width);
        var height = Math.Max(1, _surfaceBounds.Height);
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(_layout, width, height);
        return new[]
            {
                ResolveVisibleItemRect("Notice", _viewModel.NotificationVisibility, resolvedItems),
                ResolveVisibleItemRect("Squads", _viewModel.SquadsVisibility, resolvedItems),
                ResolveVisibleItemRect("Members", _viewModel.MembersVisibility, resolvedItems)
            }
            .Where(rect => rect.Width > 1 && rect.Height > 1)
            .Select(rect => new WpfRect(
                rect.X * _dpiScaleX,
                rect.Y * _dpiScaleY,
                rect.Width * _dpiScaleX,
                rect.Height * _dpiScaleY))
            .ToArray();
    }

    private static WpfRect ResolveVisibleItemRect(
        string key,
        WpfVisibility visibility,
        IReadOnlyDictionary<string, WpfRect> resolvedItems)
    {
        return visibility == WpfVisibility.Visible
            ? ResolveItemRect(key, resolvedItems)
            : new WpfRect(0, 0, 0, 0);
    }
}
