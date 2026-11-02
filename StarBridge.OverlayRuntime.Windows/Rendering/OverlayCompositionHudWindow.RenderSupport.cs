using System.Collections.ObjectModel;
using System.Diagnostics;
using System.Numerics;
using System.Windows;
using System.Windows.Media;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.Mathematics;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    // The offline capture build supplies a deterministic clock; shipping builds
    // retain the native wall-clock and monotonic timing sources.
    private static DateTimeOffset AppearanceAnimationUtcNow =>
#if STARBRIDGE_APPEARANCE_CAPTURE
        DateTimeOffset.UnixEpoch.AddMilliseconds(_catalogAnimationTimeMs);
#else
        DateTimeOffset.UtcNow;
#endif
    private static double AppearanceAnimationTicks =>
#if STARBRIDGE_APPEARANCE_CAPTURE
        _catalogAnimationTimeMs;
#else
        Environment.TickCount64;
#endif
    private bool IsEventSlideActive()
    {
        if (_state?.AnimationFrameRate == OverlayAnimationFrameRate.Off)
        {
            return false;
        }

        var animationScale = _state?.EventAnimationScale ?? 1;
        return _eventSlideStartedAtUtc != DateTimeOffset.MinValue &&
               (DateTimeOffset.UtcNow - _eventSlideStartedAtUtc).TotalMilliseconds < EventSlideMs * animationScale + 40;
    }


    private bool IsChatBarrageActive()
    {
        return _state is { ShowChat: true, ChatDisplayMode: OverlayChatDisplayMode.FullScreenBarrage } state &&
               state.ChatBarrageMotionEnabled &&
               state.ChatRows.Any(row => row.IsBarrageActive);
    }

    private bool IsFleetNoticeExitActive()
    {
        return false;
    }

    private static int ResolveAnimationFramesPerSecond(OverlayAnimationFrameRate frameRate)
    {
        var fps = (int)frameRate;
        return fps > 0 ? Math.Clamp(fps, 1, 120) : 30;
    }

    private int ResolveMotionFramesPerSecond(OverlayAnimationFrameRate frameRate) =>
        ResolveAnimationFramesPerSecond(IsChatBarrageActive() && _state is { } state
            ? state.BarrageFrameRate : frameRate);

    private static int ResolveStartupTransitionFramesPerSecond(OverlayStartupTransitionFrameRate frameRate)
    {
        return Math.Clamp((int)frameRate, 30, 120);
    }


    private void ResolveDeviceBounds()
    {
        SetCompositionViewportFields(CaptureCompositionViewport());
    }

    private OverlayCompositionViewport CaptureCompositionViewport() => OverlayCompositionViewport.ShortOfFullScreen(
        _surfaceBounds.Left, _surfaceBounds.Top, _surfaceBounds.Width, _surfaceBounds.Height, _dpiScaleX, _dpiScaleY);

    private void SetCompositionViewportFields(OverlayCompositionViewport viewport)
    {
        _left = viewport.Left;
        _top = viewport.Top;
        _pixelWidth = viewport.Width;
        _pixelHeight = viewport.Height;
        _renderDpiScaleX = viewport.DpiScaleX;
        _renderDpiScaleY = viewport.DpiScaleY;
    }

    // Runs only on the rendering dispatcher, between complete frames. Keep the
    // HWND/device/appearance episode alive; a fixed-size DComp surface alone is
    // replaced when its pixel capacity changes.
    private void ApplyCompositionViewport(OverlayCompositionViewport viewport)
    {
        if (_source is null || _compositionDevice is null || _rootVisual is null)
        {
            return;
        }

        var moved = _left != viewport.Left || _top != viewport.Top;
        var resized = _pixelWidth != viewport.Width || _pixelHeight != viewport.Height;
        Vortice.DirectComposition.IDCompositionSurface? replacement = null;
        try
        {
            if (resized)
            {
                _compositionDevice.CreateSurface((uint)viewport.Width, (uint)viewport.Height,
                    Vortice.DXGI.Format.B8G8R8A8_UNorm, Vortice.DXGI.AlphaMode.Premultiplied, out replacement).CheckError();
            }

            // Preserve focus, visibility and menu-constrained Z order.
            if ((moved || resized) && !SetCompositionWindowBounds(_source.Handle, IntPtr.Zero,
                viewport.Left, viewport.Top, viewport.Width, viewport.Height, 0x0014u))
            {
                throw new System.ComponentModel.Win32Exception(System.Runtime.InteropServices.Marshal.GetLastWin32Error());
            }

            if (replacement is not null)
            {
                _rootVisual.SetContent(replacement).CheckError();
                _compositionDevice.Commit().CheckError();
                var previous = _surface;
                _surface = replacement;
                replacement = null;
                previous?.Dispose();
            }

            SetCompositionViewportFields(viewport);
        }
        finally
        {
            replacement?.Dispose();
        }
    }

    [System.Runtime.InteropServices.DllImport("user32.dll", EntryPoint = "SetWindowPos", SetLastError = true)]
    [return: System.Runtime.InteropServices.MarshalAs(System.Runtime.InteropServices.UnmanagedType.Bool)]
    private static extern bool SetCompositionWindowBounds(IntPtr hwnd, IntPtr insertAfter,
        int x, int y, int width, int height, uint flags);

    private void ResolveDpiScale()
    {
        if (_targetDpiScale is double scale && double.IsFinite(scale) && scale > 0)
        {
            _dpiScaleX = _dpiScaleY = scale;
            return;
        }
        var visual = System.Windows.Application.Current?.MainWindow;
        var dpi = visual is null ? new DpiScale(1, 1) : VisualTreeHelper.GetDpi(visual);
        _dpiScaleX = dpi.DpiScaleX > 0 ? dpi.DpiScaleX : 1;
        _dpiScaleY = dpi.DpiScaleY > 0 ? dpi.DpiScaleY : 1;
    }

    private static WpfRect NormalizeSurfaceBounds(WpfRect bounds)
    {
        if (bounds.Width > 1 && bounds.Height > 1)
        {
            return bounds;
        }

        return new WpfRect(
            SystemParameters.VirtualScreenLeft,
            SystemParameters.VirtualScreenTop,
            Math.Max(1, SystemParameters.VirtualScreenWidth),
            Math.Max(1, SystemParameters.VirtualScreenHeight));
    }

    private OverlayHudPalette BuildPalette()
    {

        return new OverlayHudPalette(
            FromBrush(_viewModel.PanelBackgroundBrush, HudColor.FromRgb(5, 10, 17, 176)),
            FromBrush(_viewModel.PanelBorderBrush, HudColor.FromRgb(69, 174, 255)),
            FromBrush(_viewModel.TitleBrush, HudColor.FromRgb(83, 190, 255)),
            FromBrush(_viewModel.TextBrush, HudColor.FromRgb(235, 247, 255)),
            FromBrush(_viewModel.MutedBrush, HudColor.FromRgb(142, 187, 220)),
            FromBrush(_viewModel.AlertBrush, HudColor.FromRgb(255, 240, 0)),
            FromBrush(_viewModel.OnlineBrush, HudColor.FromRgb(121, 255, 158)),
            FromBrush(_viewModel.OfflineBrush, HudColor.FromRgb(255, 105, 105)),
            FromBrush(_viewModel.CrosshairBrush, HudColor.FromRgb(235, 247, 255, 215)),
            FromBrush(_viewModel.CrosshairAlertBrush, HudColor.FromRgb(255, 240, 0, 225)),
            HudColor.FromRgb(4, 16, 28));
    }

    private static IReadOnlyList<OverlayCompositionMemberRow> SnapshotMembers(ObservableCollection<OverlayMemberRow> rows)
    {
        return rows
            .Select(row => new OverlayCompositionMemberRow(
                row.DisplayName,
                row.Status,
                row.Ship,
                row.Location,
                FromBrush(row.StatusBrush, HudColor.FromRgb(142, 187, 220)),
                row.Key,
                row.Group,
                row.CueStartedAtUtc,
                row.Presence))
            .ToArray();
    }

    private static IReadOnlyList<OverlayCompositionEventRow> SnapshotEvents(ObservableCollection<OverlayEventNotificationRow> rows,
        string? sourceLabel = null)
    {
        return rows
            .Select(row => new OverlayCompositionEventRow(
                OverlayModuleSourceLabels.Prefix(row.Title, sourceLabel, row.IsDeviceLocal),
                row.Detail,
                row.Timestamp,
                (float)row.SlideOffsetX,
                (float)Math.Clamp(row.RowOpacity, 0, 1),
                (float)Math.Clamp(row.MotionProgress, 0, 1),
                row.IsEntering,
                row.IsExiting,
                row.BarrageStartedAtUtc,
                row.BarrageDurationSeconds,
                row.BarrageLane,
                row.IsBarrageActive,
                FromBrush(row.AccentBrush, HudColor.FromRgb(83, 190, 255)))
            { AppearanceActivity = row.AppearanceActivity })
            .ToArray();
    }

    private static HudColor FromBrush(System.Windows.Media.Brush brush, HudColor fallback)
    {
        return brush is SolidColorBrush solid
            ? HudColor.FromRgb(solid.Color.R, solid.Color.G, solid.Color.B, solid.Color.A)
            : fallback;
    }

    // A one-pixel dark halo under every glyph keeps text readable on bright scenes
    // without changing the panel look; four offset passes, no blur.
    private static readonly HudColor TextHaloColor = HudColor.FromRgb(0, 0, 0);
    private const double TextHaloAlpha = 0.6;
    private static readonly (float Dx, float Dy)[] TextHaloOffsets = [(1, 0), (-1, 0), (0, 1), (0, -1)];

    private void DrawTextHalo(ID2D1RenderTarget target, string text, IDWriteTextFormat format,
        float x, float y, float width, float height, double alpha, DrawTextOptions options)
    {
        var halo = GetBrush(target, TextHaloColor, alpha * TextHaloAlpha);
        foreach (var (dx, dy) in TextHaloOffsets)
            target.DrawText(text, format, RectF(x + dx, y + dy, width, height), halo, options);
    }

    private void DrawText(
        ID2D1RenderTarget target,
        string text,
        IDWriteTextFormat? format,
        float x,
        float y,
        float width,
        float height,
        HudColor color,
        double alpha,
        DrawTextOptions options = DrawTextOptions.Clip)
    {

        if (format is null || string.IsNullOrWhiteSpace(text) || width <= 0 || height <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        DrawTextHalo(target, text, format, x, y, width, height, alpha, options);
        target.DrawText(text, format, RectF(x, y, width, height), brush, options);
    }

    private float MeasureWrappedTextHeight(
        string text,
        IDWriteTextFormat? format,
        float width,
        float maxHeight,
        float fallbackHeight)
    {
        if (_writeFactory is null || format is null || string.IsNullOrWhiteSpace(text) || width <= 0)
        {
            return fallbackHeight;
        }

        using var layout = _writeFactory.CreateTextLayout(text, format, width, maxHeight);
        return Math.Clamp(layout.Metrics.Height, fallbackHeight, maxHeight);
    }

    private float MeasureTextWidth(
        string text,
        IDWriteTextFormat? format,
        float fallbackWidth = 1)
    {
        if (_writeFactory is null ||
            format is null ||
            string.IsNullOrWhiteSpace(text))
        {
            return fallbackWidth;
        }

        var key = (text, format);
        if (_textWidthCache.TryGetValue(key, out var cached))
        {
            return cached;
        }

        using var layout = _writeFactory.CreateTextLayout(
            text,
            format,
            4096,
            64);
        var measured = Math.Max(
            fallbackWidth,
            layout.Metrics.WidthIncludingTrailingWhitespace);
        if (_textWidthCache.Count >= 256)
        {
            _textWidthCache.Clear();
        }

        _textWidthCache[key] = measured;
        return measured;
    }

    private void DrawWrappedText(
        ID2D1RenderTarget target,
        string text,
        IDWriteTextFormat? format,
        float x,
        float y,
        float width,
        float maxHeight,
        HudColor color,
        double alpha)
    {

        if (_writeFactory is null || format is null || string.IsNullOrWhiteSpace(text) || width <= 0 || maxHeight <= 0 || alpha <= 0)
        {
            return;
        }

        using var layout = _writeFactory.CreateTextLayout(text, format, width, maxHeight);
        if (alpha > 0)
        {
            var halo = GetBrush(target, TextHaloColor, alpha * TextHaloAlpha);
            foreach (var (dx, dy) in TextHaloOffsets)
                target.DrawTextLayout(new Vector2(x + dx, y + dy), layout, halo, DrawTextOptions.Clip);
        }
        target.DrawTextLayout(new Vector2(x, y), layout, GetBrush(target, color, alpha), DrawTextOptions.Clip);
    }

    private void FillRect(ID2D1RenderTarget target, float x, float y, float width, float height, HudColor color, double alpha)
    {

        if (width <= 0 || height <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        target.FillRectangle(RectF(x, y, width, height), brush);
    }

    private void DrawRectangle(ID2D1RenderTarget target, float x, float y, float width, float height, HudColor color, double alpha, float stroke)
    {

        if (width <= 0 || height <= 0 || alpha <= 0 || stroke <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
        target.DrawRectangle(RectF(x, y, width, height), brush, stroke);
    }

    private void DrawLine(ID2D1RenderTarget target, float x1, float y1, float x2, float y2, HudColor color, double alpha, float stroke)
    {
        if (alpha <= 0 || stroke <= 0)
        {
            return;
        }


        var brush = GetBrush(target, color, alpha);
        target.DrawLine(new Vector2(x1, y1), new Vector2(x2, y2), brush, stroke);
    }

    private void FillEllipse(ID2D1RenderTarget target, float x, float y, float radiusX, float radiusY, HudColor color, double alpha)
    {
        if (radiusX <= 0 || radiusY <= 0 || alpha <= 0)
        {
            return;
        }


        var brush = GetBrush(target, color, alpha);
        target.FillEllipse(new Ellipse(new Vector2(x, y), radiusX, radiusY), brush);
    }

    private void DrawEllipse(ID2D1RenderTarget target, float x, float y, float radiusX, float radiusY, HudColor color, double alpha, float stroke)
    {
        if (radiusX <= 0 || radiusY <= 0 || alpha <= 0 || stroke <= 0)
        {
            return;
        }


        var brush = GetBrush(target, color, alpha);
        const float maskExpansion = 0;
        target.DrawEllipse(
            new Ellipse(new Vector2(x, y), radiusX + maskExpansion, radiusY + maskExpansion),
            brush,
            stroke + maskExpansion);
    }

    private ID2D1SolidColorBrush GetBrush(ID2D1RenderTarget target, HudColor color, double alpha)
    {

        var resolvedAlpha = (byte)Math.Clamp(Math.Round(color.A * Math.Clamp(alpha, 0, 1)), 0, 255);
        var key = new BrushKey(color.R, color.G, color.B, resolvedAlpha);
        if (_frameBrushes is not null && _frameBrushes.TryGetValue(key, out var cached))
        {
            return cached;
        }

        var brush = target.CreateSolidColorBrush(new Color4(color.R / 255f, color.G / 255f, color.B / 255f, resolvedAlpha / 255f), null);
        _frameBrushes?.Add(key, brush);
        return brush;
    }
}
