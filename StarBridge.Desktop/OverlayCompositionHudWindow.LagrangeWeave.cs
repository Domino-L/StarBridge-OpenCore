using System.Numerics;
using Vortice.Direct2D1;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private static readonly string[] LagrangeJoinableModuleKeys = ["Squads", "Members", "Chat"];
    private readonly Dictionary<LagrangeGeometryCacheKey, LagrangePanelChromePlan> _lagrangePanelPlans = [];
    private readonly Dictionary<LagrangeGeometryCacheKey, ID2D1PathGeometry> _lagrangePanelFillGeometries = [];
    private const int LagrangeGeometryCacheLimit = 64;

    private void DrawLagrangeScene(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var startupActive = IsLagrangeStartupActive();
        if (startupActive)
        {
            DrawLagrangeStartupField(target, state);
        }

        var revealIndex = 0;
        foreach (var key in state.ModuleDrawOrder)
        {
            if (!TryResolveLagrangeVisibleModule(state, key, out var rect))
            {
                continue;
            }

            var reveal = startupActive
                ? ResolveLagrangeModuleReveal(key)
                : ResolveContentReveal(rect, revealIndex++);
            if (reveal.Opacity <= 0.001)
            {
                continue;
            }

            if (_lagrangeGlowMaskOnly)
            {
                DrawLagrangePanelFrame(
                    target,
                    OffsetRect(rect, reveal.OffsetY),
                    state with { Opacity = state.Opacity * reveal.Opacity },
                    ResolveLagrangeModuleStyle(state, key).BackgroundOpacity,
                    key);
            }
            else
            {
                DrawStartupModuleByKey(
                    target,
                    state,
                    key,
                    state.Opacity * reveal.Opacity,
                    reveal.OffsetY);
            }
        }

        DrawLagrangeModuleFusionDecorations(target, state);

        if (!_lagrangeGlowMaskOnly && state.ShowCrosshair)
        {
            var crosshairReveal = startupActive
                ? Segment01(
                    (float)ResolveLagrangeStartupProgress(),
                    (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.ModuleRevealStartMs + 420),
                    (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.ModuleRevealEndMs))
                : 1f;
            DrawCrosshair(
                target,
                state with { CrosshairOpacity = state.CrosshairOpacity * crosshairReveal });
        }

        if (state.ShowEvents && state.EventRows.Count > 0 && !startupActive)
        {
            DrawLagrangeEventNotifications(target, state);
        }
    }

    private OverlayCompositionModuleStyle ResolveLagrangeModuleStyle(
        OverlayCompositionFrameState state,
        string key)
    {
        return key switch
        {
            "Notice" => state.NoticeStyle,
            "Squads" => state.SquadsStyle,
            "Members" => state.MembersStyle,
            "Chat" => state.ChatStyle,
            _ => OverlayCompositionModuleStyle.Default
        };
    }

    private bool TryResolveLagrangeVisibleModule(
        OverlayCompositionFrameState state,
        string key,
        out WpfRect rect)
    {
        if (key.Equals("Notice", StringComparison.OrdinalIgnoreCase) && state.ShowNotice)
        {
            rect = state.NoticeRect;
            return true;
        }

        return TryResolveLagrangeJoinablePanel(state, key, out rect);
    }

    private (double Opacity, float OffsetY) ResolveLagrangeModuleReveal(string key)
    {
        var progress = (float)ResolveLagrangeStartupProgress();
        var delayMs = key switch
        {
            "Notice" => 0,
            "Squads" => 130,
            "Members" => 250,
            "Chat" => 370,
            _ => 0
        };
        var start = (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.ModuleRevealStartMs + delayMs);
        var end = (float)LagrangeWeaveTimeline.At(
            Math.Min(
                LagrangeWeaveTimeline.ModuleRevealEndMs,
                LagrangeWeaveTimeline.ModuleRevealStartMs + delayMs + 430));
        var reveal = EaseOutQuart(Segment01(progress, start, end));
        return (reveal, 10f * (1 - reveal));
    }

    private void DrawLagrangePanelFrame(
        ID2D1RenderTarget target,
        WpfRect rect,
        OverlayCompositionFrameState state,
        double backgroundOpacity,
        string moduleKey)
    {
        if (rect.Width <= 3 || rect.Height <= 3)
        {
            return;
        }

        var x = (float)rect.X;
        var y = (float)rect.Y;
        var width = (float)rect.Width;
        var height = (float)rect.Height;
        var join = ResolveLagrangePanelJoin(state, moduleKey);
        var (plan, geometry) = ResolveLagrangePanelGeometry(moduleKey, width, height, join);
        var opacity = state.Opacity;

        if (!_lagrangeGlowMaskOnly)
        {
            var fillAlpha = opacity * OverlayLayoutItem.NormalizeBackgroundOpacity(backgroundOpacity);
            FillLagrangePanelShape(
                target,
                geometry,
                x + 2.2f,
                y + 2.8f,
                width,
                mirror: false,
                HudColor.FromRgb(0, 1, 4, 255),
                opacity * 0.34);
            FillLagrangePanelShape(
                target,
                geometry,
                x,
                y,
                width,
                mirror: false,
                HudColor.FromRgb(3, 5, 10, 255),
                fillAlpha);

            foreach (var curve in plan.FieldCurves)
            {
                DrawLagrangeCurve(target, curve, x, y, state.Palette.Alert, opacity * 0.10, 0.54f, 18);
                DrawLagrangeCurveRange(target, curve, 0.38f, 1, x, y, state.Palette.Alert, opacity * 0.16, 0.68f, 16);
                DrawLagrangeCurveRange(target, curve, 0.72f, 1, x, y, state.Palette.CrosshairAlert, opacity * 0.31, 0.82f, 12);
            }

            foreach (var curve in plan.ShellCurves)
            {
                DrawLagrangeCurve(target, curve, x, y, state.Palette.Background, opacity * 0.92, 3.2f, 20);
                DrawLagrangeCurve(target, curve, x, y, state.Palette.Title, opacity * 0.90, 1.18f, 20);
            }

            DrawLine(
                target,
                x + plan.TitleTickStart.X,
                y + plan.TitleTickStart.Y,
                x + plan.TitleTickEnd.X,
                y + plan.TitleTickEnd.Y,
                state.Palette.Alert,
                opacity * 0.86,
                1.08f);
            DrawLagrangeCoordinateTicks(target, x, y, width, height, state, join);
        }
        else
        {
            var glowScale = state.NightShadowBloom == OverlayNightShadowBloom.Strong ? 1.34 : 1.0;
            foreach (var curve in plan.FieldCurves)
            {
                DrawLagrangeCurveRange(target, curve, 0.16f, 1, x, y, state.Palette.Alert, opacity * 0.13 * glowScale, 0.82f, 18);
                DrawLagrangeCurveRange(target, curve, 0.52f, 1, x, y, state.Palette.Alert, opacity * 0.27 * glowScale, 1.08f, 15);
                DrawLagrangeCurveRange(target, curve, 0.80f, 1, x, y, state.Palette.CrosshairAlert, opacity * 0.54 * glowScale, 1.42f, 10);
            }
        }

        DrawLagrangeAnchorLens(target, x + plan.Anchor.X, y + plan.Anchor.Y, state, opacity);
        DrawLagrangeMassAnchor(target, x + plan.Anchor.X, y + plan.Anchor.Y, state, opacity);
    }

    private void DrawLagrangeAnchorLens(
        ID2D1RenderTarget target,
        float centerX,
        float centerY,
        OverlayCompositionFrameState state,
        double opacity)
    {
        var strong = state.NightShadowBloom == OverlayNightShadowBloom.Strong;
        if (_lagrangeGlowMaskOnly)
        {
            DrawEllipse(target, centerX, centerY, 14, 7, state.Palette.Alert, opacity * (strong ? 0.32 : 0.22), strong ? 1.2f : 0.9f);
            DrawEllipse(target, centerX, centerY, 22, 11, state.Palette.Alert, opacity * (strong ? 0.20 : 0.12), strong ? 1.0f : 0.72f);
            return;
        }

        DrawEllipse(target, centerX, centerY, 14, 7, state.Palette.Alert, opacity * 0.26, 0.62f);
        DrawEllipse(target, centerX, centerY, 22, 11, state.Palette.Alert, opacity * 0.14, 0.52f);
        DrawLine(target, centerX - 28, centerY, centerX - 11, centerY, state.Palette.Alert, opacity * 0.34, 0.64f);
    }

    private void DrawLagrangeCoordinateTicks(
        ID2D1RenderTarget target,
        float x,
        float y,
        float width,
        float height,
        OverlayCompositionFrameState state,
        LagrangePanelJoin join)
    {
        var opacity = state.Opacity;
        var right = x + width - 3;
        var center = y + height * 0.5f;
        for (var index = -2; index <= 2; index++)
        {
            var tickY = center + index * 7;
            var tick = index == 0 ? 6f : 3.5f;
            DrawLine(
                target,
                right - tick,
                tickY,
                right,
                tickY,
                state.Palette.PanelBorder,
                opacity * (index == 0 ? 0.42 : 0.22),
                0.62f);
        }

        if (join.HasFlag(LagrangePanelJoin.Top))
        {
            DrawLine(target, x + 18, y + 1, x + width - 18, y + 1, state.Palette.PanelBorder, opacity * 0.18, 0.62f);
        }

        if (join.HasFlag(LagrangePanelJoin.Bottom))
        {
            DrawLine(target, x + 18, y + height - 1, x + width - 18, y + height - 1, state.Palette.PanelBorder, opacity * 0.18, 0.62f);
        }
    }

    private void DrawLagrangeMassAnchor(
        ID2D1RenderTarget target,
        float centerX,
        float centerY,
        OverlayCompositionFrameState state,
        double opacity,
        bool active = false)
    {
        var strength = state.NightShadowBloom == OverlayNightShadowBloom.Strong ? 1.24 : 1.0;
        if (_lagrangeGlowMaskOnly)
        {
            var glowAlpha = opacity * (active ? 0.96 : 0.62) * strength;
            FillEllipse(target, centerX, centerY, active ? 6.4f : 4.7f, active ? 6.4f : 4.7f, state.Palette.Alert, glowAlpha);
            return;
        }

        DrawEllipse(target, centerX, centerY, 8.2f, 8.2f, state.Palette.Alert, opacity * (active ? 0.46 : 0.25), 0.72f);
        FillEllipse(target, centerX, centerY, 5.6f, 5.6f, state.Palette.Background, opacity * 0.96);
        DrawEllipse(target, centerX, centerY, 5.8f, 5.8f, state.Palette.Alert, opacity * (active ? 0.94 : 0.78), active ? 1.45f : 1.08f);
        FillEllipse(target, centerX, centerY, active ? 3.4f : 2.8f, active ? 3.4f : 2.8f, state.Palette.Alert, opacity * 0.98);
        FillEllipse(target, centerX, centerY, 1.12f, 1.12f, state.Palette.CrosshairAlert, opacity);
    }

    private void DrawLagrangeModuleFusionDecorations(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state)
    {
        for (var firstIndex = 0; firstIndex < LagrangeJoinableModuleKeys.Length; firstIndex++)
        {
            if (!TryResolveLagrangeJoinablePanel(state, LagrangeJoinableModuleKeys[firstIndex], out var first))
            {
                continue;
            }

            for (var secondIndex = firstIndex + 1; secondIndex < LagrangeJoinableModuleKeys.Length; secondIndex++)
            {
                if (!TryResolveLagrangeJoinablePanel(state, LagrangeJoinableModuleKeys[secondIndex], out var second))
                {
                    continue;
                }

                if (AreLagrangePanelsVerticallyJoined(first, second))
                {
                    DrawLagrangeFusionSaddle(target, state, first, second);
                }
                else if (AreLagrangePanelsVerticallyJoined(second, first))
                {
                    DrawLagrangeFusionSaddle(target, state, second, first);
                }
            }
        }
    }

    private void DrawLagrangeFusionSaddle(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        WpfRect upper,
        WpfRect lower)
    {
        var overlapLeft = (float)Math.Max(upper.Left, lower.Left);
        var overlapRight = (float)Math.Min(upper.Right, lower.Right);
        var saddleX = (overlapLeft + overlapRight) * 0.5f;
        var saddleY = (float)((upper.Bottom + lower.Top) * 0.5);
        var active = IsLagrangeStartupActive() || IsEventSlideActive();
        if (_lagrangeGlowMaskOnly)
        {
            FillEllipse(target, saddleX, saddleY, active ? 3.4f : 2.2f, active ? 3.4f : 2.2f, state.Palette.Alert, state.Opacity * (active ? 0.74 : 0.36));
            return;
        }

        var radius = 5.4f;
        FillPolygon(
            target,
            state.Palette.Background,
            state.Opacity * 0.92,
            new Vector2(saddleX, saddleY - radius),
            new Vector2(saddleX + radius, saddleY),
            new Vector2(saddleX, saddleY + radius),
            new Vector2(saddleX - radius, saddleY));
        DrawLine(target, saddleX, saddleY - radius, saddleX + radius, saddleY, state.Palette.Alert, state.Opacity * 0.74, 0.88f);
        DrawLine(target, saddleX + radius, saddleY, saddleX, saddleY + radius, state.Palette.Alert, state.Opacity * 0.74, 0.88f);
        DrawLine(target, saddleX, saddleY + radius, saddleX - radius, saddleY, state.Palette.PanelBorder, state.Opacity * 0.64, 0.76f);
        DrawLine(target, saddleX - radius, saddleY, saddleX, saddleY - radius, state.Palette.PanelBorder, state.Opacity * 0.64, 0.76f);

        DrawLagrangeFusionAdapter(target, state, upper, lower, saddleX, saddleY, true);
        DrawLagrangeFusionAdapter(target, state, upper, lower, saddleX, saddleY, false);
    }

    private void DrawLagrangeFusionAdapter(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        WpfRect upper,
        WpfRect lower,
        float saddleX,
        float saddleY,
        bool leftSide)
    {
        var upperEdge = (float)(leftSide ? upper.Left : upper.Right);
        var lowerEdge = (float)(leftSide ? lower.Left : lower.Right);
        if (Math.Abs(upperEdge - lowerEdge) < 3)
        {
            return;
        }

        var direction = leftSide ? -1f : 1f;
        var curve = new LagrangeCubicCurve(
            new Vector2(upperEdge, saddleY - 1),
            new Vector2(upperEdge + direction * 8, saddleY + 1),
            new Vector2(lowerEdge + direction * 8, saddleY - 1),
            new Vector2(lowerEdge, saddleY + 1));
        DrawLagrangeCurve(target, curve, 0, 0, state.Palette.PanelBorder, state.Opacity * 0.38, 0.72f, 14);
        var inner = new LagrangeCubicCurve(
            new Vector2(saddleX + direction * 7, saddleY),
            new Vector2((saddleX + upperEdge) * 0.5f, saddleY - 5),
            new Vector2((saddleX + lowerEdge) * 0.5f, saddleY + 5),
            new Vector2(lowerEdge, saddleY + 1));
        DrawLagrangeCurve(target, inner, 0, 0, state.Palette.Alert, state.Opacity * 0.16, 0.56f, 14);
    }

    private LagrangePanelJoin ResolveLagrangePanelJoin(
        OverlayCompositionFrameState state,
        string key)
    {
        if (!state.LagrangeWeaveStyle ||
            !TryResolveLagrangeJoinablePanel(state, key, out var current))
        {
            return LagrangePanelJoin.None;
        }

        var join = LagrangePanelJoin.None;
        foreach (var neighborKey in LagrangeJoinableModuleKeys)
        {
            if (neighborKey.Equals(key, StringComparison.OrdinalIgnoreCase) ||
                !TryResolveLagrangeJoinablePanel(state, neighborKey, out var neighbor))
            {
                continue;
            }

            if (AreLagrangePanelsVerticallyJoined(neighbor, current))
            {
                join |= LagrangePanelJoin.Top;
            }
            else if (AreLagrangePanelsVerticallyJoined(current, neighbor))
            {
                join |= LagrangePanelJoin.Bottom;
            }
        }

        return join;
    }

    private static bool TryResolveLagrangeJoinablePanel(
        OverlayCompositionFrameState state,
        string key,
        out WpfRect rect)
    {
        if (key.Equals("Squads", StringComparison.OrdinalIgnoreCase) && state.ShowSquads)
        {
            rect = state.SquadsRect;
            return true;
        }

        if (key.Equals("Members", StringComparison.OrdinalIgnoreCase) && state.ShowMembers)
        {
            rect = state.MembersRect;
            return true;
        }

        if (key.Equals("Chat", StringComparison.OrdinalIgnoreCase) &&
            state.ShowChat &&
            state.ChatDisplayMode == OverlayChatDisplayMode.MessageList)
        {
            rect = state.ChatRect;
            return true;
        }

        rect = WpfRect.Empty;
        return false;
    }

    internal static bool AreLagrangePanelsVerticallyJoined(WpfRect upper, WpfRect lower)
    {
        if (upper.Width <= 1 || upper.Height <= 1 || lower.Width <= 1 || lower.Height <= 1)
        {
            return false;
        }

        var horizontalOverlap = Math.Min(upper.Right, lower.Right) - Math.Max(upper.Left, lower.Left);
        var requiredOverlap = Math.Min(upper.Width, lower.Width) * 0.82;
        var verticalGap = lower.Top - upper.Bottom;
        return horizontalOverlap >= requiredOverlap &&
               verticalGap >= -2 &&
               verticalGap <= 6;
    }

    private void DrawLagrangeEventNotifications(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state)
    {
        if (state.EventRows.Count == 0)
        {
            return;
        }

        var rect = state.EventRect;
        var railOnRight = state.EventSide == OverlayEventNotificationSide.Right;
        var railX = railOnRight ? (float)rect.Right - 8 : (float)rect.Left + 8;
        var y = (float)rect.Y;
        var railBottom = y;
        var rowIndex = 0;
        foreach (var row in state.EventRows)
        {
            var contentWidth = Math.Max(1, (float)rect.Width - 64);
            var titleHeight = MeasureWrappedTextHeight(row.Title, _eventTitleFormat, contentWidth, 34, 15);
            var detailHeight = MeasureWrappedTextHeight(row.Detail, _eventDetailFormat, contentWidth, 48, 14);
            var itemHeight = Math.Max(70, 12 + titleHeight + 5 + detailHeight + 12);
            var fade = Math.Clamp(row.Opacity, 0, 1);
            var x = (float)rect.X + row.SlideOffsetX;
            var centerY = y + itemHeight * 0.5f;
            var active = rowIndex == 0 && (row.IsEntering || IsEventSlideActive());
            var (plan, geometry) = ResolveLagrangePanelGeometry(
                "Event",
                (float)rect.Width,
                itemHeight,
                LagrangePanelJoin.None);
            var mirror = !railOnRight;
            var anchor = MapLagrangePoint(plan.Anchor, x, y, (float)rect.Width, mirror);

            if (!_lagrangeGlowMaskOnly)
            {
                var backgroundAlpha = state.Opacity * state.EventStyle.BackgroundOpacity * fade;
                FillLagrangePanelShape(
                    target,
                    geometry,
                    x + 1.8f,
                    y + 2.2f,
                    (float)rect.Width,
                    mirror,
                    HudColor.FromRgb(0, 1, 4, 255),
                    state.Opacity * fade * 0.30);
                FillLagrangePanelShape(
                    target,
                    geometry,
                    x,
                    y,
                    (float)rect.Width,
                    mirror,
                    HudColor.FromRgb(3, 5, 10, 255),
                    backgroundAlpha);
                foreach (var curve in plan.ShellCurves)
                {
                    DrawLagrangeCurve(target, curve, x, y, state.Palette.Background, state.Opacity * fade * 0.92, 3.0f, 18, mirror, (float)rect.Width);
                    DrawLagrangeCurve(target, curve, x, y, state.Palette.Title, state.Opacity * fade * 0.88, 1.12f, 18, mirror, (float)rect.Width);
                }
                foreach (var curve in plan.FieldCurves)
                {
                    DrawLagrangeCurve(target, curve, x, y, row.AccentColor, state.Opacity * fade * 0.18, 0.64f, 14, mirror, (float)rect.Width);
                }

                var contentLeft = railOnRight ? x + 18 : x + 32;
                DrawWrappedText(target, row.Title, _eventTitleFormat, contentLeft, y + 9, contentWidth, 34, row.AccentColor, state.Opacity * state.EventStyle.TextOpacity * fade);
                DrawWrappedText(target, row.Detail, _eventDetailFormat, contentLeft, y + 12 + titleHeight + 5, contentWidth, 48, state.Palette.Text, state.Opacity * state.EventStyle.TextOpacity * fade);
                DrawText(target, row.Timestamp, _mutedRightFormat, x + (float)rect.Width - 58, y + 9, 44, 16, state.Palette.Muted, state.Opacity * state.EventStyle.TextOpacity * fade);
            }

            DrawLagrangeMassAnchor(target, anchor.X, anchor.Y, state, state.Opacity * fade, active);
            DrawLagrangeCaptureCurve(target, state, anchor, new Vector2(railX, centerY), row.AccentColor, fade, active);
            railBottom = y + itemHeight;
            y += itemHeight + 7;
            rowIndex++;
        }

        if (!_lagrangeGlowMaskOnly)
        {
            DrawLine(target, railX, (float)rect.Y - 12, railX, railBottom + 12, state.Palette.PanelBorder, state.Opacity * 0.34, 0.82f);
            for (var index = 0; index < 4; index++)
            {
                var tickY = (float)rect.Y - 5 + index * 6;
                var direction = railOnRight ? -1 : 1;
                DrawLine(target, railX, tickY, railX + direction * (index == 0 ? 8 : 4), tickY, state.Palette.Alert, state.Opacity * 0.34, 0.66f);
            }
        }
    }

    private void DrawLagrangeCaptureCurve(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        Vector2 cardAnchor,
        Vector2 railAnchor,
        HudColor color,
        float fade,
        bool active)
    {
        var direction = railAnchor.X >= cardAnchor.X ? 1f : -1f;
        var curve = new LagrangeCubicCurve(
            cardAnchor,
            cardAnchor + new Vector2(direction * 18, -8),
            railAnchor - new Vector2(direction * 15, 8),
            railAnchor);
        if (!_lagrangeGlowMaskOnly)
        {
            DrawLagrangeCurve(target, curve, 0, 0, color, state.Opacity * fade * (active ? 0.34 : 0.16), active ? 1.0f : 0.62f, 16);
        }
        else if (active)
        {
            DrawLagrangeCurve(target, curve, 0, 0, color, state.Opacity * fade * 0.76, 1.4f, 18);
            FillEllipse(target, railAnchor.X, railAnchor.Y, 3.1f, 3.1f, color, state.Opacity * fade * 0.92);
        }
    }

    private void DrawLagrangeStartupField(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state)
    {
        var progress = (float)ResolveLagrangeStartupProgress();
        var width = (float)state.Width;
        var height = (float)state.Height;
        if (width <= 1 || height <= 1)
        {
            return;
        }

        var anchorProgress = EaseOutQuart(Segment01(
            progress,
            0,
            (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.AnchorsEndMs)));
        var solveProgress = EaseOutQuart(Segment01(
            progress,
            (float)LagrangeWeaveTimeline.At(260),
            (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.FieldSolveEndMs)));
        var equilibriumProgress = EaseOutQuart(Segment01(
            progress,
            (float)LagrangeWeaveTimeline.At(920),
            (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.EquilibriumEndMs)));
        var clear = Segment01(
            progress,
            (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.ClearStartMs),
            1);
        var layerOpacity = 1 - clear;
        if (!_lagrangeGlowMaskOnly)
        {
            var curtain = 0.94 * (1 - Segment01(
                progress,
                (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.EquilibriumEndMs - 160),
                (float)LagrangeWeaveTimeline.At(LagrangeWeaveTimeline.ModuleRevealEndMs)));
            FillRect(target, 0, 0, width, height, state.Palette.Background, curtain);
        }

        var anchorA = new Vector2(width * 0.50f, height * 0.22f);
        var anchorB = new Vector2(width * 0.31f, height * 0.68f);
        var anchorC = new Vector2(width * 0.69f, height * 0.68f);
        var center = new Vector2(width * 0.50f, height * 0.53f);
        DrawLagrangeStartupConnection(target, state, anchorA, anchorB, center, solveProgress, layerOpacity);
        DrawLagrangeStartupConnection(target, state, anchorB, anchorC, center, solveProgress, layerOpacity);
        DrawLagrangeStartupConnection(target, state, anchorC, anchorA, center, solveProgress, layerOpacity);

        DrawLagrangeStartupAnchor(target, state, anchorA, anchorProgress, layerOpacity);
        DrawLagrangeStartupAnchor(target, state, anchorB, anchorProgress, layerOpacity);
        DrawLagrangeStartupAnchor(target, state, anchorC, anchorProgress, layerOpacity);

        if (equilibriumProgress > 0.001f)
        {
            var radius = 7f * equilibriumProgress;
            if (_lagrangeGlowMaskOnly)
            {
                FillEllipse(target, center.X, center.Y, 3.8f * equilibriumProgress, 3.8f * equilibriumProgress, state.Palette.Alert, state.Opacity * layerOpacity * equilibriumProgress);
            }
            else
            {
                DrawLine(target, center.X, center.Y - radius, center.X + radius, center.Y, state.Palette.Alert, state.Opacity * layerOpacity * equilibriumProgress, 1.0f);
                DrawLine(target, center.X + radius, center.Y, center.X, center.Y + radius, state.Palette.Alert, state.Opacity * layerOpacity * equilibriumProgress, 1.0f);
                DrawLine(target, center.X, center.Y + radius, center.X - radius, center.Y, state.Palette.Title, state.Opacity * layerOpacity * equilibriumProgress, 0.82f);
                DrawLine(target, center.X - radius, center.Y, center.X, center.Y - radius, state.Palette.Title, state.Opacity * layerOpacity * equilibriumProgress, 0.82f);
            }
        }
    }

    private void DrawLagrangeStartupConnection(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        Vector2 start,
        Vector2 end,
        Vector2 center,
        float progress,
        float opacity)
    {
        if (progress <= 0.001f)
        {
            return;
        }

        var curve = new LagrangeCubicCurve(
            start,
            Vector2.Lerp(start, center, 0.72f),
            Vector2.Lerp(end, center, 0.72f),
            end);
        DrawLagrangeCurveProgress(
            target,
            curve,
            progress,
            state.Palette.Title,
            state.Opacity * opacity * (_lagrangeGlowMaskOnly ? 0.68 : 0.28),
            _lagrangeGlowMaskOnly ? 1.25f : 0.78f,
            32);
    }

    private void DrawLagrangeStartupAnchor(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        Vector2 anchor,
        float progress,
        float opacity)
    {
        if (progress <= 0.001f)
        {
            return;
        }

        var radius = 2.2f + progress * 4.8f;
        if (_lagrangeGlowMaskOnly)
        {
            FillEllipse(target, anchor.X, anchor.Y, radius * 0.62f, radius * 0.62f, state.Palette.Alert, state.Opacity * opacity * progress);
        }
        else
        {
            DrawEllipse(target, anchor.X, anchor.Y, radius, radius, state.Palette.Alert, state.Opacity * opacity * progress * 0.66, 0.92f);
            FillEllipse(target, anchor.X, anchor.Y, 2.1f * progress, 2.1f * progress, state.Palette.CrosshairAlert, state.Opacity * opacity * progress);
        }
    }

    private bool IsLagrangeStartupActive()
    {
        return _settings.Skin == OverlaySkin.LagrangeWeave &&
               _settings.EnableStartupTransition &&
               _settings.StartupTransitionStyle == OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium &&
               _lagrangeStartupStartedAtUtc != DateTimeOffset.MinValue &&
               (DateTimeOffset.UtcNow - _lagrangeStartupStartedAtUtc).TotalMilliseconds <
               LagrangeWeaveTimeline.DurationMs + 30;
    }

    private double ResolveLagrangeStartupProgress()
    {
        if (_lagrangeStartupStartedAtUtc == DateTimeOffset.MinValue)
        {
            return 1;
        }

        return Math.Clamp(
            (DateTimeOffset.UtcNow - _lagrangeStartupStartedAtUtc).TotalMilliseconds /
            LagrangeWeaveTimeline.DurationMs,
            0,
            1);
    }

    private void DrawLagrangeCurve(
        ID2D1RenderTarget target,
        LagrangeCubicCurve curve,
        float offsetX,
        float offsetY,
        HudColor color,
        double opacity,
        float stroke,
        int segments,
        bool mirror = false,
        float mirrorWidth = 0)
    {
        if (opacity <= 0.001 || stroke <= 0)
        {
            return;
        }

        var previous = MapLagrangePoint(curve.Start, offsetX, offsetY, mirrorWidth, mirror);
        for (var index = 1; index <= Math.Max(4, segments); index++)
        {
            var current = MapLagrangePoint(
                LagrangeWeaveGeometry.Evaluate(curve, index / (float)Math.Max(4, segments)),
                offsetX,
                offsetY,
                mirrorWidth,
                mirror);
            DrawLine(target, previous.X, previous.Y, current.X, current.Y, color, opacity, stroke);
            previous = current;
        }
    }

    private void DrawLagrangeCurveProgress(
        ID2D1RenderTarget target,
        LagrangeCubicCurve curve,
        float progress,
        HudColor color,
        double opacity,
        float stroke,
        int segments)
    {
        var steps = Math.Max(1, (int)Math.Ceiling(Math.Max(4, segments) * Math.Clamp(progress, 0, 1)));
        var previous = curve.Start;
        for (var index = 1; index <= steps; index++)
        {
            var currentProgress = Math.Min(progress, index / (float)Math.Max(4, segments));
            var current = LagrangeWeaveGeometry.Evaluate(curve, currentProgress);
            DrawLine(target, previous.X, previous.Y, current.X, current.Y, color, opacity, stroke);
            previous = current;
        }
    }

    private void DrawLagrangeCurveRange(
        ID2D1RenderTarget target,
        LagrangeCubicCurve curve,
        float startProgress,
        float endProgress,
        float offsetX,
        float offsetY,
        HudColor color,
        double opacity,
        float stroke,
        int segments)
    {
        if (opacity <= 0.001 || stroke <= 0)
        {
            return;
        }

        var start = Math.Clamp(startProgress, 0, 1);
        var end = Math.Clamp(endProgress, start, 1);
        var steps = Math.Max(4, segments);
        var previous = LagrangeWeaveGeometry.Evaluate(curve, start) + new Vector2(offsetX, offsetY);
        for (var index = 1; index <= steps; index++)
        {
            var progress = start + (end - start) * (index / (float)steps);
            var current = LagrangeWeaveGeometry.Evaluate(curve, progress) + new Vector2(offsetX, offsetY);
            DrawLine(target, previous.X, previous.Y, current.X, current.Y, color, opacity, stroke);
            previous = current;
        }
    }

    private static Vector2 MapLagrangePoint(
        Vector2 point,
        float offsetX,
        float offsetY,
        float mirrorWidth,
        bool mirror)
    {
        return new Vector2(
            offsetX + (mirror ? mirrorWidth - point.X : point.X),
            offsetY + point.Y);
    }

    private (LagrangePanelChromePlan Plan, ID2D1PathGeometry? Geometry) ResolveLagrangePanelGeometry(
        string moduleKey,
        float width,
        float height,
        LagrangePanelJoin join)
    {
        var key = new LagrangeGeometryCacheKey(
            moduleKey,
            Math.Max(16, (int)MathF.Round(width * 4)),
            Math.Max(16, (int)MathF.Round(height * 4)),
            join);
        if (!_lagrangePanelPlans.TryGetValue(key, out var plan))
        {
            if (_lagrangePanelPlans.Count >= LagrangeGeometryCacheLimit)
            {
                DisposeLagrangeGeometryCache();
            }

            plan = LagrangeWeaveGeometry.BuildPanel(
                moduleKey,
                key.WidthQuarterPixels / 4f,
                key.HeightQuarterPixels / 4f,
                join);
            _lagrangePanelPlans[key] = plan;
        }

        if (_d2dFactory is null)
        {
            return (plan, null);
        }

        if (!_lagrangePanelFillGeometries.TryGetValue(key, out var geometry))
        {
            geometry = _d2dFactory.CreatePathGeometry();
            using (var sink = geometry.Open())
            {
                if (plan.FillOutline.Count > 0)
                {
                    sink.BeginFigure(plan.FillOutline[0], FigureBegin.Filled);
                    for (var index = 1; index < plan.FillOutline.Count; index++)
                    {
                        sink.AddLine(plan.FillOutline[index]);
                    }

                    sink.EndFigure(FigureEnd.Closed);
                }

                sink.Close();
            }

            _lagrangePanelFillGeometries[key] = geometry;
        }

        return (plan, geometry);
    }

    private void FillLagrangePanelShape(
        ID2D1RenderTarget target,
        ID2D1PathGeometry? geometry,
        float x,
        float y,
        float width,
        bool mirror,
        HudColor color,
        double opacity)
    {
        if (geometry is null || opacity <= 0)
        {
            return;
        }

        var previousTransform = target.Transform;
        try
        {
            target.Transform = mirror
                ? Matrix3x2.CreateScale(-1, 1) * Matrix3x2.CreateTranslation(x + width, y)
                : Matrix3x2.CreateTranslation(x, y);
            target.FillGeometry(geometry, GetBrush(target, color, opacity));
        }
        finally
        {
            target.Transform = previousTransform;
        }
    }

    private void DisposeLagrangeGeometryCache()
    {
        foreach (var geometry in _lagrangePanelFillGeometries.Values)
        {
            geometry.Dispose();
        }

        _lagrangePanelFillGeometries.Clear();
        _lagrangePanelPlans.Clear();
    }

    private readonly record struct LagrangeGeometryCacheKey(
        string ModuleKey,
        int WidthQuarterPixels,
        int HeightQuarterPixels,
        LagrangePanelJoin Join);
}
