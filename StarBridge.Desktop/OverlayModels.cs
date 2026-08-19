using System.Collections.ObjectModel;
using System.Globalization;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Brushes = System.Windows.Media.Brushes;

namespace StarBridge.Desktop;

public enum OverlayMemberNameMode
{
    CallsignAndGameName,
    CallsignOnly,
    GameNameOnly
}

public enum OverlayMemberPriorityMode
{
    Default,
    Self,
    SquadCommander
}

public enum OverlayMemberScopeMode
{
    CurrentSquad,
    AllFleet,
    OtherSquads
}

public enum OverlaySquadStatusDisplayMode
{
    Auto,
    Compact,
    Detailed
}

public enum OverlayHorizontalAnchor
{
    Left,
    Center,
    Right
}

public enum OverlayVerticalAnchor
{
    Top,
    Middle,
    Bottom
}

public enum OverlayVisualTheme
{
    Default,
    Anvil,
    Drake,
    Argo,
    Mirai,
    Crusader,
    Aegis,
    Rsi,
    Origin,
    Aopoa,
    Esperia,
    Gatac,
    Musashi,
    NightShadow,
    LagrangeWeave,
    Verdict
}

public enum OverlaySkin
{
    Default,
    NightShadow,
    LagrangeWeave,
    Verdict,
    Minimal
}

internal enum OverlaySkinRenderKind
{
    Default,
    NightShadow,
    LagrangeWeave,
    Verdict,
    Minimal
}

public enum OverlayCrosshairMode
{
    Cross,
    Dot,
    Circle,
    TShape,
    // Legacy serialized names retained only for migration.
    Simple = 100,
    Tech = 101
}

public enum OverlayEventNotificationSide
{
    Left,
    Right
}

public enum OverlayChatDisplayMode
{
    MessageList = 0,
    FullScreenBarrage = 1,
    SidePopups = FullScreenBarrage
}

public enum OverlayChatSide
{
    Left,
    Right
}

public enum OverlayChatBarrageRegion
{
    Upper,
    UpperMiddle,
    FullScreen
}

public enum OverlayChatBarrageDensity
{
    Sparse,
    Standard,
    Dense
}

public enum OverlayChatTextEdgeStrength
{
    Off,
    Light,
    Standard,
    Strong
}

public enum OverlayFleetChatScope
{
    Fleet,
    Squad,
    All
}

public enum OverlayEventNotificationAnimationSpeed
{
    Slow,
    Normal,
    Fast
}

public enum OverlayNightShadowBloom
{
    Off,
    Standard,
    Strong
}

internal enum OverlayBloomStrength
{
    Off,
    Standard,
    Strong
}

public enum OverlayAnimationFrameRate
{
    Off = 0,
    Fps30 = 30,
    Fps60 = 60,
    Fps120 = 120
}

[Flags]
public enum OverlayEventNotificationTypes
{
    None = 0,
    MemberPresence = 1 << 0,
    MemberServer = 1 << 1,
    SameServer = 1 << 2,
    ShipChange = 1 << 3,
    LocationChange = 1 << 4,
    // Bits 5 and 6 are retired squad-event slots. Keep later values stable so
    // existing serialized presets continue to decode correctly.
    SquadChange = 1 << 5,
    CommanderChange = 1 << 6,
    OnlineSummary = 1 << 7,
    PrimaryServer = 1 << 8,
    DeathAndRespawn = 1 << 9,
    LocalPlayReminder = 1 << 10,
    All = MemberPresence |
          MemberServer |
          SameServer |
          ShipChange |
          LocationChange |
          OnlineSummary |
          PrimaryServer |
          DeathAndRespawn |
          LocalPlayReminder
}

public sealed record OverlayEventNotificationDurationOverrides(
    double MemberPresence,
    double MemberServer,
    double SameServer,
    double ShipChange,
    double LocationChange,
    double SquadChange,
    double CommanderChange,
    double OnlineSummary,
    double PrimaryServer,
    double DeathAndRespawn,
    double LocalPlayReminder)
{
    public const double InheritDefaultSeconds = 0;
    public const double MinOverrideSeconds = 1;
    public const double MaxOverrideSeconds = 30;

    public static OverlayEventNotificationDurationOverrides InheritAll { get; } = new(
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds,
        InheritDefaultSeconds);

    public double Get(OverlayEventNotificationTypes eventType)
    {
        return eventType switch
        {
            OverlayEventNotificationTypes.MemberPresence => MemberPresence,
            OverlayEventNotificationTypes.MemberServer => MemberServer,
            OverlayEventNotificationTypes.SameServer => SameServer,
            OverlayEventNotificationTypes.ShipChange => ShipChange,
            OverlayEventNotificationTypes.LocationChange => LocationChange,
            OverlayEventNotificationTypes.OnlineSummary => OnlineSummary,
            OverlayEventNotificationTypes.PrimaryServer => PrimaryServer,
            OverlayEventNotificationTypes.DeathAndRespawn => DeathAndRespawn,
            OverlayEventNotificationTypes.LocalPlayReminder => LocalPlayReminder,
            _ => InheritDefaultSeconds
        };
    }

    public double Resolve(OverlayEventNotificationTypes eventType, double fallbackSeconds)
    {
        var overrideSeconds = Get(eventType);
        return overrideSeconds > 0
            ? NormalizeOverrideSeconds(overrideSeconds)
            : Math.Clamp(fallbackSeconds, MinOverrideSeconds, MaxOverrideSeconds);
    }

    public OverlayEventNotificationDurationOverrides Set(OverlayEventNotificationTypes eventType, double seconds)
    {
        seconds = NormalizeOverrideOrInherit(seconds);
        return eventType switch
        {
            OverlayEventNotificationTypes.MemberPresence => this with { MemberPresence = seconds },
            OverlayEventNotificationTypes.MemberServer => this with { MemberServer = seconds },
            OverlayEventNotificationTypes.SameServer => this with { SameServer = seconds },
            OverlayEventNotificationTypes.ShipChange => this with { ShipChange = seconds },
            OverlayEventNotificationTypes.LocationChange => this with { LocationChange = seconds },
            OverlayEventNotificationTypes.OnlineSummary => this with { OnlineSummary = seconds },
            OverlayEventNotificationTypes.PrimaryServer => this with { PrimaryServer = seconds },
            OverlayEventNotificationTypes.DeathAndRespawn => this with { DeathAndRespawn = seconds },
            OverlayEventNotificationTypes.LocalPlayReminder => this with { LocalPlayReminder = seconds },
            _ => this
        };
    }

    public string Serialize()
    {
        return string.Join(
            ";",
            Format(MemberPresence),
            Format(MemberServer),
            Format(SameServer),
            Format(ShipChange),
            Format(LocationChange),
            // Retired squad-event duration slots: preserve positions, not values.
            Format(InheritDefaultSeconds),
            Format(InheritDefaultSeconds),
            Format(OnlineSummary),
            Format(PrimaryServer),
            Format(DeathAndRespawn),
            Format(LocalPlayReminder));
    }

    public static OverlayEventNotificationDurationOverrides Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return InheritAll;
        }

        var parts = value.Split(';', StringSplitOptions.TrimEntries);
        return new OverlayEventNotificationDurationOverrides(
            Read(parts, 0),
            Read(parts, 1),
            Read(parts, 2),
            Read(parts, 3),
            Read(parts, 4),
            InheritDefaultSeconds,
            InheritDefaultSeconds,
            Read(parts, 7),
            Read(parts, 8),
            Read(parts, 9),
            Read(parts, 10));
    }

    public static double NormalizeOverrideOrInherit(double value)
    {
        return value <= 0 ? InheritDefaultSeconds : NormalizeOverrideSeconds(value);
    }

    public static double NormalizeOverrideSeconds(double value)
    {
        return Math.Clamp(value, MinOverrideSeconds, MaxOverrideSeconds);
    }

    private static double Read(string[] parts, int index)
    {
        return index < parts.Length &&
               double.TryParse(parts[index], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var seconds)
            ? NormalizeOverrideOrInherit(seconds)
            : InheritDefaultSeconds;
    }

    private static string Format(double seconds)
    {
        return NormalizeOverrideOrInherit(seconds).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture);
    }
}

public enum OverlayStartupTransitionStyle
{
    BridgeTerminal,
    NightShadowFlowField,
    NightShadowSilentAssassination,
    NightShadowBlackCurtainTear,
    NightShadowBladeCurtainUnfold,
    NightShadowCrimsonFold,
    LagrangeWeaveEquilibrium,
    VerdictProtocol
}

public enum OverlayStartupTransitionFrameRate
{
    Fps30 = 30,
    Fps45 = 45,
    Fps60 = 60,
    Fps120 = 120
}

public sealed record OverlayStartupStatusStep(
    string Label,
    string Value,
    string PendingState,
    string DoneState);

public sealed record OverlayStartupTransitionContext(
    IReadOnlyList<OverlayStartupStatusStep> StatusSteps,
    IReadOnlyList<string> TerminalLines,
    string HeaderTargetLabel,
    string SurfaceTitle,
    string MountingStateLabel,
    string CheckingStateLabel,
    string OnlineStateLabel,
    string BootStateLabel,
    string BottomLeftDiagnostic,
    string BottomRightDiagnostic,
    string CompletionLabel,
    string CompletionSubLabel)
{
    public static OverlayStartupTransitionContext Default { get; } = new(
        StatusSteps:
        [
            new("GAME WINDOW", "StarCitizen.exe", "WAIT", "FOUND"),
            new("GAME.LOG CHANNEL", "Game.log", "WAIT", "SYNC"),
            new("IDENTITY", "local identity", "STANDBY", "BOUND"),
            new("FLEET RELAY", "api.scstarbridge.com", "STANDBY", "READY"),
            new("HUD MODULES", "notice / squads / members / events", "WAIT", "OK"),
            new("CLICK-THROUGH", "transparent input layer", "SAFE", "ARMED"),
            new("OVERLAY SURFACE", "control layer", "MOUNT", "ONLINE")
        ],
        TerminalLines:
        [
            "> mount starbridge.overlay.surface",
            "> locate active game window",
            "> bind local identity from Game.log",
            "> sync fleet relay channel",
            "> arm click-through overlay layer",
            "> calibrate tactical HUD modules",
            "> control surface online"
        ],
        HeaderTargetLabel: "LOCAL GAME WINDOW // LOCK",
        SurfaceTitle: "STAR BRIDGE CONTROL SURFACE",
        MountingStateLabel: "MOUNTING",
        CheckingStateLabel: "SYSTEM CHECK",
        OnlineStateLabel: "OVERLAY ONLINE",
        BootStateLabel: "BOOT",
        BottomLeftDiagnostic: "SYS TAKEOVER / GRID LOCK",
        BottomRightDiagnostic: "DIAG BUS 0217 / NO INPUT CAPTURE",
        CompletionLabel: "OVERLAY ONLINE",
        CompletionSubLabel: "BRIDGE LINK ESTABLISHED");
}

public sealed record OverlayDisplaySettings(
    bool HideMissionWhenIdle,
    OverlayMemberNameMode MemberNameMode,
    bool HideOfflineMembers,
    bool HideSquadIcons,
    bool EnableTrayMode,
    double Opacity,
    bool ShowNotice,
    bool ShowSquads,
    bool ShowMission,
    bool ShowMembers,
    OverlaySkin Skin,
    OverlayVisualTheme Theme,
    bool AutoThemeByShip,
    bool ShowCrosshair,
    OverlayCrosshairMode CrosshairMode,
    bool CrosshairUseThemeColor,
    string CrosshairColor,
    double CrosshairSize,
    double CrosshairThickness,
    double CrosshairOpacity,
    bool CrosshairShowCenterMark,
    double CrosshairCenterMarkSize,
    double CrosshairGap,
    double CrosshairOutlineOpacity,
    bool EnableStartupTransition,
    OverlayStartupTransitionStyle StartupTransitionStyle,
    bool AutoFocusGameWindowOnOpen,
    bool StartupTransitionFollowOverlayTheme,
    OverlayStartupTransitionFrameRate StartupTransitionFrameRate,
    bool AutoOpenOverlayOnGameStart,
    bool AutoOpenOverlayOnGameForeground,
    bool AutoCloseOverlayOnGameBackground,
    bool ShowEventNotifications,
    OverlayEventNotificationSide EventNotificationSide,
    double EventNotificationDurationSeconds,
    double EventNotificationY,
    bool HideMemberOnlineStatus,
    OverlaySquadStatusDisplayMode SquadStatusDisplayMode,
    bool HideSelfMember,
    OverlayMemberPriorityMode MemberPriorityMode,
    OverlayMemberScopeMode MemberScopeMode,
    double MemberNameColumnRatio,
    OverlayEventNotificationTypes EventNotificationTypes,
    int EventNotificationMaxVisibleCount,
    bool EventNotificationPinImportant,
    OverlayEventNotificationAnimationSpeed EventNotificationAnimationSpeed,
    OverlayEventNotificationDurationOverrides EventNotificationDurations,
    OverlayNightShadowBloom NightShadowBloom,
    OverlayAnimationFrameRate AnimationFrameRate,
    OverlayScenePreference ScenePreference,
    bool ShowChat,
    OverlayChatDisplayMode ChatDisplayMode,
    OverlayChatSide ChatSide,
    int ChatMaxVisibleCount,
    double ChatDurationSeconds,
    bool ChatShowSender,
    bool ChatShowTimestamp,
    bool ChatShowSystemMessages,
    bool ChatHideSelfMessages,
    double ChatBarrageFontSize,
    OverlayChatBarrageRegion ChatBarrageRegion,
    OverlayChatBarrageDensity ChatBarrageDensity,
    bool ChatBarrageAvoidCenter,
    OverlayChatTextEdgeStrength ChatTextEdgeStrength,
    bool CommunicationFriendEvents,
    bool CommunicationMessagePreview,
    double CommunicationEventDurationSeconds,
    OverlayFleetChatScope FleetChatScope,
    double EventNotificationTextOpacity,
    double EventNotificationBackgroundOpacity,
    bool SkipStartupTransitionWhenGameForeground,
    OverlaySkin RequestedSkin)
{
    private const int CurrentEventNotificationSchemaVersion = 3;
    private const int EventNotificationSchemaVersionIndex = 49;
    public const double MemberStatusColumnPixelWidth = 40;
    public const int MinEventNotificationCount = 1;
    public const int MaxEventNotificationCount = 5;
    public const int MinChatVisibleCount = 1;
    public const int MaxChatVisibleCount = 8;
    public const double MinCrosshairSize = 8;
    public const double MaxCrosshairSize = 240;

    public static OverlayDisplaySettings Default { get; } = new(
        HideMissionWhenIdle: false,
        MemberNameMode: OverlayMemberNameMode.CallsignAndGameName,
        HideOfflineMembers: false,
        HideSquadIcons: false,
        EnableTrayMode: false,
        Opacity: 0.85,
        ShowNotice: true,
        ShowSquads: true,
        ShowMission: false,
        ShowMembers: true,
        Skin: OverlaySkin.Default,
        Theme: OverlayVisualTheme.Default,
        AutoThemeByShip: false,
        ShowCrosshair: false,
        CrosshairMode: OverlayCrosshairMode.Cross,
        CrosshairUseThemeColor: true,
        CrosshairColor: "#EBF7FF",
        CrosshairSize: 96,
        CrosshairThickness: 2,
        CrosshairOpacity: 0.85,
        CrosshairShowCenterMark: true,
        CrosshairCenterMarkSize: 4,
        CrosshairGap: 14,
        CrosshairOutlineOpacity: 0,
        EnableStartupTransition: true,
        StartupTransitionStyle: OverlayStartupTransitionStyle.BridgeTerminal,
        AutoFocusGameWindowOnOpen: false,
        StartupTransitionFollowOverlayTheme: false,
        StartupTransitionFrameRate: OverlayStartupTransitionFrameRate.Fps120,
        AutoOpenOverlayOnGameStart: false,
        AutoOpenOverlayOnGameForeground: false,
        AutoCloseOverlayOnGameBackground: false,
        ShowEventNotifications: true,
        EventNotificationSide: OverlayEventNotificationSide.Right,
        EventNotificationDurationSeconds: 3,
        EventNotificationY: 0.34,
        HideMemberOnlineStatus: false,
        SquadStatusDisplayMode: OverlaySquadStatusDisplayMode.Auto,
        HideSelfMember: false,
        MemberPriorityMode: OverlayMemberPriorityMode.Default,
        MemberScopeMode: OverlayMemberScopeMode.CurrentSquad,
        MemberNameColumnRatio: 0.5,
        EventNotificationTypes: OverlayEventNotificationTypes.All,
        EventNotificationMaxVisibleCount: 3,
        EventNotificationPinImportant: false,
        EventNotificationAnimationSpeed: OverlayEventNotificationAnimationSpeed.Normal,
        EventNotificationDurations: OverlayEventNotificationDurationOverrides.InheritAll,
        NightShadowBloom: OverlayNightShadowBloom.Standard,
        AnimationFrameRate: OverlayAnimationFrameRate.Fps120,
        ScenePreference: OverlayScenePreference.Auto,
        ShowChat: true,
        ChatDisplayMode: OverlayChatDisplayMode.MessageList,
        ChatSide: OverlayChatSide.Right,
        ChatMaxVisibleCount: 4,
        ChatDurationSeconds: 12,
        ChatShowSender: true,
        ChatShowTimestamp: true,
        ChatShowSystemMessages: true,
        ChatHideSelfMessages: false,
        ChatBarrageFontSize: 16,
        ChatBarrageRegion: OverlayChatBarrageRegion.UpperMiddle,
        ChatBarrageDensity: OverlayChatBarrageDensity.Standard,
        ChatBarrageAvoidCenter: true,
        ChatTextEdgeStrength: OverlayChatTextEdgeStrength.Standard,
        CommunicationFriendEvents: true,
        CommunicationMessagePreview: false,
        CommunicationEventDurationSeconds: 5,
        FleetChatScope: OverlayFleetChatScope.Fleet,
        EventNotificationTextOpacity: 1.0,
        EventNotificationBackgroundOpacity: 1.0,
        SkipStartupTransitionWhenGameForeground: false,
        RequestedSkin: OverlaySkin.Default);

    public bool EffectiveHideMemberOnlineStatus => HideOfflineMembers && HideMemberOnlineStatus;

    public OverlaySkin EffectiveRequestedSkin =>
        RequestedSkin != OverlaySkin.Default
            ? RequestedSkin
            : Skin;

    internal OverlayBloomStrength EffectiveBloomStrength =>
        NightShadowBloom switch
        {
            OverlayNightShadowBloom.Off => OverlayBloomStrength.Off,
            OverlayNightShadowBloom.Strong => OverlayBloomStrength.Strong,
            _ => OverlayBloomStrength.Standard
        };

    public string Serialize()
    {
        return string.Join(
            ",",
            "0", // Retired mission setting retained only for preset format compatibility.
            MemberNameMode,
            HideOfflineMembers ? "1" : "0",
            HideSquadIcons ? "1" : "0",
            EnableTrayMode ? "1" : "0",
            Opacity.ToString("0.00", System.Globalization.CultureInfo.InvariantCulture),
            ShowNotice ? "1" : "0",
            ShowSquads ? "1" : "0",
            "0", // Retired mission setting retained only for preset format compatibility.
            ShowMembers ? "1" : "0",
            Theme,
            AutoThemeByShip ? "1" : "0",
            ShowCrosshair ? "1" : "0",
            NormalizeCrosshairMode(CrosshairMode),
            CrosshairUseThemeColor ? "1" : "0",
            NormalizeCrosshairColor(CrosshairColor),
            NormalizeCrosshairSize(CrosshairSize).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            Math.Clamp(CrosshairThickness, 1, 8).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            Math.Clamp(CrosshairOpacity, 0.2, 1.0).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            EnableStartupTransition ? "1" : "0",
            StartupTransitionStyle,
            AutoFocusGameWindowOnOpen ? "1" : "0",
            StartupTransitionFollowOverlayTheme ? "1" : "0",
            (int)StartupTransitionFrameRate,
            ShowEventNotifications ? "1" : "0",
            EventNotificationSide,
            Math.Clamp(EventNotificationDurationSeconds, 1, 12).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            Math.Clamp(EventNotificationY, 0, 1).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture),
            HideMemberOnlineStatus ? "1" : "0",
            SquadStatusDisplayMode,
            HideSelfMember ? "1" : "0",
            MemberPriorityMode,
            MemberScopeMode,
            NormalizeMemberNameColumnRatio(MemberNameColumnRatio).ToString("0.###", System.Globalization.CultureInfo.InvariantCulture),
            ((int)NormalizeEventNotificationTypes(EventNotificationTypes)).ToString(System.Globalization.CultureInfo.InvariantCulture),
            NormalizeEventNotificationMaxVisibleCount(EventNotificationMaxVisibleCount).ToString(System.Globalization.CultureInfo.InvariantCulture),
            EventNotificationPinImportant ? "1" : "0",
            EventNotificationAnimationSpeed,
            EventNotificationDurations.Serialize(),
            CrosshairShowCenterMark ? "1" : "0",
            NormalizeCrosshairCenterMarkSize(CrosshairCenterMarkSize).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeCrosshairGap(CrosshairGap).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeCrosshairOutlineOpacity(CrosshairOutlineOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            Skin,
            NightShadowBloom,
            AutoOpenOverlayOnGameStart ? "1" : "0",
            AutoOpenOverlayOnGameForeground ? "1" : "0",
            AutoCloseOverlayOnGameBackground ? "1" : "0",
            (int)AnimationFrameRate,
            CurrentEventNotificationSchemaVersion,
            ScenePreference,
            ShowChat ? "1" : "0",
            NormalizeChatDisplayMode(ChatDisplayMode),
            ChatSide,
            NormalizeChatVisibleCount(ChatMaxVisibleCount).ToString(System.Globalization.CultureInfo.InvariantCulture),
            NormalizeChatDuration(ChatDurationSeconds).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            ChatShowSender ? "1" : "0",
            ChatShowTimestamp ? "1" : "0",
            ChatShowSystemMessages ? "1" : "0",
            ChatHideSelfMessages ? "1" : "0",
            NormalizeChatBarrageFontSize(ChatBarrageFontSize).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeChatBarrageRegion(ChatBarrageRegion),
            NormalizeChatBarrageDensity(ChatBarrageDensity),
            ChatBarrageAvoidCenter ? "1" : "0",
            NormalizeChatTextEdgeStrength(ChatTextEdgeStrength),
            CommunicationFriendEvents ? "1" : "0",
            CommunicationMessagePreview ? "1" : "0",
            NormalizeCommunicationEventDuration(CommunicationEventDurationSeconds).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeFleetChatScope(FleetChatScope),
            OverlayLayoutItem.NormalizeTextOpacity(EventNotificationTextOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            OverlayLayoutItem.NormalizeBackgroundOpacity(EventNotificationBackgroundOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            SkipStartupTransitionWhenGameForeground ? "1" : "0",
            EffectiveRequestedSkin);
    }

    public static OverlayDisplaySettings Parse(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return Default;
        }

        var parts = value.Split(',', StringSplitOptions.TrimEntries);
        if (parts.Length < 5)
        {
            return Default;
        }

        return new OverlayDisplaySettings(
            false,
            Enum.TryParse<OverlayMemberNameMode>(parts[1], out var mode) ? mode : OverlayMemberNameMode.CallsignAndGameName,
            parts[2] == "1",
            parts[3] == "1",
            parts[4] == "1",
            parts.Length > 5 && double.TryParse(parts[5], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var opacity)
                ? Math.Clamp(opacity, 0.15, 1.0)
                : Default.Opacity,
            parts.Length <= 6 || parts[6] == "1",
            parts.Length <= 7 || parts[7] == "1",
            false,
            parts.Length <= 9 || parts[9] == "1",
            parts.Length > 43 && Enum.TryParse<OverlaySkin>(parts[43], out var skin)
                ? skin
                : Default.Skin,
            parts.Length > 10 && Enum.TryParse<OverlayVisualTheme>(parts[10], out var theme)
                ? theme
                : Default.Theme,
            parts.Length > 11 && parts[11] == "1",
            parts.Length > 12 && parts[12] == "1",
            parts.Length > 13 && Enum.TryParse<OverlayCrosshairMode>(parts[13], out var crosshairMode)
                ? NormalizeCrosshairMode(crosshairMode)
                : Default.CrosshairMode,
            parts.Length <= 14 || parts[14] == "1",
            parts.Length > 15
                ? NormalizeCrosshairColor(parts[15])
                : Default.CrosshairColor,
            parts.Length > 16 && double.TryParse(parts[16], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairSize)
                ? NormalizeCrosshairSize(crosshairSize)
                : Default.CrosshairSize,
            parts.Length > 17 && double.TryParse(parts[17], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairThickness)
                ? Math.Clamp(crosshairThickness, 1, 8)
                : Default.CrosshairThickness,
            parts.Length > 18 && double.TryParse(parts[18], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairOpacity)
                ? Math.Clamp(crosshairOpacity, 0.2, 1.0)
                : Default.CrosshairOpacity,
            parts.Length <= 39 || parts[39] == "1",
            parts.Length > 40 && double.TryParse(parts[40], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairCenterMarkSize)
                ? NormalizeCrosshairCenterMarkSize(crosshairCenterMarkSize)
                : Default.CrosshairCenterMarkSize,
            parts.Length > 41 && double.TryParse(parts[41], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairGap)
                ? NormalizeCrosshairGap(crosshairGap)
                : Default.CrosshairGap,
            parts.Length > 42 && double.TryParse(parts[42], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var crosshairOutlineOpacity)
                ? NormalizeCrosshairOutlineOpacity(crosshairOutlineOpacity)
                : Default.CrosshairOutlineOpacity,
            parts.Length <= 19 || parts[19] == "1",
            parts.Length > 20 && Enum.TryParse<OverlayStartupTransitionStyle>(parts[20], out var startupTransitionStyle)
                ? startupTransitionStyle
                : Default.StartupTransitionStyle,
            parts.Length > 21 && parts[21] == "1",
            parts.Length > 22 && parts[22] == "1",
            parts.Length > 23 && TryParseStartupTransitionFrameRate(parts[23], out var startupTransitionFrameRate)
                ? startupTransitionFrameRate
                : Default.StartupTransitionFrameRate,
            parts.Length > 45 && parts[45] == "1",
            parts.Length > 46 && parts[46] == "1",
            parts.Length > 47 && parts[47] == "1",
            parts.Length <= 24 || parts[24] == "1",
            parts.Length > 25 && Enum.TryParse<OverlayEventNotificationSide>(parts[25], out var eventNotificationSide)
                ? eventNotificationSide
                : Default.EventNotificationSide,
            parts.Length > 26 && double.TryParse(parts[26], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationDuration)
                ? Math.Clamp(eventNotificationDuration, 1, 12)
                : Default.EventNotificationDurationSeconds,
            parts.Length > 27 && double.TryParse(parts[27], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationY)
                ? Math.Clamp(eventNotificationY, 0, 1)
                : Default.EventNotificationY,
            parts.Length > 28 && parts[28] == "1",
            parts.Length > 29 && Enum.TryParse<OverlaySquadStatusDisplayMode>(parts[29], out var squadStatusDisplayMode)
                ? squadStatusDisplayMode
                : Default.SquadStatusDisplayMode,
            parts.Length > 30 && parts[30] == "1",
            parts.Length > 31 && Enum.TryParse<OverlayMemberPriorityMode>(parts[31], out var memberPriorityMode)
                ? memberPriorityMode
                : Default.MemberPriorityMode,
            parts.Length > 32 && Enum.TryParse<OverlayMemberScopeMode>(parts[32], out var memberScopeMode)
                ? memberScopeMode
                : Default.MemberScopeMode,
            parts.Length > 33 && double.TryParse(parts[33], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var memberNameColumnRatio)
                ? NormalizeMemberNameColumnRatio(memberNameColumnRatio)
                : Default.MemberNameColumnRatio,
            ParseEventNotificationTypes(parts),
            parts.Length > 35 && int.TryParse(parts[35], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationMaxVisibleCount)
                ? NormalizeEventNotificationMaxVisibleCount(eventNotificationMaxVisibleCount)
                : Default.EventNotificationMaxVisibleCount,
            parts.Length > 36
                ? parts[36] == "1"
                : Default.EventNotificationPinImportant,
            parts.Length > 37 && Enum.TryParse<OverlayEventNotificationAnimationSpeed>(parts[37], out var eventNotificationAnimationSpeed)
                ? eventNotificationAnimationSpeed
                : Default.EventNotificationAnimationSpeed,
            parts.Length > 38
                ? OverlayEventNotificationDurationOverrides.Parse(parts[38])
                : Default.EventNotificationDurations,
            parts.Length > 44 && Enum.TryParse<OverlayNightShadowBloom>(parts[44], out var nightShadowBloom)
                ? nightShadowBloom
                : Default.NightShadowBloom,
            parts.Length > 48 && TryParseAnimationFrameRate(parts[48], out var animationFrameRate)
                ? animationFrameRate
                : Default.AnimationFrameRate,
            parts.Length > 50 && Enum.TryParse<OverlayScenePreference>(parts[50], out var scenePreference)
                ? scenePreference
                : Default.ScenePreference,
            parts.Length > 51 ? parts[51] == "1" : Default.ShowChat,
            parts.Length > 52 && Enum.TryParse<OverlayChatDisplayMode>(parts[52], out var chatDisplayMode)
                ? NormalizeChatDisplayMode(chatDisplayMode)
                : Default.ChatDisplayMode,
            parts.Length > 53 && Enum.TryParse<OverlayChatSide>(parts[53], out var chatSide)
                ? chatSide
                : Default.ChatSide,
            parts.Length > 54 && int.TryParse(parts[54], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var chatMaxVisibleCount)
                ? NormalizeChatVisibleCount(chatMaxVisibleCount)
                : Default.ChatMaxVisibleCount,
            parts.Length > 55 && double.TryParse(parts[55], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var chatDurationSeconds)
                ? NormalizeChatDuration(chatDurationSeconds)
                : Default.ChatDurationSeconds,
            parts.Length > 56 ? parts[56] == "1" : Default.ChatShowSender,
            parts.Length > 57 ? parts[57] == "1" : Default.ChatShowTimestamp,
            parts.Length > 58 ? parts[58] == "1" : Default.ChatShowSystemMessages,
            parts.Length > 59 ? parts[59] == "1" : Default.ChatHideSelfMessages,
            parts.Length > 60 && double.TryParse(parts[60], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var chatBarrageFontSize)
                ? NormalizeChatBarrageFontSize(chatBarrageFontSize)
                : Default.ChatBarrageFontSize,
            parts.Length > 61 && Enum.TryParse<OverlayChatBarrageRegion>(parts[61], out var chatBarrageRegion)
                ? NormalizeChatBarrageRegion(chatBarrageRegion)
                : Default.ChatBarrageRegion,
            parts.Length > 62 && Enum.TryParse<OverlayChatBarrageDensity>(parts[62], out var chatBarrageDensity)
                ? NormalizeChatBarrageDensity(chatBarrageDensity)
                : Default.ChatBarrageDensity,
            parts.Length > 63 ? parts[63] == "1" : Default.ChatBarrageAvoidCenter,
            parts.Length > 64 && Enum.TryParse<OverlayChatTextEdgeStrength>(parts[64], out var chatTextEdgeStrength)
                ? NormalizeChatTextEdgeStrength(chatTextEdgeStrength)
                : Default.ChatTextEdgeStrength,
            parts.Length > 65 ? parts[65] == "1" : Default.CommunicationFriendEvents,
            parts.Length > 66 ? parts[66] == "1" : Default.CommunicationMessagePreview,
            parts.Length > 67 && double.TryParse(parts[67], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var communicationEventDurationSeconds)
                ? NormalizeCommunicationEventDuration(communicationEventDurationSeconds)
                : Default.CommunicationEventDurationSeconds,
            parts.Length > 68 && Enum.TryParse<OverlayFleetChatScope>(parts[68], out var fleetChatScope)
                ? NormalizeFleetChatScope(fleetChatScope)
                : Default.FleetChatScope,
            parts.Length > 69 && double.TryParse(parts[69], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationTextOpacity)
                ? OverlayLayoutItem.NormalizeTextOpacity(eventNotificationTextOpacity)
                : Default.EventNotificationTextOpacity,
            parts.Length > 70 && double.TryParse(parts[70], System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationBackgroundOpacity)
                ? OverlayLayoutItem.NormalizeBackgroundOpacity(eventNotificationBackgroundOpacity)
                : Default.EventNotificationBackgroundOpacity,
            parts.Length > 71
                ? parts[71] == "1"
                : Default.SkipStartupTransitionWhenGameForeground,
            parts.Length > 72 && Enum.TryParse<OverlaySkin>(parts[72], out var requestedSkin)
                ? requestedSkin
                : parts.Length > 43 && Enum.TryParse<OverlaySkin>(parts[43], out var legacyRequestedSkin)
                    ? legacyRequestedSkin
                    : Default.RequestedSkin);
    }

    public static int NormalizeChatVisibleCount(int value) =>
        Math.Clamp(value, MinChatVisibleCount, MaxChatVisibleCount);

    public static OverlayChatDisplayMode NormalizeChatDisplayMode(OverlayChatDisplayMode value) =>
        value == OverlayChatDisplayMode.MessageList
            ? OverlayChatDisplayMode.MessageList
            : OverlayChatDisplayMode.FullScreenBarrage;

    public static double NormalizeChatDuration(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 6, 20) : Default.ChatDurationSeconds;

    public static double NormalizeChatBarrageFontSize(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 12, 28) : Default.ChatBarrageFontSize;

    public static OverlayChatBarrageRegion NormalizeChatBarrageRegion(OverlayChatBarrageRegion value) =>
        Enum.IsDefined(value) ? value : Default.ChatBarrageRegion;

    public static OverlayChatBarrageDensity NormalizeChatBarrageDensity(OverlayChatBarrageDensity value) =>
        Enum.IsDefined(value) ? value : Default.ChatBarrageDensity;

    public static OverlayChatTextEdgeStrength NormalizeChatTextEdgeStrength(OverlayChatTextEdgeStrength value) =>
        Enum.IsDefined(value) ? value : Default.ChatTextEdgeStrength;

    // Slot 68 stays in the wire format for positional compatibility, but the
    // retired squad/all scopes no longer have live behavior.
    public static OverlayFleetChatScope NormalizeFleetChatScope(OverlayFleetChatScope value) =>
        OverlayFleetChatScope.Fleet;

    public static double NormalizeCommunicationEventDuration(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 2, 12) : Default.CommunicationEventDurationSeconds;

    public static int ResolveChatBarrageCapacity(OverlayChatBarrageDensity density) =>
        NormalizeChatBarrageDensity(density) switch
        {
            OverlayChatBarrageDensity.Sparse => 3,
            OverlayChatBarrageDensity.Dense => 8,
            _ => 5
        };

    public static double ResolveChatBarragePixelsPerSecond(double durationSetting) =>
        NormalizeChatDuration(durationSetting) switch
        {
            <= 6 => 360,
            <= 8 => 280,
            <= 12 => 200,
            <= 16 => 150,
            _ => 120
        };

    public static double EstimateChatBarrageTextWidth(string? value, double fontSize)
    {
        var normalizedFontSize = NormalizeChatBarrageFontSize(fontSize);
        var scale = normalizedFontSize / 16d;
        var width = 0d;
        foreach (var character in value ?? string.Empty)
        {
            width += character > 0xFF ? 14d * scale : 8d * scale;
        }

        return width + 6d * scale;
    }

    public static double ResolveChatDurationForDisplayModeChange(
        OverlayChatDisplayMode currentMode,
        OverlayChatDisplayMode nextMode,
        double selectedDuration)
    {
        var normalizedCurrentMode = NormalizeChatDisplayMode(currentMode);
        var normalizedNextMode = NormalizeChatDisplayMode(nextMode);
        return normalizedCurrentMode != OverlayChatDisplayMode.FullScreenBarrage &&
               normalizedNextMode == OverlayChatDisplayMode.FullScreenBarrage
            ? Default.ChatDurationSeconds
            : NormalizeChatDuration(selectedDuration);
    }

    public static double NormalizeCrosshairSize(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, MinCrosshairSize, MaxCrosshairSize) : Default.CrosshairSize;
    }

    public static OverlayCrosshairMode NormalizeCrosshairMode(OverlayCrosshairMode value)
    {
        return value switch
        {
            OverlayCrosshairMode.Dot => OverlayCrosshairMode.Dot,
            OverlayCrosshairMode.Circle => OverlayCrosshairMode.Circle,
            OverlayCrosshairMode.TShape => OverlayCrosshairMode.TShape,
            _ => OverlayCrosshairMode.Cross
        };
    }

    public static double NormalizeCrosshairCenterMarkSize(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, 0, 18) : Default.CrosshairCenterMarkSize;
    }

    public static double NormalizeCrosshairGap(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, 6, 28) : Default.CrosshairGap;
    }

    public static double NormalizeCrosshairOutlineOpacity(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, 0, 0.8) : Default.CrosshairOutlineOpacity;
    }

    public static double NormalizeMemberNameColumnRatio(double value)
    {
        return Math.Clamp(value, 0.18, 0.82);
    }

    public static OverlayEventNotificationTypes NormalizeEventNotificationTypes(OverlayEventNotificationTypes value)
    {
        return value & OverlayEventNotificationTypes.All;
    }

    private static OverlayEventNotificationTypes ParseEventNotificationTypes(string[] parts)
    {
        var types = parts.Length > 34 && TryParseEventNotificationTypes(parts[34], out var parsed)
            ? parsed
            : Default.EventNotificationTypes;
        var schemaVersion = parts.Length > EventNotificationSchemaVersionIndex &&
                            int.TryParse(
                                parts[EventNotificationSchemaVersionIndex],
                                System.Globalization.NumberStyles.Integer,
                                System.Globalization.CultureInfo.InvariantCulture,
                                out var parsedSchemaVersion)
            ? parsedSchemaVersion
            : 0;
        if (schemaVersion < 2)
        {
            types |= OverlayEventNotificationTypes.DeathAndRespawn;
        }

        if (schemaVersion < 3)
        {
            types |= OverlayEventNotificationTypes.LocalPlayReminder;
        }

        return NormalizeEventNotificationTypes(types);
    }

    public static int NormalizeEventNotificationMaxVisibleCount(int value)
    {
        return Math.Clamp(value, MinEventNotificationCount, MaxEventNotificationCount);
    }

    public static double ResolveEventNotificationAnimationScale(OverlayEventNotificationAnimationSpeed speed)
    {
        return speed switch
        {
            OverlayEventNotificationAnimationSpeed.Slow => 1.35,
            OverlayEventNotificationAnimationSpeed.Fast => 0.72,
            _ => 1.0
        };
    }

    private static bool TryParseEventNotificationTypes(string? value, out OverlayEventNotificationTypes types)
    {
        if (int.TryParse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var numeric))
        {
            types = NormalizeEventNotificationTypes((OverlayEventNotificationTypes)numeric);
            return true;
        }

        if (Enum.TryParse<OverlayEventNotificationTypes>(value, out var parsed))
        {
            types = NormalizeEventNotificationTypes(parsed);
            return true;
        }

        types = Default.EventNotificationTypes;
        return false;
    }

    private static bool TryParseStartupTransitionFrameRate(string? value, out OverlayStartupTransitionFrameRate frameRate)
    {
        if (int.TryParse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var fps) &&
            Enum.IsDefined(typeof(OverlayStartupTransitionFrameRate), fps))
        {
            frameRate = (OverlayStartupTransitionFrameRate)fps;
            return true;
        }

        if (Enum.TryParse<OverlayStartupTransitionFrameRate>(value, out frameRate) &&
            Enum.IsDefined(typeof(OverlayStartupTransitionFrameRate), frameRate))
        {
            return true;
        }

        frameRate = Default.StartupTransitionFrameRate;
        return false;
    }

    private static bool TryParseAnimationFrameRate(string? value, out OverlayAnimationFrameRate frameRate)
    {
        if (int.TryParse(value, System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var fps) &&
            Enum.IsDefined(typeof(OverlayAnimationFrameRate), fps))
        {
            frameRate = (OverlayAnimationFrameRate)fps;
            return true;
        }

        if (Enum.TryParse<OverlayAnimationFrameRate>(value, out frameRate) &&
            Enum.IsDefined(typeof(OverlayAnimationFrameRate), frameRate))
        {
            return true;
        }

        frameRate = Default.AnimationFrameRate;
        return false;
    }

    public static string NormalizeCrosshairColor(string? value)
    {
        var text = value?.Trim();
        if (string.IsNullOrWhiteSpace(text))
        {
            return Default.CrosshairColor;
        }

        if (text.StartsWith('#'))
        {
            text = text[1..];
        }

        if (text.Length == 3)
        {
            text = string.Concat(text.Select(ch => $"{ch}{ch}"));
        }

        return text.Length == 6 && text.All(Uri.IsHexDigit)
            ? $"#{text.ToUpperInvariant()}"
            : Default.CrosshairColor;
    }
}

internal static class OverlayStartupTransitionPolicy
{
    public static OverlayDisplaySettings ResolveForOpen(
        OverlayDisplaySettings settings,
        bool isGameForeground)
    {
        if (!settings.EnableStartupTransition ||
            !settings.SkipStartupTransitionWhenGameForeground ||
            !isGameForeground)
        {
            return settings;
        }

        return settings with { EnableStartupTransition = false };
    }
}

public sealed record OverlayCommandState(
    string? NoticeTitle,
    string? NoticeText,
    string? FleetTaskTitle,
    string? FleetTaskBrief,
    string? RallyPoint,
    string? RequiredShip);

public sealed record OverlayChatMessage(
    long Sequence,
    string ChannelId,
    string SenderCallsign,
    string SenderGameId,
    string Text,
    DateTimeOffset CreatedAt,
    bool IsSystem,
    bool IsSelf,
    string SenderColor,
    string? SourceLabel = null);

public sealed record MemberAvatarRow(
    string Name,
    string Initials,
    string Status,
    string? AvatarPath = null,
    Brush? NameBrush = null,
    bool IsCommander = false,
    string GameId = "",
    string? Callsign = null,
    string? AccountId = null,
    bool IsSelf = false,
    string? LiveStatus = null)
{
    public string PresenceText => PlayerPresencePresentation.Format(
        PlayerPresencePresentation.ResolveShared(LiveStatus, Status));
    public Brush StatusBrush => PlayerPresencePresentation.Brush(
        PlayerPresencePresentation.ResolveShared(LiveStatus, Status));
}

public sealed class OverlayLayoutItem
{
    public const string RetiredMissionKey = "Mission";

    public OverlayLayoutItem(
        string key,
        string title,
        double x,
        double y,
        double width,
        double height,
        Brush brush,
        OverlayHorizontalAnchor? horizontalAnchor = null,
        OverlayVerticalAnchor? verticalAnchor = null,
        bool isLocked = false,
        double textOpacity = 1.0,
        double backgroundOpacity = 1.0)
    {
        Key = key;
        Title = title;
        X = x;
        Y = y;
        Width = width;
        Height = height;
        Brush = brush;
        HorizontalAnchor = horizontalAnchor ?? InferHorizontalAnchor(x, width);
        VerticalAnchor = verticalAnchor ?? InferVerticalAnchor(y, height);
        IsLocked = isLocked;
        TextOpacity = NormalizeTextOpacity(textOpacity);
        BackgroundOpacity = NormalizeBackgroundOpacity(backgroundOpacity);
    }

    public string Key { get; }

    public string Title { get; }

    public double X { get; set; }

    public double Y { get; set; }

    public double Width { get; set; }

    public double Height { get; set; }

    public Brush Brush { get; }

    public OverlayHorizontalAnchor HorizontalAnchor { get; set; }

    public OverlayVerticalAnchor VerticalAnchor { get; set; }

    public bool IsLocked { get; set; }

    public double TextOpacity { get; set; }

    public double BackgroundOpacity { get; set; }

    public string Serialize()
    {
        return string.Join(
            ",",
            Key,
            X.ToString("0.####", CultureInfo.InvariantCulture),
            Y.ToString("0.####", CultureInfo.InvariantCulture),
            Width.ToString("0.####", CultureInfo.InvariantCulture),
            Height.ToString("0.####", CultureInfo.InvariantCulture),
            HorizontalAnchor,
            VerticalAnchor,
            IsLocked ? "1" : "0",
            NormalizeTextOpacity(TextOpacity).ToString("0.##", CultureInfo.InvariantCulture),
            NormalizeBackgroundOpacity(BackgroundOpacity).ToString("0.##", CultureInfo.InvariantCulture));
    }

    public static IEnumerable<OverlayLayoutItem> ParseMany(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            yield break;
        }

        foreach (var item in value.Split(';', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries))
        {
            var parts = item.Split(',', StringSplitOptions.TrimEntries);
            if (parts.Length < 5 ||
                !TryParseLayoutNumber(parts[1], out var x) ||
                !TryParseLayoutNumber(parts[2], out var y) ||
                !TryParseLayoutNumber(parts[3], out var width) ||
                !TryParseLayoutNumber(parts[4], out var height))
            {
                continue;
            }

            var key = parts[0];
            if (IsRetiredModuleKey(key))
            {
                continue;
            }

            var horizontalAnchor = parts.Length > 5 &&
                Enum.TryParse<OverlayHorizontalAnchor>(parts[5], ignoreCase: true, out var parsedHorizontalAnchor)
                    ? parsedHorizontalAnchor
                    : InferHorizontalAnchor(x, width);
            var verticalAnchor = parts.Length > 6 &&
                Enum.TryParse<OverlayVerticalAnchor>(parts[6], ignoreCase: true, out var parsedVerticalAnchor)
                    ? parsedVerticalAnchor
                    : InferVerticalAnchor(y, height);
            var isLocked = parts.Length > 7 && ParseLayoutBool(parts[7]);
            var textOpacity = parts.Length > 8 && TryParseLayoutNumber(parts[8], out var parsedTextOpacity)
                ? parsedTextOpacity
                : 1.0;
            var backgroundOpacity = parts.Length > 9 && TryParseLayoutNumber(parts[9], out var parsedBackgroundOpacity)
                ? parsedBackgroundOpacity
                : 1.0;
            yield return new OverlayLayoutItem(
                key,
                GetTitle(key),
                Math.Clamp(x, 0, 0.95),
                Math.Clamp(y, 0, 0.95),
                Math.Clamp(width, 0.05, 1),
                Math.Clamp(height, 0.05, 1),
                GetBrush(key),
                horizontalAnchor,
                verticalAnchor,
                isLocked,
                textOpacity,
                backgroundOpacity);
        }
    }

    public static double NormalizeTextOpacity(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, 0.15, 1.0) : 1.0;
    }

    public static double NormalizeBackgroundOpacity(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 1.0;
    }

    public static bool IsRetiredModuleKey(string? key)
    {
        return RetiredMissionKey.Equals(key?.Trim(), StringComparison.OrdinalIgnoreCase);
    }

    private static bool TryParseLayoutNumber(string value, out double number)
    {
        return double.TryParse(value, NumberStyles.Float, CultureInfo.InvariantCulture, out number) ||
               double.TryParse(value, NumberStyles.Float, CultureInfo.CurrentCulture, out number);
    }

    private static bool ParseLayoutBool(string value)
    {
        return value.Equals("1", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("true", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("locked", StringComparison.OrdinalIgnoreCase);
    }

    private static OverlayHorizontalAnchor InferHorizontalAnchor(double x, double width)
    {
        var center = x + width / 2;
        if (center <= 0.38)
        {
            return OverlayHorizontalAnchor.Left;
        }

        return center >= 0.62 ? OverlayHorizontalAnchor.Right : OverlayHorizontalAnchor.Center;
    }

    private static OverlayVerticalAnchor InferVerticalAnchor(double y, double height)
    {
        var center = y + height / 2;
        if (center <= 0.36)
        {
            return OverlayVerticalAnchor.Top;
        }

        return center >= 0.68 ? OverlayVerticalAnchor.Bottom : OverlayVerticalAnchor.Middle;
    }

    private static string GetTitle(string key)
    {
        return key switch
        {
            "Notice" => "通讯事件",
            "Squads" => "舰队总览",
            "Members" => "成员状态",
            "Chat" => "场景通讯",
            _ => key
        };
    }

    private static Brush GetBrush(string key)
    {
        return key switch
        {
            "Notice" => Brushes.Yellow,
            "Squads" => Brushes.DeepSkyBlue,
            "Members" => Brushes.Gray,
            "Chat" => Brushes.MediumPurple,
            _ => Brushes.DeepSkyBlue
        };
    }
}
