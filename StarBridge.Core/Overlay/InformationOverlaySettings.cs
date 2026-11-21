namespace StarBridge.Core.Overlay;

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
    OverlaySkin RequestedSkin,
    double EventNotificationDecorationOpacity,
    OverlayCalmDisplay CalmDisplay,
    int CalmWaitSeconds,
    double CalmIdleOpacity,
    double CalmLitOpacity,
    OverlayCalmLightWhen CalmLightWhen,
    string CalmPeekHotkey,
    // 0.7.3 visor projection settings at CSV 81..82; older files read the defaults. CSV 80 is a
    // reserved column (see Serialize).
    OverlayVisorSize VisorSize = OverlayVisorSize.Medium,
    bool VisorHolidayGold = false,
    // 11-06 user: the DM badge moves freely ("角标自由"). CSV 83..84: the badge's screen-edge side (its right
    // edge on the right half, else its left edge) and its top, as screen fractions; -1 = the default spot.
    double VisorBadgeX = OverlayDisplaySettings.UnsetVisorBadge,
    double VisorBadgeY = OverlayDisplaySettings.UnsetVisorBadge,
    // 0.7.3 visor (11-07): how far the side panels fold toward the screen centre, in degrees (0-60 since 11-14, user "可以"; default 15).
    // CSV 85; older files read the default.
    double VisorTilt = OverlayDisplaySettings.DefaultVisorTilt,
    // 0.7.3 visor (11-07 user: "可选"): the chat group keeps its faint plate and outline (on), or shows the text only.
    // CSV 86; older files read on.
    bool VisorChatPlate = true,
    // 0.7.3 visor members size (11-07 user: "宽度自适应是不是该和高度自适应分开"): CSV 87..90. With a dimension adaptive,
    // the members follow their content up to its value (a maximum); otherwise the value is the fixed size. Visor
    // design units (scaled by resolution and the visor size); older files read adaptive with the defaults.
    bool VisorMembersAutoWidth = true,
    bool VisorMembersAutoHeight = true,
    double VisorMembersWidth = OverlayDisplaySettings.DefaultVisorMembersWidth,
    double VisorMembersHeight = OverlayDisplaySettings.DefaultVisorMembersHeight,
    // 0.7.3 visor events and chat width (11-07 user: "2放"), CSV 91..94: as the members width, adaptive (the value is
    // the maximum) or fixed; their height comes from the existing line counts.
    bool VisorEventsAutoWidth = true,
    bool VisorChatAutoWidth = true,
    double VisorEventsWidth = OverlayDisplaySettings.DefaultVisorMembersWidth,
    double VisorChatWidth = OverlayDisplaySettings.DefaultVisorMembersWidth,
    // 0.7.3 visor (11-11 user: "浮层外观应该让视距也可调"): how far the visor's camera is from the screen, in design
    // units of a 1080-high screen (600-3000 in steps of 50, default 1000: the look before it was adjustable). Nearer
    // gives a stronger perspective, farther a flatter one; with no tilt it changes nothing. CSV 95; older files read
    // the default.
    double VisorViewingDistance = OverlayDisplaySettings.DefaultVisorViewingDistance,
    // 0.7.3 visor (11-12 user: "我觉得应该允许事件随意调整位置了"): where the events sit across the screen, as a
    // screen fraction of their screen-edge side (the right edge when EventNotificationSide is Right, else the left edge);
    // -1 keeps them at the screen edge as before. CSV 96; older files read -1.
    double VisorEventsX = OverlayDisplaySettings.UnsetVisorBadge)
{
    private const int CurrentEventNotificationSchemaVersion = 3;
    private const string ReservedVisorColumn = "Visor";
    /// <summary>A DM badge coordinate that means "the default spot".</summary>
    public const double UnsetVisorBadge = -1;
    /// <summary>The visor's fold angle (立体程度) range and default, in degrees.</summary>
    public const double DefaultVisorTilt = 15, MinVisorTilt = 0, MaxVisorTilt = 60;
    /// <summary>The visor camera's viewing distance (视距) range, step and default, in design units of a 1080-high screen.</summary>
    public const double DefaultVisorViewingDistance = 1000, MinVisorViewingDistance = 600, MaxVisorViewingDistance = 3000,
        VisorViewingDistanceStep = 50;
    /// <summary>
    /// The visor members size in visor design units (×0.707 = pixels at 2560x1440, medium size). Defaults ("小而精"):
    /// the width of the two member columns at their caps, the height of eight members with the counts and a page line.
    /// The tallest holds twenty rows, the roster's own page limit.
    /// </summary>
    public const double DefaultVisorMembersWidth = 364, MinVisorMembersWidth = 220, MaxVisorMembersWidth = 480;
    // 11-07 (user: "youat可以"): "你在" joined the title line, so eight rows need 394 and twenty 874.
    public const double DefaultVisorMembersHeight = 394, MinVisorMembersHeight = 191, MaxVisorMembersHeight = 874;
    // Runtime projection only. CSV and the constructor-based settings wire remain unchanged.
    // OverlayWorkspaceStore owns persistence as part of the preset transaction.
    public OverlayAppearanceOptions AppearanceOptions { get; init; } = OverlayAppearanceOptions.Empty;
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
        // 11-10 user ("默认改成 100%"): the overall opacity never took effect before 0.7.3; its old defaults are moved to
        // full once (InformationOverlayDefaults.MigrateLegacyOpacity) and the default is full
        Opacity: 1.0,
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
        // 11-13: the plate's real opacity; 15% is the faint plate the visor always had
        EventNotificationBackgroundOpacity: InformationOverlayDefaults.LegacyBackgroundScale,
        SkipStartupTransitionWhenGameForeground: false,
        RequestedSkin: OverlaySkin.Default,
        EventNotificationDecorationOpacity: 1.0,
        // New settings start calm; older files parse as Unset (see Parse).
        CalmDisplay: OverlayCalmDisplay.On,
        CalmWaitSeconds: OverlayCalmDisplayLevels.DefaultWaitSeconds,
        CalmIdleOpacity: 0,
        CalmLitOpacity: 0,
        CalmLightWhen: OverlayCalmLightWhen.Relevant,
        CalmPeekHotkey: "");

    public bool EffectiveHideMemberOnlineStatus => HideOfflineMembers && HideMemberOnlineStatus;

    public OverlaySkin EffectiveRequestedSkin =>
        RequestedSkin != OverlaySkin.Default
            ? RequestedSkin
            : Skin;


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
            NormalizeTextOpacity(EventNotificationTextOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeBackgroundOpacity(EventNotificationBackgroundOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            SkipStartupTransitionWhenGameForeground ? "1" : "0",
            EffectiveRequestedSkin,
            NormalizeDecorationOpacity(EventNotificationDecorationOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            CalmDisplay,
            OverlayCalmDisplayLevels.NormalizeWaitSeconds(CalmWaitSeconds).ToString(System.Globalization.CultureInfo.InvariantCulture),
            OverlayCalmDisplayLevels.NormalizeOpacity(CalmIdleOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            OverlayCalmDisplayLevels.NormalizeOpacity(CalmLitOpacity).ToString("0.##", System.Globalization.CultureInfo.InvariantCulture),
            CalmLightWhen,
            OverlayCalmDisplayLevels.NormalizePeekHotkey(CalmPeekHotkey),
            // CSV 80 held a visor style for a short while on 11-06 (user then kept only the visor
            // projection: "只保留默认的吧"). The column stays so 81..82 keep their place; it is always
            // written as "Visor" and never read.
            ReservedVisorColumn,
            VisorSize,
            VisorHolidayGold ? "1" : "0",
            NormalizeVisorBadge(VisorBadgeX).ToString("0.####", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorBadge(VisorBadgeY).ToString("0.####", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorTilt(VisorTilt).ToString("0.#", System.Globalization.CultureInfo.InvariantCulture),
            VisorChatPlate ? "1" : "0",
            VisorMembersAutoWidth ? "1" : "0",
            VisorMembersAutoHeight ? "1" : "0",
            NormalizeVisorMembersWidth(VisorMembersWidth).ToString("0", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorMembersHeight(VisorMembersHeight).ToString("0", System.Globalization.CultureInfo.InvariantCulture),
            VisorEventsAutoWidth ? "1" : "0",
            VisorChatAutoWidth ? "1" : "0",
            NormalizeVisorMembersWidth(VisorEventsWidth).ToString("0", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorMembersWidth(VisorChatWidth).ToString("0", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorViewingDistance(VisorViewingDistance).ToString("0", System.Globalization.CultureInfo.InvariantCulture),
            NormalizeVisorBadge(VisorEventsX).ToString("0.####", System.Globalization.CultureInfo.InvariantCulture));
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

        OverlayArchivedAppearanceMigration.MigrateCsv(parts);

        return new OverlayDisplaySettings(
            false,
            TryParseDefinedEnum<OverlayMemberNameMode>(parts[1], out var mode) ? mode : OverlayMemberNameMode.CallsignAndGameName,
            parts[2] == "1",
            parts[3] == "1",
            parts[4] == "1",
            parts.Length > 5 && TryParseFiniteDouble(parts[5], out var opacity)
                ? Math.Clamp(opacity, 0.15, 1.0)
                : Default.Opacity,
            parts.Length <= 6 || parts[6] == "1",
            parts.Length <= 7 || parts[7] == "1",
            false,
            parts.Length <= 9 || parts[9] == "1",
            parts.Length > 43 && TryParseDefinedEnum<OverlaySkin>(parts[43], out var skin)
                ? skin
                : Default.Skin,
            parts.Length > 10 && TryParseDefinedEnum<OverlayVisualTheme>(parts[10], out var theme)
                ? theme
                : Default.Theme,
            parts.Length > 11 && parts[11] == "1",
            parts.Length > 12 && parts[12] == "1",
            parts.Length > 13 && TryParseDefinedEnum<OverlayCrosshairMode>(parts[13], out var crosshairMode)
                ? NormalizeCrosshairMode(crosshairMode)
                : Default.CrosshairMode,
            parts.Length <= 14 || parts[14] == "1",
            parts.Length > 15
                ? NormalizeCrosshairColor(parts[15])
                : Default.CrosshairColor,
            parts.Length > 16 && TryParseFiniteDouble(parts[16], out var crosshairSize)
                ? NormalizeCrosshairSize(crosshairSize)
                : Default.CrosshairSize,
            parts.Length > 17 && TryParseFiniteDouble(parts[17], out var crosshairThickness)
                ? Math.Clamp(crosshairThickness, 1, 8)
                : Default.CrosshairThickness,
            parts.Length > 18 && TryParseFiniteDouble(parts[18], out var crosshairOpacity)
                ? Math.Clamp(crosshairOpacity, 0.2, 1.0)
                : Default.CrosshairOpacity,
            parts.Length <= 39 || parts[39] == "1",
            parts.Length > 40 && TryParseFiniteDouble(parts[40], out var crosshairCenterMarkSize)
                ? NormalizeCrosshairCenterMarkSize(crosshairCenterMarkSize)
                : Default.CrosshairCenterMarkSize,
            parts.Length > 41 && TryParseFiniteDouble(parts[41], out var crosshairGap)
                ? NormalizeCrosshairGap(crosshairGap)
                : Default.CrosshairGap,
            parts.Length > 42 && TryParseFiniteDouble(parts[42], out var crosshairOutlineOpacity)
                ? NormalizeCrosshairOutlineOpacity(crosshairOutlineOpacity)
                : Default.CrosshairOutlineOpacity,
            parts.Length <= 19 || parts[19] == "1",
            parts.Length > 20 && TryParseDefinedEnum<OverlayStartupTransitionStyle>(parts[20], out var startupTransitionStyle)
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
            parts.Length > 25 && TryParseDefinedEnum<OverlayEventNotificationSide>(parts[25], out var eventNotificationSide)
                ? eventNotificationSide
                : Default.EventNotificationSide,
            parts.Length > 26 && TryParseFiniteDouble(parts[26], out var eventNotificationDuration)
                ? Math.Clamp(eventNotificationDuration, 1, 12)
                : Default.EventNotificationDurationSeconds,
            parts.Length > 27 && TryParseFiniteDouble(parts[27], out var eventNotificationY)
                ? Math.Clamp(eventNotificationY, 0, 1)
                : Default.EventNotificationY,
            parts.Length > 28 && parts[28] == "1",
            parts.Length > 29 && TryParseDefinedEnum<OverlaySquadStatusDisplayMode>(parts[29], out var squadStatusDisplayMode)
                ? squadStatusDisplayMode
                : Default.SquadStatusDisplayMode,
            parts.Length > 30 && parts[30] == "1",
            parts.Length > 31 && TryParseDefinedEnum<OverlayMemberPriorityMode>(parts[31], out var memberPriorityMode)
                ? memberPriorityMode
                : Default.MemberPriorityMode,
            parts.Length > 32 && TryParseDefinedEnum<OverlayMemberScopeMode>(parts[32], out var memberScopeMode)
                ? memberScopeMode
                : Default.MemberScopeMode,
            parts.Length > 33 && TryParseFiniteDouble(parts[33], out var memberNameColumnRatio)
                ? NormalizeMemberNameColumnRatio(memberNameColumnRatio)
                : Default.MemberNameColumnRatio,
            ParseEventNotificationTypes(parts),
            parts.Length > 35 && int.TryParse(parts[35], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var eventNotificationMaxVisibleCount)
                ? NormalizeEventNotificationMaxVisibleCount(eventNotificationMaxVisibleCount)
                : Default.EventNotificationMaxVisibleCount,
            parts.Length > 36
                ? parts[36] == "1"
                : Default.EventNotificationPinImportant,
            parts.Length > 37 && TryParseDefinedEnum<OverlayEventNotificationAnimationSpeed>(parts[37], out var eventNotificationAnimationSpeed)
                ? eventNotificationAnimationSpeed
                : Default.EventNotificationAnimationSpeed,
            parts.Length > 38
                ? OverlayEventNotificationDurationOverrides.Parse(parts[38])
                : Default.EventNotificationDurations,
            parts.Length > 44 && TryParseDefinedEnum<OverlayNightShadowBloom>(parts[44], out var nightShadowBloom)
                ? nightShadowBloom
                : Default.NightShadowBloom,
            parts.Length > 48 && TryParseAnimationFrameRate(parts[48], out var animationFrameRate)
                ? animationFrameRate
                : Default.AnimationFrameRate,
            parts.Length > 50 && TryParseDefinedEnum<OverlayScenePreference>(parts[50], out var scenePreference)
                ? scenePreference
                : Default.ScenePreference,
            parts.Length > 51 ? parts[51] == "1" : Default.ShowChat,
            parts.Length > 52 && TryParseDefinedEnum<OverlayChatDisplayMode>(parts[52], out var chatDisplayMode)
                ? NormalizeChatDisplayMode(chatDisplayMode)
                : Default.ChatDisplayMode,
            parts.Length > 53 && TryParseDefinedEnum<OverlayChatSide>(parts[53], out var chatSide)
                ? chatSide
                : Default.ChatSide,
            parts.Length > 54 && int.TryParse(parts[54], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var chatMaxVisibleCount)
                ? NormalizeChatVisibleCount(chatMaxVisibleCount)
                : Default.ChatMaxVisibleCount,
            parts.Length > 55 && TryParseFiniteDouble(parts[55], out var chatDurationSeconds)
                ? NormalizeChatDuration(chatDurationSeconds)
                : Default.ChatDurationSeconds,
            parts.Length > 56 ? parts[56] == "1" : Default.ChatShowSender,
            parts.Length > 57 ? parts[57] == "1" : Default.ChatShowTimestamp,
            parts.Length > 58 ? parts[58] == "1" : Default.ChatShowSystemMessages,
            parts.Length > 59 ? parts[59] == "1" : Default.ChatHideSelfMessages,
            parts.Length > 60 && TryParseFiniteDouble(parts[60], out var chatBarrageFontSize)
                ? NormalizeChatBarrageFontSize(chatBarrageFontSize)
                : Default.ChatBarrageFontSize,
            parts.Length > 61 && TryParseDefinedEnum<OverlayChatBarrageRegion>(parts[61], out var chatBarrageRegion)
                ? NormalizeChatBarrageRegion(chatBarrageRegion)
                : Default.ChatBarrageRegion,
            parts.Length > 62 && TryParseDefinedEnum<OverlayChatBarrageDensity>(parts[62], out var chatBarrageDensity)
                ? NormalizeChatBarrageDensity(chatBarrageDensity)
                : Default.ChatBarrageDensity,
            parts.Length > 63 ? parts[63] == "1" : Default.ChatBarrageAvoidCenter,
            parts.Length > 64 && TryParseDefinedEnum<OverlayChatTextEdgeStrength>(parts[64], out var chatTextEdgeStrength)
                ? NormalizeChatTextEdgeStrength(chatTextEdgeStrength)
                : Default.ChatTextEdgeStrength,
            parts.Length > 65 ? parts[65] == "1" : Default.CommunicationFriendEvents,
            parts.Length > 66 ? parts[66] == "1" : Default.CommunicationMessagePreview,
            parts.Length > 67 && TryParseFiniteDouble(parts[67], out var communicationEventDurationSeconds)
                ? NormalizeCommunicationEventDuration(communicationEventDurationSeconds)
                : Default.CommunicationEventDurationSeconds,
            parts.Length > 68 && TryParseDefinedEnum<OverlayFleetChatScope>(parts[68], out var fleetChatScope)
                ? NormalizeFleetChatScope(fleetChatScope)
                : Default.FleetChatScope,
            parts.Length > 69 && TryParseFiniteDouble(parts[69], out var eventNotificationTextOpacity)
                ? NormalizeTextOpacity(eventNotificationTextOpacity)
                : Default.EventNotificationTextOpacity,
            parts.Length > 70 && TryParseFiniteDouble(parts[70], out var eventNotificationBackgroundOpacity)
                ? NormalizeBackgroundOpacity(eventNotificationBackgroundOpacity)
                // a file from before this field drew the full faint plate: 100% on the old scale, scaled on load (11-13)
                : 1.0,
            parts.Length > 71
                ? parts[71] == "1"
                : Default.SkipStartupTransitionWhenGameForeground,
            parts.Length > 72 && TryParseDefinedEnum<OverlaySkin>(parts[72], out var requestedSkin)
                ? requestedSkin
                : parts.Length > 43 && TryParseDefinedEnum<OverlaySkin>(parts[43], out var legacyRequestedSkin)
                    ? legacyRequestedSkin
                    : Default.RequestedSkin,
            parts.Length > 73 && TryParseFiniteDouble(parts[73], out var eventNotificationDecorationOpacity)
                ? NormalizeDecorationOpacity(eventNotificationDecorationOpacity)
                : Default.EventNotificationDecorationOpacity,
            // A file written before calm display existed stays as it was: Unset behaves as Off.
            parts.Length > 74 && TryParseDefinedEnum<OverlayCalmDisplay>(parts[74], out var calmDisplay)
                ? calmDisplay
                : OverlayCalmDisplay.Unset,
            parts.Length > 75 && int.TryParse(parts[75], System.Globalization.NumberStyles.Integer, System.Globalization.CultureInfo.InvariantCulture, out var calmWait)
                ? OverlayCalmDisplayLevels.NormalizeWaitSeconds(calmWait)
                : OverlayCalmDisplayLevels.DefaultWaitSeconds,
            parts.Length > 76 && TryParseFiniteDouble(parts[76], out var calmIdle)
                ? OverlayCalmDisplayLevels.NormalizeOpacity(calmIdle)
                : 0,
            parts.Length > 77 && TryParseFiniteDouble(parts[77], out var calmLit)
                ? OverlayCalmDisplayLevels.NormalizeOpacity(calmLit)
                : 0,
            parts.Length > 78 && TryParseDefinedEnum<OverlayCalmLightWhen>(parts[78], out var calmLightWhen)
                ? calmLightWhen
                : OverlayCalmLightWhen.Relevant,
            parts.Length > 79 ? OverlayCalmDisplayLevels.NormalizePeekHotkey(parts[79]) : "",
            parts.Length > 81 && TryParseDefinedEnum<OverlayVisorSize>(parts[81], out var visorSize) ? visorSize : OverlayVisorSize.Medium,
            parts.Length > 82 && parts[82] == "1",
            parts.Length > 83 && TryParseFiniteDouble(parts[83], out var badgeX) ? NormalizeVisorBadge(badgeX) : -1,
            parts.Length > 84 && TryParseFiniteDouble(parts[84], out var badgeY) ? NormalizeVisorBadge(badgeY) : -1,
            parts.Length > 85 && TryParseFiniteDouble(parts[85], out var visorTilt) ? NormalizeVisorTilt(visorTilt) : DefaultVisorTilt,
            parts.Length <= 86 || parts[86] != "0",
            parts.Length <= 87 || parts[87] != "0",
            parts.Length <= 88 || parts[88] != "0",
            parts.Length > 89 && TryParseFiniteDouble(parts[89], out var membersWidth) ? NormalizeVisorMembersWidth(membersWidth) : DefaultVisorMembersWidth,
            parts.Length > 90 && TryParseFiniteDouble(parts[90], out var membersHeight) ? NormalizeVisorMembersHeight(membersHeight) : DefaultVisorMembersHeight,
            parts.Length <= 91 || parts[91] != "0",
            parts.Length <= 92 || parts[92] != "0",
            parts.Length > 93 && TryParseFiniteDouble(parts[93], out var eventsWidth) ? NormalizeVisorMembersWidth(eventsWidth) : DefaultVisorMembersWidth,
            parts.Length > 94 && TryParseFiniteDouble(parts[94], out var chatWidth) ? NormalizeVisorMembersWidth(chatWidth) : DefaultVisorMembersWidth,
            parts.Length > 95 && TryParseFiniteDouble(parts[95], out var viewingDistance)
                ? NormalizeVisorViewingDistance(viewingDistance)
                : DefaultVisorViewingDistance,
            parts.Length > 96 && TryParseFiniteDouble(parts[96], out var eventsX) ? NormalizeVisorBadge(eventsX) : UnsetVisorBadge);
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
        return double.IsFinite(value) ? Math.Clamp(value, 0.18, 0.82) : Default.MemberNameColumnRatio;
    }

    /// <summary>A badge coordinate is a screen fraction 0..1; anything else (including -1) means the default spot.</summary>
    public static double NormalizeVisorBadge(double value) => value is >= 0 and <= 1 ? value : -1;

    /// <summary>Whole design units within the members width range; anything not a finite number is the default.</summary>
    public static double NormalizeVisorMembersWidth(double value) =>
        double.IsFinite(value) ? Math.Round(Math.Clamp(value, MinVisorMembersWidth, MaxVisorMembersWidth)) : DefaultVisorMembersWidth;

    /// <summary>Whole design units within the members height range; anything not a finite number is the default.</summary>
    public static double NormalizeVisorMembersHeight(double value) =>
        double.IsFinite(value) ? Math.Round(Math.Clamp(value, MinVisorMembersHeight, MaxVisorMembersHeight)) : DefaultVisorMembersHeight;

    /// <summary>Whole degrees within 0-60; anything not a finite number is the default.</summary>
    public static double NormalizeVisorTilt(double value) =>
        double.IsFinite(value) ? Math.Round(Math.Clamp(value, MinVisorTilt, MaxVisorTilt)) : DefaultVisorTilt;

    /// <summary>Within 600-3000 in steps of 50; anything not a finite number is the default (1000).</summary>
    public static double NormalizeVisorViewingDistance(double value) =>
        double.IsFinite(value)
            ? Math.Round(Math.Clamp(value, MinVisorViewingDistance, MaxVisorViewingDistance) / VisorViewingDistanceStep) *
              VisorViewingDistanceStep
            : DefaultVisorViewingDistance;

    private static bool TryParseFiniteDouble(string value, out double parsed) =>
        double.TryParse(value, System.Globalization.NumberStyles.Float, System.Globalization.CultureInfo.InvariantCulture, out parsed) &&
        double.IsFinite(parsed);

    private static bool TryParseDefinedEnum<T>(string value, out T parsed) where T : struct, Enum =>
        Enum.TryParse(value, out parsed) && Enum.IsDefined(parsed);

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

    public static double NormalizeTextOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.15, 1.0) : 1.0;

    public static double NormalizeBackgroundOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 1.0;

    public static double NormalizeDecorationOpacity(double value) =>
        double.IsFinite(value) ? Math.Clamp(value, 0.0, 1.0) : 1.0;
}
