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

/// <summary>Frame state, palette and row records shared by every drawing partial.</summary>
internal sealed partial class OverlayCompositionHudWindow
{
    private readonly record struct BrushKey(byte R, byte G, byte B, byte A);

    [Flags]
    private enum NightShadowPanelJoin
    {
        None = 0,
        Top = 1,
        Bottom = 2,
        TopLeftStep = 4,
        TopRightStep = 8,
        BottomLeftStep = 16,
        BottomRightStep = 32,
        TopLeftNeighborOutside = 64,
        TopRightNeighborOutside = 128,
        BottomLeftNeighborOutside = 256,
        BottomRightNeighborOutside = 512
    }

    private readonly record struct HudColor(byte R, byte G, byte B, byte A)
    {
        public static HudColor FromRgb(byte red, byte green, byte blue, byte alpha = 255)
        {
            return new HudColor(red, green, blue, alpha);
        }
    }

    private sealed record OverlayHudPalette(
        HudColor PanelBackground,
        HudColor PanelBorder,
        HudColor Title,
        HudColor Text,
        HudColor Muted,
        HudColor Alert,
        HudColor Online,
        HudColor Offline,
        HudColor Crosshair,
        HudColor CrosshairAlert,
        HudColor Background);

    private sealed record OverlayCompositionModuleStyle(
        double TextOpacity,
        double BackgroundOpacity,
        double DecorationOpacity)
    {
        public static OverlayCompositionModuleStyle Default { get; } = new(1.0, 1.0, 1.0);
    }

    private sealed record OverlayCompositionFrameState(
        double Width,
        double Height,
        double Opacity,
        OverlayHudPalette Palette,
        OverlaySkinRenderKind RenderKind,
        bool ShowNotice,
        bool ShowSquads,
        bool ShowMembers,
        bool ShowChat,
        bool ShowCrosshair,
        bool ShowEvents,
        WpfRect NoticeRect,
        WpfRect SquadsRect,
        WpfRect MembersRect,
        WpfRect ChatRect,
        WpfRect EventRect,
        OverlayCompositionModuleStyle EventStyle,
        OverlayCompositionModuleStyle NoticeStyle,
        OverlayCompositionModuleStyle SquadsStyle,
        OverlayCompositionModuleStyle MembersStyle,
        OverlayCompositionModuleStyle ChatStyle,
        IReadOnlyList<string> ModuleDrawOrder,
        OverlayEventNotificationSide EventSide,
        OverlayNightShadowBloom NightShadowBloom,
        string FleetNoticeTitle,
        string FleetNotice,
        string NoticeTimerLabel,
        string SquadsTitle,
        string SquadPrimaryName,
        string SquadSummary,
        string SquadServerSummary,
        string SquadFocusLine,
        string OverviewLocationPlaceholder,
        string OverviewLocationPlaceholderMetric,
        IReadOnlyList<OverlayOverviewLocationCount> OverviewTopLocations,
        OverlayOverviewLocationLayoutResult OverviewLocationLayout,
        string MembersTitle,
        IReadOnlyList<OverlayCompositionMemberRow> MemberRows,
        string ChatTitle,
        OverlayChatDisplayMode ChatDisplayMode,
        OverlayChatSide ChatSide,
        double ChatBarrageFontSize,
        OverlayChatBarrageRegion ChatBarrageRegion,
        OverlayChatBarrageDensity ChatBarrageDensity,
        bool ChatBarrageAvoidCenter,
        OverlayChatTextEdgeStrength ChatTextEdgeStrength,
        IReadOnlyList<OverlayCompositionEventRow> ChatRows,
        int ChatPulse,
        bool ChatBarrageMotionEnabled,
        bool HideMemberStatus,
        double MemberNameRatio,
        string HotkeyLabel,
        OverlayCrosshairMode CrosshairMode,
        double CrosshairSize,
        double CrosshairThickness,
        double CrosshairOpacity,
        bool CrosshairShowCenterMark,
        double CrosshairCenterMarkSize,
        double CrosshairGap,
        double CrosshairOutlineOpacity,
        double EventAnimationScale,
        IReadOnlyList<OverlayCompositionEventRow> EventRows,
        int EventPulse,
        OverlayStartupTransitionFrameRate StartupTransitionFrameRate,
        OverlayAnimationFrameRate AnimationFrameRate)
    {
        public long AppearanceEpoch { get; init; }
        public OverlayAnimationFrameRate BarrageFrameRate { get; init; }
        public IReadOnlyList<OverlayAppearanceActivity> CommunicationAppearanceActivities { get; init; } = [];
        public OverlaySkin AppearanceSkin { get; init; }
        public OverlayAppearanceOptions AppearanceOptions { get; init; } = OverlayAppearanceOptions.Empty;
        public OverlayModuleSourceLabels SourceLabels { get; init; } = OverlayModuleSourceLabels.Empty;
        public OverlayModuleEmptyStates EmptyStates { get; init; } = OverlayModuleEmptyStates.Empty;
        public string EmptyNoticeTitle { get; init; } = "NOTICE";
        public string EmptyEventsTitle { get; init; } = "EVENTS";
        // Top notice slot extras: rally accent, a right-aligned hint/side mark, its colour.
        public bool NoticeAccent { get; init; }
        public string? NoticeMeta { get; init; }
        public bool NoticeMetaAccent { get; init; }
        // Unread direct messages: a mark on the chat title, or beside the top slot.
        public string? ChatUnread { get; init; }
        public string? NoticeUnread { get; init; }
        public OverlayMemberPagingFrame MemberPaging { get; init; } = OverlayMemberPagingFrame.Single;
        public OverlayOverviewFacts? OverviewFacts { get; init; }
        public bool NightShadowStyle => RenderKind == OverlaySkinRenderKind.NightShadow;


        public bool VerdictStyle => RenderKind == OverlaySkinRenderKind.Verdict;
    }

    private sealed record OverlayCompositionMemberRow(
        string DisplayName,
        string Status,
        string Ship,
        string Location,
        HudColor StatusColor,
        string? Key = null,
        OverlayRosterGroup? Group = null,
        DateTimeOffset? CueStartedAtUtc = null,
        StarBridge.Core.Presence.PlayerPresenceKind? Presence = null);

    private sealed record OverlayCompositionEventRow(
        string Title,
        string Detail,
        string Timestamp,
        float SlideOffsetX,
        float Opacity,
        float MotionProgress,
        bool IsEntering,
        bool IsExiting,
        DateTimeOffset BarrageStartedAtUtc,
        double BarrageDurationSeconds,
        int BarrageLane,
        bool IsBarrageActive,
        HudColor AccentColor)
    {
        public OverlayAppearanceActivity AppearanceActivity { get; init; }
    }

    private readonly record struct NightShadowStartupReveal(
        bool Applies,
        double Opacity,
        float ClipProgress,
        float Progress)
    {
        public static NightShadowStartupReveal Inactive { get; } = new(false, 1, 1, 1);
    }
}
