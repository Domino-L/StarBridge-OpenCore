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
        {
            DrawPanelFrame(target, rect, state, 42, 150, 18, 60, style.BackgroundOpacity, style.DecorationOpacity, moduleKey: "Notice");
        }
        DrawNoticePanelContent(target, state, rect);
    }

    private void DrawNoticePanelContent(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        WpfRect rect)
    {
        var textOpacity = state.Opacity * state.NoticeStyle.TextOpacity;
        var x = (float)rect.X + 20;
        var titleX = (float)rect.X + 20;
        var y = (float)rect.Y + 16;
        var contentRight = (float)rect.Right - 136;
        var titleWidth = (float)rect.Width - 150;
        var noticeTitleFormat = _titleFormat;
        DrawSourceHeader(
            target,
            state.EmptyStates.Notice is null ? state.FleetNoticeTitle : state.EmptyNoticeTitle,
            state.SourceLabels.Notice,
            state.SourceLabels.IsOwn(OverlayModuleFlags.Notice),
            noticeTitleFormat,
            titleX,
            y,
            titleWidth,
            state,
            textOpacity,
            state.NoticeAccent ? NoticeRallyAccent : null);
        if (state.NoticeMeta is { Length: > 0 } meta)
        {
            var metaLeft = titleX + Math.Min(titleWidth, MeasureTextWidth(state.FleetNoticeTitle, noticeTitleFormat)) + 16;
            DrawText(target, meta, _mutedRightFormat, metaLeft, y + 3, Math.Max(1, contentRight - metaLeft), 18,
                state.NoticeMetaAccent ? NoticeRallyAccent : state.Palette.Muted, textOpacity);
        }
        var bodyY = y + 27;
        var bodyWidth = (float)rect.Width - 156;
        var timerX = (float)rect.Right - 126;
        var timerY = (float)rect.Y;
        var timerHeight = (float)rect.Height;
        // The notice is a banner: its source status always stays one line.
        if (!DrawModuleEmptyMessage(target, state.EmptyStates.Notice, x, bodyY + 4, bodyWidth, 18, state, textOpacity))
            DrawText(target, state.FleetNotice, _textFormat, x, bodyY, bodyWidth, 24, state.Palette.Text, textOpacity);
        if (state.EmptyStates.Notice is null)
            DrawText(target, state.NoticeTimerLabel, _textRightFormat, timerX, timerY, 108, timerHeight, state.Palette.Alert, textOpacity);
    }


    private void DrawSquadsPanel(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var rect = state.SquadsRect;
        var style = state.SquadsStyle;
        var textOpacity = state.Opacity * style.TextOpacity;
        var nightShadowJoin = NightShadowPanelJoin.None;
        const bool useNightShadowLayout = false;
        DrawPanelFrame(target, rect, state, 30, 120, 34, 120, style.BackgroundOpacity, style.DecorationOpacity, nightShadowJoin, "Squads");
        var left = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var titleLeft = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var top = (float)rect.Y + (useNightShadowLayout ? 18 : 16);
        var contentWidth = (float)Math.Max(1, rect.Width - (useNightShadowLayout ? 56 : 34));
        var rowY = top + (useNightShadowLayout ? 34 : 31);
        var squadsTitleFormat = _titleFormat;
        var primaryFormat = _textFormat;
        var standardMetricFormat = _textRightFormat;
        if (OverviewShowsTitle(state)) DrawSourceHeader(
            target,
            state.SquadsTitle,
            state.SourceLabels.Overview,
            state.SourceLabels.IsOwn(OverlayModuleFlags.Overview),
            squadsTitleFormat,
            titleLeft,
            top,
            Math.Max(1, (float)rect.Right - titleLeft - (state.OverviewFacts is null ? 28 : 92)),
            state,
            textOpacity);

        if (DrawModuleEmptyMessage(target, state.EmptyStates.Overview, left, rowY, contentWidth,
                (float)rect.Bottom - rowY - 8, state, textOpacity)) return;

        if (state.OverviewFacts is { } facts && !IsPartySceneLabel(state.SquadsTitle))
        {
            float contentBottom;
            target.PushAxisAlignedClip(RectF((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height), AntialiasMode.PerPrimitive);
            try
            {
                contentBottom = DrawOverviewFacts(target, state, facts, rect, left, top, rowY, contentWidth, textOpacity);
            }
            finally
            {
                target.PopAxisAlignedClip();
            }
            return;
        }

        var compactMetrics =
            contentWidth < OverlaySquadStatusRowLayout.CompactThreshold;
        var metricFormat = compactMetrics
            ? _mutedRightFormat
            : standardMetricFormat;
        var statusColumns = OverlaySquadStatusRowLayout.Resolve(contentWidth);
        // Rooms keep their sentences; a short module shows what fits and clips the rest.
        target.PushAxisAlignedClip(RectF((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height), AntialiasMode.PerPrimitive);
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
        var focusRoom = (float)rect.Bottom - (rowY + 22) - 4;
        if (focusRoom >= 15) DrawText(
            target,
            state.SquadFocusLine,
            _mutedFormat,
            left,
            rowY + 22,
            contentWidth,
            Math.Min(IsPartySceneLabel(state.SquadsTitle) ? 54 : 15, focusRoom),
            state.Palette.Muted,
            textOpacity);
        if (!IsPartySceneLabel(state.SquadsTitle) && (float)rect.Bottom - (rowY + 40) >= 18) DrawOverviewLocations(
            target,
            state,
            left,
            rowY + 40,
            contentWidth,
            textOpacity);
        target.PopAxisAlignedClip();

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
        var textOpacity = state.Opacity * style.TextOpacity;
        var nightShadowJoin = NightShadowPanelJoin.None;
        const bool useNightShadowLayout = false;
        DrawPanelFrame(target, rect, state, 36, 150, 32, 110, style.BackgroundOpacity, style.DecorationOpacity, nightShadowJoin, "Members");
        var left = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var titleLeft = (float)rect.X + (useNightShadowLayout ? 28 : 20);
        var top = (float)rect.Y + (useNightShadowLayout ? 18 : 16);
        var contentWidth = (float)Math.Max(1, rect.Width - (useNightShadowLayout ? 56 : 34));
        var rowY = top + (useNightShadowLayout ? 34 : 32);
        var clipRect = RectF((float)rect.X, (float)rect.Y, (float)rect.Width, (float)rect.Height);
        var rowsBottom = (float)rect.Bottom - 8;
        var membersTitleFormat = _titleFormat;
        var memberHeaderWidth = Math.Max(0, (float)rect.Right - titleLeft - 28);
        var memberPageIndicator = ResolveMemberPageIndicator(state, memberHeaderWidth, membersTitleFormat);
        DrawSourceHeader(
            target,
            state.MembersTitle,
            state.SourceLabels.Members,
            state.SourceLabels.IsOwn(OverlayModuleFlags.Members),
            membersTitleFormat,
            titleLeft,
            top,
            Math.Max(1, memberHeaderWidth - memberPageIndicator.Width),
            state,
            textOpacity);
        DrawMemberPageIndicator(target, state, (float)rect.Right - 28, top, textOpacity, memberPageIndicator);
        if (DrawModuleEmptyMessage(target, state.EmptyStates.Members, left, rowY, contentWidth,
                rowsBottom - rowY, state, textOpacity)) return;
        var statusWidth = state.HideMemberStatus ? 0 : 40f;
        var remaining = Math.Max(40, contentWidth - statusWidth);
        var nameWidth = (float)(remaining * state.MemberNameRatio);
        target.PushAxisAlignedClip(clipRect, AntialiasMode.PerPrimitive);
        try
        {
            DrawMemberRows(target, state, left, rowY, contentWidth, nameWidth, textOpacity);
        }
        finally
        {
            target.PopAxisAlignedClip();
        }
    }
}
