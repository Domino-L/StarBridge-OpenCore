using Vortice.Direct2D1;
using WpfRect = System.Windows.Rect;

namespace StarBridge.Desktop;

internal sealed partial class OverlayCompositionHudWindow
{
    private long _appearanceEpoch;
    private (OverlaySkin Skin, OverlaySceneKind Kind, string? Room, string? Channel, bool Local, string? Modules)? _appearanceScope;
    private void UpdateExtendedAppearanceScope(OverlaySkin skin, OverlaySceneContext scene, OverlayModulePresentation? modules)
    {
        var scope = (skin, scene.Kind, scene.RoomId, scene.ChatChannelId, scene.IsLocalOnly, modules?.ScopeKey);
        if(_appearanceScope == scope) return;
        _appearanceScope = scope;
        _appearanceEpoch++;
    }
    // Optional external appearance implementation. Ordinary builds erase these calls.
    partial void ObserveExtendedAppearanceFrame(OverlayCompositionFrameState state);
    partial void ResetExtendedAppearanceLifecycle();
    partial void PrepareExtendedAppearanceAnimationFrame(ref bool appearanceChanged);
    partial void ResolveExtendedAppearanceSampleDelay(ref int sampleDelayMs);
    partial void RecordExtendedAppearanceFrameCommit();

    public double AppearanceStartupFocusRemainingMs =>
#if STARBRIDGE_VERDICT_NEXT
        _settings.Skin == OverlaySkin.Verdict ? VerdictNextFocusRemainingMs() : 0;
#else
        0;
#endif

    private void BeginAppearanceStartup(out bool started, out double durationMs)
    {
        started = false;
        durationMs = 0;
#if STARBRIDGE_VERDICT_NEXT
        if (TryBeginVerdictNextStartup(ref started, ref durationMs)) return;
#endif
        TryBeginExtendedAppearanceStartup(ref started, ref durationMs);
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
            false,
            false,
            false);
        TryReadExtendedAppearanceAnimationState(ref state);
#if STARBRIDGE_VERDICT_NEXT
        if (_state is { VerdictStyle: true }) state = ReadVerdictNextAnimationState();
#endif
        // Installed appearance contributions run after the legacy commercial
        // adapter, which may replace its own animation flags. Optional methods
        // erase from ordinary builds; this never changes catalog eligibility.
        TryReadInstalledAppearanceAnimationState(ref state);
        return state;
    }

    private ID2D1CommandList? BuildAppearanceGlowMask(ID2D1DeviceContext target)
    {
#if STARBRIDGE_VERDICT_NEXT
        if (_state is { VerdictStyle: true }) return null; // Shared renderer owns its local halo.
#endif
        ID2D1CommandList? glowMask = null;
        TryBuildExtendedAppearanceGlowMask(target, ref glowMask);
        return glowMask;
    }

    private void DrawAppearanceGlow(
        ID2D1DeviceContext target,
        OverlayCompositionFrameState state,
        ID2D1CommandList? glowMask)
    {
        var handled = false;
#if STARBRIDGE_VERDICT_NEXT
        if (state.VerdictStyle) return;
#endif
        TryDrawExtendedAppearanceGlow(target, state, glowMask, ref handled);
    }

    private void DisposeAppearanceResources()
    {
#if STARBRIDGE_VERDICT_NEXT
        DisposeVerdictNextResources();
#endif
        DisposeExtendedAppearanceResources();
        DisposeInstalledAppearanceResources();
    }

    private void DrawSceneModules(ID2D1RenderTarget target, OverlayCompositionFrameState state)
    {
#if STARBRIDGE_VERDICT_NEXT
        if (state.VerdictStyle) { DrawVerdictNextScene(target, state); return; }
#endif
        var handled = false;
        TryDrawInstalledAppearanceScene(target, state, ref handled);
        if (handled)
        {
            return;
        }

        TryDrawExtendedAppearanceScene(target, state, ref handled);
        if (handled)
        {
            return;
        }

        DrawStandardScene(target, state);
    }

    partial void TryDrawExtendedAppearanceScene(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        ref bool handled);

    // Separate seam for an installed external pack: built-in commercial
    // appearances already implement the Extended methods in private builds.
    partial void TryDrawInstalledAppearanceScene(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        ref bool handled);

    partial void TryReadInstalledAppearanceAnimationState(ref AppearanceAnimationState state);

    partial void DisposeInstalledAppearanceResources();

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
                state.Opacity * reveal.Opacity,
                reveal.OffsetY);
        }

        if (state.ShowCrosshair)
        {
            DrawCrosshair(target, state);
        }

        if (state.ShowEvents)
        {
            DrawEventNotifications(target, state);
        }
    }

    private void DrawStartupModuleByKey(
        ID2D1RenderTarget target,
        OverlayCompositionFrameState state,
        string key,
        double opacity,
        float offsetY)
    {
        switch (key)
        {
            case "Notice":
                DrawNoticePanel(target, state with
                {
                    Opacity = opacity,
                    NoticeRect = OffsetRect(state.NoticeRect, offsetY)
                });
                break;
            case "Squads":
                DrawSquadsPanel(target, state with
                {
                    Opacity = opacity,
                    SquadsRect = OffsetRect(state.SquadsRect, offsetY)
                });
                break;
            case "Members":
                DrawMembersPanel(target, state with
                {
                    Opacity = opacity,
                    MembersRect = OffsetRect(state.MembersRect, offsetY)
                });
                break;
            case "Chat":
                DrawChatPanel(target, state with
                {
                    Opacity = opacity,
                    ChatRect = OffsetRect(state.ChatRect, offsetY)
                });
                break;
        }
    }

    private (double Opacity, float OffsetY) ResolveContentReveal(WpfRect rect, int index)
    {
        // Calm display rides the same per-module visibility every scene already applies.
        var calm = CalmFactor(rect);
        if (_contentRevealStartedAtUtc == DateTimeOffset.MinValue)
        {
            return (calm, 0);
        }

        var elapsedMs = (AppearanceAnimationUtcNow - _contentRevealStartedAtUtc).TotalMilliseconds;
        var delayMs = ResolveContentRevealDelayMs(rect, index);
        var progress = Smooth01((float)((elapsedMs - delayMs) / ContentRevealMs));
        return (progress * calm, ContentRevealOffsetY * (1 - progress));
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
               (AppearanceAnimationUtcNow - _contentRevealStartedAtUtc).TotalMilliseconds <
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
