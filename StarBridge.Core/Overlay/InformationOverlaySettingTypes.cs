namespace StarBridge.Core.Overlay;

public enum OverlayScenePreference
{
    Auto,
    Fleet,
    PartyRoom
}

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
    // Value 14 belonged to the archived appearance; keep later wire IDs stable.
    Verdict = 15
}

public enum OverlaySkin
{
    Default,
    NightShadow,
    // Value 2 belonged to the archived appearance; keep later wire IDs stable.
    Verdict = 3,
    // Stable optional-pack identity only. Registration and artwork are external;
    // knowing an ID does not make an appearance installed or usable.
    HajiCitizen
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
        return !double.IsFinite(value) || value <= 0 ? InheritDefaultSeconds : NormalizeOverrideSeconds(value);
    }

    public static double NormalizeOverrideSeconds(double value)
    {
        return double.IsFinite(value) ? Math.Clamp(value, MinOverrideSeconds, MaxOverrideSeconds) : MinOverrideSeconds;
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
    // Value 6 belonged to the archived appearance.
    VerdictProtocol = 7
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

    public static OverlayStartupTransitionContext ForLanguage(string? language)
    {
        if (language is not null &&
            (language.StartsWith("zh-Hant", StringComparison.OrdinalIgnoreCase) ||
             language.Equals("zh-TW", StringComparison.OrdinalIgnoreCase) ||
             language.Equals("zh-HK", StringComparison.OrdinalIgnoreCase)))
        {
            return new OverlayStartupTransitionContext(
                StatusSteps:
                [
                    new("遊戲視窗", "StarCitizen.exe", "掃描", "已找到"),
                    new("遊戲日誌通道", "Game.log", "等待", "已同步"),
                    new("遊戲身份", "本機身份", "待命", "已綁定"),
                    new("艦隊中繼", "api.scstarbridge.com", "待命", "已就緒"),
                    new("浮層模組", "公告 / 艦隊總覽 / 成員 / 事件", "等待", "就緒"),
                    new("滑鼠穿透", "透明輸入層", "安全", "已啟用"),
                    new("浮層介面", "控制層", "掛載", "已上線")
                ],
                TerminalLines:
                [
                    "> 掛載星海艦橋浮層介面",
                    "> 尋找目前遊戲視窗",
                    "> 從 Game.log 綁定本機身份",
                    "> 同步艦隊中繼通道",
                    "> 啟用滑鼠穿透層",
                    "> 校準戰術浮層模組",
                    "> 控制介面已上線"
                ],
                HeaderTargetLabel: "本機遊戲視窗 // 鎖定",
                SurfaceTitle: "星海艦橋控制介面",
                MountingStateLabel: "正在掛載",
                CheckingStateLabel: "系統檢查",
                OnlineStateLabel: "浮層在線",
                BootStateLabel: "啟動",
                BottomLeftDiagnostic: "系統接管 / 網格鎖定",
                BottomRightDiagnostic: "診斷匯流排 0217 / 不攔截輸入",
                CompletionLabel: "浮層已接入",
                CompletionSubLabel: "艦橋鏈路已建立");
        }

        if (language is not null && language.StartsWith("zh", StringComparison.OrdinalIgnoreCase))
        {
            return new OverlayStartupTransitionContext(
                StatusSteps:
                [
                    new("游戏窗口", "StarCitizen.exe", "扫描", "已找到"),
                    new("游戏日志通道", "Game.log", "等待", "已同步"),
                    new("游戏身份", "本机身份", "待命", "已绑定"),
                    new("舰队中继", "api.scstarbridge.com", "待命", "已就绪"),
                    new("浮层模块", "公告 / 舰队总览 / 成员 / 事件", "等待", "就绪"),
                    new("鼠标穿透", "透明输入层", "安全", "已启用"),
                    new("浮层界面", "控制层", "装载", "已上线")
                ],
                TerminalLines:
                [
                    "> 装载星海舰桥浮层界面",
                    "> 查找当前游戏窗口",
                    "> 从 Game.log 绑定本机身份",
                    "> 同步舰队中继通道",
                    "> 启用鼠标穿透层",
                    "> 校准战术浮层模块",
                    "> 控制界面已上线"
                ],
                HeaderTargetLabel: "本机游戏窗口 // 锁定",
                SurfaceTitle: "星海舰桥控制界面",
                MountingStateLabel: "正在装载",
                CheckingStateLabel: "系统检查",
                OnlineStateLabel: "浮层在线",
                BootStateLabel: "启动",
                BottomLeftDiagnostic: "系统接管 / 网格锁定",
                BottomRightDiagnostic: "诊断总线 0217 / 不拦截输入",
                CompletionLabel: "浮层已接入",
                CompletionSubLabel: "舰桥链路已建立");
        }

        return Default;
    }
}
