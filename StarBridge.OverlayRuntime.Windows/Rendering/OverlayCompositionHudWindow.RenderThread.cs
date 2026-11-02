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

/// <summary>Render thread, frame loop and device resources: window, strokes and text formats.</summary>
internal sealed partial class OverlayCompositionHudWindow
{
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
            DesktopRuntimeDiagnostics.WriteCrashLog(exception);
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
        var appearanceChanged = true;
        PrepareExtendedAppearanceAnimationFrame(ref appearanceChanged);
        var eventSlideActive = IsEventSlideActive();
        var contentRevealActive = IsContentRevealActive();
        var appearanceAnimation = ReadAppearanceAnimationState();
        var appearanceStartupActive = appearanceAnimation.StartupActive;
        var eventFlowActive = appearanceAnimation.EventFlowActive;
        var ambientFlowActive = appearanceAnimation.AmbientFlowActive;
        var chatBarrageActive = IsChatBarrageActive();
        var fleetNoticeExitActive = IsFleetNoticeExitActive();
        var memberMotionActive = IsMemberMotionActive();
        var calmMotionActive = IsCalmMotionActive();
        var requestedFramesPerSecond = contentRevealActive || appearanceStartupActive
            ? ResolveStartupTransitionFramesPerSecond(_settings.StartupTransitionFrameRate)
            : ResolveMotionFramesPerSecond(_settings.AnimationFrameRate);
        var framesPerSecond = _adaptiveFramePacer.Resolve(requestedFramesPerSecond, Environment.TickCount64);
        var sampleDelayMs = 0;
        if (!eventSlideActive && !contentRevealActive && !appearanceStartupActive &&
            !eventFlowActive && !chatBarrageActive && !fleetNoticeExitActive && !memberMotionActive && !calmMotionActive)
            ResolveExtendedAppearanceSampleDelay(ref sampleDelayMs);
        _frameScheduler?.UpdateFrameRate(framesPerSecond, sampleDelayMs);

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

        // Installed held-cel appearances can advance their clock without painting
        // an identical surface. Other native motion still requires every frame.
        var nativeMotionRequiresPaint = _appearanceMotionInvalidator.ObserveContinuousMotion(
            eventSlideActive || contentRevealActive || appearanceStartupActive ||
            eventFlowActive || chatBarrageActive || fleetNoticeExitActive || memberMotionActive || calmMotionActive);
        if (appearanceChanged || nativeMotionRequiresPaint) DrawFrame();
        if (!IsFleetNoticeExitActive() && _fleetNoticeExitStartedAtUtc != DateTimeOffset.MinValue)
        {
            _fleetNoticeExitState = null;
            _fleetNoticeExitStartedAtUtc = DateTimeOffset.MinValue;
            fleetNoticeExitActive = false;
        }

        if (!eventSlideActive && !contentRevealActive && !appearanceStartupActive && !eventFlowActive && !ambientFlowActive && !chatBarrageActive && !fleetNoticeExitActive && !memberMotionActive && !calmMotionActive)
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
        ProtectCreatedPreviewWindow(_source.Handle);
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


    private void CreateTextFormats()
    {
        _textWidthCache.Clear();
        _titleFormat = CreateTextFormat("Segoe UI Semibold", 13, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _textFormat = CreateTextFormat("Segoe UI", 12, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        _textRightFormat = CreateTextFormat("Segoe UI", 12, DWriteFontWeight.Normal, DWriteTextAlignment.Trailing);
        _mutedFormat = CreateTextFormat("Segoe UI", 10, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        _overviewValueFormat = CreateTextFormat("Segoe UI Semibold", 14, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _overviewNumberFormat = CreateTextFormat("Segoe UI Semibold", 20, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _mutedRightFormat = CreateTextFormat("Segoe UI", 10, DWriteFontWeight.Normal, DWriteTextAlignment.Trailing);
        _sourceLabelFormat = CreateTextFormat("Segoe UI", 11, DWriteFontWeight.Normal, DWriteTextAlignment.Leading);
        ResetSourceLabelCaches();
        _tinyFormat = CreateTextFormat("Segoe UI Semibold", 9, DWriteFontWeight.SemiBold, DWriteTextAlignment.Leading);
        _tinyCenterFormat = CreateTextFormat("Segoe UI Semibold", 8, DWriteFontWeight.SemiBold, DWriteTextAlignment.Center);
        _centerFormat = CreateTextFormat("Segoe UI", 10, DWriteFontWeight.Normal, DWriteTextAlignment.Center);
        _eventTitleFormat = CreateTextFormat(
            "Segoe UI Semibold",
            12,
            DWriteFontWeight.SemiBold,
            DWriteTextAlignment.Leading,
            WordWrapping.Wrap,
            ParagraphAlignment.Near);
        _eventDetailFormat = CreateTextFormat(
            "Segoe UI",
            11,
            DWriteFontWeight.Normal,
            DWriteTextAlignment.Leading,
            WordWrapping.Wrap,
            ParagraphAlignment.Near);
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
        // HUD type: Bahnschrift for Latin text and figures (even-width digits), one
        // point larger than the Segoe sizes the layout was tuned for; CJK falls back
        // to the system font (Microsoft YaHei UI on Windows 10/11).
        var hudFamily = family.StartsWith("Segoe UI", StringComparison.Ordinal) ? "Bahnschrift" : family;
        var hudSize = hudFamily != family && size <= 13 ? size + 1 : size;
        var format = _writeFactory!.CreateTextFormat(
            hudFamily,
            null!,
            weight,
            DWriteFontStyle.Normal,
            DWriteFontStretch.Normal,
            hudSize,
            "zh-CN");
        format.TextAlignment = alignment;
        format.ParagraphAlignment = paragraphAlignment;
        format.WordWrapping = wordWrapping;
        return format;
    }
}
