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

/// <summary>Draws a frame and releases render-thread resources.</summary>
internal sealed partial class OverlayCompositionHudWindow
{
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
        _surface.BeginDraw(frameRect, out dxgiSurface, out _).CheckError();
        var drawn = false;
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
                    drawn = true;
                    return;
                }
                catch (Exception exception)
                {
                    _glowDevicePathDisabled = true;
                    DesktopRuntimeDiagnostics.WriteDiagnosticLog($"overlay-d2d-device-context fallback=legacy error={exception.GetType().Name} message={exception.Message}");
                }
            }

            DrawFrameWithoutGlow(dxgiSurface);
            drawn = true;
        }
        finally
        {
            DisposeFrameBrushes();
            dxgiSurface?.Dispose();
            _surface.EndDraw().CheckError();
            _compositionDevice.Commit().CheckError();
            // Historical commit observation, not current rendering health or
            // a user/device acceptance receipt. Failed commits never set it.
            Volatile.Write(ref _firstFrameCommitted, 1);
            if (drawn) ConfirmAnnouncementOnScreen();
            RecordExtendedAppearanceFrameCommit();
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
            : ResolveMotionFramesPerSecond(_settings.AnimationFrameRate);
        _adaptiveFramePacer.ReportFrame(requestedFramesPerSecond, frameMs, Environment.TickCount64);
    }

    private void DrawFrameWithoutGlow(IDXGISurface dxgiSurface)
    {
        var properties = new RenderTargetProperties(
            RenderTargetType.Default,
            new Vortice.DCommon.PixelFormat(DxgiFormat.B8G8R8A8_UNorm, Vortice.DCommon.AlphaMode.Premultiplied),
            (float)(96.0 * _renderDpiScaleX),
            (float)(96.0 * _renderDpiScaleY),
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
        var dpiX = (float)(96.0 * _renderDpiScaleX);
        var dpiY = (float)(96.0 * _renderDpiScaleY);
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

        StopCalm();

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
        _sourceLabelFormat?.Dispose();
        _mutedFormat?.Dispose();
        _overviewValueFormat?.Dispose();
        _overviewNumberFormat?.Dispose();
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
        _sourceLabelFormat = null;
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
}
