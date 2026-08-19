using Vortice.Direct2D1;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private void BeginAppearanceStartup(out bool started, out double durationMs)
    {
        started = false;
        durationMs = 0;
        TryBeginExtendedAppearanceStartup(ref started, ref durationMs);
        if (started)
        {
            return;
        }

        if (ShouldPlayLagrangeStartup())
        {
            _lagrangeStartupStartedAtUtc = DateTimeOffset.UtcNow;
            started = true;
            durationMs = LagrangeWeaveTimeline.DurationMs;
        }
    }

    private bool BeginExtendedStartupTransition(int settleDelayMs)
    {
        var handled = false;
        TryBeginExtendedStartupTransition(settleDelayMs, ref handled);
        return handled;
    }

    private AppearanceAnimationState ReadAppearanceAnimationState()
    {
        var state = new AppearanceAnimationState(
            IsLagrangeStartupActive(),
            false,
            false);
        TryReadExtendedAppearanceAnimationState(ref state);
        return state;
    }

    private ID2D1CommandList? BuildAppearanceGlowMask(ID2D1DeviceContext target)
    {
        ID2D1CommandList? glowMask = null;
        TryBuildExtendedAppearanceGlowMask(target, ref glowMask);
        return glowMask ?? (ShouldDrawLagrangeGlow(_state)
            ? BuildLagrangeGlowMask(target)
            : null);
    }

    private void DrawAppearanceGlow(
        ID2D1DeviceContext target,
        OverlayCompositionFrameState state,
        ID2D1CommandList? glowMask)
    {
        var handled = false;
        TryDrawExtendedAppearanceGlow(target, state, glowMask, ref handled);
        if (!handled)
        {
            DrawLagrangeGlow(target, state, glowMask);
        }
    }

    private void DisposeAppearanceResources()
    {
        DisposeLagrangeGeometryCache();
        DisposeExtendedAppearanceResources();
    }

    private void DrawScene(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        EnsureHudTextFormats(state.MinimalStyle);

        var handled = false;
        TryDrawExtendedAppearanceScene(target, state, ref handled);
        if (handled)
        {
            return;
        }

        if (state.LagrangeWeaveStyle)
        {
            DrawLagrangeScene(target, state);
            return;
        }

        DrawStandardScene(target, state);
    }

    partial void TryDrawExtendedAppearanceScene(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        ref bool handled);

    partial void TryBeginExtendedAppearanceStartup(ref bool started, ref double durationMs);

    partial void TryBeginExtendedStartupTransition(int settleDelayMs, ref bool handled);

    partial void TryReadExtendedAppearanceAnimationState(ref AppearanceAnimationState state);

    partial void TryBuildExtendedAppearanceGlowMask(
        ID2D1DeviceContext target,
        ref ID2D1CommandList? glowMask);

    partial void TryDrawExtendedAppearanceGlow(
        ID2D1DeviceContext target,
        OverlayCompositionFrameState state,
        ID2D1CommandList? glowMask,
        ref bool handled);

    partial void DisposeExtendedAppearanceResources();

    private void DrawStandardScene(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
        var revealIndex = 0;
        foreach (var key in state.ModuleDrawOrder)
        {
            var visible = key switch
            {
                "Notice" => state.ShowNotice,
                "Squads" => state.ShowSquads,
                "Members" => state.ShowMembers,
                "Chat" => state.ShowChat,
                _ => false
            };
            if (!visible)
            {
                continue;
            }

            var rect = key switch
            {
                "Notice" => state.NoticeRect,
                "Squads" => state.SquadsRect,
                "Members" => state.MembersRect,
                "Chat" => state.ChatRect,
                _ => WpfRect.Empty
            };
            var reveal = ResolveContentReveal(rect, revealIndex++);
            DrawStartupModuleByKey(
                target,
                state,
                key,
                reveal.Opacity,
                reveal.OffsetY);
        }

        if (state.ShowCrosshair)
        {
            DrawCrosshair(target, state);
        }

        if (state.ShowEvents && state.EventRows.Count > 0)
        {
            DrawEventNotifications(target, state);
        }
    }

    private void DrawStartupModuleByKey(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        string key,
        double revealOpacity,
        float offsetY)
    {
        switch (key)
        {
            case "Notice":
                DrawNoticePanel(target, state with
                {
                    TextOpacity = state.TextOpacity * revealOpacity,
                    BackgroundOpacity = state.BackgroundOpacity * revealOpacity,
                    NoticeRect = OffsetRect(state.NoticeRect, offsetY)
                });
                break;
            case "Squads":
                DrawSquadsPanel(target, state with
                {
                    TextOpacity = state.TextOpacity * revealOpacity,
                    BackgroundOpacity = state.BackgroundOpacity * revealOpacity,
                    SquadsRect = OffsetRect(state.SquadsRect, offsetY)
                });
                break;
            case "Members":
                DrawMembersPanel(target, state with
                {
                    TextOpacity = state.TextOpacity * revealOpacity,
                    BackgroundOpacity = state.BackgroundOpacity * revealOpacity,
                    MembersRect = OffsetRect(state.MembersRect, offsetY)
                });
                break;
            case "Chat":
                DrawChatPanel(target, state with
                {
                    TextOpacity = state.TextOpacity * revealOpacity,
                    BackgroundOpacity = state.BackgroundOpacity * revealOpacity,
                    ChatRect = OffsetRect(state.ChatRect, offsetY)
                });
                break;
        }
    }

    private (double Opacity, float OffsetY) ResolveContentReveal(WpfRect rect, int index)
    {
        if (_contentRevealStartedAtUtc == DateTimeOffset.MinValue)
        {
            return (1, 0);
        }

        var elapsedMs = (DateTimeOffset.UtcNow - _contentRevealStartedAtUtc).TotalMilliseconds;
        var delayMs = ResolveContentRevealDelayMs(rect, index);
        var progress = Smooth01((float)((elapsedMs - delayMs) / ContentRevealMs));
        return (progress, ContentRevealOffsetY * (1 - progress));
    }

    private double ResolveContentRevealDelayMs(WpfRect rect, int index)
    {
        if (rect.Width <= 1 || rect.Height <= 1 || _surfaceBounds.Height <= 1)
        {
            return Math.Min(ContentRevealMaxDelayMs, index * 18);
        }

        var normalizedY = Math.Clamp(
            (rect.Y + rect.Height * 0.45) / Math.Max(1, _surfaceBounds.Height),
            0,
            1);
        return Math.Min(ContentRevealMaxDelayMs, normalizedY * 110 + index * 14);
    }

    private bool IsContentRevealActive()
    {
        return _contentRevealStartedAtUtc != DateTimeOffset.MinValue &&
               (DateTimeOffset.UtcNow - _contentRevealStartedAtUtc).TotalMilliseconds <
               ContentRevealMs + ContentRevealMaxDelayMs + 80;
    }

    private static WpfRect OffsetRect(WpfRect rect, float offsetY)
    {
        return offsetY == 0
            ? rect
            : new WpfRect(rect.X, rect.Y + offsetY, rect.Width, rect.Height);
    }

    private static float EaseOutQuart(float value)
    {
        var clamped = Math.Clamp(value, 0f, 1f);
        return 1f - MathF.Pow(1f - clamped, 4f);
    }

    private readonly record struct AppearanceAnimationState(
        bool StartupActive,
        bool EventFlowActive,
        bool AmbientFlowActive);
}
