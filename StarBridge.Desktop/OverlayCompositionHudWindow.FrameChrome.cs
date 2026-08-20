using System.Collections.ObjectModel;
using System.Diagnostics;
using System.IO;
using System.Numerics;
using System.Windows.Media.Imaging;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.Mathematics;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private void DrawCrosshair(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        if (!state.ShowCrosshair ||
            (_lagrangeGlowMaskOnly && state.LagrangeWeaveStyle))
        {
            return;
        }

        var cx = (float)(state.Width * 0.5);
        var cy = (float)(state.Height * 0.5);
        var size = (float)state.CrosshairSize;
        var alpha = (float)state.CrosshairOpacity;
        var outlineAlpha = alpha * (float)state.CrosshairOutlineOpacity;
        var outlineColor = HudColor.FromRgb(2, 7, 12, 240);
        var mode = OverlayDisplaySettings.NormalizeCrosshairMode(state.CrosshairMode);
        var thickness = (float)state.CrosshairThickness;
        var showCenterMark = state.CrosshairShowCenterMark && state.CrosshairCenterMarkSize > 0.5;

        if (mode == OverlayCrosshairMode.Dot)
        {
            DrawCrosshairDot(target, state, cx, cy, thickness, alpha, outlineAlpha, outlineColor);
            return;
        }

        if (mode == OverlayCrosshairMode.Circle)
        {
            var radius = Math.Clamp(size * 0.31f, 4f, Math.Max(4f, size * 0.5f - 2f));
            if (outlineAlpha > 0)
            {
                DrawEllipse(target, cx, cy, radius, radius, outlineColor, outlineAlpha, thickness + 2f);
            }

            DrawEllipse(target, cx, cy, radius, radius, state.Palette.Crosshair, alpha, thickness);
            if (showCenterMark)
            {
                DrawCrosshairDot(target, state, cx, cy, thickness, alpha, outlineAlpha, outlineColor);
            }

            return;
        }

        var scale = size / 96f;
        var gap = (float)state.CrosshairGap;
        var arm = (float)Math.Clamp(38 - gap, 12, 30);
        var near = gap * scale;
        var far = (gap + arm) * scale;
        if (mode != OverlayCrosshairMode.TShape)
        {
            DrawCrosshairLine(target, cx, cy - far, cx, cy - near, state.Palette.Crosshair, alpha, thickness, outlineAlpha, outlineColor);
        }

        DrawCrosshairLine(target, cx, cy + near, cx, cy + far, state.Palette.Crosshair, alpha, thickness, outlineAlpha, outlineColor);
        DrawCrosshairLine(target, cx - far, cy, cx - near, cy, state.Palette.Crosshair, alpha, thickness, outlineAlpha, outlineColor);
        DrawCrosshairLine(target, cx + near, cy, cx + far, cy, state.Palette.Crosshair, alpha, thickness, outlineAlpha, outlineColor);

        if (showCenterMark)
        {
            DrawCrosshairDot(target, state, cx, cy, thickness, alpha, outlineAlpha, outlineColor);
        }
    }

    private void DrawCrosshairDot(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        float cx,
        float cy,
        float thickness,
        double alpha,
        double outlineAlpha,
        HudColor outlineColor)
    {
        var dotRadius = Math.Max(0.75f, (float)state.CrosshairCenterMarkSize * 0.5f);
        FillEllipse(target, cx, cy, dotRadius + Math.Max(0, thickness * 0.35f), dotRadius + Math.Max(0, thickness * 0.35f), outlineColor, outlineAlpha);
        FillEllipse(target, cx, cy, dotRadius, dotRadius, state.Palette.Crosshair, alpha);
    }

    private void DrawCrosshairLine(
        ID2D1RenderTarget target,
        float x1,
        float y1,
        float x2,
        float y2,
        HudColor color,
        double alpha,
        float stroke,
        double outlineAlpha,
        HudColor outlineColor)
    {
        if (outlineAlpha > 0)
        {
            DrawLine(target, x1, y1, x2, y2, outlineColor, outlineAlpha, stroke + 2.2f);
        }

        DrawLine(target, x1, y1, x2, y2, color, alpha, stroke);
    }


    private void DrawPanelFrame(
        ID2D1RenderTarget target,
        WpfRect rect,
        OverlayCompositionFrameState state,
        float topScanStart,
        float topScanEnd,
        float leftScanStart,
        float leftScanEnd,
        double backgroundOpacity,
        NightShadowPanelJoin nightShadowJoin = NightShadowPanelJoin.None,
        string moduleKey = "")
    {
        var x = (float)rect.X;
        var y = (float)rect.Y;
        var w = (float)rect.Width;
        var h = (float)rect.Height;

        if (state.LagrangeWeaveStyle)
        {
            DrawLagrangePanelFrame(target, rect, state, backgroundOpacity, moduleKey);
            return;
        }

        if (state.MinimalStyle)
        {
            DrawMinimalFrame(
                target,
                x,
                y,
                w,
                h,
                state.Palette.PanelBackground,
                state.BackgroundOpacity * OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundOpacity),
                state.BackgroundOpacity);

            var minimalInset = Math.Min(PanelChromeInset, Math.Max(0, Math.Min(w, h) * 0.22f));
            var minimalHeight = Math.Max(1, h - minimalInset * 2);
            var minimalLeftEndY = Math.Max(leftScanStart, Math.Min(minimalHeight - 8, leftScanEnd));
            DrawLine(target, x + minimalInset, y + minimalInset + leftScanStart, x + minimalInset, y + minimalInset + minimalLeftEndY, state.Palette.PanelBorder, MinimalOverlaySkinStyle.GuideOpacity * state.BackgroundOpacity, (float)MinimalOverlaySkinStyle.BorderThickness);
            return;
        }


        FillRect(target, x, y, w, h, state.Palette.PanelBackground, state.BackgroundOpacity * OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundOpacity));

        var frameX = x + PanelFrameInset;
        var frameY = y + PanelFrameInset;
        var frameWidth = Math.Max(1, w - PanelFrameInset * 2);
        var frameHeight = Math.Max(1, h - PanelFrameInset * 2);
        var chromeInset = Math.Min(PanelChromeInset, Math.Max(0, Math.Min(frameWidth, frameHeight) * 0.22f));
        var chromeX = frameX + chromeInset;
        var chromeY = frameY + chromeInset;
        var chromeWidth = Math.Max(1, frameWidth - chromeInset * 2);
        var chromeHeight = Math.Max(1, frameHeight - chromeInset * 2);
        var topScanEndX = Math.Max(topScanStart, Math.Min(chromeWidth - 8, topScanEnd));
        var leftScanEndY = Math.Max(leftScanStart, Math.Min(chromeHeight - 8, leftScanEnd));
        DrawRectangle(target, frameX, frameY, frameWidth, frameHeight, state.Palette.PanelBorder, state.BackgroundOpacity, 1);
        DrawLine(target, chromeX + topScanStart, chromeY, chromeX + topScanEndX, chromeY, state.Palette.PanelBorder, 0.32f * state.BackgroundOpacity, 1);
        DrawLine(target, chromeX, chromeY + leftScanStart, chromeX, chromeY + leftScanEndY, state.Palette.PanelBorder, 0.32f * state.BackgroundOpacity, 1);
        DrawCorners(target, chromeX, chromeY, chromeWidth, chromeHeight, state.Palette.Title, state.BackgroundOpacity);
    }

    private void DrawMinimalFrame(
        ID2D1RenderTarget target,
        float x,
        float y,
        float width,
        float height,
        HudColor fillColor,
        double fillOpacity,
        double borderOpacity)
    {
        if (_d2dFactory is null || width <= 0 || height <= 0)
        {
            return;
        }

        var metrics = MinimalOverlaySkinStyle.ResolveFrame(width, height);
        var chamfer = (float)metrics.Chamfer;
        FillPolygon(
            target,
            fillColor,
            fillOpacity,
            new Vector2(x + chamfer, y),
            new Vector2(x + width - chamfer, y),
            new Vector2(x + width, y + chamfer),
            new Vector2(x + width, y + height - chamfer),
            new Vector2(x + width - chamfer, y + height),
            new Vector2(x + chamfer, y + height),
            new Vector2(x, y + height - chamfer),
            new Vector2(x, y + chamfer));

        var horizontalGap = (float)metrics.HorizontalGap;
        var verticalGap = (float)metrics.VerticalGap;
        var horizontalGapStart = x + width * 0.5f - horizontalGap * 0.5f;
        var horizontalGapEnd = horizontalGapStart + horizontalGap;
        var verticalGapStart = y + height * 0.5f - verticalGap * 0.5f;
        var verticalGapEnd = verticalGapStart + verticalGap;

        using var geometry = _d2dFactory.CreatePathGeometry();
        using (var sink = geometry.Open())
        {
            AddCornerLine(sink, x, y + chamfer, x + chamfer, y);
            AddCornerLine(sink, x + width - chamfer, y, x + width, y + chamfer);
            AddCornerLine(sink, x + width, y + height - chamfer, x + width - chamfer, y + height);
            AddCornerLine(sink, x + chamfer, y + height, x, y + height - chamfer);

            AddCornerLine(sink, x + chamfer, y, horizontalGapStart, y);
            AddCornerLine(sink, horizontalGapEnd, y, x + width - chamfer, y);
            AddCornerLine(sink, x + chamfer, y + height, horizontalGapStart, y + height);
            AddCornerLine(sink, horizontalGapEnd, y + height, x + width - chamfer, y + height);
            AddCornerLine(sink, x, y + chamfer, x, verticalGapStart);
            AddCornerLine(sink, x, verticalGapEnd, x, y + height - chamfer);
            AddCornerLine(sink, x + width, y + chamfer, x + width, verticalGapStart);
            AddCornerLine(sink, x + width, verticalGapEnd, x + width, y + height - chamfer);
            sink.Close();
        }

        target.DrawGeometry(
            geometry,
            GetBrush(
                target,
                new HudColor(
                    MinimalOverlaySkinStyle.BorderRed,
                    MinimalOverlaySkinStyle.BorderGreen,
                    MinimalOverlaySkinStyle.BorderBlue,
                    byte.MaxValue),
                borderOpacity),
            (float)MinimalOverlaySkinStyle.BorderThickness);
    }


    private void DrawCorners(ID2D1RenderTarget target, float x, float y, float w, float h, HudColor color, double opacity)
    {
        if (_d2dFactory is null || opacity <= 0)
        {
            return;
        }

        using var lineGeometry = _d2dFactory.CreatePathGeometry();
        using (var sink = lineGeometry.Open())
        {
            AddCornerLine(sink, x, y + 18, x, y + 5);
            AddCornerLine(sink, x + 5, y, x + 28, y);
            AddCornerLine(sink, x + w - 28, y, x + w - 5, y);
            AddCornerLine(sink, x + w, y + 5, x + w, y + 18);
            AddCornerLine(sink, x, y + h - 18, x, y + h - 5);
            AddCornerLine(sink, x + 5, y + h, x + 28, y + h);
            AddCornerLine(sink, x + w - 28, y + h, x + w - 5, y + h);
            AddCornerLine(sink, x + w, y + h - 5, x + w, y + h - 18);
            sink.Close();
        }

        using var diagonalGeometry = _d2dFactory.CreatePathGeometry();
        using (var sink = diagonalGeometry.Open())
        {
            AddCornerLine(sink, x, y + 5, x + 5, y);
            AddCornerLine(sink, x + w - 5, y, x + w, y + 5);
            AddCornerLine(sink, x, y + h - 5, x + 5, y + h);
            AddCornerLine(sink, x + w - 5, y + h, x + w, y + h - 5);
            sink.Close();
        }

        var lineBrush = GetBrush(target, color, PanelCornerLineOpacity * opacity);
        target.DrawGeometry(lineGeometry, lineBrush, PanelCornerLineStrokeWidth, _cornerStrokeStyle);

        var diagonalBrush = GetBrush(target, color, PanelCornerDiagonalOpacity * opacity);
        target.DrawGeometry(diagonalGeometry, diagonalBrush, PanelCornerDiagonalStrokeWidth, _cornerStrokeStyle);
    }

    private static void AddCornerLine(
        ID2D1GeometrySink sink,
        float x1,
        float y1,
        float x2,
        float y2)
    {
        sink.BeginFigure(new Vector2(x1, y1), FigureBegin.Hollow);
        sink.AddLine(new Vector2(x2, y2));
        sink.EndFigure(FigureEnd.Open);
    }

    private static void AddClosedPolygon(ID2D1GeometrySink sink, params Vector2[] points)
    {
        if (points.Length == 0)
        {
            return;
        }

        sink.BeginFigure(points[0], FigureBegin.Filled);
        for (var index = 1; index < points.Length; index++)
        {
            sink.AddLine(points[index]);
        }

        sink.EndFigure(FigureEnd.Closed);
    }

    private void FillPolygon(ID2D1RenderTarget target, HudColor color, double alpha, params Vector2[] points)
    {
        if (_d2dFactory is null || points.Length < 3 || alpha <= 0)
        {
            return;
        }


        using var geometry = _d2dFactory.CreatePathGeometry();
        using (var sink = geometry.Open())
        {
            AddClosedPolygon(sink, points);
            sink.Close();
        }

        target.FillGeometry(geometry, GetBrush(target, color, alpha));
    }

}
