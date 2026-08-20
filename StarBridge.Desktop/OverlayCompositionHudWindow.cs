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
    private const double LagrangeEventMotionMs = 420.0;
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
    private Thread? _thread;
    private Dispatcher? _renderDispatcher;
    private Exception? _startupException;
    private bool _disposed;
    private bool _renderThreadDisposed;
    private bool _isVisible;
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
    private IDWriteTextFormat? _mutedRightFormat;
    private IDWriteTextFormat? _tinyFormat;
    private IDWriteTextFormat? _tinyCenterFormat;
    private IDWriteTextFormat? _centerFormat;
    private IDWriteTextFormat? _eventTitleFormat;
    private IDWriteTextFormat? _eventDetailFormat;
    private OverlaySkin? _hudTextFormatSkin;
    private IDWriteTextFormat? _chatBarrageTitleFormat;
    private IDWriteTextFormat? _chatBarrageTextFormat;
    private IDWriteTextFormat? _chatBarrageTimestampFormat;
    private float _chatBarrageFormatSize;
    private readonly OverlayBarrageTextMeasurementCache _chatBarrageTextMeasurementCache = new();
    private readonly Dictionary<(string Text, IDWriteTextFormat Format), float> _textWidthCache = [];
    private ID2D1StrokeStyle? _cornerStrokeStyle;
    private Dictionary<BrushKey, ID2D1SolidColorBrush>? _frameBrushes;
    private OverlayCompositionFrameState? _state;
    private bool _lagrangeGlowMaskOnly;
    private DateTimeOffset _lagrangeStartupStartedAtUtc = DateTimeOffset.MinValue;
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
        OverlaySceneContext sceneContext)
    {
        _ownerDispatcher = Dispatcher.CurrentDispatcher;
        _layout = layout;
        _settings = settings;
        _language = language;
        _surfaceBounds = NormalizeSurfaceBounds(surfaceBounds);
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
            chatMessages);
        _viewModel.PropertyChanged += OverlayViewModel_PropertyChanged;
        ApplyLayoutDependentViewModelState();
    }

    public event EventHandler? Closed;

    public bool IsVisible => _isVisible;

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

        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            return;
        }

        dispatcher.BeginInvoke(() =>
        {
            if (_source?.Handle is not { } handle || handle == IntPtr.Zero)
            {
                return;
            }

            ShowWindow(handle, visible ? SwShowna : SwHide);
            if (visible)
            {
                OverlayHwndDiagnostics.EnsureTopmost(handle, "experimental-hud-show", force: true);
                DrawFrame();
            }
        }, DispatcherPriority.Send);
    }

    public void QueueGameEventNotification(
        OverlayEventNotificationTypes eventType,
        string title,
        string detail,
        bool important,
        bool positive)
    {
        if (_disposed || !_settings.ShowEventNotifications)
        {
            return;
        }

        _viewModel.QueueGameEventNotification(eventType, title, detail, important, positive);
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
        OverlayDisplaySettings settings,
        OverlayRosterSelectionSettings rosterSelectionSettings,
        string language,
        bool hasFleet,
        OverlayCommandState commandState,
        PlayerPresenceKind localPresence,
        string localShard,
        WpfRect surfaceBounds,
        OverlayStartupTransitionContext startupTransitionContext,
        OverlaySceneContext sceneContext)
    {
        if (_disposed)
        {
            return;
        }

        _settings = settings;
        _language = language;
        _surfaceBounds = NormalizeSurfaceBounds(surfaceBounds);
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
            chatMessages);
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
        if (IsNightShadowStyle(_settings) ||
            _settings.Skin == OverlaySkin.LagrangeWeave)
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

    private bool ShouldPlayLagrangeStartup()
    {
        return _settings.EnableStartupTransition &&
               _settings.Skin == OverlaySkin.LagrangeWeave &&
               _settings.StartupTransitionStyle == OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium;
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

    private void RenderThreadMain()
    {
        var readyStopwatch = Stopwatch.StartNew();
        try
        {
            _renderDispatcher = Dispatcher.CurrentDispatcher;
            if (IsDisposeRequested())
            {
                _started.Set();
                return;
            }

            var createStopwatch = Stopwatch.StartNew();
            CreateWindowAndResources();
            LogPerformance("dcomp-hud-create-window-resources", createStopwatch);
            if (IsDisposeRequested())
            {
                _started.Set();
                DisposeOnRenderThread();
                return;
            }

            var firstFrameStopwatch = Stopwatch.StartNew();
            DrawFrame();
            LogPerformance("dcomp-hud-first-frame", firstFrameStopwatch);
            if (IsDisposeRequested())
            {
                _started.Set();
                DisposeOnRenderThread();
                return;
            }

            ShowWindow(_source!.Handle, SwShowna);
            EnableMouseClickThrough();
            StartHitTraceDiagnostics();
            StartTopmostGuard();

            _frameScheduler = new OverlayFrameScheduler(_renderDispatcher, RenderAnimationFrame);

            _started.Set();
            LogPerformance("dcomp-hud-render-ready", readyStopwatch);
            Dispatcher.Run();
        }
        catch (Exception exception)
        {
            _startupException = exception;
            _started.Set();
            LogPerformance("dcomp-hud-render-failed", readyStopwatch, force: true);
            App.WriteCrashLog(exception);
            DisposeOnRenderThread();
        }
    }

    private bool IsDisposeRequested()
    {
        lock (_disposeLock)
        {
            return _disposed;
        }
    }

    private void RenderAnimationFrame()
    {
        var eventSlideActive = IsEventSlideActive();
        var contentRevealActive = IsContentRevealActive();
        var appearanceAnimation = ReadAppearanceAnimationState();
        var appearanceStartupActive = appearanceAnimation.StartupActive;
        var eventFlowActive = appearanceAnimation.EventFlowActive;
        var ambientFlowActive = appearanceAnimation.AmbientFlowActive;
        var chatBarrageActive = IsChatBarrageActive();
        var fleetNoticeExitActive = IsFleetNoticeExitActive();
        var requestedFramesPerSecond = contentRevealActive || appearanceStartupActive
            ? ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate)
            : ResolveAnimationFramesPerSecond(_settings.AnimationFrameRate);
        var framesPerSecond = _adaptiveFramePacer.Resolve(requestedFramesPerSecond, Environment.TickCount64);
        _frameScheduler?.UpdateFrameRate(framesPerSecond);

        if (eventFlowActive && !ambientFlowActive && !eventSlideActive && !contentRevealActive && !appearanceStartupActive)
        {
            var now = DateTimeOffset.UtcNow;
            if (_lastEventFlowFrameAtUtc != DateTimeOffset.MinValue &&
                (now - _lastEventFlowFrameAtUtc).TotalMilliseconds < EventFlowFrameMs)
            {
                return;
            }

            _lastEventFlowFrameAtUtc = now;
        }

        DrawFrame();
        if (!IsFleetNoticeExitActive() && _fleetNoticeExitStartedAtUtc != DateTimeOffset.MinValue)
        {
            _fleetNoticeExitState = null;
            _fleetNoticeExitStartedAtUtc = DateTimeOffset.MinValue;
            fleetNoticeExitActive = false;
        }

        if (!eventSlideActive && !contentRevealActive && !appearanceStartupActive && !eventFlowActive && !ambientFlowActive && !chatBarrageActive && !fleetNoticeExitActive)
        {
            _frameScheduler?.Stop();
            _lastEventFlowFrameAtUtc = DateTimeOffset.MinValue;
        }
    }

    private void CreateWindowAndResources()
    {
        var parameters = new HwndSourceParameters("StarBridge Overlay DirectComposition HUD")
        {
            PositionX = _left,
            PositionY = _top,
            Width = _pixelWidth,
            Height = _pixelHeight,
            WindowStyle = WsPopup | WsVisible,
            ExtendedWindowStyle = OverlayHwndDiagnostics.ClickThroughExtendedStyle,
            UsesPerPixelOpacity = true
        };

        _source = new HwndSource(parameters);
        _source.AddHook(WindowProc);
        OverlayHwndDiagnostics.LogState(_source.Handle, "experimental-hud-created");

        var featureLevels = new[]
        {
            D3DFeatureLevel.Level_11_1,
            D3DFeatureLevel.Level_11_0,
            D3DFeatureLevel.Level_10_1,
            D3DFeatureLevel.Level_10_0
        };

        _d3dDevice = D3D11Api.D3D11CreateDevice(
            DriverType.Hardware,
            DeviceCreationFlags.BgraSupport,
            featureLevels);

        _dxgiDevice = _d3dDevice!.QueryInterface<IDXGIDevice>();
        _compositionDevice = DCompApi.DCompositionCreateDevice<IDCompositionDevice>(_dxgiDevice);
        _compositionDevice.CreateTargetForHwnd(_source.Handle, true, out _target);
        OverlayHwndDiagnostics.LogState(_source.Handle, "experimental-hud-target-bound");
        _compositionDevice.CreateVisual(out _rootVisual);
        _compositionDevice.CreateSurface(
            (uint)_pixelWidth,
            (uint)_pixelHeight,
            DxgiFormat.B8G8R8A8_UNorm,
            DxgiAlphaMode.Premultiplied,
            out _surface);
        _rootVisual!.SetContent(_surface);
        _target!.SetRoot(_rootVisual);
        _compositionDevice.Commit();

        _d2dFactory = Vortice.Direct2D1.D2D1.D2D1CreateFactory<ID2D1Factory1>(D2DFactoryType.SingleThreaded);
        _d2dDevice = _d2dFactory.CreateDevice(_dxgiDevice);
        _d2dDeviceContext = _d2dDevice.CreateDeviceContext(DeviceContextOptions.None);
        CreateStrokeStyles();
        _writeFactory = DWrite.DWriteCreateFactory<IDWriteFactory>(DWriteFactoryType.Shared);
        CreateTextFormats();
        EnableMouseClickThrough();
    }

    private void StartTopmostGuard()
    {
        _topmostGuardTimer?.Stop();
        _topmostGuardTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromMilliseconds(750)
        };
        _topmostGuardTimer.Tick += (_, _) =>
        {
            if (!_isVisible || _source?.Handle is not { } handle || handle == IntPtr.Zero)
            {
                return;
            }

            OverlayHwndDiagnostics.EnsureTopmost(handle, "experimental-hud-guard");
        };
        _topmostGuardTimer.Start();
    }

    private void CreateStrokeStyles()
    {
        if (_d2dFactory is null)
        {
            return;
        }

        var cornerStyle = new StrokeStyleProperties
        {
            StartCap = CapStyle.Flat,
            EndCap = CapStyle.Flat,
            DashCap = CapStyle.Flat,
            LineJoin = LineJoin.Bevel,
            MiterLimit = 1,
            DashStyle = Vortice.Direct2D1.DashStyle.Solid,
            DashOffset = 0
        };
        _cornerStrokeStyle = _d2dFactory.CreateStrokeStyle(cornerStyle);
    }


    private void CreateTextFormats(OverlaySkin? skin = null)
    {
        _textWidthCache.Clear();
        _eventDetailFormat?.Dispose();
        _eventTitleFormat?.Dispose();
        _centerFormat?.Dispose();
        _tinyCenterFormat?.Dispose();
        _tinyFormat?.Dispose();
        _mutedRightFormat?.Dispose();
        _mutedFormat?.Dispose();
        _textRightFormat?.Dispose();
        _textFormat?.Dispose();
        _titleFormat?.Dispose();

        var effectiveSkin = skin ?? _settings.Skin;
        var skinProfile = OverlaySkinCatalog.Get(effectiveSkin);
        var titleSize = (float)skinProfile.TitleFontSize;
        var textSize = (float)skinProfile.TextFontSize;
        var mutedSize = (float)skinProfile.MutedFontSize;
        var tinySize = (float)skinProfile.TinyFontSize;
        var tinyCenterSize = (float)skinProfile.TinyCenterFontSize;

        _titleFormat = CreateTextFormat("Segoe UI Semibold", titleSize, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _textFormat = CreateTextFormat("Segoe UI", textSize, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        _textRightFormat = CreateTextFormat("Segoe UI", textSize, DWriteFontWeight.Normal, DWriteTextAlignment.Trailing);
        _mutedFormat = CreateTextFormat("Segoe UI", mutedSize, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        _mutedRightFormat = CreateTextFormat("Segoe UI", mutedSize, DWriteFontWeight.Normal, DWriteTextAlignment.Trailing);
        _tinyFormat = CreateTextFormat("Segoe UI Semibold", tinySize, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _tinyCenterFormat = CreateTextFormat("Segoe UI Semibold", tinyCenterSize, DWriteFontWeight.SemiBold, DWriteTextAlignment.Center);
        _centerFormat = CreateTextFormat("Segoe UI", mutedSize, DWriteFontWeight.Normal, DWriteTextAlignment.Center);
        _eventTitleFormat = CreateTextFormat(
            "Segoe UI Semibold",
            (float)skinProfile.EventTitleFontSize,
            DWriteFontWeight.SemiBold,
            DWriteTextAlignment.Leading,
            WordWrapping.Wrap,
            ParagraphAlignment.Near);
        _eventDetailFormat = CreateTextFormat(
            "Segoe UI",
            (float)skinProfile.EventDetailFontSize,
            DWriteFontWeight.Normal,
            DWriteTextAlignment.Leading,
            WordWrapping.Wrap,
            ParagraphAlignment.Near);
        _hudTextFormatSkin = effectiveSkin;
    }

    private void EnsureHudTextFormats(OverlaySkin skin)
    {
        if (_titleFormat is not null && _hudTextFormatSkin == skin)
        {
            return;
        }

        CreateTextFormats(skin);
    }

    private void EnsureChatBarrageTextFormats(float fontSize)
    {
        var normalizedSize = (float)OverlayDisplaySettings.NormalizeChatBarrageFontSize(fontSize);
        if (_chatBarrageTitleFormat is not null &&
            _chatBarrageTextFormat is not null &&
            _chatBarrageTimestampFormat is not null &&
            Math.Abs(_chatBarrageFormatSize - normalizedSize) < 0.01f)
        {
            return;
        }

        _chatBarrageTitleFormat?.Dispose();
        _chatBarrageTextFormat?.Dispose();
        _chatBarrageTimestampFormat?.Dispose();
        _chatBarrageTextMeasurementCache.Clear();
        _chatBarrageTitleFormat = CreateTextFormat(
            "Segoe UI Semibold",
            normalizedSize,
            DWriteFontWeight.SemiBold,
            DWriteTextAlignment.Leading);
        _chatBarrageTextFormat = CreateTextFormat(
            "Segoe UI",
            normalizedSize,
            DWriteFontWeight.Normal,
            DWriteTextAlignment.Leading);
        _chatBarrageTimestampFormat = CreateTextFormat(
            "Segoe UI",
            Math.Max(9, normalizedSize * 0.72f),
            DWriteFontWeight.Normal,
            DWriteTextAlignment.Leading);
        _chatBarrageFormatSize = normalizedSize;
    }

    private IDWriteTextFormat CreateTextFormat(
        string family,
        float size,
        DWriteFontWeight weight,
        DWriteTextAlignment alignment,
        WordWrapping wordWrapping = WordWrapping.NoWrap,
        ParagraphAlignment paragraphAlignment = ParagraphAlignment.Center)
    {
        var format = _writeFactory!.CreateTextFormat(
            family,
            null!,
            weight,
            DWriteFontStyle.Normal,
            DWriteFontStretch.Normal,
            size,
            "zh-CN");
        format.TextAlignment = alignment;
        format.ParagraphAlignment = paragraphAlignment;
        format.WordWrapping = wordWrapping;
        return format;
    }

    private void PublishStateToRenderer(bool forceEventPulse)
    {
        var state = BuildFrameState();
        if (_deferEventNotificationsUntilContentRevealCompletes && !forceEventPulse)
        {
            state = state with
            {
                ShowEvents = false,
                EventRows = Array.Empty<OverlayCompositionEventRow>()
            };
        }

        var dispatcher = _renderDispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            _state = state;
            return;
        }

        dispatcher.BeginInvoke(() =>
        {
            var pulseChanged = forceEventPulse || state.EventPulse != _lastEventPulse;
            var previousState = _state;
            if (state.ShowNotice)
            {
                _fleetNoticeExitState = null;
                _fleetNoticeExitStartedAtUtc = DateTimeOffset.MinValue;
            }
            else if (previousState is { ShowNotice: true } &&
                     (previousState.NightShadowStyle || previousState.VerdictStyle))
            {
                _fleetNoticeExitState = previousState;
                _fleetNoticeExitStartedAtUtc = DateTimeOffset.UtcNow;
            }

            _state = state;
            if (pulseChanged && state.EventRows.Count > 0)
            {
                _lastEventPulse = state.EventPulse;
                _eventSlideStartedAtUtc = DateTimeOffset.UtcNow;
            }

            var appearanceAnimation = ReadAppearanceAnimationState();
            if ((pulseChanged && state.EventRows.Count > 0) ||
                IsContentRevealActive() ||
                appearanceAnimation.StartupActive ||
                appearanceAnimation.EventFlowActive ||
                appearanceAnimation.AmbientFlowActive ||
                IsChatBarrageActive() ||
                IsFleetNoticeExitActive())
            {
                var requestedFramesPerSecond = IsContentRevealActive() || appearanceAnimation.StartupActive
                    ? ResolveStartupTransitionFramesPerSecond(state.StartupTransitionFrameRate)
                    : ResolveAnimationFramesPerSecond(state.AnimationFrameRate);
                var framesPerSecond = _adaptiveFramePacer.Resolve(requestedFramesPerSecond, Environment.TickCount64);
                _frameScheduler?.Start(framesPerSecond);
            }

            DrawFrame();
        }, DispatcherPriority.Render);
    }

    private OverlayCompositionFrameState BuildFrameState()
    {
        var width = Math.Max(1, _surfaceBounds.Width);
        var height = Math.Max(1, _surfaceBounds.Height);
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(_layout, width, height);
        var noticeRect = ResolveItemRect("Notice", resolvedItems);
        var squadsRect = ResolveItemRect("Squads", resolvedItems);
        var membersRect = ResolveItemRect("Members", resolvedItems);
        var chatRect = ResolveItemRect("Chat", resolvedItems);
        var noticeStyle = ResolveModuleStyle("Notice");
        var squadsStyle = ResolveModuleStyle("Squads");
        var membersStyle = ResolveModuleStyle("Members");
        var chatStyle = ResolveModuleStyle("Chat");
        var eventRect = ResolveEventNotificationRect(width, height);
        var eventStyle = new OverlayCompositionModuleStyle(
            OverlayLayoutItem.NormalizeTextOpacity(_settings.EventNotificationTextOpacity),
            OverlayLayoutItem.NormalizeBackgroundOpacity(_settings.EventNotificationBackgroundOpacity));
        var overviewTopLocations = _viewModel.OverviewTopLocations.Take(2).ToArray();
        var overviewLocationLayout = OverlayOverviewLocationLayout.Resolve(
            squadsRect.Width,
            squadsRect.Height,
            overviewTopLocations);

        return new OverlayCompositionFrameState(
            width,
            height,
            Math.Clamp(_settings.Opacity, 0.15, 1.0),
            Math.Clamp(_settings.Opacity, 0.15, 1.0),
            BuildPalette(),
            OverlaySkinCatalog.Get(_settings.Skin).RenderKind,
            _viewModel.NotificationVisibility == WpfVisibility.Visible,
            _viewModel.SquadsVisibility == WpfVisibility.Visible,
            _viewModel.MembersVisibility == WpfVisibility.Visible,
            _viewModel.ChatVisibility == WpfVisibility.Visible,
            _viewModel.CrosshairVisibility == WpfVisibility.Visible,
            _viewModel.EventNotificationVisibility == WpfVisibility.Visible,
            noticeRect,
            squadsRect,
            membersRect,
            chatRect,
            eventRect,
            eventStyle,
            noticeStyle,
            squadsStyle,
            membersStyle,
            chatStyle,
            ResolveModuleDrawOrder(),
            _settings.EventNotificationSide,
            _settings.NightShadowBloom,
            _viewModel.FleetNoticeTitle,
            _viewModel.FleetNotice,
            _viewModel.NoticeTimerLabel,
            _viewModel.SquadsTitle,
            _viewModel.SquadStatusPrimaryName,
            _viewModel.SquadStatusSummary,
            _viewModel.SquadStatusServerSummary,
            _viewModel.SquadStatusFocusLine,
            _viewModel.OverviewLocationPlaceholder,
            _viewModel.OverviewLocationPlaceholderMetric,
            overviewTopLocations,
            overviewLocationLayout,
            _viewModel.MembersTitle,
            SnapshotMembers(_viewModel.Members, _settings.Skin == OverlaySkin.Minimal),
            _viewModel.ChatTitle,
            _viewModel.ChatDisplayMode,
            _viewModel.ChatSide,
            OverlayDisplaySettings.NormalizeChatBarrageFontSize(_settings.ChatBarrageFontSize),
            OverlayDisplaySettings.NormalizeChatBarrageRegion(_settings.ChatBarrageRegion),
            OverlayDisplaySettings.NormalizeChatBarrageDensity(_settings.ChatBarrageDensity),
            _settings.ChatBarrageAvoidCenter,
            OverlayDisplaySettings.NormalizeChatTextEdgeStrength(_settings.ChatTextEdgeStrength),
            SnapshotEvents(_viewModel.ChatMessages, _settings.Skin == OverlaySkin.Minimal),
            _viewModel.ChatPulse,
            _settings.AnimationFrameRate != OverlayAnimationFrameRate.Off,
            _settings.EffectiveHideMemberOnlineStatus,
            OverlayDisplaySettings.NormalizeMemberNameColumnRatio(_settings.MemberNameColumnRatio),
            _viewModel.HotkeyToggleLabel,
            _settings.CrosshairMode,
            OverlayDisplaySettings.NormalizeCrosshairSize(_settings.CrosshairSize),
            Math.Clamp(_settings.CrosshairThickness, 1, 8),
            Math.Clamp(_settings.CrosshairOpacity, 0.2, 1.0),
            _settings.CrosshairShowCenterMark,
            OverlayDisplaySettings.NormalizeCrosshairCenterMarkSize(_settings.CrosshairCenterMarkSize),
            OverlayDisplaySettings.NormalizeCrosshairGap(_settings.CrosshairGap),
            OverlayDisplaySettings.NormalizeCrosshairOutlineOpacity(_settings.CrosshairOutlineOpacity),
            OverlayDisplaySettings.ResolveEventNotificationAnimationScale(_settings.EventNotificationAnimationSpeed),
            SnapshotEvents(_viewModel.EventNotifications, _settings.Skin == OverlaySkin.Minimal),
            _viewModel.EventNotificationPulse,
            _settings.StartupTransitionFrameRate,
            _settings.AnimationFrameRate);
    }

    private static bool IsNightShadowStyle(OverlayDisplaySettings settings)
    {
        return settings.Skin == OverlaySkin.NightShadow ||
               settings.Theme == OverlayVisualTheme.NightShadow;
    }

    private void ApplyLayoutDependentViewModelState()
    {
        var resolvedItems = OverlaySurfaceLayout.ResolveItems(
            _layout,
            Math.Max(1, _surfaceBounds.Width),
            Math.Max(1, _surfaceBounds.Height));
        var membersRect = ResolveItemRect("Members", resolvedItems);
        _viewModel.ApplyMemberViewport(membersRect.Height);
        _viewModel.ApplyChatBarrageViewportWidth(Math.Max(1, _surfaceBounds.Width));
    }

    private static WpfRect ResolveItemRect(
        string key,
        IReadOnlyDictionary<string, WpfRect> resolvedItems)
    {
        return resolvedItems.TryGetValue(key, out var rect)
            ? rect
            : new WpfRect(0, 0, 1, 1);
    }

    private WpfRect ResolveEventNotificationRect(double width, double height)
    {
        // Reserve enough vertical space for wrapped title/detail rows before DirectWrite measures them.
        var eventHeight = Math.Max(72, _viewModel.EventNotifications.Count * 90);
        return OverlaySurfaceLayout.ResolveEventNotificationRect(
            width,
            height,
            _settings.EventNotificationSide,
            _settings.EventNotificationY,
            eventHeight);
    }

    private OverlayCompositionHudWindow.OverlayCompositionModuleStyle ResolveModuleStyle(string key)
    {
        var item = _layout.FirstOrDefault(layoutItem =>
            layoutItem.Key.Equals(key, StringComparison.OrdinalIgnoreCase));
        return item is null
            ? OverlayCompositionModuleStyle.Default
            : new OverlayCompositionModuleStyle(
                OverlayLayoutItem.NormalizeTextOpacity(item.TextOpacity),
                OverlayLayoutItem.NormalizeBackgroundOpacity(item.BackgroundOpacity));
    }

    private IReadOnlyList<string> ResolveModuleDrawOrder()
    {
        var keys = _layout
            .Select(item => item.Key)
            .Where(IsCompositionOverlayModuleKey)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        foreach (var key in new[] { "Notice", "Squads", "Members", "Chat" })
        {
            if (!keys.Contains(key, StringComparer.OrdinalIgnoreCase))
            {
                keys.Add(key);
            }
        }

        return keys;
    }

    private static bool IsCompositionOverlayModuleKey(string key)
    {
        return key.Equals("Notice", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Squads", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Members", StringComparison.OrdinalIgnoreCase) ||
               key.Equals("Chat", StringComparison.OrdinalIgnoreCase);
    }

    private void DrawFrame()
    {
        if (_surface is null || _d2dFactory is null || _compositionDevice is null)
        {
            return;
        }

        var frameStartedTicks = Stopwatch.GetTimestamp();

        // The glow mask and core pass must resolve moving elements from the
        // same instant, otherwise they periodically separate at pixel edges.
        _frameNowUtc = _frameClockStartedAtUtc + _frameClock.Elapsed;

        RawRect frameRect = new RectI(0, 0, _pixelWidth, _pixelHeight);
        IDXGISurface? dxgiSurface = null;
        _surface.BeginDraw(frameRect, out dxgiSurface, out _);
        try
        {
            if (dxgiSurface is null)
            {
                throw new InvalidOperationException("DirectComposition surface did not provide a DXGI drawing surface.");
            }

            if (!_glowDevicePathDisabled && _d2dDeviceContext is not null)
            {
                try
                {
                    DrawFrameWithDeviceContext(_d2dDeviceContext, dxgiSurface);
                    return;
                }
                catch (Exception exception)
                {
                    _glowDevicePathDisabled = true;
                    App.WriteDiagnosticLog($"overlay-d2d-device-context fallback=legacy error={exception.GetType().Name} message={exception.Message}");
                }
            }

            DrawFrameWithoutGlow(dxgiSurface);
        }
        finally
        {
            DisposeFrameBrushes();
            dxgiSurface?.Dispose();
            _surface.EndDraw();
            _compositionDevice.Commit();
            ReportFrameTiming(frameStartedTicks);
        }
    }

    private void ReportFrameTiming(long frameStartedTicks)
    {
        var completedTicks = Stopwatch.GetTimestamp();
        var frameMs = (completedTicks - frameStartedTicks) * 1000.0 / Stopwatch.Frequency;
        var requestedFramesPerSecond = IsContentRevealActive() ||
                                       ReadAppearanceAnimationState().StartupActive
            ? ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate)
            : ResolveAnimationFramesPerSecond(_settings.AnimationFrameRate);
        _adaptiveFramePacer.ReportFrame(requestedFramesPerSecond, frameMs, Environment.TickCount64);
    }

    private void DrawFrameWithoutGlow(IDXGISurface dxgiSurface)
    {
        var properties = new RenderTargetProperties(
            RenderTargetType.Default,
            new Vortice.DCommon.PixelFormat(DxgiFormat.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            (float)(96.0 * _dpiScaleX),
            (float)(96.0 * _dpiScaleY),
            RenderTargetUsage.None,
            Vortice.Direct2D1.FeatureLevel.Default);
        using var target = _d2dFactory!.CreateDxgiSurfaceRenderTarget(dxgiSurface, properties);
        target.BeginDraw();
        target.TextAntialiasMode = D2DTextAntialiasMode.Grayscale;
        target.Clear(new Color4(0, 0, 0, 0));
        _frameBrushes = [];
        if (_state is not null)
        {
            DrawScene(target, _state);
        }

        ulong tag1 = 0;
        ulong tag2 = 0;
        target.EndDraw(out tag1, out tag2).CheckError();
    }

    private void DrawFrameWithDeviceContext(ID2D1DeviceContext target, IDXGISurface dxgiSurface)
    {
        var dpiX = (float)(96.0 * _dpiScaleX);
        var dpiY = (float)(96.0 * _dpiScaleY);
        target.SetDpi(dpiX, dpiY);

        var bitmapProperties = new BitmapProperties1(
            new Vortice.DCommon.PixelFormat(DxgiFormat.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            dpiX,
            dpiY,
            BitmapOptions.Target | BitmapOptions.CannotDraw);

        using var surfaceBitmap = target.CreateBitmapFromDxgiSurface(dxgiSurface, bitmapProperties);
        using var glowMask = BuildAppearanceGlowMask(target);

        target.Target = surfaceBitmap;
        try
        {
            target.BeginDraw();
            target.TextAntialiasMode = D2DTextAntialiasMode.Grayscale;
            target.Clear(new Color4(0, 0, 0, 0));
            _frameBrushes = [];
            if (_state is not null)
            {
                DrawAppearanceGlow(target, _state, glowMask);
                DrawScene(target, _state);
            }

            ulong tag1 = 0;
            ulong tag2 = 0;
            target.EndDraw(out tag1, out tag2).CheckError();
        }
        finally
        {
            target.Target = null;
        }
    }

    private ID2D1CommandList? BuildLagrangeGlowMask(ID2D1DeviceContext target)
    {
        if (_state is null)
        {
            return null;
        }

        var commandList = target.CreateCommandList();
        target.Target = commandList;
        try
        {
            target.BeginDraw();
            _frameBrushes = [];
            _lagrangeGlowMaskOnly = true;
            try
            {
                DrawScene(target, _state);
            }
            finally
            {
                _lagrangeGlowMaskOnly = false;
                DisposeFrameBrushes();
            }

            ulong tag1 = 0;
            ulong tag2 = 0;
            target.EndDraw(out tag1, out tag2).CheckError();
            commandList.Close();
            return commandList;
        }
        finally
        {
            _lagrangeGlowMaskOnly = false;
            DisposeFrameBrushes();
            target.Target = null;
        }
    }

    private void DrawLagrangeGlow(
        ID2D1DeviceContext target,
        OverlayCompositionFrameState state,
        ID2D1CommandList? glowMask)
    {
        if (glowMask is null || !ShouldDrawLagrangeGlow(state))
        {
            return;
        }

        var strong = state.NightShadowBloom == OverlayNightShadowBloom.Strong;
        var startup = IsLagrangeStartupActive();
        var outerBlur = ConfigureOverlayGlowBlur(
            target,
            glowMask,
            ref _outerGlowEffect,
            startup ? strong ? 15f : 11.5f : strong ? 9.2f : 6.2f);
        var innerBlur = ConfigureOverlayGlowBlur(
            target,
            glowMask,
            ref _innerGlowEffect,
            startup ? strong ? 6.2f : 4.5f : strong ? 3.8f : 2.5f);
        DrawOverlayGlowLayer(target, outerBlur, strong && startup ? 2 : 1);
        DrawOverlayGlowLayer(target, innerBlur, strong ? 2 : 1);
    }

    private static ID2D1Effect ConfigureOverlayGlowBlur(
        ID2D1DeviceContext target,
        ID2D1CommandList glowMask,
        ref ID2D1Effect? blur,
        float standardDeviation)
    {
        blur ??= new ID2D1Effect(target.CreateEffect(EffectGuids.GaussianBlur));
        blur.SetInput(0, glowMask, true);
        blur.SetValue((uint)GaussianBlurProperties.StandardDeviation, standardDeviation);
        blur.SetValue((uint)GaussianBlurProperties.Optimization, GaussianBlurOptimization.Balanced);
        return blur;
    }

    private static void DrawOverlayGlowLayer(ID2D1DeviceContext target, ID2D1Effect blur, int passes)
    {
        for (var pass = 0; pass < passes; pass++)
        {
            target.DrawImage(
                blur.Output,
                null,
                null,
                Vortice.Direct2D1.InterpolationMode.Linear,
                Vortice.Direct2D1.CompositeMode.SourceOver);
        }
    }

    private static bool ShouldDrawLagrangeGlow(OverlayCompositionFrameState? state)
    {
        return state is { LagrangeWeaveStyle: true } &&
               state.NightShadowBloom != OverlayNightShadowBloom.Off;
    }

    private void DisposeFrameBrushes()
    {
        if (_frameBrushes is null)
        {
            return;
        }

        foreach (var brush in _frameBrushes.Values)
        {
            brush.Dispose();
        }

        _frameBrushes = null;
    }

    private void DisposeOnRenderThread()
    {
        if (_renderThreadDisposed)
        {
            return;
        }

        _renderThreadDisposed = true;
        _frameScheduler?.Stop();
        _frameScheduler?.Dispose();
        _hitTraceTimer?.Stop();
        _topmostGuardTimer?.Stop();
        _frameScheduler = null;
        _hitTraceTimer = null;
        _topmostGuardTimer = null;
        _eventDetailFormat?.Dispose();
        _eventTitleFormat?.Dispose();
        _chatBarrageTimestampFormat?.Dispose();
        _chatBarrageTextFormat?.Dispose();
        _chatBarrageTitleFormat?.Dispose();
        _centerFormat?.Dispose();
        _tinyCenterFormat?.Dispose();
        _tinyFormat?.Dispose();
        _mutedRightFormat?.Dispose();
        _mutedFormat?.Dispose();
        _textRightFormat?.Dispose();
        _textFormat?.Dispose();
        _titleFormat?.Dispose();
        _cornerStrokeStyle?.Dispose();
        _writeFactory?.Dispose();
        _innerGlowEffect?.Dispose();
        _outerGlowEffect?.Dispose();
        DisposeAppearanceResources();
        _d2dDeviceContext?.Dispose();
        _d2dDevice?.Dispose();
        _d2dFactory?.Dispose();
        _surface?.Dispose();
        _rootVisual?.Dispose();
        _target?.Dispose();
        _compositionDevice?.Dispose();
        _dxgiDevice?.Dispose();
        _d3dDevice?.Dispose();
        _source?.Dispose();

        _eventDetailFormat = null;
        _eventTitleFormat = null;
        _chatBarrageTimestampFormat = null;
        _chatBarrageTextFormat = null;
        _chatBarrageTitleFormat = null;
        _chatBarrageFormatSize = 0;
        _centerFormat = null;
        _tinyCenterFormat = null;
        _tinyFormat = null;
        _mutedRightFormat = null;
        _mutedFormat = null;
        _textRightFormat = null;
        _textFormat = null;
        _titleFormat = null;
        _cornerStrokeStyle = null;
        _writeFactory = null;
        _innerGlowEffect = null;
        _outerGlowEffect = null;
        _d2dDeviceContext = null;
        _d2dDevice = null;
        _d2dFactory = null;
        _surface = null;
        _rootVisual = null;
        _target = null;
        _compositionDevice = null;
        _dxgiDevice = null;
        _d3dDevice = null;
        _source = null;

        var dispatcher = _renderDispatcher ?? Dispatcher.CurrentDispatcher;
        if (!dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished)
        {
            dispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
        }
    }

    private void NotifyClosedIfNeeded(bool notifyClosed)
    {
        if (!notifyClosed)
        {
            return;
        }

        if (_ownerDispatcher.HasShutdownStarted || _ownerDispatcher.HasShutdownFinished)
        {
            return;
        }

        _ownerDispatcher.BeginInvoke(() => Closed?.Invoke(this, EventArgs.Empty), DispatcherPriority.Background);
    }

    private void EnableMouseClickThrough()
    {
        try
        {
            var handle = _source?.Handle ?? IntPtr.Zero;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            OverlayHwndDiagnostics.ApplyClickThrough(handle, "experimental-hud-apply");
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
        }
    }

    private static void LogPerformance(string operation, Stopwatch stopwatch, bool force = false)
    {
        stopwatch.Stop();
        if (!force &&
            stopwatch.ElapsedMilliseconds < SlowOperationThresholdMs &&
            !OverlayHwndDiagnostics.IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        App.WriteDiagnosticLog($"overlay-perf operation={operation} elapsedMs={stopwatch.Elapsed.TotalMilliseconds:F1}");
    }

    private void StartHitTraceDiagnostics()
    {
        if (!OverlayHwndDiagnostics.IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        var handle = _source?.Handle ?? IntPtr.Zero;
        if (handle == IntPtr.Zero)
        {
            return;
        }

        _hitTraceDiagnosticsCount = 0;
        _hitTraceTimer?.Stop();
        _hitTraceTimer = new DispatcherTimer(DispatcherPriority.Background)
        {
            Interval = TimeSpan.FromSeconds(1)
        };
        _hitTraceTimer.Tick += (_, _) => LogRuntimeHitTrace(handle, "experimental-hud");
        _hitTraceTimer.Start();
        LogRuntimeHitTrace(handle, "experimental-hud");
    }

    private void LogRuntimeHitTrace(IntPtr handle, string label)
    {
        var count = ++_hitTraceDiagnosticsCount;
        OverlayHwndDiagnostics.LogMouseHitTest(handle, $"{label}-hit", count);
        if (count == 1 || count % 5 == 0)
        {
            OverlayHwndDiagnostics.LogVisibleTopLevelWindows($"{label}-windows", count);
        }
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmNcHitTest)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "experimental-hud", "WM_NCHITTEST", ++_hitTestDiagnosticsCount);
            handled = true;
            return new IntPtr(HtTransparent);
        }

        if (msg == WmMouseActivate)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "experimental-hud", "WM_MOUSEACTIVATE", ++_mouseActivateDiagnosticsCount);
            handled = true;
            return new IntPtr(MaNoActivate);
        }

        if (IsMouseInputMessage(msg))
        {
            OverlayHwndDiagnostics.LogInputMessage(hwnd, "experimental-hud", MouseMessageName(msg), ++_mouseInputDiagnosticsCount);
        }

        return IntPtr.Zero;
    }

    private static bool IsMouseInputMessage(int msg)
    {
        return msg is WmMouseMove or
            WmLButtonDown or
            WmLButtonUp or
            WmRButtonDown or
            WmRButtonUp or
            WmMButtonDown or
            WmMButtonUp or
            WmMouseWheel or
            WmXButtonDown or
            WmXButtonUp;
    }

    private static string MouseMessageName(int msg)
    {
        return msg switch
        {
            WmMouseMove => "WM_MOUSEMOVE",
            WmLButtonDown => "WM_LBUTTONDOWN",
            WmLButtonUp => "WM_LBUTTONUP",
            WmRButtonDown => "WM_RBUTTONDOWN",
            WmRButtonUp => "WM_RBUTTONUP",
            WmMButtonDown => "WM_MBUTTONDOWN",
            WmMButtonUp => "WM_MBUTTONUP",
            WmMouseWheel => "WM_MOUSEWHEEL",
            WmXButtonDown => "WM_XBUTTONDOWN",
            WmXButtonUp => "WM_XBUTTONUP",
            _ => $"WM_0x{msg:X4}"
        };
    }

    private static RawRectF RectF(float x, float y, float width, float height)
    {
        return new Vortice.Mathematics.Rect(x, y, width, height);
    }

    private static RawRectF ResolveHorizontalRevealClip(
        float x,
        float y,
        float width,
        float height,
        double reveal,
        bool attachedOnRight)
    {
        var revealedWidth = Math.Max(0.5f, width * (float)Math.Clamp(reveal, 0, 1));
        return attachedOnRight
            ? RectF(x + width - revealedWidth, y - 4, revealedWidth + 4, height + 8)
            : RectF(x - 4, y - 4, revealedWidth + 4, height + 8);
    }

    private static float Segment01(float value, float start, float end)
    {
        if (end <= start)
        {
            return value >= end ? 1 : 0;
        }

        return Smooth01((value - start) / (end - start));
    }

    private static float Smooth01(float value)
    {
        var t = Math.Clamp(value, 0, 1);
        return t * t * (3 - 2 * t);
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private readonly record struct BrushKey(byte R, byte G, byte B, byte A);

    [Flags]
    private enum NightShadowPanelJoin
    {
        None = 0,
        Top = 1,
        Bottom = 2,
        TopLeftStep = 4,
        TopRightStep = 8,
        BottomLeftStep = 16,
        BottomRightStep = 32,
        TopLeftNeighborOutside = 64,
        TopRightNeighborOutside = 128,
        BottomLeftNeighborOutside = 256,
        BottomRightNeighborOutside = 512
    }

    private readonly record struct HudColor(byte R, byte G, byte B, byte A)
    {
        public static HudColor FromRgb(byte red, byte green, byte blue, byte alpha = 255)
        {
            return new HudColor(red, green, blue, alpha);
        }
    }

    private sealed record OverlayHudPalette(
        HudColor PanelBackground,
        HudColor PanelBorder,
        HudColor Title,
        HudColor Text,
        HudColor Muted,
        HudColor Alert,
        HudColor Online,
        HudColor Offline,
        HudColor Crosshair,
        HudColor CrosshairAlert,
        HudColor Background);

    private sealed record OverlayCompositionModuleStyle(
        double TextOpacity,
        double BackgroundOpacity)
    {
        public static OverlayCompositionModuleStyle Default { get; } = new(1.0, 1.0);
    }

    private sealed record OverlayCompositionFrameState(
        double Width,
        double Height,
        double TextOpacity,
        double BackgroundOpacity,
        OverlayHudPalette Palette,
        OverlaySkinRenderKind RenderKind,
        bool ShowNotice,
        bool ShowSquads,
        bool ShowMembers,
        bool ShowChat,
        bool ShowCrosshair,
        bool ShowEvents,
        WpfRect NoticeRect,
        WpfRect SquadsRect,
        WpfRect MembersRect,
        WpfRect ChatRect,
        WpfRect EventRect,
        OverlayCompositionModuleStyle EventStyle,
        OverlayCompositionModuleStyle NoticeStyle,
        OverlayCompositionModuleStyle SquadsStyle,
        OverlayCompositionModuleStyle MembersStyle,
        OverlayCompositionModuleStyle ChatStyle,
        IReadOnlyList<string> ModuleDrawOrder,
        OverlayEventNotificationSide EventSide,
        OverlayNightShadowBloom NightShadowBloom,
        string FleetNoticeTitle,
        string FleetNotice,
        string NoticeTimerLabel,
        string SquadsTitle,
        string SquadPrimaryName,
        string SquadSummary,
        string SquadServerSummary,
        string SquadFocusLine,
        string OverviewLocationPlaceholder,
        string OverviewLocationPlaceholderMetric,
        IReadOnlyList<OverlayOverviewLocationCount> OverviewTopLocations,
        OverlayOverviewLocationLayoutResult OverviewLocationLayout,
        string MembersTitle,
        IReadOnlyList<OverlayCompositionMemberRow> MemberRows,
        string ChatTitle,
        OverlayChatDisplayMode ChatDisplayMode,
        OverlayChatSide ChatSide,
        double ChatBarrageFontSize,
        OverlayChatBarrageRegion ChatBarrageRegion,
        OverlayChatBarrageDensity ChatBarrageDensity,
        bool ChatBarrageAvoidCenter,
        OverlayChatTextEdgeStrength ChatTextEdgeStrength,
        IReadOnlyList<OverlayCompositionEventRow> ChatRows,
        int ChatPulse,
        bool ChatBarrageMotionEnabled,
        bool HideMemberStatus,
        double MemberNameRatio,
        string HotkeyLabel,
        OverlayCrosshairMode CrosshairMode,
        double CrosshairSize,
        double CrosshairThickness,
        double CrosshairOpacity,
        bool CrosshairShowCenterMark,
        double CrosshairCenterMarkSize,
        double CrosshairGap,
        double CrosshairOutlineOpacity,
        double EventAnimationScale,
        IReadOnlyList<OverlayCompositionEventRow> EventRows,
        int EventPulse,
        OverlayStartupTransitionFrameRate StartupTransitionFrameRate,
        OverlayAnimationFrameRate AnimationFrameRate)
    {
        public bool NightShadowStyle => RenderKind == OverlaySkinRenderKind.NightShadow;

        public bool LagrangeWeaveStyle => RenderKind == OverlaySkinRenderKind.LagrangeWeave;

        public bool VerdictStyle => RenderKind == OverlaySkinRenderKind.Verdict;

        public bool MinimalStyle => RenderKind == OverlaySkinRenderKind.Minimal;
    }

    private sealed record OverlayCompositionMemberRow(
        string DisplayName,
        string Status,
        string Ship,
        string Location,
        HudColor StatusColor);

    private sealed record OverlayCompositionEventRow(
        string Title,
        string Detail,
        string Timestamp,
        float SlideOffsetX,
        float Opacity,
        float MotionProgress,
        bool IsEntering,
        bool IsExiting,
        DateTimeOffset BarrageStartedAtUtc,
        double BarrageDurationSeconds,
        int BarrageLane,
        bool IsBarrageActive,
        HudColor AccentColor);

    private readonly record struct NightShadowStartupReveal(
        bool Applies,
        double Opacity,
        float ClipProgress,
        float Progress)
    {
        public static NightShadowStartupReveal Inactive { get; } = new(false, 1, 1, 1);
    }
}
