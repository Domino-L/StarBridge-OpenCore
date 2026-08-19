using System.Numerics;
using Vortice.Direct2D1;
using Vortice.DirectWrite;
using Vortice.Mathematics;
using DWriteTextAlignment = Vortice.DirectWrite.TextAlignment;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private void DrawNoticePanel(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var rect = state.NoticeRect;
        var style = state.NoticeStyle;
        if (state.LagrangeWeaveStyle)
        {
            DrawLagrangePanelFrame(target, rect, state, style.BackgroundOpacity, "Notice");
        }
        else
        {
            DrawPanelFrame(target, rect, state, 42, 150, 18, 60, style.BackgroundOpacity, moduleKey: "Notice");
        }
        DrawNoticePanelContent(target, state, rect);
    }

    private void DrawNoticePanelContent(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        WpfRect rect)
    {
        var textOpacity = state.TextOpacity * state.NoticeStyle.TextOpacity;
        var x = (float)rect.X + 20;
        var titleX = (float)rect.X + 20;
        var y = (float)rect.Y + 16;
        var contentRight = (float)rect.Right - 136;
        var titleWidth = (float)rect.Width - 150;
        var noticeTitleFormat = _titleFormat;
        DrawText(
            target,
            state.FleetNoticeTitle,
            noticeTitleFormat,
            titleX,
            y,
            titleWidth,
            22,
            state.Palette.Title,
            textOpacity);
        var bodyY = y + 27;
        var bodyWidth = (float)rect.Width - 156;
        var timerX = (float)rect.Right - 126;
        var timerY = (float)rect.Y;
        var timerHeight = (float)rect.Height;
        DrawText(target, state.NoticeTimerLabel, _textRightFormat, timerX, timerY, 108, timerHeight, state.Palette.Alert, textOpacity);
    }


    private void DrawSquadsPanel(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var rect = state.SquadsRect;
        var style = state.SquadsStyle;
        var textOpacity = state.TextOpacity * style.TextOpacity;
        var nightShadowJoin = NightShadowPanelJoin.None;
        const bool useNightShadowLayout = false;
        DrawPanelFrame(target, rect, state, 30, 120, 34, 120, style.BackgroundOpacity, nightShadowJoin, "Squads");
        var left = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var titleLeft = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var top = (float)rect.Y + (useNightShadowLayout ? 18 : 16);
        var contentWidth = (float)Math.Max(1, rect.Width - (useNightShadowLayout ? 56 : 34));
        var rowY = top + (useNightShadowLayout ? 34 : 31);
        var squadsTitleFormat = _titleFormat;
        var primaryFormat = _textFormat;
        var standardMetricFormat = _textRightFormat;
        DrawText(
            target,
            state.SquadsTitle,
            squadsTitleFormat,
            titleLeft,
            top,
            Math.Max(1, (float)rect.Right - titleLeft - 28),
            22,
            state.Palette.Title,
            textOpacity);

        var compactMetrics =
            contentWidth < OverlaySquadStatusRowLayout.CompactThreshold;
        var metricFormat = compactMetrics
            ? _mutedRightFormat
            : standardMetricFormat;
        var statusColumns = OverlaySquadStatusRowLayout.Resolve(contentWidth);
        DrawText(
            target,
            state.SquadPrimaryName,
            primaryFormat,
            left + statusColumns.Primary.Left,
            rowY,
            statusColumns.Primary.Width,
            18,
            state.Palette.Text,
            textOpacity);
        DrawText(
            target,
            state.SquadSummary,
            metricFormat,
            left + statusColumns.Summary.Left,
            rowY,
            statusColumns.Summary.Width,
            18,
            state.Palette.Online,
            textOpacity);
        DrawText(
            target,
            state.SquadServerSummary,
            metricFormat,
            left + statusColumns.Server.Left,
            rowY,
            statusColumns.Server.Width,
            18,
            state.Palette.Text,
            textOpacity);
        DrawText(
            target,
            state.SquadFocusLine,
            _mutedFormat,
            left,
            rowY + 22,
            contentWidth,
            15,
            state.Palette.Muted,
            textOpacity);
        DrawOverviewLocations(
            target,
            state,
            left,
            rowY + 40,
            contentWidth,
            textOpacity);

    }

    private void DrawOverviewLocations(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        float left,
        float top,
        float contentWidth,
        double textOpacity)
    {
        if (state.OverviewTopLocations.Count == 0)
        {
            var metric = state.OverviewLocationPlaceholderMetric;
            var metricWidth = string.IsNullOrWhiteSpace(metric)
                ? 0
                : Math.Max(18, MeasureTextWidth(metric, _mutedRightFormat) + 2);
            DrawText(
                target,
                state.OverviewLocationPlaceholder,
                _mutedFormat,
                left,
                top,
                Math.Max(1, contentWidth - metricWidth - (metricWidth > 0 ? 8 : 0)),
                15,
                state.Palette.Text,
                textOpacity);
            if (metricWidth > 0)
            {
                DrawText(
                    target,
                    metric,
                    _mutedRightFormat,
                    left + contentWidth - metricWidth,
                    top,
                    metricWidth,
                    15,
                    state.Palette.Muted,
                    textOpacity);
            }

            return;
        }

        var layout = state.OverviewLocationLayout;
        if (layout.Orientation == OverlayOverviewLocationOrientation.Horizontal)
        {
            var segmentWidth = contentWidth / Math.Max(1, layout.VisibleItems.Count);
            for (var index = 0; index < layout.VisibleItems.Count; index++)
            {
                var location = layout.VisibleItems[index];
                var segmentLeft = left + index * segmentWidth;
                var usableWidth = Math.Max(1, segmentWidth - (index + 1 < layout.VisibleItems.Count ? 10 : 0));
                var metric = location.DisplayMetricText;
                var metricWidth = Math.Max(18, MeasureTextWidth(metric, _mutedRightFormat) + 2);
                DrawText(
                    target,
                    location.DisplayName,
                    _mutedFormat,
                    segmentLeft,
                    top,
                    Math.Max(1, usableWidth - metricWidth - 8),
                    15,
                    state.Palette.Text,
                    textOpacity);
                DrawText(
                    target,
                    metric,
                    _mutedRightFormat,
                    segmentLeft + usableWidth - metricWidth,
                    top,
                    metricWidth,
                    15,
                    state.Palette.Muted,
                    textOpacity);
            }

            return;
        }

        for (var index = 0; index < layout.VisibleItems.Count; index++)
        {
            var location = layout.VisibleItems[index];
            var y = top + index * 18;
            var count = location.DisplayMetricText;
            var countWidth = Math.Max(18, MeasureTextWidth(count, _mutedRightFormat) + 2);
            DrawText(
                target,
                location.DisplayName,
                _mutedFormat,
                left,
                y,
                Math.Max(1, contentWidth - countWidth - 8),
                15,
                state.Palette.Text,
                textOpacity);
            DrawText(
                target,
                count,
                _mutedRightFormat,
                left + contentWidth - countWidth,
                y,
                countWidth,
                15,
                state.Palette.Muted,
                textOpacity);
        }
    }

    private void DrawMembersPanel(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var rect = state.MembersRect;
        var style = state.MembersStyle;
        var textOpacity = state.TextOpacity * style.TextOpacity;
        var nightShadowJoin = NightShadowPanelJoin.None;
        const bool useNightShadowLayout = false;
        DrawPanelFrame(target, rect, state, 36, 150, 32, 110, style.BackgroundOpacity, nightShadowJoin, "Members");
        var left = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var titleLeft = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var top = (float)rect.Y + (useNightShadowLayout ? 18 : 16);
        var contentWidth = (float)Math.Max(1, rect.Width - (useNightShadowLayout ? 56 : 34));
        var rowY = top + (useNightShadowLayout ? 34 : 32);
        var clipRect = RectF((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height);
        var rowsBottom = (float)rect.Bottom - 8;
        var membersTitleFormat = _titleFormat;
        DrawText(
            target,
            state.MembersTitle,
            membersTitleFormat,
            titleLeft,
            top,
            Math.Max(1, (float)rect.Right - titleLeft - 28),
            22,
            state.Palette.Title,
            textOpacity);
        var statusWidth = state.HideMemberStatus ? 0 : 40f;
        var remaining = Math.Max(40, contentWidth - statusWidth);
        var nameWidth = (float)(remaining * state.MemberNameRatio);
        var locationWidth = Math.Max(40, remaining - nameWidth);
        target.PushAxisAlignedClip(clipRect, AntialiasMode.PerPrimitive);
        try
        {
            foreach (var member in state.MemberRows)
            {
                DrawText(
                    target,
                    member.DisplayName,
                    _textFormat,
                    left,
                    rowY,
                    nameWidth,
                    18,
                    state.Palette.Text,
                    textOpacity);
                if (!state.HideMemberStatus)
                {
                    var statusText = state.MinimalStyle && member.Status.Equals("应用在线", StringComparison.Ordinal)
                        ? "应用\n在线"
                        : member.Status;
                    var statusTop = rowY;
                    var statusHeight = state.MinimalStyle && statusText.Contains('\n') ? 30f : 18f;
                    DrawText(target, statusText, _centerFormat, left + nameWidth, statusTop, statusWidth, statusHeight, member.StatusColor, textOpacity);
                }

                DrawText(target, member.Location, _mutedRightFormat, left + nameWidth + statusWidth, rowY + 1, locationWidth, 16, state.Palette.Muted, textOpacity);
                DrawText(target, member.Ship, _mutedFormat, left, rowY + 17, contentWidth, 14, state.Palette.Muted, textOpacity);
                rowY += 35;
            }
        }
        finally
        {
            target.PopAxisAlignedClip();
        }
    }

    private void DrawChatPanel(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        if (state.ChatDisplayMode == OverlayChatDisplayMode.FullScreenBarrage)
        {
            DrawChatBarrage(target, state);
            return;
        }

        var rect = state.ChatRect;
        var style = state.ChatStyle;
        var textOpacity = state.TextOpacity * style.TextOpacity;
        var nightShadowJoin = NightShadowPanelJoin.None;
        const bool useNightShadowLayout = false;
        DrawPanelFrame(target, rect, state, 28, 142, 28, 126, style.BackgroundOpacity, nightShadowJoin, "Chat");
        var left = (float)rect.X + (useNightShadowLayout ? 28 : 18);
        var titleLeft = (float)rect.X + (useNightShadowLayout ? 28 : 18);
        var top = (float)rect.Y + (useNightShadowLayout ? 18 : 14);
        var contentWidth = (float)Math.Max(1, rect.Width - (useNightShadowLayout ? 56 : 36));
        var contentTop = top + (useNightShadowLayout ? 36 : 30);
        var contentBottom = (float)rect.Bottom - 8;
        var clipRect = RectF((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height);
        var chatTitleFormat = _titleFormat;
        DrawText(
            target,
            state.ChatTitle,
            chatTitleFormat,
            titleLeft,
            top,
            Math.Max(1, (float)rect.Right - titleLeft - 28),
            22,
            state.Palette.Title,
            textOpacity);
        var chatMeta = state.ChatTitle.Contains("房间", StringComparison.OrdinalIgnoreCase) ||
                       state.ChatTitle.Equals("PARTY COMMS", StringComparison.OrdinalIgnoreCase)
            ? "PARTY COMMS"
            : "FLEET COMMS";

        var cursorTop = contentTop;
        target.PushAxisAlignedClip(clipRect, AntialiasMode.PerPrimitive);
        try
        {
            for (var index = state.ChatRows.Count - 1; index >= 0; index--)
            {
                var row = state.ChatRows[index];
                var titleWidth = Math.Max(30, contentWidth - 58);
                var detailHeight = MeasureWrappedTextHeight(row.Detail, _eventDetailFormat, contentWidth - 12, 42, 14);
                var desiredRowHeight = Math.Max(42, 22 + detailHeight + 8);
                var availableHeight = contentBottom - cursorTop;
                if (availableHeight < 42)
                {
                    break;
                }

                var rowHeight = index == state.ChatRows.Count - 1
                    ? Math.Min(desiredRowHeight, availableHeight)
                    : desiredRowHeight;
                if (rowHeight > availableHeight)
                {
                    break;
                }

                var detailMaxHeight = Math.Max(14, rowHeight - 30);
                FillRect(target, left, cursorTop + 3, 2, rowHeight - 10, row.AccentColor, textOpacity * 0.78);
                DrawText(target, row.Title, _eventTitleFormat, left + 10, cursorTop, titleWidth, 18, row.AccentColor, textOpacity);
                DrawText(target, row.Timestamp, _mutedRightFormat, left + contentWidth - 48, cursorTop, 48, 18, state.Palette.Muted, textOpacity * 0.78);
                DrawWrappedText(target, row.Detail, _eventDetailFormat, left + 10, cursorTop + 20, contentWidth - 12, detailMaxHeight, state.Palette.Text, textOpacity * 0.92);

                cursorTop += rowHeight;
            }
        }
        finally
        {
            target.PopAxisAlignedClip();
        }
    }

    private void DrawChatBarrage(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        EnsureChatBarrageTextFormats((float)state.ChatBarrageFontSize);
        var style = state.ChatStyle;
        var safeTop = (float)Math.Clamp(state.Height * 0.08, 54, 108);
        var safeBottom = state.ChatBarrageRegion switch
        {
            OverlayChatBarrageRegion.Upper => (float)(state.Height * 0.38),
            OverlayChatBarrageRegion.FullScreen => (float)(state.Height * 0.92),
            _ => (float)(state.Height * 0.66)
        };
        safeBottom = Math.Max(safeTop + 1, safeBottom);
        var laneSpacing = state.ChatBarrageDensity switch
        {
            OverlayChatBarrageDensity.Sparse => (float)state.ChatBarrageFontSize + 24,
            OverlayChatBarrageDensity.Dense => (float)state.ChatBarrageFontSize + 8,
            _ => (float)state.ChatBarrageFontSize + 15
        };
        var maximumLanes = state.ChatBarrageDensity switch
        {
            OverlayChatBarrageDensity.Sparse => 5,
            OverlayChatBarrageDensity.Dense => 12,
            _ => 9
        };
        var laneCount = Math.Clamp((int)Math.Floor((safeBottom - safeTop) / laneSpacing) + 1, 1, maximumLanes);
        var textOpacity = state.TextOpacity * style.TextOpacity;
        var now = _frameNowUtc;
        var fontScale = (float)(state.ChatBarrageFontSize / 16d);
        foreach (var row in state.ChatRows)
        {
            var title = string.IsNullOrWhiteSpace(row.Title) ? "通讯消息" : row.Title;
            var titleWidth = MeasureBarrageTextWidth(title, _chatBarrageTitleFormat, state.ChatBarrageFontSize, 0, 9, 260);
            var detailWidth = MeasureBarrageTextWidth(row.Detail, _chatBarrageTextFormat, state.ChatBarrageFontSize, 1, 18, 980);
            var timestampWidth = string.IsNullOrWhiteSpace(row.Timestamp)
                ? 0
                : MeasureBarrageTextWidth(row.Timestamp, _chatBarrageTimestampFormat, state.ChatBarrageFontSize * 0.72, 2, 28, 58);
            var titleDetailGap = 8 * fontScale;
            var timestampGap = timestampWidth > 0 ? 10 * fontScale : 0;
            var totalWidth = 18 * fontScale + titleWidth + titleDetailGap + detailWidth + timestampGap + timestampWidth;
            var durationMs = Math.Max(1, row.BarrageDurationSeconds * 1000);
            var progress = state.ChatBarrageMotionEnabled && row.IsBarrageActive
                ? (float)Math.Clamp((now - row.BarrageStartedAtUtc).TotalMilliseconds / durationMs, 0, 1)
                : 0.2f;
            var travel = (float)state.Width + totalWidth + 120;
            var x = (float)state.Width + 48 - travel * progress;
            var lane = Math.Abs(row.BarrageLane) % laneCount;
            var y = ResolveChatBarrageLaneY(state, lane, laneCount, safeTop, safeBottom);
            var edgeFade = Math.Clamp(Math.Min(progress / 0.035f, (1 - progress) / 0.055f), 0, 1);
            var alpha = textOpacity * row.Opacity * edgeFade;
            if (!state.ChatBarrageMotionEnabled)
            {
                alpha = textOpacity * row.Opacity;
            }



            var textHeight = (float)state.ChatBarrageFontSize + 8;
            FillRect(target, x, y + 5, Math.Max(2, 3 * fontScale), Math.Max(8, 11 * fontScale), row.AccentColor, alpha * 0.86);

            var textX = x + 18 * fontScale;
            DrawChatBarrageText(target, title, _chatBarrageTitleFormat, textX, y, titleWidth, textHeight, row.AccentColor, alpha, state.ChatTextEdgeStrength);
            textX += titleWidth + titleDetailGap;
            DrawChatBarrageText(target, row.Detail, _chatBarrageTextFormat, textX, y, detailWidth, textHeight, state.Palette.Text, alpha, state.ChatTextEdgeStrength);
            if (timestampWidth > 0)
            {
                DrawChatBarrageText(target, row.Timestamp, _chatBarrageTimestampFormat, textX + detailWidth + timestampGap, y + 2, timestampWidth, textHeight, state.Palette.Muted, alpha * 0.72, state.ChatTextEdgeStrength);
            }
        }
    }

    private static float ResolveChatBarrageLaneY(
        OverlayCompositionFrameState state,
        int lane,
        int laneCount,
        float safeTop,
        float safeBottom)
    {
        if (!state.ChatBarrageAvoidCenter || state.ChatBarrageRegion == OverlayChatBarrageRegion.Upper)
        {
            return laneCount <= 1 ? safeTop : safeTop + (safeBottom - safeTop) * lane / (laneCount - 1);
        }

        var upperBottom = (float)Math.Min(safeBottom, state.Height * 0.39);
        var lowerTop = (float)Math.Max(safeTop, state.Height * 0.61);
        var upperSpan = Math.Max(0, upperBottom - safeTop);
        var lowerSpan = Math.Max(0, safeBottom - lowerTop);
        if (lowerSpan <= 1)
        {
            return laneCount <= 1 ? safeTop : safeTop + upperSpan * lane / (laneCount - 1);
        }

        var upperLaneCount = Math.Clamp(
            (int)Math.Round(laneCount * upperSpan / Math.Max(1, upperSpan + lowerSpan)),
            1,
            Math.Max(1, laneCount - 1));
        if (lane < upperLaneCount)
        {
            return upperLaneCount <= 1 ? safeTop : safeTop + upperSpan * lane / (upperLaneCount - 1);
        }

        var lowerLane = lane - upperLaneCount;
        var lowerLaneCount = laneCount - upperLaneCount;
        return lowerLaneCount <= 1 ? lowerTop : lowerTop + lowerSpan * lowerLane / (lowerLaneCount - 1);
    }


    private void DrawChatBarrageText(
        ID2D1RenderTarget target,
        string text,
        IDWriteTextFormat? format,
        float x,
        float y,
        float width,
        float height,
        HudColor color,
        double alpha,
        OverlayChatTextEdgeStrength edgeStrength)
    {
        var normalizedStrength = OverlayDisplaySettings.NormalizeChatTextEdgeStrength(edgeStrength);
        if (normalizedStrength == OverlayChatTextEdgeStrength.Off)
        {
            DrawText(target, text, format, x, y, width, height, color, alpha, DrawTextOptions.Clip | DrawTextOptions.NoSnap);
            return;
        }

        var edge = HudColor.FromRgb(0, 0, 0);
        var edgeAlpha = alpha * (normalizedStrength switch
        {
            OverlayChatTextEdgeStrength.Light => 0.42,
            OverlayChatTextEdgeStrength.Strong => 0.9,
            _ => 0.68
        });
        var edgeOffset = normalizedStrength switch
        {
            OverlayChatTextEdgeStrength.Light => 0.45f,
            OverlayChatTextEdgeStrength.Strong => 1.0f,
            _ => 0.7f
        };
        var options = DrawTextOptions.Clip | DrawTextOptions.NoSnap;
        DrawText(target, text, format, x - edgeOffset, y, width, height, edge, edgeAlpha, options);
        DrawText(target, text, format, x + edgeOffset, y, width, height, edge, edgeAlpha, options);
        DrawText(target, text, format, x, y - edgeOffset, width, height, edge, edgeAlpha, options);
        DrawText(target, text, format, x, y + edgeOffset, width, height, edge, edgeAlpha, options);
        DrawText(target, text, format, x, y, width, height, color, alpha, options);
    }

    private float MeasureBarrageTextWidth(
        string value,
        IDWriteTextFormat? format,
        double fontSize,
        int formatRole,
        float minimum,
        float maximum)
    {
        var scale = (float)(OverlayDisplaySettings.NormalizeChatBarrageFontSize(fontSize) / 16d);
        var fallback = Math.Clamp(
            (float)OverlayDisplaySettings.EstimateChatBarrageTextWidth(value, fontSize),
            minimum * scale,
            maximum * scale);
        if (_writeFactory is null || format is null || string.IsNullOrEmpty(value))
        {
            return fallback;
        }

        return _chatBarrageTextMeasurementCache.GetOrAdd(
            value,
            (float)fontSize,
            formatRole,
            () =>
            {
                using var layout = _writeFactory.CreateTextLayout(
                    value,
                    format,
                    maximum * scale,
                    Math.Max(24, (float)fontSize + 10));
                return Math.Clamp(
                    layout.Metrics.WidthIncludingTrailingWhitespace + Math.Max(1, scale),
                    minimum * scale,
                    maximum * scale);
            });
    }
}
