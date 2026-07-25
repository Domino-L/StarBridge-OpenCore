using System.Diagnostics;
using System.Numerics;
using System.Runtime.InteropServices;
using System.Threading;
using System.Windows;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Threading;
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

namespace StarBridge.Desktop;

internal sealed class OverlayCompositionStartupTransitionWindow : IDisposable
{
    private const int WsPopup = unchecked((int)0x80000000);
    private const int WsVisible = 0x10000000;
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
    private const double StartupWaitMs = 2200;
    private const float TakeoverEnd = 0.084f;
    private const float ConsoleOpenStart = 0.084f;
    private const float ConsoleOpenEnd = 0.223f;
    private const float LinkStart = 0.223f;
    private const float CompletionStart = 0.549f;
    private const float GameFocusHandoffLead = 0.055f;
    private const float CompletionPeakEnd = 0.635f;
    private const float SweepStart = 0.635f;
    private const float ConsoleCollapseDuration = 0.080f;
    private const float FadeStart = CompletionPeakEnd + ConsoleCollapseDuration * 0.5f;
    private const int SlowOperationThresholdMs = 80;

    public static double ProgressCompleteFadeStartMs => OverlayStartupTransitionLayer.DurationMs * (CompletionStart + 0.06);
    public static double PreferredGameFocusDelayMs => OverlayStartupTransitionLayer.DurationMs * (CompletionStart - GameFocusHandoffLead);

    private static readonly List<OverlayCompositionStartupTransitionWindow> ActiveWindows = [];
    private static readonly object ActiveWindowsLock = new();
    private static readonly PeripheralAnchor[] PeripheralAnchors =
    [
        new("GAME.LOG", "SYNC", 1, 0.24f, 0.24f, 1),
        new("IDENTITY", "OK", 2, 0.16f, 0.62f, 1),
        new("RELAY", "READY", 3, 0.82f, 0.36f, -1),
        new("HUD", "OK", 4, 0.70f, 0.78f, -1),
        new("SURFACE", "ONLINE", 6, 0.52f, 0.86f, 1)
    ];
    private static readonly DiagnosticPanelSpec[] DiagnosticPanels =
    [
        new(0, 0.163f, 0.285f, "SCAN"),
        new(1, 0.256f, 0.365f, "WAIT"),
        new(2, 0.349f, 0.395f, "STANDBY")
    ];

    private readonly ManualResetEventSlim _started = new(false);
    private readonly object _disposeLock = new();
    private readonly List<DataTick> _dataTicks = [];

    private Thread? _thread;
    private Dispatcher? _dispatcher;
    private Exception? _startupException;
    private bool _disposed;
    private bool _renderThreadDisposed;

    private HwndSource? _source;
    private DispatcherTimer? _frameTimer;
    private DispatcherTimer? _closeTimer;
    private DispatcherTimer? _hitTraceTimer;
    private readonly Stopwatch _clock = new();

    private ID3D11Device? _d3dDevice;
    private ID3D11DeviceContext? _d3dContext;
    private IDXGIDevice? _dxgiDevice;
    private IDCompositionDevice? _compositionDevice;
    private IDCompositionTarget? _target;
    private IDCompositionVisual? _rootVisual;
    private IDCompositionSurface? _surface;
    private ID2D1Factory? _d2dFactory;
    private IDWriteFactory? _writeFactory;
    private IDWriteTextFormat? _titleFormat;
    private IDWriteTextFormat? _monoFormat;
    private IDWriteTextFormat? _smallFormat;
    private IDWriteTextFormat? _smallRightFormat;
    private IDWriteTextFormat? _tinyFormat;
    private IDWriteTextFormat? _tinyRightFormat;
    private IDWriteTextFormat? _centerFormat;
    private Dictionary<BrushKey, ID2D1SolidColorBrush>? _frameBrushes;

    private OverlayDisplaySettings _settings = OverlayDisplaySettings.Default;
    private OverlayStartupTransitionContext _context = OverlayStartupTransitionContext.Default;
    private TerminalCompositionPalette _palette = TerminalCompositionPalette.Default;
    private IReadOnlyList<WpfRect> _revealTargets = [];
    private int _left;
    private int _top;
    private int _width;
    private int _height;
    private double _frameIntervalMs;
    private int _hitTestDiagnosticsCount;
    private int _mouseActivateDiagnosticsCount;
    private int _hitTraceDiagnosticsCount;
    private int _mouseInputDiagnosticsCount;

    private OverlayCompositionStartupTransitionWindow()
    {
    }

    public static bool TryStart(
        Window owner,
        OverlayDisplaySettings settings,
        string language,
        OverlayStartupTransitionContext? context,
        IReadOnlyList<WpfRect> revealTargets,
        out OverlayCompositionStartupTransitionWindow? transitionWindow)
    {
        _ = language;
        transitionWindow = null;
        if (!settings.EnableStartupTransition ||
            settings.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal)
        {
            return false;
        }

        var window = new OverlayCompositionStartupTransitionWindow();
        try
        {
            window.Start(ResolveDeviceBounds(owner), settings, context ?? OverlayStartupTransitionContext.Default, revealTargets);
            transitionWindow = window;
            lock (ActiveWindowsLock)
            {
                ActiveWindows.Add(window);
            }

            return true;
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            window.Dispose();
            return false;
        }
    }

    public static bool TryStart(
        WpfRect surfaceBounds,
        double dpiScaleX,
        double dpiScaleY,
        OverlayDisplaySettings settings,
        string language,
        OverlayStartupTransitionContext? context,
        IReadOnlyList<WpfRect> revealTargets,
        out OverlayCompositionStartupTransitionWindow? transitionWindow)
    {
        _ = language;
        transitionWindow = null;
        if (!settings.EnableStartupTransition ||
            settings.StartupTransitionStyle != OverlayStartupTransitionStyle.BridgeTerminal)
        {
            return false;
        }

        var bounds = (
            X: (int)Math.Round(surfaceBounds.X * dpiScaleX),
            Y: (int)Math.Round(surfaceBounds.Y * dpiScaleY),
            Width: (int)Math.Round(surfaceBounds.Width * dpiScaleX),
            Height: (int)Math.Round(surfaceBounds.Height * dpiScaleY));
        var window = new OverlayCompositionStartupTransitionWindow();
        try
        {
            window.Start(bounds, settings, context ?? OverlayStartupTransitionContext.Default, revealTargets);
            transitionWindow = window;
            lock (ActiveWindowsLock)
            {
                ActiveWindows.Add(window);
            }

            return true;
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            window.Dispose();
            return false;
        }
    }

    public void Dispose()
    {
        lock (_disposeLock)
        {
            if (_disposed)
            {
                return;
            }

            _disposed = true;
        }

        lock (ActiveWindowsLock)
        {
            ActiveWindows.Remove(this);
        }

        var dispatcher = _dispatcher;
        if (dispatcher is null || dispatcher.HasShutdownStarted || dispatcher.HasShutdownFinished)
        {
            return;
        }

        if (dispatcher.CheckAccess())
        {
            DisposeOnRenderThread();
        }
        else
        {
            dispatcher.BeginInvoke(DisposeOnRenderThread, DispatcherPriority.Send);
        }
    }

    private void Start(
        (int X, int Y, int Width, int Height) bounds,
        OverlayDisplaySettings settings,
        OverlayStartupTransitionContext context,
        IReadOnlyList<WpfRect> revealTargets)
    {
        var stopwatch = Stopwatch.StartNew();
        try
        {
            if (bounds.Width <= 1 || bounds.Height <= 1)
            {
                throw new InvalidOperationException("Overlay transition composition bounds are empty.");
            }

            _left = bounds.X;
            _top = bounds.Y;
            _width = bounds.Width;
            _height = bounds.Height;
            _settings = settings;
            _context = context;
            _palette = ResolvePalette(settings);
            _revealTargets = revealTargets.ToArray();
            _frameIntervalMs = GetTargetFrameIntervalMs(settings.StartupTransitionFrameRate);
            BuildDataTicks();

            _thread = new Thread(RenderThreadMain)
            {
                IsBackground = true,
                Name = "StarBridge Overlay DirectComposition Transition"
            };
            _thread.SetApartmentState(ApartmentState.STA);
            _thread.Start();

            if (!_started.Wait(TimeSpan.FromMilliseconds(StartupWaitMs)))
            {
                throw new TimeoutException("DirectComposition overlay transition startup timed out.");
            }

            if (_startupException is not null)
            {
                throw new InvalidOperationException("DirectComposition overlay transition startup failed.", _startupException);
            }
        }
        finally
        {
            LogPerformance("dcomp-transition-start", stopwatch);
        }
    }

    private void RenderThreadMain()
    {
        var readyStopwatch = Stopwatch.StartNew();
        try
        {
            _dispatcher = Dispatcher.CurrentDispatcher;
            var createStopwatch = Stopwatch.StartNew();
            CreateWindowAndResources();
            LogPerformance("dcomp-transition-create-window-resources", createStopwatch);
            var firstFrameStopwatch = Stopwatch.StartNew();
            DrawFrame(0);
            LogPerformance("dcomp-transition-first-frame", firstFrameStopwatch);
            ShowWindow(_source!.Handle, SwShowna);
            EnableMouseClickThrough();
            StartHitTraceDiagnostics();

            _clock.Start();
            _frameTimer = new DispatcherTimer(DispatcherPriority.Render)
            {
                Interval = TimeSpan.FromMilliseconds(_frameIntervalMs)
            };
            _frameTimer.Tick += OnFrameTick;
            _frameTimer.Start();

            _closeTimer = new DispatcherTimer(DispatcherPriority.Background)
            {
                Interval = TimeSpan.FromMilliseconds(OverlayStartupTransitionLayer.DurationMs + 130)
            };
            _closeTimer.Tick += (_, _) => Dispose();
            _closeTimer.Start();

            _started.Set();
            LogPerformance("dcomp-transition-render-ready", readyStopwatch);
            Dispatcher.Run();
        }
        catch (Exception exception)
        {
            _startupException = exception;
            _started.Set();
            LogPerformance("dcomp-transition-render-failed", readyStopwatch, force: true);
            App.WriteCrashLog(exception);
            DisposeOnRenderThread();
        }
    }

    private void CreateWindowAndResources()
    {
        var parameters = new HwndSourceParameters("StarBridge Overlay Startup Transition")
        {
            PositionX = _left,
            PositionY = _top,
            Width = _width,
            Height = _height,
            WindowStyle = WsPopup | WsVisible,
            ExtendedWindowStyle = OverlayHwndDiagnostics.ClickThroughExtendedStyle,
            UsesPerPixelOpacity = true
        };

        _source = new HwndSource(parameters);
        _source.AddHook(WindowProc);
        OverlayHwndDiagnostics.LogState(_source.Handle, "startup-transition-created");
        EnableMouseClickThrough();

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
        OverlayHwndDiagnostics.LogState(_source.Handle, "startup-transition-target-bound");
        _compositionDevice.CreateVisual(out _rootVisual);
        _compositionDevice.CreateSurface(
            (uint)_width,
            (uint)_height,
            DxgiFormat.B8G8R8A8_UNorm,
            DxgiAlphaMode.Premultiplied,
            out _surface);
        _rootVisual!.SetContent(_surface);
        _target!.SetRoot(_rootVisual);
        _compositionDevice.Commit();

        _d2dFactory = Vortice.Direct2D1.D2D1.D2D1CreateFactory<ID2D1Factory>(D2DFactoryType.SingleThreaded);
        _writeFactory = DWrite.DWriteCreateFactory<IDWriteFactory>(DWriteFactoryType.Shared);
        CreateTextFormats();
    }

    private void CreateTextFormats()
    {
        if (_writeFactory is null)
        {
            return;
        }

        _titleFormat = CreateTextFormat("Segoe UI Semibold", 16, DWriteFontWeight.SemiBold, DWriteTextAlignment.Center);
        _monoFormat = CreateTextFormat("Consolas", 13, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        _smallFormat = CreateTextFormat("Consolas", 11, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _smallRightFormat = CreateTextFormat("Consolas", 11, DWriteFontWeight.SemiBold, DWriteTextAlignment.Trailing);
        _tinyFormat = CreateTextFormat("Consolas", 9, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _tinyRightFormat = CreateTextFormat("Consolas", 9, DWriteFontWeight.SemiBold, DWriteTextAlignment.Trailing);
        _centerFormat = CreateTextFormat("Segoe UI Semibold", 12, DWriteFontWeight.SemiBold, DWriteTextAlignment.Center);
    }

    private IDWriteTextFormat CreateTextFormat(
        string family,
        float size,
        DWriteFontWeight weight,
        DWriteTextAlignment alignment)
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
        format.ParagraphAlignment = ParagraphAlignment.Center;
        format.WordWrapping = WordWrapping.NoWrap;
        return format;
    }

    private void OnFrameTick(object? sender, EventArgs e)
    {
        try
        {
            var elapsedMs = _clock.Elapsed.TotalMilliseconds;
            DrawFrame(elapsedMs);
            if (elapsedMs >= OverlayStartupTransitionLayer.DurationMs + 80)
            {
                Dispose();
            }
        }
        catch (Exception exception)
        {
            App.WriteCrashLog(exception);
            Dispose();
        }
    }

    private void DrawFrame(double elapsedMs)
    {
        if (_surface is null || _d2dFactory is null || _compositionDevice is null)
        {
            return;
        }

        var progress = (float)Math.Clamp(elapsedMs / OverlayStartupTransitionLayer.DurationMs, 0, 1);
        RawRect frameRect = new RectI(0, 0, _width, _height);

        IDXGISurface? dxgiSurface = null;
        ID2D1RenderTarget? target = null;
        _surface.BeginDraw(frameRect, out dxgiSurface, out _);
        try
        {
            var properties = new RenderTargetProperties(
                RenderTargetType.Default,
                new Vortice.DCommon.PixelFormat(DxgiFormat.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
                96,
                96,
                RenderTargetUsage.None,
                Vortice.Direct2D1.FeatureLevel.Default);
            target = _d2dFactory.CreateDxgiSurfaceRenderTarget(dxgiSurface, properties);
            target.BeginDraw();
            target.Clear(new Color4(0, 0, 0, 0));
            _frameBrushes = [];
            DrawScene(target, progress);
            ulong tag1 = 0;
            ulong tag2 = 0;
            target.EndDraw(out tag1, out tag2);
        }
        finally
        {
            DisposeFrameBrushes();
            target?.Dispose();
            dxgiSurface?.Dispose();
            _surface.EndDraw();
            _compositionDevice.Commit();
        }
    }

    private IReadOnlyList<OverlayStartupStatusStep> StatusSteps => _context.StatusSteps.Count >= 7
        ? _context.StatusSteps
        : OverlayStartupTransitionContext.Default.StatusSteps;

    private IReadOnlyList<string> TerminalLines => _context.TerminalLines.Count > 0
        ? _context.TerminalLines
        : OverlayStartupTransitionContext.Default.TerminalLines;

    private void DrawScene(ID2D1RenderTarget target, float p)
    {
        var layerOpacity = TerminalLayerOpacity(p);
        if (layerOpacity <= 0.001f)
        {
            return;
        }

        DrawTerminalBackground(target, p, layerOpacity);
        DrawTakeoverIgnition(target, p, layerOpacity);
        DrawMatrixCanvas(target, p, layerOpacity);
        DrawFullscreenFrame(target, p, layerOpacity);
        DrawPeripheralEdgeAccess(target, p, layerOpacity);
        DrawEdgeDiagnostics(target, p, layerOpacity);
        DrawGlobalReadouts(target, p, layerOpacity);
        DrawUpperLeftDiagnostics(target, p, layerOpacity);
        DrawControlSurfaceBackplane(target, p, layerOpacity);
        DrawDiagnosticStrip(target, p, layerOpacity);
        DrawPeripheralScreenScans(target, p, layerOpacity);
        DrawPeripheralLinkLayer(target, p, layerOpacity);
        DrawTerminalAuraPulses(target, p, layerOpacity);
        DrawTerminalConsole(target, p, layerOpacity);
        DrawOverlayMountTargets(target, p, layerOpacity);
        DrawTerminalFlash(target, p, layerOpacity);
        DrawCompletionSweep(target, p, layerOpacity);
        DrawGlitches(target, p, layerOpacity);
    }

    private void DrawTerminalBackground(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var takeover = Smooth01(t / TakeoverEnd);
        var intensity = takeover * (0.50f + 0.34f * MathF.Sin(Math.Clamp(t / 0.72f, 0, 1) * MathF.PI));
        var impact = Pulse(t, 0.012f, 0.052f) + Pulse(t, 0.046f, 0.040f);
        FillRect(target, 0, 0, _width, _height, _palette.Background, (0.80f + 0.16f * takeover + 0.06f * impact) * layerOpacity);

        var cx = _width * 0.5f;
        var cy = _height * 0.48f;
        FillRect(target, _width * 0.18f, cy - _height * 0.20f, _width * 0.64f, _height * 0.40f, _palette.Primary, 0.006f * intensity * layerOpacity);
        FillHorizontalSoftBand(target, cx - _width * 0.34f, cy, _width * 0.68f, _height * 0.16f, _palette.Primary, 0.010f * intensity * layerOpacity);

        var gridAlpha = (0.012f + 0.026f * takeover + 0.012f * intensity) * (1 - Smooth01((t - 0.92f) / 0.08f)) * layerOpacity;
        if (gridAlpha > 0.003f)
        {
            using var gridBrush = Brush(target, _palette.Primary, gridAlpha);
            for (var x = 0.5f; x < _width; x += 56)
            {
                target.DrawLine(new Vector2(x, 0), new Vector2(x, _height), gridBrush, 0.65f);
            }

            for (var y = 0.5f; y < _height; y += 56)
            {
                target.DrawLine(new Vector2(0, y), new Vector2(_width, y), gridBrush, 0.65f);
            }
        }

        FillHorizontalSoftBand(target, _width * 0.12f, _height * 0.18f, _width * 0.76f, 18, _palette.Primary, (0.030f + 0.030f * impact) * takeover * layerOpacity);
        FillHorizontalSoftBand(target, _width * 0.18f, _height * 0.82f, _width * 0.64f, 16, _palette.Primary, 0.024f * takeover * layerOpacity);
        FillRect(target, 0, 0, _width, _height * 0.16f, Color(0, 0, 0), 0.25f * layerOpacity);
        FillRect(target, 0, _height * 0.72f, _width, _height * 0.28f, Color(0, 0, 0), 0.28f * layerOpacity);
    }

    private void DrawTakeoverIgnition(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        if (t > TakeoverEnd + 0.035f)
        {
            return;
        }

        var local = Math.Clamp(t / TakeoverEnd, 0, 1);
        var flicker = Pulse(t, 0.010f, 0.022f) + Pulse(t, 0.034f, 0.024f) + 0.65f * Pulse(t, 0.065f, 0.030f);
        var alpha = (0.42f + 0.58f * flicker) * (1 - Smooth01((t - TakeoverEnd) / 0.035f)) * layerOpacity;
        var cy = _height * 0.5f + 14;
        var lineWidth = _width * (0.05f + 0.34f * Smooth01(local));
        var x = (_width - lineWidth) * 0.5f;

        FillHorizontalSoftBand(target, x - 60, cy, lineWidth + 120, 16, _palette.Primary, 0.15f * alpha);
        FillRect(target, x, cy - 1.2f, lineWidth, 2.4f, _palette.Primary, 0.66f * alpha);
        FillRect(target, x + lineWidth * 0.42f, cy - 0.5f, lineWidth * 0.16f, 1, _palette.Text, 0.92f * alpha);

        var pulse = Pulse(t, 0.030f, 0.060f);
        if (pulse > 0.01f)
        {
            FillRect(target, _width * 0.20f, cy - 28, _width * 0.60f, 56, _palette.Primary, 0.055f * pulse * layerOpacity);
            FillRect(target, _width * 0.34f, cy - 3, _width * 0.32f, 6, _palette.Text, 0.12f * pulse * layerOpacity);
        }

        var cornerPulse = Pulse(t, 0.024f, 0.075f);
        if (cornerPulse <= 0.01f)
        {
            return;
        }

        var inset = 22f;
        using var corner = Brush(target, _palette.Text, 0.72f * cornerPulse * layerOpacity);
        DrawAnimatedCorner(target, corner, inset, inset, 118, 1, 1, 1);
        DrawAnimatedCorner(target, corner, _width - inset, inset, 118, -1, 1, 1);
        DrawAnimatedCorner(target, corner, _width - inset, _height - inset, 118, -1, -1, 1);
        DrawAnimatedCorner(target, corner, inset, _height - inset, 118, 1, -1, 1);
    }

    private void DrawMatrixCanvas(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var takeover = Smooth01(t / TakeoverEnd);
        var finishFade = 1 - Smooth01((t - FadeStart) / 0.12f);
        var intensity = takeover * MathF.Sin(Math.Clamp(t / (TakeoverEnd + 0.03f), 0, 1) * MathF.PI) * finishFade;
        var scanY = -_height * 0.18f + _height * 1.34f * Math.Clamp(t / TakeoverEnd, 0, 1);
        var opacity = (1 - Smooth01((t - TakeoverEnd) / 0.035f)) * intensity * layerOpacity;
        if (opacity <= 0.002f)
        {
            return;
        }

        FillRect(target, 0, scanY - 18, _width, 36, _palette.Primary, 0.035f * opacity);
        FillRect(target, 0, scanY - 4, _width, 8, _palette.Primary, 0.10f * opacity);
        FillRect(target, 0, scanY - 0.6f, _width, 1.2f, _palette.Text, 0.16f * opacity);
    }

    private void DrawFullscreenFrame(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var flash = Pulse(t, 0.022f, 0.082f);
        var steady = Smooth01((t - 0.075f) / 0.08f) * (1 - Smooth01((t - FadeStart) / 0.12f));
        var opacity = Math.Clamp(steady * 0.55f + flash * 0.80f, 0, 1) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var inset = 24f;
        var width = Math.Max(0, _width - inset * 2);
        var height = Math.Max(0, _height - inset * 2);
        using var framePen = Brush(target, _palette.Primary, (0.18f + 0.12f * flash) * opacity);
        using var hotPen = Brush(target, _palette.Text, (0.44f + 0.46f * flash) * opacity);
        target.DrawRectangle(Rect(inset, inset, width, height), framePen, 0.8f);
        DrawAnimatedCorner(target, hotPen, inset, inset, 96, 1, 1, Smooth01((t - 0.018f) / 0.055f));
        DrawAnimatedCorner(target, hotPen, _width - inset, inset, 96, -1, 1, Smooth01((t - 0.026f) / 0.055f));
        DrawAnimatedCorner(target, hotPen, _width - inset, _height - inset, 96, -1, -1, Smooth01((t - 0.034f) / 0.055f));
        DrawAnimatedCorner(target, hotPen, inset, _height - inset, 96, 1, -1, Smooth01((t - 0.042f) / 0.055f));

        using var bandPen = Brush(target, _palette.Primary, 0.24f * opacity);
        target.DrawLine(new Vector2(_width * 0.18f, inset + 72), new Vector2(_width * 0.82f, inset + 72), bandPen, 0.8f);
        target.DrawLine(new Vector2(_width * 0.18f, _height - inset - 72), new Vector2(_width * 0.82f, _height - inset - 72), bandPen, 0.8f);
    }

    private void DrawEdgeDiagnostics(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var opacity = Smooth01((t - 0.06f) / 0.18f) * (1 - Smooth01((t - FadeStart) / 0.12f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        using var tickPen = Brush(target, _palette.Primary, 0.24f * opacity);
        using var hotPen = Brush(target, _palette.Text, 0.50f * opacity);
        for (var i = 0; i < 18; i++)
        {
            var x = 56 + i * Math.Max(42f, (_width - 112f) / 17f);
            var pulse = Smooth01((t - (0.08f + i * 0.006f)) / 0.08f);
            var length = 8 + 12 * (i % 3 == 0 ? 1 : 0);
            var pen = i % 4 == 0 ? hotPen : tickPen;
            target.DrawLine(new Vector2(x, 28), new Vector2(x, 28 + length * pulse), pen, 1);
            target.DrawLine(new Vector2(x, _height - 28), new Vector2(x, _height - 28 - length * pulse), tickPen, 1);
        }

        for (var i = 0; i < 10; i++)
        {
            var y = 92 + i * Math.Max(48f, (_height - 184f) / 9f);
            var pulse = Smooth01((t - (0.1f + i * 0.01f)) / 0.08f);
            target.DrawLine(new Vector2(28, y), new Vector2(28 + 16 * pulse, y), tickPen, 1);
            target.DrawLine(new Vector2(_width - 28, y), new Vector2(_width - 28 - 16 * pulse, y), i % 3 == 0 ? hotPen : tickPen, 1);
        }

        var blockOpacity = (0.16f + 0.12f * MathF.Sin(t * MathF.PI * 8)) * opacity;
        FillRect(target, 32, _height * 0.5f - 42, 3, 84, _palette.Primary, blockOpacity);
        FillRect(target, _width - 35, _height * 0.5f - 42, 3, 84, _palette.Primary, blockOpacity);
        DrawText(target, _context.BottomLeftDiagnostic, _tinyFormat, 42, _height - 54, 320, 18, _palette.Primary, 0.72f * opacity);
        DrawText(target, _context.BottomRightDiagnostic, _tinyRightFormat, _width - 342, _height - 54, 300, 18, _palette.Primary, 0.72f * opacity);
    }

    private void DrawPeripheralEdgeAccess(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var access = Smooth01(t / 0.055f) * (1 - Smooth01((t - 0.165f) / 0.090f)) * layerOpacity;
        if (access <= 0.01f)
        {
            return;
        }

        var extend = Smooth01(t / 0.12f);
        var centerX = _width * 0.5f;
        var topY = Math.Clamp(_height * 0.09f, 62, 108);
        var bottomY = _height - topY;
        var halfWidth = _width * 0.38f * extend;
        DrawLayeredLine(target, centerX - halfWidth, topY, centerX + halfWidth, topY, 0.28f * access);
        DrawLayeredLine(target, centerX - halfWidth * 0.86f, bottomY, centerX + halfWidth * 0.86f, bottomY, 0.22f * access);

        using var tick = Brush(target, _palette.Primary, 0.18f * access);
        using var hot = Brush(target, _palette.Text, 0.24f * access);
        for (var i = 0; i < 7; i++)
        {
            var y = _height * (0.20f + i * 0.085f);
            var phase = Smooth01((t - i * 0.010f) / 0.075f);
            var length = (12 + (i % 3) * 5) * phase;
            target.DrawLine(new Vector2(28, y), new Vector2(28 + length, y), i == 2 || i == 5 ? hot : tick, 0.8f);
            target.DrawLine(new Vector2(_width - 28, y), new Vector2(_width - 28 - length, y), i == 1 || i == 4 ? hot : tick, 0.8f);
        }
    }

    private void DrawGlobalReadouts(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var opacity = Smooth01((t - 0.06f) / 0.18f) * (1 - Smooth01((t - FadeStart) / 0.12f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        DrawTitleStrip(target, t, opacity);
        DrawConnectionRail(target, t, opacity);
    }

    private void DrawTitleStrip(ID2D1RenderTarget target, float t, float opacity)
    {
        var stripWidth = Math.Min(980, _width - 96);
        if (stripWidth <= 120)
        {
            return;
        }

        var open = Smooth01((t - 0.06f) / 0.16f);
        var rectX = (_width - stripWidth * open) * 0.5f;
        var rectW = stripWidth * open;
        FillRect(target, rectX, 32, rectW, 48, _palette.Background, 0.82f * opacity);
        FillRect(target, rectX, 32, rectW, 48, _palette.Primary, 0.035f * opacity);
        DrawLayeredLine(target, rectX, 32, rectX + rectW, 32, opacity * 0.42f);
        DrawLayeredLine(target, rectX, 80, rectX + rectW, 80, opacity * 0.26f);

        if (open < 0.82f)
        {
            return;
        }

        var state = t >= CompletionStart ? _context.OnlineStateLabel : t >= LinkStart ? _context.CheckingStateLabel : _context.MountingStateLabel;
        DrawText(target, _context.HeaderTargetLabel, _tinyFormat, rectX + 18, 44, rectW * 0.30f, 18, _palette.Muted, 0.86f * opacity);
        DrawText(target, _context.SurfaceTitle, _titleFormat, rectX, 34, rectW, 44, _palette.Text, 0.98f * opacity);
        DrawText(target, state, _tinyRightFormat, rectX + rectW - 218, 44, 200, 18, t >= CompletionStart ? _palette.Success : _palette.Primary, 0.9f * opacity);
    }

    private void DrawConnectionRail(ID2D1RenderTarget target, float t, float opacity)
    {
        var railWidth = Math.Min(760, _width - 180);
        if (railWidth <= 180)
        {
            return;
        }

        var x = (_width - railWidth) * 0.5f;
        var y = 96f;
        var count = Math.Min(7, StatusSteps.Count);
        var gap = 8f;
        var segment = (railWidth - gap * (count - 1)) / count;
        for (var i = 0; i < count; i++)
        {
            var activation = StatusProgress(t, i);
            var appear = Smooth01((t - (LinkStart + i * 0.026f)) / 0.10f);
            if (appear <= 0.01f)
            {
                continue;
            }

            var sx = x + i * (segment + gap);
            var color = activation > 0.95f ? _palette.Success : activation > 0.12f ? _palette.Primary : _palette.Muted;
            FillRect(target, sx, y, segment, 1, _palette.Muted, 0.10f * opacity * appear);
            FillRect(target, sx, y, segment * activation, 1, color, 0.42f * opacity * appear);
            if (activation > 0.02f && activation < 1)
            {
                FillRect(target, sx + segment * activation - 10, y - 2, 20, 5, _palette.Primary, 0.08f * opacity * appear);
            }
        }
    }

    private void DrawUpperLeftDiagnostics(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var fade = (1 - Smooth01((t - FadeStart) / 0.10f)) * layerOpacity;
        if (fade <= 0.01f)
        {
            return;
        }

        var width = Math.Clamp(_width * 0.16f, 268, 320);
        var height = 58f;
        var gap = 9f;
        var x = Math.Clamp(_width * 0.030f, 44, 70);
        var y = Math.Clamp(_height * 0.135f, 112, 156);

        for (var i = 0; i < DiagnosticPanels.Length; i++)
        {
            DrawDiagnosticPanel(target, DiagnosticPanels[i], i, x, y + i * (height + gap), width, height, t, fade);
        }
    }

    private void DrawDiagnosticPanel(
        ID2D1RenderTarget target,
        DiagnosticPanelSpec panel,
        int stackIndex,
        float x,
        float y,
        float width,
        float height,
        float t,
        float layerOpacity)
    {
        var appear = Smooth01((t - panel.AppearStart) / 0.055f);
        if (appear <= 0.01f)
        {
            return;
        }

        var done = Smooth01((t - panel.DoneStart) / 0.050f);
        var pulse = Pulse(t, panel.AppearStart, 0.080f) * 0.45f + Pulse(t, panel.DoneStart, 0.085f);
        var alpha = appear * layerOpacity;
        var slideX = x - (1 - appear) * 18;
        var step = StatusSteps[Math.Clamp(panel.StatusIndex, 0, StatusSteps.Count - 1)];
        var state = done >= 0.96f ? step.DoneState : panel.PendingState;
        var stateColor = done >= 0.96f ? _palette.Success : done > 0.12f ? _palette.Primary : _palette.Warning;

        FillPanelGradient(target, slideX, y, width, height, 0.34f * alpha);
        FillRect(target, slideX, y, width, height, _palette.Background, 0.46f * alpha);
        FillRect(target, slideX, y, width, height, stateColor, (0.020f + 0.030f * pulse) * alpha);

        using var outer = Brush(target, _palette.Primary, (0.075f + 0.13f * pulse) * alpha);
        using var border = Brush(target, _palette.Primary, (0.25f + 0.22f * pulse) * alpha);
        using var hot = Brush(target, _palette.Text, (0.10f + 0.16f * pulse) * alpha);
        target.DrawRectangle(Rect(slideX - 2, y - 2, width + 4, height + 4), outer, 2.0f);
        target.DrawRectangle(Rect(slideX, y, width, height), border, 0.9f);
        target.DrawRectangle(Rect(slideX + 5, y + 5, width - 10, height - 10), hot, 0.45f);

        DrawText(target, step.Label, _tinyFormat, slideX + 11, y + 7, width - 94, 14, _palette.Primary, 0.72f * alpha);
        DrawText(target, DiagnosticValue(step, panel, done), _smallFormat, slideX + 11, y + 27, width - 98, 18, _palette.Text, 0.76f * alpha);
        DrawText(target, state, _tinyRightFormat, slideX + width - 80, y + 26, 62, 16, stateColor, (0.62f + 0.22f * done + 0.16f * pulse) * alpha);

        FillEllipse(target, slideX + width - 16, y + 13, 2.8f + 1.8f * pulse, 2.8f + 1.8f * pulse, stateColor, (0.30f + 0.38f * done + 0.22f * pulse) * alpha);

        var trackX = slideX + 11;
        var trackY = y + height - 8;
        var trackWidth = width - 22;
        FillRect(target, trackX, trackY, trackWidth, 1, _palette.Muted, 0.08f * alpha);
        FillRect(target, trackX, trackY, trackWidth * Math.Clamp(done, 0.08f, 1), 1, stateColor, (0.18f + 0.26f * done) * alpha);

        var scan = Math.Clamp((t - (panel.AppearStart + 0.012f)) / 0.150f, 0, 1);
        if (scan > 0 && scan < 1)
        {
            var sweepX = trackX - 14 + (trackWidth + 28) * Smooth01(scan);
            FillRect(target, sweepX - 16, y + 3, 34, height - 7, _palette.Primary, 0.060f * MathF.Sin(scan * MathF.PI) * alpha);
            FillRect(target, sweepX, y + 4, 1, height - 9, _palette.Text, 0.10f * MathF.Sin(scan * MathF.PI) * alpha);
        }

        if (stackIndex == 0)
        {
            FillRect(target, slideX - 10, y + 8, 1, height * DiagnosticStackProgress(t), _palette.Primary, 0.11f * alpha);
        }
    }

    private void DrawControlSurfaceBackplane(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var opacity = Smooth01((t - 0.22f) / 0.18f) * (1 - Smooth01((t - FadeStart) / 0.12f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var panelWidth = Math.Min(980, _width * 0.68f);
        var x = (_width - panelWidth) * 0.5f;
        var centerY = _height * 0.52f + 20;
        FillHorizontalSoftBand(target, x - 50, centerY - 88, panelWidth + 100, 24, _palette.Primary, 0.018f * opacity);
        FillHorizontalSoftBand(target, x + 34, centerY + 108, panelWidth - 68, 18, _palette.Primary, 0.014f * opacity);

        using var rail = Brush(target, _palette.Primary, 0.13f * opacity);
        using var hot = Brush(target, _palette.Text, 0.18f * opacity);
        for (var i = 0; i < 4; i++)
        {
            var yy = centerY - 96 + i * 64;
            target.DrawLine(new Vector2(x + 70, yy), new Vector2(x + panelWidth - 70, yy), rail, 0.7f);
            var sweep = Smooth01((t - (0.30f + i * 0.055f)) / 0.22f);
            if (sweep > 0 && sweep < 1)
            {
                var sx = x + 120 + (panelWidth - 240) * sweep;
                target.DrawLine(new Vector2(sx - 42, yy), new Vector2(sx + 18, yy), hot, 1.0f);
            }
        }

        FillRect(target, x + 18, centerY - 118, 1, 236, _palette.Primary, 0.08f * opacity);
        FillRect(target, x + panelWidth - 19, centerY - 118, 1, 236, _palette.Primary, 0.08f * opacity);
    }

    private void DrawDiagnosticStrip(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var opacity = Smooth01((t - 0.32f) / 0.18f) * (1 - Smooth01((t - FadeStart) / 0.12f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var stripWidth = Math.Min(780, _width - 120);
        var x = (_width - stripWidth) * 0.5f;
        var y = _height * 0.5f + Math.Min(330, _height * 0.32f);
        var cell = (stripWidth - 17 * 5) / 18;
        for (var i = 0; i < 18; i++)
        {
            var statusIndex = Math.Min(StatusSteps.Count - 1, i / 3);
            var ready = StatusProgress(t, statusIndex);
            var pulse = 0.24f + 0.76f * MathF.Sin((t * 3 + i * 0.11f) * MathF.PI);
            var alpha = (0.035f + ready * 0.12f + pulse * 0.045f) * opacity;
            FillRect(target, x + i * (cell + 5), y, cell, 4, ready > 0.95f ? _palette.Success : _palette.Primary, alpha);
        }
    }

    private void DrawPeripheralScreenScans(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var vertical = Pulse(t, 0.030f, 0.115f) * layerOpacity;
        if (vertical > 0.01f)
        {
            var p = Math.Clamp((t - 0.030f) / 0.115f, 0, 1);
            var x = -_width * 0.06f + _width * 1.12f * Smooth01(p);
            FillVerticalSoftBand(target, x, 0, _height, 30, _palette.Primary, 0.075f * vertical);
            FillRect(target, x - 0.5f, 0, 1, _height, _palette.Text, 0.16f * vertical);
        }

        var horizontal = Pulse(t, SweepStart + 0.012f, 0.135f) * layerOpacity;
        if (horizontal <= 0.01f)
        {
            return;
        }

        var y = CompletionSweepY(_height, t);
        FillHorizontalSoftBand(target, 0, y, _width, 34, _palette.Primary, 0.075f * horizontal);
        FillRect(target, 0, y - 0.5f, _width, 1, _palette.Text, 0.20f * horizontal);
    }

    private void DrawPeripheralLinkLayer(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var metrics = ResolveConsoleMetrics(t);
        if (metrics.Open <= 0.30f || metrics.Collapse >= 0.94f)
        {
            return;
        }

        var origin = new Vector2(metrics.X + metrics.Width * 0.5f, metrics.Y + metrics.Height * 0.5f);
        foreach (var anchor in PeripheralAnchors)
        {
            DrawPeripheralAnchor(target, t, layerOpacity, origin, anchor);
        }
    }

    private void DrawPeripheralAnchor(ID2D1RenderTarget target, float t, float layerOpacity, Vector2 origin, PeripheralAnchor anchor)
    {
        var start = StatusStart(anchor.StatusIndex) - 0.050f;
        var active = Smooth01((t - start) / 0.090f) * (1 - Smooth01((t - (start + 0.310f)) / 0.120f));
        if (active <= 0.01f)
        {
            return;
        }

        var progress = StatusProgress(t, anchor.StatusIndex);
        var pulse = StatusPulse(t, anchor.StatusIndex);
        var alpha = active * layerOpacity;
        var targetPoint = new Vector2(_width * anchor.X, _height * anchor.Y);
        var endPoint = Vector2.Lerp(origin, targetPoint, 0.92f);
        var color = progress > 0.95f ? _palette.Success : _palette.Primary;

        using var lineGlow = Brush(target, _palette.Primary, 0.045f * alpha);
        using var line = Brush(target, color, (0.12f + 0.14f * progress + 0.12f * pulse) * alpha);
        target.DrawLine(origin, endPoint, lineGlow, 3.0f);
        target.DrawLine(origin, endPoint, line, 0.8f);

        var dotProgress = Smooth01((t - start) / 0.160f);
        var dot = Vector2.Lerp(origin, endPoint, dotProgress);
        FillEllipse(target, dot.X, dot.Y, 2.3f + pulse * 1.6f, 2.3f + pulse * 1.6f, _palette.Text, (0.34f + 0.28f * pulse) * alpha);

        var labelX = targetPoint.X + anchor.LabelSide * 12;
        var labelY = targetPoint.Y - 12;
        var tickX = targetPoint.X + anchor.LabelSide * 7;
        var tickEnd = targetPoint.X + anchor.LabelSide * 34;
        using var tick = Brush(target, color, (0.22f + 0.24f * progress + 0.18f * pulse) * alpha);
        target.DrawLine(new Vector2(tickX, targetPoint.Y), new Vector2(tickEnd, targetPoint.Y), tick, 0.8f);
        FillEllipse(target, targetPoint.X, targetPoint.Y, 3.0f + pulse * 2.2f, 3.0f + pulse * 2.2f, color, (0.30f + 0.38f * progress + 0.18f * pulse) * alpha);

        var textX = anchor.LabelSide > 0 ? labelX + 28 : labelX - 112;
        var status = progress > 0.95f ? anchor.DoneState : "LINK";
        DrawText(target, anchor.Label, _tinyFormat, textX, labelY, 96, 14, _palette.Muted, 0.74f * alpha);
        DrawText(target, status, anchor.LabelSide > 0 ? _tinyFormat : _tinyRightFormat, textX, labelY + 13, 96, 14, color, (0.58f + 0.28f * progress + 0.14f * pulse) * alpha);
    }

    private void DrawTerminalAuraPulses(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var metrics = ResolveConsoleMetrics(t);
        if (metrics.Open <= 0.10f)
        {
            return;
        }

        DrawTerminalAuraPulse(target, metrics, Pulse(t, ConsoleOpenEnd - 0.018f, 0.125f), 0.82f, layerOpacity);
        DrawTerminalAuraPulse(target, metrics, Pulse(t, CompletionStart, 0.180f), 1.22f, layerOpacity);
    }

    private void DrawTerminalAuraPulse(ID2D1RenderTarget target, ConsoleMetrics metrics, float pulse, float scale, float layerOpacity)
    {
        if (pulse <= 0.01f)
        {
            return;
        }

        var cx = metrics.X + metrics.Width * 0.5f;
        var cy = metrics.Y + metrics.Height * 0.5f;
        var width = metrics.Width * (0.80f + 0.18f * scale);
        var height = Math.Max(22, metrics.Height * (0.18f + 0.05f * scale));
        FillRect(target, cx - width * 0.5f, cy - height * 0.5f, width, height, _palette.Primary, 0.010f * pulse * layerOpacity);
        FillHorizontalSoftBand(target, cx - width * 0.42f, cy, width * 0.84f, 14, _palette.Primary, 0.034f * pulse * layerOpacity);
        FillRect(target, cx - width * 0.22f, cy - 1, width * 0.44f, 2, _palette.Text, 0.018f * pulse * layerOpacity);
    }

    private void DrawTerminalConsole(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var opacity = Smooth01((t - ConsoleOpenStart) / 0.12f) * (1 - Smooth01((t - 0.9f) / 0.08f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var metrics = ResolveConsoleMetrics(t);
        var x = metrics.X;
        var y = metrics.Y;
        var consoleWidth = metrics.Width;
        var consoleHeight = metrics.Height;
        var open = metrics.Open;
        var collapse = metrics.Collapse;
        DrawConsoleShell(target, x, y, consoleWidth, consoleHeight, opacity, collapse, t);

        if (open > 0.74f && collapse < 0.82f)
        {
            var contentOpacity = 1 - Smooth01((collapse - 0.24f) / 0.34f);
            target.PushAxisAlignedClip(Rect(x + 1, y + 1, Math.Max(1, consoleWidth - 2), Math.Max(1, consoleHeight - 2)), AntialiasMode.PerPrimitive);
            try
            {
                if (contentOpacity > 0.01f)
                {
                    var contentAlpha = contentOpacity * opacity;
                    FillPanelGradient(target, x + 2, y + 2, consoleWidth - 4, 44, contentAlpha * 0.9f);
                    DrawLayeredLine(target, x + 10, y + 45, x + consoleWidth - 10, y + 45, 0.24f * contentAlpha);

                    DrawWindowDots(target, x + 16, y + 17, contentAlpha);
                    DrawText(target, _context.SurfaceTitle, _centerFormat, x, y + 9, consoleWidth, 28, _palette.Text, 0.96f * contentAlpha);
                    DrawText(target, t >= CompletionStart ? _context.OnlineStateLabel : _context.BootStateLabel, _tinyRightFormat, x + consoleWidth - 146, y + 12, 130, 20, _palette.Success, 0.95f * contentAlpha);
                    DrawTerminalLines(target, x, y, consoleWidth, consoleHeight, t, contentAlpha);
                    DrawStatusChips(target, x, y, consoleWidth, t, contentAlpha);
                    DrawConsoleProgress(target, x, y, consoleWidth, consoleHeight, t, contentAlpha);
                    DrawConsoleScan(target, x, y, consoleWidth, consoleHeight, t, contentAlpha);
                    DrawSmallCorners(target, x, y, consoleWidth, consoleHeight, contentAlpha);
                }

                if (collapse >= 0.58f)
                {
                    DrawConsoleCollapseLine(target, x, y, consoleWidth, consoleHeight, t, opacity);
                }
            }
            finally
            {
                target.PopAxisAlignedClip();
            }
        }
        else if (collapse >= 0.82f)
        {
            DrawConsoleCollapseLine(target, x, y, consoleWidth, consoleHeight, t, opacity);
        }
    }

    private void DrawConsoleCollapseLine(ID2D1RenderTarget target, float x, float y, float width, float height, float t, float opacity)
    {
        var linePulse = 0.56f + 0.44f * MathF.Sin(t * MathF.PI * 28);
        var cy = y + height * 0.5f;
        FillRect(target, x - 26, cy - 5, width + 52, 10, _palette.Primary, (0.035f + linePulse * 0.035f) * opacity);
        FillRect(target, x - 12, cy - 2, width + 24, 4, _palette.Primary, (0.16f + linePulse * 0.16f) * opacity);
        FillRect(target, x, cy - 0.5f, width, 1, _palette.Text, (0.38f + linePulse * 0.32f) * opacity);
    }

    private void DrawTerminalLines(ID2D1RenderTarget target, float x, float y, float width, float height, float t, float opacity)
    {
        var lineX = x + 28;
        var lineY = y + 64;
        var maxWidth = Math.Max(0, width - 330);
        var lineCount = Math.Min(8, TerminalLines.Count);
        for (var i = 0; i < lineCount; i++)
        {
            var start = LinkStart + 0.022f + i * 0.040f - Math.Max(0, i - 3) * 0.010f;
            var duration = Math.Max(0.026f, 0.054f - i * 0.004f);
            var local = Math.Clamp((t - start) / duration, 0, 1);
            if (local <= 0.01f)
            {
                continue;
            }

            var line = TerminalLines[i];
            var visibleCharacters = Math.Max(1, (int)MathF.Round(line.Length * Smooth01(local)));
            var text = line[..Math.Min(visibleCharacters, line.Length)];
            if (local < 1)
            {
                text += "_";
            }

            var alpha = Smooth01(local) * opacity;
            FillRect(target, lineX - 8, lineY + i * 24 + 10, 3, 3, _palette.Primary, 0.24f * alpha);
            if (text.StartsWith('>'))
            {
                DrawText(target, ">", _monoFormat, lineX, lineY + i * 24, 16, 23, _palette.Primary, 0.78f * alpha);
                DrawText(target, text[1..].TrimStart(), _monoFormat, lineX + 19, lineY + i * 24, maxWidth - 19, 23, _palette.Muted, 0.82f * alpha);
            }
            else
            {
                DrawText(target, text, _monoFormat, lineX, lineY + i * 24, maxWidth, 23, _palette.Muted, 0.82f * alpha);
            }
        }
    }

    private void DrawStatusChips(ID2D1RenderTarget target, float x, float y, float width, float t, float opacity)
    {
        var chipX = x + width - 286;
        var chipY = y + 64;
        var rowHeight = 31f;
        var count = Math.Min(7, StatusSteps.Count);
        FillRect(target, chipX - 14, chipY - 13, 258, count * rowHeight + 22, _palette.Background, 0.18f * opacity);
        FillRect(target, chipX - 14, chipY - 13, 1, count * rowHeight + 22, _palette.Primary, 0.15f * opacity);
        for (var i = 0; i < count; i++)
        {
            var statusIndex = i;
            var local = Smooth01((t - (StatusStart(statusIndex) - 0.045f)) / 0.095f);
            if (local <= 0.01f)
            {
                continue;
            }

            var progress = StatusProgress(t, statusIndex);
            var pulse = StatusPulse(t, statusIndex);
            var status = StatusSteps[statusIndex];
            var rectX = chipX + (1 - local) * 10;
            var rectY = chipY + i * rowHeight;
            var alpha = local * opacity;
            var isDone = progress >= 0.96f;
            var stateColor = isDone ? _palette.Success : progress > 0.12f ? _palette.Primary : _palette.Warning;
            var state = isDone ? status.DoneState : status.PendingState;

            FillRect(target, rectX - 3, rectY + 2, 222, 24, stateColor, 0.018f * pulse * alpha);
            FillRect(target, rectX, rectY + rowHeight - 4, 214, 1, _palette.Muted, 0.08f * alpha);
            FillRect(target, rectX, rectY + rowHeight - 4, 214 * progress, 1, stateColor, 0.36f * alpha);
            FillRect(target, rectX - 6, rectY + 9, 3, 11, stateColor, (0.20f + progress * 0.42f + pulse * 0.28f) * alpha);
            DrawText(target, NormalizeStatusLabel(status.Label), _tinyFormat, rectX + 6, rectY + 1, 145, 16, _palette.Muted, 0.84f * alpha);
            DrawText(target, state, _tinyRightFormat, rectX + 146, rectY + 1, 64, 16, stateColor, (0.62f + progress * 0.30f + pulse * 0.08f) * alpha);
            DrawText(target, CompactStatusValue(status.Value), _tinyFormat, rectX + 6, rectY + 15, 204, 13, _palette.Primary, 0.44f * alpha);
        }
    }

    private void DrawConsoleProgress(ID2D1RenderTarget target, float x, float y, float width, float height, float t, float opacity)
    {
        var completed = 0f;
        for (var i = 0; i < StatusSteps.Count; i++)
        {
            completed += StatusProgress(t, i);
        }

        var progress = Math.Clamp(completed / StatusSteps.Count, 0, 1);
        progress = Math.Max(progress, Smooth01((t - 0.2f) / 0.2f) * 0.16f);
        if (t >= CompletionStart)
        {
            progress = Math.Max(progress, 0.94f + Smooth01((t - CompletionStart) / 0.06f) * 0.06f);
        }

        var trackX = x + 18;
        var trackY = y + height - 24;
        var trackW = Math.Max(0, width - 36);
        FillRect(target, trackX, trackY, trackW, 4, _palette.Text, 0.035f * opacity);
        FillRect(target, trackX, trackY, trackW, 1, _palette.Primary, 0.12f * opacity);
        FillRect(target, trackX, trackY, trackW * progress, 4, _palette.Success, 0.42f * opacity);
        FillRect(target, trackX, trackY, trackW * progress, 1, _palette.Text, 0.20f * opacity);
        var headX = trackX + trackW * progress;
        FillRect(target, headX - 12, trackY - 3, 24, 10, _palette.Primary, 0.055f * opacity);
    }

    private void DrawConsoleScan(ID2D1RenderTarget target, float x, float y, float width, float height, float t, float opacity)
    {
        var local = Math.Clamp((t - 0.28f) / 0.52f, 0, 1);
        var scanOpacity = MathF.Sin(local * MathF.PI) * opacity;
        if (scanOpacity <= 0.01f)
        {
            return;
        }

        var scanY = y - height * 0.25f + height * 1.38f * local;
        FillRect(target, x + 8, scanY - 18, width - 16, 36, _palette.Primary, 0.028f * scanOpacity);
        FillRect(target, x + 8, scanY - 3, width - 16, 6, _palette.Primary, 0.075f * scanOpacity);
        FillRect(target, x + 8, scanY - 0.5f, width - 16, 1, _palette.Text, 0.060f * scanOpacity);
    }

    private void DrawSmallCorners(ID2D1RenderTarget target, float x, float y, float width, float height, float opacity)
    {
        var inset = 14f;
        var left = x + inset;
        var top = y + inset;
        var right = x + width - inset;
        var bottom = y + height - inset;
        using var pen = Brush(target, _palette.Primary, 0.72f * opacity);
        var len = 44f;
        DrawMountCornerLines(target, pen, left, top, right, bottom, len);
    }

    private void DrawOverlayMountTargets(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        if (_revealTargets.Count == 0)
        {
            return;
        }

        var opacity = Smooth01((t - 0.56f) / 0.14f) * (1 - Smooth01((t - 0.94f) / 0.06f)) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var cx = _width * 0.5f;
        var cy = _height * 0.52f;
        using var linkPen = Brush(target, _palette.Primary, 0.10f * opacity);
        using var borderPen = Brush(target, _palette.Primary, 0.32f * opacity);
        using var hotPen = Brush(target, _palette.Text, 0.46f * opacity);

        for (var i = 0; i < _revealTargets.Count; i++)
        {
            var local = Smooth01((t - (0.58f + i * 0.025f)) / 0.14f);
            if (local <= 0.01f)
            {
                continue;
            }

            var source = _revealTargets[i];
            var inflateX = (1 - local) * 30f;
            var inflateY = (1 - local) * 18f;
            var x = (float)source.X - inflateX;
            var y = (float)source.Y - inflateY;
            var w = Math.Max(0, (float)source.Width + inflateX * 2);
            var h = Math.Max(0, (float)source.Height + inflateY * 2);
            var scanY = CompletionSweepY(_height, t);
            var swept = scanY >= y + h * 0.45f;
            var targetCenter = new Vector2(x + w * 0.5f, y + h * 0.5f);
            target.DrawLine(new Vector2(cx, cy), targetCenter, swept ? hotPen : linkPen, swept ? 0.8f : 0.6f);
            FillRect(target, x, y, w, h, _palette.Primary, (swept ? 0.030f : 0.015f) * opacity * local);
            using (var rectBorder = Brush(target, _palette.Primary, (swept ? 0.42f : 0.26f) * opacity * local))
            {
                target.DrawRectangle(Rect(x, y, w, h), rectBorder, 0.8f);
            }

            DrawMountCorners(target, x, y, w, h, Math.Min(46, Math.Max(20, w * 0.18f)), swept ? hotPen : borderPen, hotPen, local);
            DrawMountScan(target, x, y, w, h, t, i, opacity * local);
        }
    }

    private void DrawMountCorners(ID2D1RenderTarget target, float x, float y, float w, float h, float length, ID2D1Brush borderPen, ID2D1Brush hotPen, float opacity)
    {
        DrawMountCornerLines(target, borderPen, x, y, x + w, y + h, length);
        FillRect(target, x - 2.5f, y - 2.5f, 5, 5, _palette.Text, 0.42f * opacity);
        FillRect(target, x + w - 2.5f, y - 2.5f, 5, 5, _palette.Text, 0.42f * opacity);
        FillRect(target, x + w - 2.5f, y + h - 2.5f, 5, 5, _palette.Text, 0.42f * opacity);
        FillRect(target, x - 2.5f, y + h - 2.5f, 5, 5, _palette.Text, 0.42f * opacity);
    }

    private void DrawMountScan(ID2D1RenderTarget target, float x, float y, float width, float height, float t, int index, float opacity)
    {
        var scan = Math.Clamp((t - (0.66f + index * 0.014f)) / 0.2f, 0, 1);
        if (scan <= 0 || scan >= 1)
        {
            return;
        }

        var scanX = x - width * 0.18f + width * 1.36f * scan;
        target.PushAxisAlignedClip(Rect(x, y, width, height), AntialiasMode.PerPrimitive);
        try
        {
            FillRect(target, scanX - 10, y, 26, height, _palette.Primary, 0.08f * opacity);
            using var line = Brush(target, _palette.Text, 0.64f * opacity);
            target.DrawLine(new Vector2(scanX, y), new Vector2(scanX, y + height), line, 0.8f);
        }
        finally
        {
            target.PopAxisAlignedClip();
        }
    }

    private void DrawWindowDots(ID2D1RenderTarget target, float x, float y, float opacity)
    {
        FillEllipse(target, x, y, 3.5f, 3.5f, _palette.Primary, 0.78f * opacity);
        FillEllipse(target, x + 13, y, 3.5f, 3.5f, _palette.Warning, 0.82f * opacity);
        FillEllipse(target, x + 26, y, 3.5f, 3.5f, _palette.Success, 0.82f * opacity);
    }

    private void DrawTerminalFlash(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var flash = 0f;
        if (t >= CompletionStart && t <= CompletionStart + 0.030f)
        {
            flash = Smooth01((t - CompletionStart) / 0.030f) * 0.78f;
        }
        else if (t > CompletionStart + 0.030f && t <= CompletionStart + 0.090f)
        {
            flash = (1 - Smooth01((t - (CompletionStart + 0.030f)) / 0.060f)) * 0.78f;
        }

        if (flash <= 0.01f)
        {
            return;
        }

        var cx = _width * 0.5f;
        var cy = _height * 0.52f;
        FillRect(target, cx - _width * 0.30f, cy - 24, _width * 0.60f, 48, _palette.Primary, 0.16f * flash * layerOpacity);
        FillRect(target, cx - _width * 0.17f, cy - 5, _width * 0.34f, 10, _palette.Text, 0.48f * flash * layerOpacity);
        FillRect(target, cx - _width * 0.48f, cy - 1, _width * 0.96f, 2, _palette.Primary, 0.38f * flash * layerOpacity);
        FillRect(target, _width * 0.20f, cy - 84, _width * 0.13f, 168, _palette.Primary, 0.045f * flash * layerOpacity);
        FillRect(target, _width * 0.67f, cy - 84, _width * 0.13f, 168, _palette.Primary, 0.045f * flash * layerOpacity);
    }

    private void DrawCompletionSweep(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        var collapse = Math.Clamp((t - CompletionPeakEnd) / ConsoleCollapseDuration, 0, 1);
        if (collapse > 0 && collapse < 1)
        {
            var expand = Smooth01(collapse);
            var lineWidth = _width * (0.18f + expand * 0.82f);
            var y = _height * 0.5f + 20;
            var x = (_width - lineWidth) * 0.5f;
            FillRect(target, x, y - 5, lineWidth, 10, _palette.Primary, 0.08f * layerOpacity);
            FillRect(target, x, y - 2, lineWidth, 4, _palette.Primary, 0.42f * layerOpacity);
            FillRect(target, x + lineWidth * 0.44f, y - 0.5f, lineWidth * 0.12f, 1, _palette.Text, 0.78f * layerOpacity);
        }

        var sweep = Math.Clamp((t - SweepStart) / 0.085f, 0, 1);
        if (sweep > 0 && sweep < 1)
        {
            var ySweep = CompletionSweepY(_height, t);
            var opacity = MathF.Sin(sweep * MathF.PI) * layerOpacity;
            FillRect(target, 0, ySweep - 18, _width, 36, _palette.Primary, 0.10f * opacity);
            FillRect(target, 0, ySweep - 4, _width, 8, _palette.Primary, 0.24f * opacity);
            FillRect(target, 0, ySweep - 0.5f, _width, 1, _palette.Text, 0.64f * opacity);
        }

        var holdOpacity = CompletionHoldOpacity(t) * layerOpacity;
        if (holdOpacity <= 0.01f)
        {
            return;
        }

        var labelY = _height * 0.5f - 28;
        DrawText(target, _context.CompletionLabel, _centerFormat, 0, labelY, _width, 24, _palette.Text, 0.82f * holdOpacity);
        DrawText(target, _context.CompletionSubLabel, _centerFormat, 0, labelY + 21, _width, 18, _palette.Primary, 0.58f * holdOpacity);
    }

    private void DrawGlitches(ID2D1RenderTarget target, float t, float layerOpacity)
    {
        DrawGlitchLine(target, _height * 0.35f, t, 0.58f, 0.09f, layerOpacity);
        DrawGlitchLine(target, _height * 0.61f, t, 0.63f, 0.085f, layerOpacity);
    }

    private void DrawGlitchLine(ID2D1RenderTarget target, float y, float t, float start, float span, float layerOpacity)
    {
        var local = Math.Clamp((t - start) / span, 0, 1);
        var opacity = MathF.Sin(local * MathF.PI) * layerOpacity;
        if (opacity <= 0.01f)
        {
            return;
        }

        var x = -_width * 0.28f + _width * 0.6f * local;
        FillRect(target, x, y, _width * 1.3f, 2, _palette.Primary, 0.95f * opacity);
        FillRect(target, x + _width * 0.47f, y, _width * 0.12f, 2, _palette.Text, 0.8f * opacity);
    }

    private void DrawConsoleShell(ID2D1RenderTarget target, float x, float y, float width, float height, float opacity, float collapse, float t)
    {
        var cy = y + height * 0.5f;
        var openImpact = Pulse(t, ConsoleOpenEnd - 0.028f, 0.080f);
        var completeImpact = Pulse(t, CompletionStart, 0.082f);
        var impact = Math.Clamp(openImpact * 0.80f + completeImpact, 0, 1);
        FillHorizontalSoftBand(target, x - 70, cy, width + 140, Math.Max(18, height * 0.24f), _palette.Primary, (0.040f + 0.070f * impact) * opacity);
        FillPanelGradient(target, x, y, width, height, opacity);
        FillRect(target, x + 1, y + 1, width - 2, Math.Min(56, height - 2), _palette.Text, (0.012f + 0.018f * impact) * opacity * (1 - collapse));

        using var outerGlow = Brush(target, _palette.Primary, (0.12f + 0.16f * impact) * opacity);
        using var outer = Brush(target, _palette.Primary, (0.34f + 0.28f * impact) * opacity);
        using var inner = Brush(target, _palette.Text, (0.22f + 0.36f * impact) * opacity);
        target.DrawRectangle(Rect(x - 4, y - 4, width + 8, height + 8), outerGlow, 4.2f);
        target.DrawRectangle(Rect(x, y, width, height), outer, 1.35f + 0.65f * impact);
        target.DrawRectangle(Rect(x + 7, y + 7, Math.Max(0, width - 14), Math.Max(0, height - 14)), inner, 0.55f + 0.25f * impact);

        var len = Math.Min(62, width * 0.11f);
        using var corner = Brush(target, _palette.Text, 0.50f * opacity);
        DrawMountCornerLines(target, corner, x + 12, y + 12, x + width - 12, y + height - 12, len);

        FillRect(target, x, y, width, 1, _palette.Text, 0.18f * opacity);
        FillRect(target, x, y + height - 1, width, 1, _palette.Primary, 0.22f * opacity);
        FillRect(target, x, cy - 0.5f, width, 1, _palette.Primary, 0.10f * opacity * collapse);
    }

    private void FillPanelGradient(ID2D1RenderTarget target, float x, float y, float width, float height, float opacity)
    {
        FillRect(target, x, y, width, height, _palette.Background, 0.88f * opacity);
        FillRect(target, x, y, width, height * 0.44f, _palette.Primary, 0.030f * opacity);
        FillRect(target, x, y + height * 0.42f, width, height * 0.58f, Color(0, 0, 0), 0.10f * opacity);
        FillRect(target, x, y, width * 0.22f, height, _palette.Primary, 0.018f * opacity);
        FillRect(target, x + width * 0.78f, y, width * 0.22f, height, _palette.Primary, 0.014f * opacity);
    }

    private void FillHorizontalSoftBand(ID2D1RenderTarget target, float x, float centerY, float width, float height, TerminalColor color, float alpha)
    {
        FillRect(target, x, centerY - height * 0.5f, width, height, color, alpha * 0.32f);
        FillRect(target, x, centerY - height * 0.18f, width, height * 0.36f, color, alpha * 0.58f);
        FillRect(target, x, centerY - 0.5f, width, 1, color, alpha);
    }

    private void FillVerticalSoftBand(ID2D1RenderTarget target, float centerX, float y, float height, float width, TerminalColor color, float alpha)
    {
        FillRect(target, centerX - width * 0.5f, y, width, height, color, alpha * 0.30f);
        FillRect(target, centerX - width * 0.16f, y, width * 0.32f, height, color, alpha * 0.54f);
        FillRect(target, centerX - 0.5f, y, 1, height, color, alpha);
    }

    private void DrawLayeredLine(ID2D1RenderTarget target, float x1, float y1, float x2, float y2, float opacity)
    {
        using var glow = Brush(target, _palette.Primary, 0.10f * opacity);
        using var mid = Brush(target, _palette.Primary, 0.36f * opacity);
        using var hot = Brush(target, _palette.Text, 0.28f * opacity);
        target.DrawLine(new Vector2(x1, y1), new Vector2(x2, y2), glow, 4.5f);
        target.DrawLine(new Vector2(x1, y1), new Vector2(x2, y2), mid, 1.4f);
        target.DrawLine(new Vector2(x1, y1), new Vector2(x2, y2), hot, 0.55f);
    }

    private static string NormalizeStatusLabel(string label)
    {
        return label.Replace("CLICK-THROUGH", "CLICK THROUGH", StringComparison.OrdinalIgnoreCase);
    }

    private static string CompactStatusValue(string value)
    {
        const int maxLength = 30;
        if (string.IsNullOrWhiteSpace(value))
        {
            return string.Empty;
        }

        return value.Length <= maxLength ? value : value[..(maxLength - 1)] + "...";
    }

    private static string DiagnosticValue(OverlayStartupStatusStep step, DiagnosticPanelSpec panel, float done)
    {
        if (panel.StatusIndex == 0 && done < 0.90f)
        {
            var value = string.IsNullOrWhiteSpace(step.Value) ? "StarCitizen.exe" : step.Value;
            return value.StartsWith("waiting", StringComparison.OrdinalIgnoreCase)
                ? value
                : "waiting for " + value;
        }

        return string.IsNullOrWhiteSpace(step.Value) ? step.Label : step.Value;
    }

    private static float DiagnosticStackProgress(float t)
    {
        var first = DiagnosticPanels[0].AppearStart;
        var last = DiagnosticPanels[^1].AppearStart + 0.10f;
        return Smooth01((t - first) / Math.Max(0.001f, last - first));
    }

    private ConsoleMetrics ResolveConsoleMetrics(float t)
    {
        var open = Smooth01((t - ConsoleOpenStart) / (ConsoleOpenEnd - ConsoleOpenStart));
        var overshoot = 1 + 0.060f * Pulse(t, ConsoleOpenEnd - 0.030f, 0.080f);
        var collapse = Smooth01((t - CompletionPeakEnd) / ConsoleCollapseDuration);
        var consoleWidth = Math.Min(900, _width * 0.64f) * (0.04f + open * 0.96f) * overshoot;
        var fullHeight = Math.Min(390, _height * 0.46f);
        var consoleHeight = Math.Max(7, fullHeight * (0.025f + open * 0.975f) * (1 - collapse) + 7 * collapse);
        var x = (_width - consoleWidth) * 0.5f;
        var y = _height * 0.5f - consoleHeight * 0.5f + 14;
        return new ConsoleMetrics(x, y, consoleWidth, consoleHeight, open, collapse);
    }

    private static void DrawAnimatedCorner(
        ID2D1RenderTarget target,
        ID2D1Brush pen,
        float x,
        float y,
        float size,
        int xDir,
        int yDir,
        float progress)
    {
        if (progress <= 0.01f)
        {
            return;
        }

        var horizontal = Math.Clamp(progress * 1.65f, 0, 1);
        var vertical = Math.Clamp((progress - 0.36f) * 1.65f, 0, 1);
        target.DrawLine(new Vector2(x, y), new Vector2(x + size * xDir * horizontal, y), pen, 2);
        target.DrawLine(new Vector2(x, y), new Vector2(x, y + size * yDir * vertical), pen, 2);
    }

    private static void DrawMountCornerLines(
        ID2D1RenderTarget target,
        ID2D1Brush pen,
        float left,
        float top,
        float right,
        float bottom,
        float length)
    {
        target.DrawLine(new Vector2(left, top), new Vector2(left + length, top), pen, 1);
        target.DrawLine(new Vector2(left, top), new Vector2(left, top + length), pen, 1);
        target.DrawLine(new Vector2(right, top), new Vector2(right - length, top), pen, 1);
        target.DrawLine(new Vector2(right, top), new Vector2(right, top + length), pen, 1);
        target.DrawLine(new Vector2(left, bottom), new Vector2(left + length, bottom), pen, 1);
        target.DrawLine(new Vector2(left, bottom), new Vector2(left, bottom - length), pen, 1);
        target.DrawLine(new Vector2(right, bottom), new Vector2(right - length, bottom), pen, 1);
        target.DrawLine(new Vector2(right, bottom), new Vector2(right, bottom - length), pen, 1);
    }

    private static float TerminalLayerOpacity(float t)
    {
        if (t < 0.05f)
        {
            return t / 0.05f;
        }

        if (t < FadeStart)
        {
            return 1;
        }

        return 1 - Math.Clamp((t - FadeStart) / (1 - FadeStart), 0, 1);
    }

    private static float CompletionHoldOpacity(float t)
    {
        if (t < CompletionStart)
        {
            return 0;
        }

        if (t < CompletionPeakEnd)
        {
            var fadeIn = Smooth01((t - CompletionStart) / 0.035f);
            var fadeOut = 1 - Smooth01((t - (CompletionStart + 0.105f)) / 0.075f);
            return 0.92f * fadeIn * fadeOut;
        }

        return 0.30f * (1 - Smooth01((t - SweepStart) / 0.065f));
    }

    private static float StatusStart(int index)
    {
        return 0.275f + index * 0.038f;
    }

    private static float StatusProgress(float t, int index)
    {
        return Smooth01((t - StatusStart(index)) / 0.050f);
    }

    private static float StatusPulse(float t, int index)
    {
        var local = Math.Clamp((t - StatusStart(index)) / 0.085f, 0, 1);
        return MathF.Sin(local * MathF.PI);
    }

    private static float CompletionSweepY(float height, float t)
    {
        var sweep = Math.Clamp((t - SweepStart) / 0.085f, 0, 1);
        return -height * 0.12f + height * 1.24f * Smooth01(sweep);
    }

    private void BuildDataTicks()
    {
        _dataTicks.Clear();
        for (var i = 0; i < 86; i++)
        {
            var edge = i % 4;
            var fx = Fract(i * 0.381966f);
            var fy = Fract(i * 0.618034f);
            var x = edge switch
            {
                0 => _width * fx,
                1 => _width * (0.70f + 0.28f * fx),
                2 => _width * (0.02f + 0.28f * fx),
                _ => _width * fx
            };
            var y = edge switch
            {
                0 => _height * (0.12f + 0.12f * fy),
                1 => _height * fy,
                2 => _height * fy,
                _ => _height * (0.78f + 0.14f * fy)
            };

            _dataTicks.Add(new DataTick(
                x,
                y,
                22 + 88 * Fract(i * 0.217f),
                0.6f + 1.4f * Fract(i * 0.139f),
                0.12f + 0.46f * Fract(i * 0.071f)));
        }
    }

    private static float GetTargetFrameIntervalMs(OverlayStartupTransitionFrameRate frameRate)
    {
        var fps = Math.Clamp((int)frameRate, 24, 120);
        return 1000f / fps;
    }

    private static (int X, int Y, int Width, int Height) ResolveDeviceBounds(Window owner)
    {
        var source = PresentationSource.FromVisual(owner);
        var transform = source?.CompositionTarget?.TransformToDevice ?? Matrix.Identity;
        var left = owner.Left * transform.M11;
        var top = owner.Top * transform.M22;
        var width = Math.Max(1, owner.ActualWidth > 1 ? owner.ActualWidth : owner.Width) * transform.M11;
        var height = Math.Max(1, owner.ActualHeight > 1 ? owner.ActualHeight : owner.Height) * transform.M22;
        return (
            (int)Math.Floor(left),
            (int)Math.Floor(top),
            (int)Math.Ceiling(width),
            (int)Math.Ceiling(height));
    }

    private static TerminalCompositionPalette ResolvePalette(OverlayDisplaySettings settings)
    {
        return settings.StartupTransitionFollowOverlayTheme
            ? settings.Theme switch
            {
                OverlayVisualTheme.Anvil => new(Color(0, 255, 141), Color(229, 255, 242), Color(120, 221, 173), Color(121, 255, 92), Color(208, 255, 0), Color(0, 18, 14)),
                OverlayVisualTheme.Drake => new(Color(255, 138, 18), Color(255, 236, 196), Color(230, 151, 62), Color(255, 190, 52), Color(255, 222, 89), Color(22, 10, 0)),
                OverlayVisualTheme.Argo => new(Color(255, 111, 55), Color(255, 235, 211), Color(255, 167, 113), Color(125, 255, 126), Color(142, 255, 116), Color(23, 12, 3)),
                OverlayVisualTheme.Musashi => new(Color(255, 212, 98), Color(255, 246, 214), Color(131, 242, 221), Color(94, 255, 225), Color(91, 255, 230), Color(20, 17, 5)),
                OverlayVisualTheme.Mirai => new(Color(83, 196, 255), Color(235, 250, 255), Color(122, 191, 220), Color(105, 255, 218), Color(255, 92, 72), Color(5, 20, 30)),
                OverlayVisualTheme.Crusader => new(Color(20, 145, 255), Color(240, 250, 255), Color(146, 202, 255), Color(97, 255, 126), Color(84, 255, 107), Color(4, 16, 34)),
                OverlayVisualTheme.Aegis => new(Color(55, 224, 214), Color(224, 255, 250), Color(112, 201, 193), Color(92, 255, 185), Color(255, 51, 41), Color(0, 18, 16)),
                OverlayVisualTheme.Rsi => new(Color(150, 143, 255), Color(250, 246, 255), Color(187, 166, 220), Color(116, 238, 210), Color(255, 151, 58), Color(20, 12, 34)),
                OverlayVisualTheme.Origin => new(Color(88, 170, 255), Color(245, 250, 255), Color(132, 185, 232), Color(135, 255, 180), Color(255, 96, 83), Color(7, 17, 28)),
                OverlayVisualTheme.Aopoa => new(Color(77, 255, 225), Color(230, 255, 250), Color(116, 211, 198), Color(156, 255, 77), Color(171, 255, 67), Color(4, 28, 30)),
                OverlayVisualTheme.Esperia => new(Color(255, 60, 78), Color(255, 228, 236), Color(211, 125, 162), Color(255, 108, 128), Color(168, 77, 255), Color(30, 6, 20)),
                OverlayVisualTheme.Gatac => new(Color(255, 176, 210), Color(255, 238, 246), Color(203, 147, 221), Color(255, 190, 230), Color(255, 122, 76), Color(24, 10, 32)),
                OverlayVisualTheme.NightShadow => new(Color(214, 31, 53), Color(232, 237, 242), Color(135, 145, 156), Color(238, 238, 242), Color(255, 54, 74), Color(3, 5, 8)),
                _ => TerminalCompositionPalette.Default
            }
            : TerminalCompositionPalette.Default;
    }

    private void DisposeOnRenderThread()
    {
        if (_renderThreadDisposed)
        {
            return;
        }

        _renderThreadDisposed = true;
        _frameTimer?.Stop();
        _closeTimer?.Stop();
        _hitTraceTimer?.Stop();
        _frameTimer = null;
        _closeTimer = null;
        _hitTraceTimer = null;

        _centerFormat?.Dispose();
        _tinyRightFormat?.Dispose();
        _tinyFormat?.Dispose();
        _smallRightFormat?.Dispose();
        _smallFormat?.Dispose();
        _monoFormat?.Dispose();
        _titleFormat?.Dispose();
        _centerFormat = null;
        _tinyRightFormat = null;
        _tinyFormat = null;
        _smallRightFormat = null;
        _smallFormat = null;
        _monoFormat = null;
        _titleFormat = null;

        _writeFactory?.Dispose();
        _d2dFactory?.Dispose();
        _surface?.Dispose();
        _rootVisual?.Dispose();
        _target?.Dispose();
        _compositionDevice?.Dispose();
        _dxgiDevice?.Dispose();
        _d3dContext?.Dispose();
        _d3dDevice?.Dispose();
        _writeFactory = null;
        _d2dFactory = null;
        _surface = null;
        _rootVisual = null;
        _target = null;
        _compositionDevice = null;
        _dxgiDevice = null;
        _d3dContext = null;
        _d3dDevice = null;

        _source?.Dispose();
        _source = null;

        var dispatcher = _dispatcher ?? Dispatcher.CurrentDispatcher;
        if (!dispatcher.HasShutdownStarted && !dispatcher.HasShutdownFinished)
        {
            dispatcher.BeginInvokeShutdown(DispatcherPriority.Background);
        }
    }

    private IntPtr WindowProc(IntPtr hwnd, int msg, IntPtr wParam, IntPtr lParam, ref bool handled)
    {
        if (msg == WmNcHitTest)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "startup-transition", "WM_NCHITTEST", ++_hitTestDiagnosticsCount);
            handled = true;
            return new IntPtr(HtTransparent);
        }

        if (msg == WmMouseActivate)
        {
            OverlayHwndDiagnostics.LogMessage(hwnd, "startup-transition", "WM_MOUSEACTIVATE", ++_mouseActivateDiagnosticsCount);
            handled = true;
            return new IntPtr(MaNoActivate);
        }

        if (IsMouseInputMessage(msg))
        {
            OverlayHwndDiagnostics.LogInputMessage(hwnd, "startup-transition", MouseMessageName(msg), ++_mouseInputDiagnosticsCount);
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

    private void EnableMouseClickThrough()
    {
        try
        {
            var handle = _source?.Handle ?? IntPtr.Zero;
            if (handle == IntPtr.Zero)
            {
                return;
            }

            OverlayHwndDiagnostics.ApplyClickThrough(handle, "startup-transition-apply");
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
        _hitTraceTimer.Tick += (_, _) => LogRuntimeHitTrace(handle, "startup-transition");
        _hitTraceTimer.Start();
        LogRuntimeHitTrace(handle, "startup-transition");
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

    private ID2D1SolidColorBrush GetBrush(ID2D1RenderTarget target, TerminalColor color, float alpha)
    {
        var a = (byte)Math.Clamp(MathF.Round(Math.Clamp(alpha, 0, 1) * 255), 0, 255);
        var key = new BrushKey(
            (byte)Math.Clamp(MathF.Round(color.R * 255), 0, 255),
            (byte)Math.Clamp(MathF.Round(color.G * 255), 0, 255),
            (byte)Math.Clamp(MathF.Round(color.B * 255), 0, 255),
            a);

        if (_frameBrushes is not null && _frameBrushes.TryGetValue(key, out var cached))
        {
            return cached;
        }

        var brush = target.CreateSolidColorBrush(new Color4(color.R, color.G, color.B, a / 255f), null);
        _frameBrushes?.Add(key, brush);
        return brush;
    }

    private static ID2D1SolidColorBrush Brush(ID2D1RenderTarget target, TerminalColor color, float alpha)
    {
        return target.CreateSolidColorBrush(new Color4(color.R, color.G, color.B, Math.Clamp(alpha, 0, 1)), null);
    }

    private void FillRect(ID2D1RenderTarget target, float x, float y, float width, float height, TerminalColor color, float alpha)
    {
        if (width <= 0 || height <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        target.FillRectangle(Rect(x, y, width, height), brush);
    }

    private void FillEllipse(ID2D1RenderTarget target, float x, float y, float radiusX, float radiusY, TerminalColor color, float alpha)
    {
        if (radiusX <= 0 || radiusY <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        target.FillEllipse(new Ellipse(new Vector2(x, y), radiusX, radiusY), brush);
    }

    private void DrawText(
        ID2D1RenderTarget target,
        string text,
        IDWriteTextFormat? format,
        float x,
        float y,
        float width,
        float height,
        TerminalColor color,
        float alpha)
    {
        if (format is null || string.IsNullOrWhiteSpace(text) || width <= 0 || height <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        target.DrawText(text, format, new Vortice.Mathematics.Rect(x, y, width, height), brush, DrawTextOptions.Clip);
    }

    private static RawRectF Rect(float x, float y, float width, float height)
    {
        return new Vortice.Mathematics.Rect(x, y, width, height);
    }

    private static float SmoothStep(float edge0, float edge1, float value)
    {
        if (Math.Abs(edge1 - edge0) < 0.0001f)
        {
            return value >= edge1 ? 1 : 0;
        }

        var t = Math.Clamp((value - edge0) / (edge1 - edge0), 0, 1);
        return t * t * (3 - 2 * t);
    }

    private static float Smooth01(float value)
    {
        var t = Math.Clamp(value, 0, 1);
        return t * t * (3 - 2 * t);
    }

    private static float Pulse(float value, float start, float span)
    {
        if (span <= 0)
        {
            return 0;
        }

        var t = Math.Clamp((value - start) / span, 0, 1);
        if (t <= 0 || t >= 1)
        {
            return 0;
        }

        return MathF.Sin(t * MathF.PI);
    }

    private static float Fract(float value)
    {
        return value - MathF.Floor(value);
    }

    private static TerminalColor Color(byte r, byte g, byte b)
    {
        return new TerminalColor(r / 255f, g / 255f, b / 255f);
    }

    [DllImport("user32.dll")]
    private static extern bool ShowWindow(IntPtr hWnd, int nCmdShow);

    private readonly record struct DataTick(float X, float Y, float Width, float Thickness, float Start);

    private readonly record struct PeripheralAnchor(string Label, string DoneState, int StatusIndex, float X, float Y, int LabelSide);

    private readonly record struct DiagnosticPanelSpec(int StatusIndex, float AppearStart, float DoneStart, string PendingState);

    private readonly record struct ConsoleMetrics(float X, float Y, float Width, float Height, float Open, float Collapse);

    private readonly record struct BrushKey(byte R, byte G, byte B, byte A);

    private readonly record struct TerminalColor(float R, float G, float B);

    private readonly record struct TerminalCompositionPalette(
        TerminalColor Primary,
        TerminalColor Text,
        TerminalColor Muted,
        TerminalColor Success,
        TerminalColor Warning,
        TerminalColor Background)
    {
        public static TerminalCompositionPalette Default { get; } = new(
            Color(85, 215, 255),
            Color(237, 251, 255),
            Color(137, 168, 184),
            Color(114, 255, 182),
            Color(255, 209, 102),
            Color(2, 8, 13));
    }
}
