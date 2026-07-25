using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.Mathematics;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
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
               state.AnimationFrameRate != OverlayAnimationFrameRate.Off &&
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

    private static int ResolveStartupTransitionFramesPerSecond(OverlayStartupTransitionFrameRate frameRate)
    {
        return Math.Clamp((int)frameRate, 30, 120);
    }


    private void ResolveDeviceBounds()
    {
        _left = (int)Math.Floor(_surfaceBounds.Left * _dpiScaleX);
        _top = (int)Math.Floor(_surfaceBounds.Top * _dpiScaleY);
        _pixelWidth = (int)Math.Ceiling(Math.Max(1, _surfaceBounds.Width) * _dpiScaleX);
        _pixelHeight = (int)Math.Ceiling(Math.Max(1, _surfaceBounds.Height) * _dpiScaleY);
    }

    private void ResolveDpiScale()
    {
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

        if (_settings.Skin == OverlaySkin.LagrangeWeave)
        {
            return new OverlayHudPalette(
                HudColor.FromRgb(8, 11, 19, 218),
                HudColor.FromRgb(86, 101, 121),
                HudColor.FromRgb(174, 186, 201),
                HudColor.FromRgb(229, 235, 241),
                HudColor.FromRgb(135, 147, 163),
                HudColor.FromRgb(240, 167, 107),
                HudColor.FromRgb(130, 197, 162),
                HudColor.FromRgb(135, 147, 163),
                FromBrush(_viewModel.CrosshairBrush, HudColor.FromRgb(240, 167, 107, 215)),
                FromBrush(_viewModel.CrosshairAlertBrush, HudColor.FromRgb(255, 240, 207, 225)),
                HudColor.FromRgb(3, 5, 10));
        }

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

    private IReadOnlyList<OverlayCompositionSquadRow> SnapshotSquads(ObservableCollection<OverlaySquadRow> rows)
    {
        return rows
            .Select(row => new OverlayCompositionSquadRow(
                row.Name,
                row.Icon,
                row.DetailLine,
                row.SummaryLine,
                FromBrush(row.StatusBrush, HudColor.FromRgb(83, 190, 255)),
                row.EmblemPath,
                SnapshotSquadEmblem(row.EmblemPath),
                row.IsPartyRoomIcon))
            .ToArray();
    }

    private OverlayCompositionBitmapData? SnapshotSquadEmblem(string? emblemPath)
    {
        if (string.IsNullOrWhiteSpace(emblemPath))
        {
            return null;
        }

        var cacheKey = BuildSquadEmblemCacheKey(emblemPath);
        if (_squadEmblemSnapshots.TryGetValue(cacheKey, out var cached))
        {
            return cached;
        }

        OverlayCompositionBitmapData? snapshot = null;
        try
        {
            var decoded = ImageDecodeCache.Load(emblemPath, 32);
            if (decoded is not null)
            {
                BitmapSource source = decoded;
                if (source.Format != PixelFormats.Pbgra32)
                {
                    source = new FormatConvertedBitmap(source, PixelFormats.Pbgra32, null, 0);
                    source.Freeze();
                }

                var stride = checked(source.PixelWidth * 4);
                var pixels = new byte[checked(stride * source.PixelHeight)];
                source.CopyPixels(pixels, stride, 0);
                snapshot = new OverlayCompositionBitmapData(
                    cacheKey,
                    source.PixelWidth,
                    source.PixelHeight,
                    stride,
                    pixels);
            }
        }
        catch
        {
            snapshot = null;
        }

        _squadEmblemSnapshots[cacheKey] = snapshot;
        return snapshot;
    }

    private static string BuildSquadEmblemCacheKey(string emblemPath)
    {
        try
        {
            if (File.Exists(emblemPath))
            {
                var file = new FileInfo(emblemPath);
                return $"{file.FullName}|{file.LastWriteTimeUtc.Ticks}|{file.Length}";
            }
        }
        catch
        {
        }

        return emblemPath;
    }

    private static IReadOnlyList<OverlayCompositionMemberRow> SnapshotMembers(ObservableCollection<OverlayMemberRow> rows)
    {
        return rows
            .Select(row => new OverlayCompositionMemberRow(
                row.DisplayName,
                row.Status,
                row.Ship,
                row.Location,
                FromBrush(row.StatusBrush, HudColor.FromRgb(142, 187, 220))))
            .ToArray();
    }

    private static IReadOnlyList<OverlayCompositionEventRow> SnapshotEvents(ObservableCollection<OverlayEventNotificationRow> rows)
    {
        return rows
            .Select(row => new OverlayCompositionEventRow(
                row.Title,
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
                FromBrush(row.AccentBrush, HudColor.FromRgb(83, 190, 255))))
            .ToArray();
    }

    private static HudColor FromBrush(System.Windows.Media.Brush brush, HudColor fallback)
    {
        return brush is SolidColorBrush solid
            ? HudColor.FromRgb(solid.Color.R, solid.Color.G, solid.Color.B, solid.Color.A)
            : fallback;
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
        if (_lagrangeGlowMaskOnly)
        {
            return;
        }

        if (format is null || string.IsNullOrWhiteSpace(text) || width <= 0 || height <= 0 || alpha <= 0)
        {
            return;
        }

        var brush = GetBrush(target, color, alpha);
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
