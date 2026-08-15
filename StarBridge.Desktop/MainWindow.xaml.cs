using Microsoft.Win32;
using StarBridge.Core.Events;
using StarBridge.Core.FleetChat;
using StarBridge.Core.Fleets;
using StarBridge.Core.LogWatching;
using StarBridge.Core.Parsing;
using StarBridge.Core.Presence;
using StarBridge.Core.Profiles;
using StarBridge.Core.State;
using StarBridge.Core.TrustSafety;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.Diagnostics.CodeAnalysis;
using System.Globalization;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Json;
using System.Reflection;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.RegularExpressions;
using System.Threading;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Data;
using System.Windows.Input;
using System.Windows.Interop;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using System.Windows.Threading;
using Brushes = System.Windows.Media.Brushes;
using Color = System.Windows.Media.Color;
using Cursors = System.Windows.Input.Cursors;
using HorizontalAlignment = System.Windows.HorizontalAlignment;
using OpenFileDialog = Microsoft.Win32.OpenFileDialog;
using SaveFileDialog = Microsoft.Win32.SaveFileDialog;
using WinForms = System.Windows.Forms;
using DrawingColor = System.Drawing.Color;
using ControlsImage = System.Windows.Controls.Image;
using ControlsOrientation = System.Windows.Controls.Orientation;
using MediaFontFamily = System.Windows.Media.FontFamily;

namespace StarBridge.Desktop;

public partial class MainWindow : Window, IAppUpdateUi
{
    private const bool UseBridgeShell = true;
    private static bool IsBridgeShellEnabled => UseBridgeShell;

    private sealed record OverlayPresetEntry(string Id, string Name);

    private sealed record OverlayPresetManifest(List<OverlayPresetEntry> Presets);

    private sealed record OverlayPresetPackage(int Version, string Name, string Settings, string Layout);

    private const int OverlayHotkeyId = 0x5343;
    private const int WmHotkey = 0x0312;
    private const int WmGameCompatibleHotkey = 0x8053;
    private const int InformationOverlayHotkeyCommand = 0;
    private const int InGameMenuHotkeyCommand = 1;
    private const int WmGetMinMaxInfo = 0x0024;
    private const int MonitorDefaultToNearest = 0x00000002;
    private const int ShowWindowRestore = 9;
    private const int OverlayGameFocusWithoutTransitionDelayMs = 120;
    private const int OverlaySlowOperationThresholdMs = 80;
    private const uint ModNoRepeat = 0x4000;
    private const string OverlayPresetDefault = "preset1";
    private const string OverlayPresetCombat = "combat";
    private const string OverlayPresetCompact = "compact";
    private const string OverlayPresetCommand = "command";
    private const string OverlayPresetCustom = "custom";
    private const int OverlayEditorHistoryLimit = 50;
    private const double OverlayEditorSmartSnapThreshold = 12;
    private static readonly JsonSerializerOptions OverlayPresetJsonOptions = new()
    {
        WriteIndented = true
    };
    private const double OverlayEditorModuleSnapThreshold = 24;
    private const double OverlayEditorVerticalModuleSnapThreshold = 32;
    private const string OverlayEditorAlignmentGuideTag = "__overlay_editor_alignment_guide";
    private const string OverlayMemberPreviewRowTag = "__overlay_member_preview_row";
    private const double OverlayMemberColumnSplitHandleWidth = 7;
    private const string DefaultRelayUrl = "https://api.scstarbridge.com";
    private const string LocalSystemAssetsRelativeDirectory = "assets/systems";
    private static readonly OverlayEventNotificationTypes[] OverlayEventDurationOrder =
    [
        OverlayEventNotificationTypes.MemberPresence,
        OverlayEventNotificationTypes.MemberServer,
        OverlayEventNotificationTypes.SameServer,
        OverlayEventNotificationTypes.ShipChange,
        OverlayEventNotificationTypes.LocationChange,
        OverlayEventNotificationTypes.OnlineSummary,
        OverlayEventNotificationTypes.PrimaryServer,
        OverlayEventNotificationTypes.DeathAndRespawn,
        OverlayEventNotificationTypes.LocalPlayReminder
    ];
    private const string UnofficialProductDisclaimer =
        "StarBridge 是玩家社区工具，非 CIG、RSI、Star Citizen 或 Squadron 42 官方产品。相关名称、图像与素材归其权利方所有。";
    private const int FleetSyncImageMaxBytes = 512 * 1024;
    private const int FleetBannerSyncImageMaxBytes = 2 * 1024 * 1024;
    private const int InitialGameLogReplayMaxBytes = 2 * 1024 * 1024;
    private const int InitialGameLogReplayMaxLines = 1500;
    private const int QuantumContextReplayMaxBytes = 16 * 1024 * 1024;
    private const int QuantumContextReplayMaxLines = 30000;
    private static readonly TimeSpan LocalSquadEditProtectionWindow = TimeSpan.FromSeconds(45);
    private static readonly TimeSpan NetworkRealtimePullInterval = TimeSpan.FromSeconds(3);
    private static readonly TimeSpan NetworkRealtimePushDebounce = TimeSpan.FromMilliseconds(650);
    private static readonly TimeSpan NetworkRealtimePushMinimumInterval = TimeSpan.FromSeconds(2);
    private static readonly Regex JoinPuShardRegex = new(
        @"<Join PU>.*?\bshard\[(?<shard>[^\]]+)\]",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex UpdateShardIdRegex = new(
        @"<Update Shard Id>\s+New Shard Id:\s*(?<shard>[A-Z0-9_-]+)",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex GenericGameServerShardRegex = new(
        @"\b(?:shard|server|hub)\b.*?\b(?<shard>pub_[A-Z0-9_-]+)\b|\b(?<shard>pub_[A-Z0-9_-]+)\b.*?\b(?:shard|server|hub)\b",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex GameServerDisconnectRegex = new(
        @"<Channel(?: Process)? (?:Disconnection|Disconnected)>(?=[^\r\n]*gamerules=""SC_Default"")(?=[^\r\n]*(?:reason=""[^""]*(?:Player requested disconnect|Remote Disconnect)[^""]*""|cause=30016))",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex GameServerReturnedToFrontendRegex = new(
        @"<Change Server End>.*?IsPersistedInGameMode\[0\]",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly Regex EmailAddressRegex = new(
        @"(?<![\w.+*-])(?<local>[A-Z0-9._%+\-*]{1,64})@(?<domain>[A-Z0-9.-]+\.[A-Z]{2,})",
        RegexOptions.Compiled | RegexOptions.IgnoreCase | RegexOptions.CultureInvariant);
    private static readonly (string Id, string Name, string ChineseName, string FileName)[] AllowedFleetSystemAssets =
    [
        ("stanton", "Stanton", "斯坦顿", "stanton.png"),
        ("pyro", "Pyro", "派罗", "pyro.png"),
        ("nyx", "Nyx", "尼克斯", "nyx.png")
    ];
    private const int MaxManageFleetTags = 5;

    private static readonly ManageFleetTagCategoryDefinition[] FleetTagCategoryDefinitions =
    [
        new("core", "玩法主轴", "#38B8F2", "舰队最核心的活动方向。"),
        new("combat", "战斗类型", "#E08A92", "舰队偏好的武装行动与战术类型。"),
        new("industry", "工业与资源", "#D6B56A", "采集、维修、补给与资源生产相关玩法。"),
        new("trade", "运输与贸易", "#8FBDEB", "货运、贸易、走私和物流组织方式。"),
        new("exploration", "探索与情报", "#75C9D6", "侦察、探索、情报和路线发现。"),
        new("support", "支援与医疗", "#7EDBA0", "医疗、救援、补给和战场支援。"),
        new("scale", "行动规模", "#A7B9C8", "舰队活动的常见人数和节奏。"),
        new("style", "组织风格", "#C99CFF", "成员协作、纪律和社群氛围。"),
        new("ship", "舰船偏好", "#9DAAB3", "舰队常用舰种和载具倾向。")
    ];

    private static readonly ManageFleetTagDefinition[] FleetTagDefinitions =
    [
        new("core_combat", "战斗", "core", "以武装行动、火力对抗和战术执行为核心。"),
        new("core_industry", "工业", "core", "以采集、制造、维修和资源产出为核心。"),
        new("core_exploration", "探索", "core", "以侦察、远航、地点发现和情报收集为核心。"),
        new("core_commerce", "商业", "core", "以交易、经营、市场和收益为核心。"),
        new("core_logistics", "后勤", "core", "以运输、补给、保障和舰队支援为核心。"),
        new("core_social", "社交", "core", "以休闲开黑、社区活动和成员交流为核心。"),

        new("combat_pvp", "PVP", "combat", "面向玩家对抗的行动。"),
        new("combat_pve", "PVE", "combat", "面向环境任务和非玩家目标的行动。"),
        new("combat_fps", "FPS", "combat", "以步兵、室内和地面人员战斗为主。"),
        new("combat_dogfight", "狗斗", "combat", "以小型舰机动空战为主。"),
        new("combat_air", "空战", "combat", "以舰船空中或太空战斗为主。"),
        new("combat_ground", "地面战斗", "combat", "以地面载具、据点和地面火力为主。"),
        new("combat_boarding", "登船作战", "combat", "以登船、清舱、夺控和船内交战为主。"),
        new("combat_escort", "护航", "combat", "保护运输舰、工业船、目标船或任务对象。"),
        new("combat_interdiction", "拦截", "combat", "拦截目标、封控航线或阻止敌方撤离。"),
        new("combat_bounty", "赏金", "combat", "以赏金目标追踪和击杀为主。"),
        new("combat_security", "安保", "combat", "巡逻、护卫、区域安全和防御行动。"),
        new("combat_piracy", "海盗", "combat", "偏非法或灰色地带的掠夺玩法。"),
        new("combat_privateering", "私掠", "combat", "带组织目标的武装掠夺或半合法行动。"),
        new("combat_mercenary", "佣兵", "combat", "接取战斗委托或作为外包武装力量行动。"),
        new("combat_anti_piracy", "反海盗", "combat", "打击海盗、护卫商队和保护民用目标。"),

        new("industry_mining", "采矿", "industry", "矿物采集、矿船协作和矿区行动。"),
        new("industry_salvage", "打捞", "industry", "残骸回收、材料回收和清场行动。"),
        new("industry_manufacturing", "制造", "industry", "面向生产、加工和制造链路的组织活动。"),
        new("industry_repair", "维修", "industry", "为舰船、载具或行动单位提供维修支持。"),
        new("industry_resupply", "补给", "industry", "提供燃料、弹药、装备或行动物资。"),
        new("industry_engineering", "工程", "industry", "偏工程维护、系统支持和舰队技术保障。"),
        new("industry_gathering", "资源采集", "industry", "泛资源采集玩法，不限定单一职业。"),
        new("industry_wikelo", "维克洛", "industry", "以物换物、交换资源或非货币交易玩法。"),

        new("trade_cargo", "货运", "trade", "货物运输、仓储和物流线路。"),
        new("trade_trading", "贸易", "trade", "购买、出售、倒卖和市场收益玩法。"),
        new("trade_smuggling", "走私", "trade", "高风险或非法货物运输。"),
        new("trade_courier", "快递", "trade", "小型运输、短线投递和快速交付。"),
        new("trade_bulk_transport", "大宗运输", "trade", "大规模货物调度和多船运输。"),
        new("trade_personnel", "人员运输", "trade", "运送成员、乘客或任务人员。"),
        new("trade_merchant_fleet", "商队", "trade", "长线贸易或多船商业行动。"),
        new("trade_logistics", "物流", "trade", "物资、船只、人员和装备流转。"),

        new("exploration_deep_space", "深空探索", "exploration", "远距离探索、长线航行和未知区域活动。"),
        new("exploration_scouting", "侦察", "exploration", "前出观察、目标确认和路线探测。"),
        new("exploration_intel", "情报", "exploration", "收集、整理和共享行动信息。"),
        new("exploration_route", "路线勘测", "exploration", "记录航线、跳点、风险点和补给路线。"),
        new("exploration_location", "地点发现", "exploration", "寻找地点、据点、资源点或特殊目标。"),
        new("exploration_beacon", "信标响应", "exploration", "响应求救、任务信标或临时事件。"),
        new("exploration_expedition", "远征", "exploration", "长时间、多目标的探索行动。"),
        new("exploration_infiltration", "渗透侦察", "exploration", "隐蔽进入、观察和情报回传。"),
        new("exploration_data", "数据收集", "exploration", "记录服务器、位置、舰船、目标或行动数据。"),

        new("support_medical", "医疗", "support", "治疗、复活、医疗船和战场救护。"),
        new("support_rescue", "救援", "support", "救人、救船、救场和紧急响应。"),
        new("support_search_rescue", "搜救", "support", "搜索失联成员、事故地点或目标对象。"),
        new("support_refuel", "加油", "support", "提供燃料支援和续航保障。"),
        new("support_towing", "牵引", "support", "拖船、移动受损舰船或处理残骸位置。"),
        new("support_rear", "后勤支援", "support", "行动后方保障、补给和人员协调。"),
        new("support_battlefield", "战场支援", "support", "在战斗中提供治疗、维修、补给或辅助。"),
        new("support_emergency", "应急响应", "support", "快速处理突发状况和高优先级求助。"),

        new("scale_solo_friendly", "单人友好", "scale", "单人玩家也能参与，不强制编队。"),
        new("scale_squad_ops", "小队行动", "scale", "以少量成员协同为主。"),
        new("scale_medium_fleet", "中型舰队", "scale", "多小队或多职责配合的行动规模。"),
        new("scale_large_fleet", "大型舰队", "scale", "大规模成员、舰船和指挥协作。"),
        new("scale_regular", "定期活动", "scale", "有固定或较稳定的活动安排。"),
        new("scale_long", "长线行动", "scale", "持续时间较长或跨阶段推进。"),
        new("scale_quick", "快速任务", "scale", "短时间完成，适合临时参与。"),
        new("scale_weekend", "周末活动", "scale", "主要集中在周末组织。"),

        new("style_casual", "休闲", "style", "轻松开黑，不强调高压纪律。"),
        new("style_hardcore", "硬核", "style", "高投入、高执行要求和高协作密度。"),
        new("style_beginner", "新手友好", "style", "欢迎新玩家，并提供基础帮助。"),
        new("style_training", "教学", "style", "以带新、训练和机制讲解为重点。"),
        new("style_disciplined", "组织严谨", "style", "有明确纪律、流程和行动规范。"),
        new("style_milsim", "军事模拟", "style", "偏拟真指挥、编制和战术执行。"),
        new("style_roleplay", "角色扮演", "style", "重视角色设定、叙事和沉浸式互动。"),
        new("style_freeform", "自由活动", "style", "成员可自由安排，不强制参与。"),
        new("style_command", "指挥体系", "style", "有明确指挥层级和调度分工。"),
        new("style_squad_autonomy", "小队自治", "style", "小队可独立决策和组织行动。"),

        new("ship_small", "小型舰", "ship", "偏好小型舰、单人船或轻型行动。"),
        new("ship_medium", "中型舰", "ship", "偏好中型多用途舰船和小队协作。"),
        new("ship_large", "大型舰", "ship", "偏好大型舰船、多岗位和多人协作。"),
        new("ship_capital", "旗舰", "ship", "拥有或围绕旗舰级舰船组织行动。"),
        new("ship_carrier", "舰载机", "ship", "使用舰载机、机库和母舰协同玩法。"),
        new("ship_multiship", "多船协同", "ship", "多舰种、多职责协同执行。"),
        new("ship_ground_vehicle", "地面载具", "ship", "地面车辆、登陆和地面支援参与较多。"),
        new("ship_heavy_firepower", "重型火力", "ship", "偏重火力舰船、炮艇或大型火力平台。"),
        new("ship_specialist", "专业船队", "ship", "按职业船、工业船或专门舰种编组。")
    ];

    private enum FleetShipSortColumn
    {
        Spec,
        Name,
        Status,
        Price,
        Owner,
        Role
    }

    private enum FleetShipRoleCategory
    {
        Combat,
        Transport,
        Industrial,
        Exploration,
        Support,
        Utility
    }

    private sealed record FleetShipRoleVisual(
        FleetShipRoleCategory Category,
        string Key,
        string DisplayName,
        string ColorHex,
        string DispatchDescription);

    private sealed record FleetShipSpecVisual(
        string Spec,
        string DisplayName,
        string ColorHex);

    private static readonly FleetShipSpecVisual[] FleetShipSpecVisuals =
    [
        new("旗舰级", "旗舰级", FleetShipSpecPalette.Capital),
        new("大型", "大型", FleetShipSpecPalette.Large),
        new("中型", "中型", FleetShipSpecPalette.Medium),
        new("小型", "小型", FleetShipSpecPalette.Small)
    ];

    private static readonly FleetShipRoleVisual[] FleetShipRoleVisuals =
    [
        new(FleetShipRoleCategory.Combat, "Combat", "战斗", "#E08A92", "战斗、护卫、拦截、巡逻"),
        new(FleetShipRoleCategory.Transport, "Transport", "运输", "#8FBDEB", "运输、货运、贸易"),
        new(FleetShipRoleCategory.Industrial, "Industrial", "工业", "#D6B56A", "采矿、打捞、工业"),
        new(FleetShipRoleCategory.Exploration, "Exploration", "探索", "#75C9D6", "探索、侦察、扫描"),
        new(FleetShipRoleCategory.Support, "Support", "支援", "#7EDBA0", "医疗、救援、维修、补给"),
        new(FleetShipRoleCategory.Utility, "Utility", "其他", "#9DAAB3", "通用、多用途、未归类")
    ];

    private static FleetShipRoleVisual GetFleetShipRoleVisual(FleetShipRoleCategory category) =>
        FleetShipRoleVisuals.First(item => item.Category == category);

    private enum FleetRightSidebarMode
    {
        Commander,
        Member
    }

    private enum MembersPanelMode
    {
        Member,
        Admin
    }

    private enum PersonalSection
    {
        Profile,
        AppSettings,
        DataSync,
        Notifications
    }

    private enum PersonalDashboardSection
    {
        Identity,
        AppSettings,
        SyncPrivacy,
        Hangar,
        Notifications,
        SecurityFeedback
    }

    private sealed record FleetInstantTaskResponseStats(
        int ConfirmedCount,
        int ReadyCount,
        int UnableCount,
        int RespondedCount)
    {
        public static FleetInstantTaskResponseStats Empty { get; } = new(0, 0, 0, 0);
    }

    private sealed record ManageFleetTagCategoryDefinition(
        string Id,
        string Name,
        string AccentHex,
        string Description);

    private sealed record ManageFleetTagDefinition(
        string Id,
        string Name,
        string CategoryId,
        string Description);

    private sealed record FleetActivityWindowDraft(
        string[] Days,
        string StartTime,
        string EndTime,
        bool EndsNextDay = false);

    private sealed record GameServerLogSnapshot(
        string? Shard,
        bool IsLoggedOut,
        int MatchedLines);

    private sealed record GameServerLogRefreshResult(
        bool Found,
        bool Changed,
        bool Cleared,
        string Region,
        string Shard,
        string Message);

    private sealed record SyncChoiceResult(
        bool SyncEnabled,
        bool SyncOnlineStatus,
        bool SyncShipStatus,
        bool SyncLocationStatus,
        bool SyncServerInfo,
        bool PersonalHangarVisible,
        SyncPrivacyVisibilityScope VisibilityScope);

    private sealed class ManageFleetTagOptionRow
    {
        public ManageFleetTagOptionRow(
            ManageFleetTagDefinition tag,
            ManageFleetTagCategoryDefinition category)
        {
            Id = tag.Id;
            Name = tag.Name;
            CategoryId = tag.CategoryId;
            CategoryName = category.Name;
            Description = tag.Description;
            AccentHex = category.AccentHex;
            AccentBrush = BrushFromHex(category.AccentHex);
            BorderBrush = BrushFromHex(category.AccentHex, 0.68);
            BackgroundBrush = BrushFromHex(category.AccentHex, 0.14);
        }

        public string Id { get; }
        public string Name { get; }
        public string CategoryId { get; }
        public string CategoryName { get; }
        public string Description { get; }
        public string AccentHex { get; }
        public System.Windows.Media.Brush AccentBrush { get; }
        public System.Windows.Media.Brush BorderBrush { get; }
        public System.Windows.Media.Brush BackgroundBrush { get; }
        public string TooltipText => $"{CategoryName} / {Name}\n{Description}";
    }

    private sealed record PersonalHangarDistributionRow(
        string Name,
        string CountText,
        System.Windows.Media.Brush Brush);

    private sealed record PersonalHangarPreviewRow(
        string Name,
        string EnglishName,
        string Type,
        string Value,
        string Status,
        string ImportedAt,
        string SyncedAt,
        System.Windows.Media.Brush TypeBrush,
        System.Windows.Media.Brush ValueBrush,
        System.Windows.Media.Brush StatusBrush);

    private static readonly IReadOnlyDictionary<string, string> FleetShipManufacturerDisplayNames =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["AEGS"] = "AEGIS",
            ["AGES"] = "AEGIS",
            ["ANVL"] = "ANVIL",
            ["ARGO"] = "ARGO",
            ["BANU"] = "BANU",
            ["CNOU"] = "CONSOLIDATED OUTLAND",
            ["CRUS"] = "CRUSADER",
            ["DRAK"] = "DRAKE",
            ["ESPR"] = "ESPERIA",
            ["GAMA"] = "GATAC",
            ["GLSN"] = "GREY'S MARKET",
            ["GRIN"] = "GREYCAT",
            ["KRIG"] = "KRUGER",
            ["MISC"] = "MISC",
            ["MRAI"] = "MIRAI",
            ["ORIG"] = "ORIGIN",
            ["RSI"] = "RSI",
            ["TMBL"] = "TUMBRIL",
            ["VNCL"] = "VANDUUL",
            ["XIAN"] = "XI'AN",
            ["XNAA"] = "AOPOA"
        };

    private readonly RegexLogEventParser _parser = new();
    private readonly FleetState _fleetState = new();
    private DateTimeOffset? _fleetStateCachedAtUtc;
    private readonly StartupDataGateController _startupDataGate = new();
    private CancellationTokenSource? _startupDataSyncCts;
    private readonly QuantumTravelContextTracker _quantumTravelContext = new();
    private readonly ObservableCollection<PlayerRow> _players = [];
    private readonly ObservableCollection<SpecifiedVisibilityMemberRow> _specifiedVisibilityMembers = [];
    private readonly ObservableCollection<PrivateVisibilityGroupRow> _privateVisibilityGroups = [];
    private readonly ObservableCollection<NetworkFleetCard> _networkFleets = [];
    private readonly List<NetworkFleetCard> _allNetworkFleets = [];
    private bool _isFleetBannerDirectoryBackfillInProgress;
    private readonly ObservableCollection<OwnedShipRecord> _ownedShips = [];
    private readonly ObservableCollection<PersonalHangarDistributionRow> _personalHangarDistributionRows = [];
    private readonly ObservableCollection<PersonalHangarPreviewRow> _personalHangarPreviewRows = [];
    private readonly ObservableCollection<FleetShipInventoryRow> _fleetShipInventory = [];
    private readonly ObservableCollection<FleetShipInventoryRow> _fleetShipDatabaseRows = [];
    private string? _fleetShipSidebarSnapshot;
    private readonly Dictionary<string, DateTimeOffset> _localFleetShipSharedAtCache = new(StringComparer.OrdinalIgnoreCase);
    private FleetShipSortColumn _fleetShipSortColumn = FleetShipSortColumn.Spec;
    private bool _fleetShipSortDescending = true;
    private string _fleetShipDatabaseFilter = "全部";
    private string _fleetShipDatabaseSearch = "";
    private readonly ObservableCollection<FleetTaskHistoryRow> _fleetTaskHistory = [];
    private readonly ObservableCollection<FleetActionPlanRow> _fleetActionPlans = [];
    private string _commandDeckActionPlanDetailId = "";
    private readonly ObservableCollection<FleetEventLogRow> _fleetEventLogs = [];
    private readonly ObservableCollection<FleetEventLogRow> _fleetEventTimelineRows = [];
    private readonly ObservableCollection<FleetEventActionPlanRow> _fleetEventActionPlanRows = [];
    private readonly ObservableCollection<FleetNotificationCenterItemRow> _fleetNotificationCenterItems = [];
    private readonly ObservableCollection<FleetNotificationCenterItemRow> _fleetMemberTimelineItems = [];
    private readonly ObservableCollection<FleetRoleGroupRow> _fleetSystemRoleGroups = [];
    private readonly ObservableCollection<FleetRoleGroupRow> _fleetCustomRoleGroups = [];
    private readonly ObservableCollection<FleetPermissionGroupRow> _fleetSelectedRolePermissionGroups = [];
    private readonly Dictionary<string, LocalFleetRoleGroup> _fleetRoleGroupDefinitions = new(StringComparer.OrdinalIgnoreCase);
    private readonly ObservableCollection<FleetMemberManagementRow> _fleetMemberRows = [];
    private readonly ObservableCollection<FleetApplicationRow> _fleetApplications = [];
    private readonly ObservableCollection<FleetInviteRow> _fleetInviteRows = [];
    private readonly ObservableCollection<ManageFleetSystemOptionRow> _manageFleetSystemOptions = [];
    private readonly ObservableCollection<FleetTimeZoneOptionRow> _fleetTimeZoneOptions = [];
    private readonly ObservableCollection<FleetExternalContactRow> _fleetExternalContacts = [];
    private readonly ObservableCollection<ManageFleetTagOptionRow> _createFleetSelectedTags = [];
    private readonly ObservableCollection<ManageFleetTagOptionRow> _manageProfileSelectedTags = [];
    private readonly ObservableCollection<ManageFleetTagOptionRow> _findFleetFilterSelectedTags = [];
    private readonly ObservableCollection<string> _findFleetAppliedFilterLabels = [];
    private readonly ObservableCollection<ManageFleetTagOptionRow> _manageTagDraftPreviewRows = [];
    public ObservableCollection<string> FleetRoleSelectionOptions { get; } = [];
    private FleetRoleGroupRow? _selectedFleetRoleGroup;
    private string? _fleetRoleGroupNameEditSnapshot;
    private bool _isClosingFleetRoleGroupNameEditor;
    private bool _isFleetRoleGroupsDirty;
    private bool _isSavingFleetRoleGroupsDraft;
    private string? _fleetRoleGroupsDraftBaselineJson;
    private readonly HashSet<string> _manageProfileSelectedTagIds = new(StringComparer.OrdinalIgnoreCase)
    {
        "combat_pvp",
        "core_industry",
        "core_exploration",
        "style_disciplined"
    };
    private readonly HashSet<string> _createFleetSelectedTagIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _findFleetFilterTagIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _manageTagDraftIds = new(StringComparer.OrdinalIgnoreCase);
    private bool _isCreateFleetTagSelectorMode;
    private bool _isFindFleetTagFilterSelectorMode;
    private readonly List<FleetEventLogRow> _allFleetEventLogs = [];
    private NetworkFleetApplicationSnapshot[] _fleetApplicationSnapshots = [];
    private NetworkFleetInviteSnapshot[] _fleetInviteSnapshots = [];
    private NetworkFleetInviteSnapshot? _currentFleetInviteDialogInvite;
    private NetworkFleetCard? _selectedFindFleetCard;
    private readonly FleetDirectoryState _fleetDirectoryState = new();
    private FleetInvitePreviewResponse? _findFleetInvitePreview;
    private string _findFleetInviteCode = "";
    private readonly Dictionary<string, LocalFleetMemberPermission> _fleetMemberPermissions = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, NetworkPlayerSnapshot> _networkSnapshots = new(StringComparer.OrdinalIgnoreCase);
    private DateTimeOffset _localFleetLogoEditTime;
    private DateTimeOffset _localFleetBannerEditTime;
    private DateTimeOffset _fleetJoinedAtUtc = DateTimeOffset.MinValue;
    private readonly HashSet<string> _joinedActionPlanIds = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _pendingFleetApplicationCodes = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _findFleetJoinInProgressCodes = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _acknowledgedFleetOrderKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, string> _fleetInstantTaskResponses = new(StringComparer.OrdinalIgnoreCase);
    private MembersPanelMode _membersPanelMode = MembersPanelMode.Admin;
    private bool _isPersonalRightSidebarCompact;
    private bool _isClosingPersonalDisplayNameEditor;
    private const double PersonalConsoleActivityItemHeight = 30;
    private const double PersonalConsoleActivityItemGap = 7;
    private const int PersonalConsoleActivityMinItems = 2;
    private const int PersonalConsoleActivityMaxItems = 5;
    private readonly GridViewColumn PlayerNameColumn = new();
    private readonly GridViewColumn PlayerStatusColumn = new();
    private readonly GridViewColumn PlayerShipColumn = new();
    private readonly GridViewColumn PlayerLocationColumn = new();
    private readonly List<OverlayLayoutItem> _overlayLayout = [];
    private readonly List<OverlayEditorHistoryState> _overlayEditorUndoHistory = [];
    private readonly List<OverlayEditorHistoryState> _overlayEditorRedoHistory = [];
    private readonly DispatcherTimer _gameProcessTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private readonly DispatcherTimer _networkSyncTimer = new() { Interval = TimeSpan.FromSeconds(15) };
    private readonly DispatcherTimer _presenceHeartbeatTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly DispatcherTimer _networkPlayerRealtimePullTimer = new() { Interval = NetworkRealtimePullInterval };
    private readonly DispatcherTimer _networkRealtimePushTimer = new() { Interval = NetworkRealtimePushDebounce };
    private readonly DispatcherTimer _profileSyncDebounceTimer = new() { Interval = TimeSpan.FromMilliseconds(800) };
    private readonly DispatcherTimer _fleetClockTimer = new() { Interval = TimeSpan.FromSeconds(1) };
    private readonly DispatcherTimer _relayLatencyTimer = new() { Interval = TimeSpan.FromSeconds(20) };
    private readonly DispatcherTimer _appStatsTimer = new() { Interval = TimeSpan.FromSeconds(30) };
    private readonly DispatcherTimer _temporaryEntitlementTimer = new();
    private readonly DispatcherTimer _entitlementRefreshTimer = new() { Interval = TimeSpan.FromSeconds(5) };
    private readonly HttpClient _networkClient = new() { Timeout = TimeSpan.FromSeconds(15) };
    private readonly FleetDirectoryCache _fleetDirectoryCache = new();
    private readonly StarBridgeRelayClient _relayClient;
    private readonly AppUpdateService _appUpdateService;
    private GameLogWatcher? _watcher;
    private string? _logPath;
    private DateTimeOffset _lastGameLogReadAt = DateTimeOffset.MinValue;
    private string? _localPlayer;
    private string? _localPlayerId;
    private string? _accountName;
    private string? _authToken;
    private string? _accountId;
    private readonly AccountSessionCoordinator _accountSessionCoordinator = new();
    private bool _isAccountTransition;
    private bool _authenticationExpired;
    private string? _lastAnimatedHeaderConnectionStatus;
    private string? _lastNetworkPlayerSnapshotFingerprint;
    private readonly HashSet<string> _accountEntitlements = new(StringComparer.OrdinalIgnoreCase);
    private readonly Dictionary<string, DateTimeOffset> _temporaryEntitlements = new(StringComparer.OrdinalIgnoreCase);
    private readonly Queue<OverlayAppearanceUnlockNotice> _pendingOverlayAppearanceUnlockNotices = new();
    private readonly HashSet<string> _queuedOverlayAppearanceUnlockKeys = new(StringComparer.OrdinalIgnoreCase);
    private readonly HashSet<string> _acknowledgedEntitlementNotices = DesktopAppConfig.LoadAcknowledgedEntitlementNotices();
    private ApplicationBehaviorSettings _applicationBehaviorSettings = ApplicationBehaviorSettings.Default;
    private bool _isApplyingApplicationBehaviorSettings;
    private readonly GameplayStatisticsRecorder _gameplayStatisticsRecorder = new();
    private readonly LocalPlaySessionReminder _localPlaySessionReminder = new();
    private LocalPlayReminderSettings _localPlayReminderSettings = LocalPlayReminderSettings.Default;
    private bool _isApplyingLocalPlayReminderSettings;
    private int _lastLocalPlayReminderCopyIndex = -1;
    private bool _isApplyingGameplayStatisticsConsent;
    private bool _isGameplayStatisticsSyncing;
    private bool _gameplayStatisticsPrivacySyncPending;
    private string? _gameplayStatisticsSyncError;
    private DateTimeOffset _lastGameplayStatisticsSyncAt = DateTimeOffset.MinValue;
    private bool _gameplayConsentDialogIsInitial;
    private bool _isShowingOverlayAppearanceUnlockNotice;
    private bool _isRefreshingEntitlements;
    private OverlaySkin? _overlaySkinRequestedWhileLocked;
    private string? _avatarPath;
    private string? _cachedAvatarImagePath;
    private DateTime _cachedAvatarImageWriteTimeUtc;
    private string? _cachedAvatarImageData;
    private string? _fleetLogoPath;
    private string? _fleetBannerPath;
    private string? _fleetBannerSourcePath;
    private const double FleetBannerStandardCropRatio = 12.0;
    private const double FleetBannerPickerMinCropScale = 0.35;
    private const double FleetBannerPickerMinCropWidth = 320.0;
    private const double FleetBannerPickerMinCropHeight = 28.0;
    private BitmapImage? _bannerPickerSourceImage;
    private BitmapSource? _bannerPickerPreviewImage;
    private string? _bannerPickerSourcePath;
    private Rect _bannerPickerImageDisplayRect;
    private Rect _bannerPickerCropRect;
    private double _bannerPickerCropScale = 1.0;
    private bool _isUpdatingBannerPickerScaleControl;
    private bool _isBannerCropDragging;
    private bool _isBannerCropResizing;
    private System.Windows.Point _bannerCropDragStart;
    private Rect _bannerCropDragStartRect;
    private System.Windows.Point _bannerCropResizeStart;
    private Rect _bannerCropResizeStartRect;
    private string _bannerCropResizeHandle = "";
    private System.Windows.Media.Brush? _bannerPickerDropZoneDefaultBackground;
    private System.Windows.Media.Brush? _bannerPickerDropZoneDefaultBorder;
    private string? _createFleetLogoPath;
    private string _fleetName = "No Fleet";
    private string _fleetCode = "N/A";
    private string _fleetChiefCommander = "Unassigned";
    private string _fleetDeputyCommander = "Unassigned";
    private string _fleetDescription = "";
    private const string FleetDescriptionPublicPlaceholder = "暂无舰队介绍";
    private string _fleetType = "Combat";
    private string _fleetJoinPolicy = "Open";
    private bool _fleetRecruitingEnabled;
    private string _fleetRecruitingTarget = "所有玩家";
    private string _fleetInviteCodeCreationPolicy = FleetInvitationAccessPolicy.AllMembers;
    private string _fleetInvitationCardPolicy = FleetInvitationAccessPolicy.AllMembers;
    private const string DefaultFleetActivityStartTime = "19:00";
    private const string DefaultFleetActivityEndTime = "22:00";
    private const string DefaultFleetActiveTimeText = "19:00 - 22:00 UTC+8";
    private string _fleetActiveTime = DefaultFleetActiveTimeText;
    private const int MaxFleetActivityWindowCount = 3;
    private static readonly string[] FleetActivityTimeOptions = BuildFleetActivityTimeOptions();
    private readonly List<FleetActivityWindowDraft> _fleetActivityWindows = [];
    private FleetInfoPanelKind _selectedFleetInfoPanel = FleetInfoPanelKind.CurrentTask;
    private bool _isFleetRailCollapsed;
    private string _fleetNoticeTitle = "";
    private string _fleetNoticeContent = "";
    private DateTimeOffset? _fleetNoticePublishedAt;
    private bool _isManageProfileEditMode;
    private bool _isManageProfileRefreshing;
    private bool _isManageProfileDirty;
    private bool _isManageProfileDiscardingDraft;
    private ManageProfileSaveState _manageProfileSaveState = ManageProfileSaveState.Idle;
    private string? _manageProfileDraftBaselineStateJson;
    private bool _isUpdatingFleetActivityWindowEditor;
    private DateTimeOffset _fleetProfileSyncEchoProtectedUntilUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _fleetProfileSyncEchoConfirmedAtUtc = DateTimeOffset.MinValue;
    private long _fleetProfileRevision;
    private string _latestFleetSnapshotCode = "";
    private DateTimeOffset _latestFleetSnapshotUpdatedAtUtc = DateTimeOffset.MinValue;
    private string _latestFleetMemberPresenceFingerprint = "";
    private string? _pendingFleetProfileDescription;
    private string? _pendingFleetProfileType;
    private string? _pendingFleetProfileActiveTime;
    private string? _pendingFleetProfileJoinPolicy;
    private bool? _pendingFleetProfileRecruitingEnabled;
    private string? _pendingFleetProfileRecruitingTarget;
    private string? _pendingFleetInviteCodeCreationPolicy;
    private string? _pendingFleetInvitationCardPolicy;
    private bool? _pendingFleetProfileEmailNotificationsEnabled;
    private string? _pendingFleetProfileActivityWindowsKey;
    private string? _pendingFleetProfileActiveDaysDescription;
    private string? _pendingFleetProfileActivityCadence;
    private string? _pendingFleetProfileTimeZoneId;
    private bool? _pendingFleetPublicListingEnabled;
    private string? _pendingFleetPublicMemberScaleMode;
    private string? _pendingFleetPublicShipScaleMode;
    private bool? _pendingFleetPublicProfileEnabled;
    private bool? _pendingFleetPublicShowDescription;
    private bool? _pendingFleetPublicShowTags;
    private bool? _pendingFleetPublicShowActiveSystems;
    private bool? _pendingFleetPublicShowActivityTime;
    private bool? _pendingFleetPublicShowExternalContacts;
    private string _manageProfileDisplayShortName = "";
    private string _manageProfilePublicDisplayName = "";
    private string? _selectedFleetSystemId;
    private readonly HashSet<string> _selectedFleetSystemIds = new(StringComparer.OrdinalIgnoreCase);
    private string _fleetLanguage = "zh-CN";
    private string _fleetTimeZoneId = "China Standard Time";
    private string _fleetWebsiteUrl = "";
    private string _fleetActiveDaysDescription = "不固定";
    private string _fleetActivityCadence = "休闲";
    private string _fleetRecruitmentStatus = "开放招募";
    private bool _manageShowDescriptionPublic = true;
    private bool _manageShowAnnouncementPublic = true;
    private bool _manageAllowPublicProfileView = true;
    private const string FleetPublicMemberScaleExact = "Exact";
    private const string FleetPublicMemberScaleApprox = "Approx";
    private const string FleetPublicMemberScaleHidden = "Hidden";
    private const string FleetPublicShipScaleTypeSummary = "TypeSummary";
    private const string FleetPublicShipScaleTotalOnly = "TotalOnly";
    private const string FleetPublicShipScaleHidden = "Hidden";
    private bool _fleetPublicListingEnabled = true;
    private string _fleetPublicMemberScaleMode = FleetPublicMemberScaleExact;
    private string _fleetPublicShipScaleMode = FleetPublicShipScaleTypeSummary;
    private const int CurrentSyncConsentVersion = 1;
    private bool _fleetPublicShowTags = true;
    private bool _fleetPublicShowActiveSystems = true;
    private bool _fleetPublicShowActivityTime = true;
    private bool _fleetPublicShowExternalContacts;
    private FleetExternalContactPublicationMode _fleetExternalContactPublicationMode;
    private bool _legacyExternalContactPublicationConfirmed;
    private string _activeManageTagCategoryId = FleetTagCategoryDefinitions[0].Id;
    private string _fleetCurrentTaskTitle = "";
    private string _fleetCurrentTaskBrief = "";
    private string _fleetCurrentTaskParticipants = "";
    private string _fleetCurrentTaskRally = "";
    private string _fleetCurrentTaskShip = "";
    private const string FleetTaskMetaHeader = "任务信息:";
    private const double OverlayEditorDesignCanvasWidth = 1600;
    private const double OverlayEditorDesignCanvasHeight = 900;
    private static readonly bool FleetActionFeatureSettingsLocked = true;
    private static bool EnableFleetActionManagementUi => !FleetActionFeatureSettingsLocked;
    private bool _fleetCurrentTaskEmailCall;
    private bool _fleetEmailNotificationsEnabled = true;
    private DateTime? _fleetCurrentTaskTime;
    private string _fleetCurrentTaskHistoryKey = "";
    private int _fleetCurrentTaskNoticeRevision;
    private readonly Dictionary<string, NetworkFleetShipSnapshot> _remoteFleetShips = new(StringComparer.OrdinalIgnoreCase);
    private string _fleetActionTitle = "";
    private string _fleetActionContent = "";
    private DateTime? _fleetActionStartTime;
    private bool _fleetActionNotifyMembers;
    private string _selectedActionPlanId = "";
    private string _selectedFleetEventFocusPlanId = "";
    private string _editingActionPlanId = "";
    private bool _joinActionNotifyMe;
    private string? _callsign;
    private bool _allowEmailNotifications = true;
    private GameIdVisibilityPreference _gameIdVisibilityPreference =
        GameIdVisibilityPolicy.Normalize(null, null, null);
    private bool _isSavingGameIdVisibility;
    private bool _gameIdVisibilitySavePending;
    private SyncPrivacySettings _syncPrivacySettings = SyncPrivacySettings.Default;
    private PlayerEventSharingSettings _playerEventSharingSettings = PlayerEventSharingSettings.Default;
    private readonly DualAxisPrivacySettingsStore _dualAxisPrivacySettingsStore = new(
        DesktopAppConfig.ConfigDirectory);
    private DualAxisPrivacySettings _dualAxisPrivacySettings = DualAxisPrivacySettings.Migrate(
        SyncPrivacySettings.Default,
        PlayerEventSharingSettings.Default);
    private PrivateVisibilityGroupClient? _privateVisibilityGroupClient;
    private PrivateVisibilityGroupDirectoryLoader? _privateVisibilityGroupLoader;
    private PrivateVisibilityGroupMutationGate? _privateVisibilityGroupMutationGate;
    private bool _isApplyingDualAxisPrivacyEditor;
    private bool _isSavingDualAxisPrivacy;
    private string? _editingVisibilityGroupId;
    private string? _editingVisibilityGroupLocalReferenceId;
    private NotificationSettings _notificationSettings = NotificationSettings.Default;
    private string _gameServerRegion = "未知";
    private string _gameServerShard = "";
    private DateTimeOffset _gameServerObservedAtUtc = DateTimeOffset.MinValue;
    private IOverlayHost? _overlayWindow;
    private bool _overlayHiddenForMainWindowMinimize;
    private DispatcherTimer? _overlayGameFocusDelayTimer;
    private OverlayLayoutItem? _activeOverlayItem;
    private OverlayLayoutItem? _selectedOverlayInspectorItem;
    private bool _isOverlayEventNotificationSelected;
    private bool _isOverlayCrosshairSelected;
    private FrameworkElement? _activeOverlayEditorElement;
    private bool _isOverlayResize;
    private bool _isOverlayEditorGridVisible = true;
    private bool _isOverlayEditorEdgeSnapEnabled = true;
    private bool _isOverlayLayoutLocked;
    private bool _isOverlayEditorFullScreen;
    private bool _isOverlayEditorCompact;
    private bool _isOverlayEditorInspectorOpen;
    private OverlayEditorCompactDrawer _overlayEditorCompactDrawer;
    private bool _overlayInspectorWasOpenBeforeFullScreen;
    private bool _overlayInspectorReturnStateCaptured;
    private double _overlayInspectorReturnScrollOffset;
    private string? _overlayInspectorReturnSectionKey;
    private bool _isOverlayEditorLivePreviewEnabled;
    private bool _isOverlayFullScreenToolsOpen = true;
    private bool _isOverlayEditorLayoutDirty;
    private DateTimeOffset? _overlayEditorLastSavedAt;
    private string _savedOverlayPresetSnapshot = OverlayPresetDefault;
    private string _savedOverlaySettingsSnapshot = "";
    private string _savedOverlayLayoutSnapshot = "";
    private double _overlayEditorSnapSize;
    private double _overlayEditorNudgeStep = 1;
    private DispatcherTimer? _overlaySettingsSmoothScrollTimer;
    private double _overlaySettingsSmoothScrollTarget;
    private OverlaySkin _selectedOverlaySkin = OverlaySkin.Default;
    private string? _overlaySettingsProgrammaticTargetKey;
    private string? _overlaySettingsActiveKey;
    private bool _overlaySettingsActiveRailInitialized;
    private bool _isSyncingOverlayEditorPlacementControls;
    private bool _isSyncingOverlayInspectorAnchorControls;
    private bool _isSyncingOverlayInspectorModuleControls;
    private bool _isSyncingOverlayInspectorCrosshairControls;
    private bool _isSyncingOverlayModuleStyleControls;
    private bool _isSyncingOverlaySceneControls;
    private System.Windows.Point _overlayEditorDragStartPoint;
    private Rect _overlayEditorDragStartRect;
    private Rect? _overlayEditorLiveEditRect;
    private bool _overlayEditorRenderPendingAfterLiveEdit;
    private Transform? _overlayEditorPreviousRenderTransform;
    private CacheMode? _overlayEditorPreviousCacheMode;
    private ScaleTransform? _overlayEditorLiveScaleTransform;
    private TranslateTransform? _overlayEditorLiveTranslateTransform;
    private OverlayLayoutItem? _overlayEditorSnapTargetOwner;
    private (double Start, double Center, double End)[] _overlayEditorHorizontalSnapTargets = [];
    private (double Start, double Center, double End)[] _overlayEditorVerticalSnapTargets = [];
    private readonly List<Border> _overlayEditorAlignmentGuides = [];
    private OverlayEditorHistoryState? _overlayEditorActiveDragHistoryState;
    private bool _isRestoringOverlayEditorHistory;
    private bool _isOverlayEventNotificationDrag;
    private bool _isOverlayMemberColumnSplitDrag;
    private bool _isOverlayFullScreenToolsDragging;
    private bool _isApplyingOverlayEditorCanvasScale;
    private FrameworkElement? _activeOverlayEventNotificationPreview;
    private FrameworkElement? _activeOverlayMemberColumnSplitRow;
    private System.Windows.Point _overlayEventNotificationDragStartPoint;
    private System.Windows.Point _overlayFullScreenToolsDragStartPoint;
    private double _overlayFullScreenToolsDragStartX;
    private double _overlayFullScreenToolsDragStartY;
    private double _overlayEventNotificationDragStartY;
    private OverlayEditorFullScreenSnapshot? _overlayEditorFullScreenSnapshot;
    private OverlayDisplaySettings _overlaySettings = OverlayDisplaySettings.Default;

    private enum OverlayEditorCompactDrawer
    {
        None,
        Categories,
        Settings,
        Inspector
    }

    private sealed record OverlayEditorHistoryState(
        string Layout,
        OverlayDisplaySettings Settings,
        string? SelectedModuleKey,
        bool EventNotificationSelected,
        bool CrosshairSelected);

    private sealed record OverlayEditorFullScreenSnapshot(
        WindowState WindowState,
        ResizeMode ResizeMode,
        bool Topmost,
        Rect NormalBounds,
        double MinWidth,
        double MinHeight,
        Thickness FrameBorderThickness,
        Thickness MainContentMargin,
        Thickness OverlayEditRootMargin,
        GridLength OverlayEditorHeaderRowHeight,
        Visibility OverlayEditorHeaderVisibility,
        GridLength WindowTitleRowHeight,
        GridLength TopNavigationRowHeight,
        GridLength TopBannerReserveRowHeight,
        Visibility CustomTitleBarVisibility,
        Visibility TopFleetBannerVisibility);

    private sealed class FleetTaskBriefInfo
    {
        public string Brief { get; init; } = "";
        public string TaskType { get; init; } = "自定义";
        public string Duration { get; init; } = "待定";
        public string CombatIntensity { get; init; } = "未指定";
        public bool MedicalRequired { get; init; }
        public bool GroundCombat { get; init; }
        public string Division { get; init; } = "按现场指挥分配";
        public bool HasStructuredMeta { get; init; }
    }

    private sealed record PublishTaskShipOptionRow(
        string ShipName,
        string ShipCode,
        string ShipSpec,
        string ShipRole,
        string ShipStatus,
        string OwnerText,
        string SourceText,
        string OwnerStatusText,
        System.Windows.Media.Brush OwnerStatusBrush,
        bool IsCatalogOnly)
    {
        public string ShipMetaText => $"{ShipSpec} / {ShipStatus} / {ShipRole}";
        public string SelectionText => IsCatalogOnly
            ? $"{ShipName} / {ShipCode} / 全库目录"
            : $"{ShipName} / {ShipRole} / {OwnerText}";
    }

    private readonly ObservableCollection<PublishTaskShipOptionRow> _publishTaskShipOptions = [];

    private static readonly string[] PublishTaskLocationSuggestions =
    [
        "新巴贝奇",
        "新巴贝奇星际港",
        "新巴贝奇 Commons",
        "洛维尔",
        "奥里森",
        "Area18",
        "Port Tressler",
        "Everus Harbor",
        "Baijini Point",
        "Seraphim Station",
        "Grim HEX"
    ];
    private readonly List<OverlayPresetEntry> _overlayPresetEntries = [];
    private string _activeOverlayPreset = OverlayPresetDefault;
    private string _language = "zh";
    private bool _isGameProcessRunning;
    private PlayerPresenceKind _localPresence = PlayerPresenceKind.Offline;
    private DateTimeOffset _lastAppInteractionAtUtc = DateTimeOffset.UtcNow;
    private DateTimeOffset _lastAppInteractionSampleAtUtc = DateTimeOffset.MinValue;
    private bool _isLoadingSettings;
    private bool _isApplyingSyncPrivacyControls;
    private bool _isApplyingPlayerEventSharingControls;
    private bool _isLoginDialogOpen;
    private bool _isClosingAfterOfflineUpload;
    private bool _isNetworkSyncRunning;
    private bool _isNetworkRealtimePullRunning;
    private bool _isNetworkRealtimePushRunning;
    private bool _isPresenceHeartbeatRunning;
    private bool _isNetworkSnapshotPushRunning;
    private bool _networkRealtimePushQueued;
    private bool _pendingPrivacyOfflineClear;
    private bool _isNetworkSyncIssueRetrying;
    private bool _isRefreshingAccountPanel;
    private bool _isUpdatingSpecifiedMemberSelection;
    private bool _isRelayLatencyProbeRunning;
    private int _networkSyncFailureCount;
    private int _presenceHeartbeatFailureCount;
    private long _lastRelayLatencyMs = -1;
    private RelayServiceHealthState _relayServiceHealthState = RelayServiceHealthState.Unknown;
    private int _relayHealthConsecutiveFailures;
    private DateTimeOffset _lastSuccessfulRelayHealthAt = DateTimeOffset.MinValue;
    private DateTimeOffset _nextNetworkSyncAt = DateTimeOffset.MinValue;
    private DateTimeOffset _lastNetworkRealtimePushAt = DateTimeOffset.MinValue;
    private CancellationTokenSource? _syncStatusOverlayCts;
    private CancellationTokenSource? _relayRecoveryNoticeCts;
    private TaskCompletionSource<bool>? _appConfirmationSource;
    private TaskCompletionSource<bool>? _overlayAppearanceUnlockSource;
    private TaskCompletionSource<SyncChoiceResult?>? _syncChoiceSource;
    private TaskCompletionSource<FleetSuccessorOption?>? _fleetSuccessorSource;
    private TaskCompletionSource<bool>? _updateConfirmationSource;
    private bool _updateOverlayCanClose;
    private bool _startupUpdateCheckQueued;
    private HwndSource? _hotkeySource;
    private bool _hotkeyRegistered;
    private readonly GameCompatibleHotkeyListener _gameCompatibleHotkeyListener = new();
    private readonly OverlayHotkeyTriggerGate _overlayHotkeyTriggerGate =
        new(TimeSpan.FromMilliseconds(180));
    private readonly OverlayHotkeyTriggerGate _inGameMenuHotkeyTriggerGate =
        new(TimeSpan.FromMilliseconds(180));
    private readonly InGameMenuCoordinator _inGameMenuCoordinator = new();
    private bool _hasFleet;
    private bool _isCreatingFleet;
    private bool _fleetDirectorySyncPending;
    private DateTimeOffset _fleetMembershipChangedAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.MinValue;
    private const int FleetMembershipSyncGraceSeconds = 45;
    private const int FleetDirectoryRetrySeconds = 20;
    private string _appStatsClientId = "";
    private bool _appStatsInstallRegistered;
    private bool _isAppStatsHeartbeatRunning;
    private AppStatsSnapshot? _homeAppStats;
    private DateTimeOffset _lastAppStatsHeartbeatAtUtc = DateTimeOffset.MinValue;
    private DateTimeOffset _lastOverlayStatsSampleAtUtc = DateTimeOffset.MinValue;
    private long _pendingOverlayUsageSeconds;
    private readonly List<NetworkPlayerSharedEventSnapshot> _sharedLifeEvents = [];

    private sealed record OverlayAppearanceUnlockNotice(
        OverlaySkin Skin,
        string Entitlement,
        string AcknowledgementKey,
        bool IsPermanent,
        DateTimeOffset? ExpiresAt);

    public MainWindow()
    {
        _isLoadingSettings = true;
        InitializeComponent();
        HelpReleaseHistoryList.ItemsSource = AppReleaseHistoryCatalog.Entries;
        ConfigureBridgeShellMode();
        PromoteFindFleetDetailOverlayToWindowRoot();
        ContentRendered += MainWindow_ContentRendered;
        _inGameMenuCoordinator.ActionRequested += InGameMenuCoordinator_ActionRequested;
        _inGameMenuCoordinator.Closed += InGameMenuCoordinator_Closed;
        _inGameMenuCoordinator.FleetRefreshRequested += InGameMenuCoordinator_FleetRefreshRequested;
        _inGameMenuCoordinator.FleetCommunicationRequested += InGameMenuCoordinator_FleetCommunicationRequested;
        _inGameMenuCoordinator.FleetMemberActionRequested += InGameMenuCoordinator_FleetMemberActionRequested;
        _inGameMenuCoordinator.FleetShipImageReportRequested += InGameMenuCoordinator_FleetShipImageReportRequested;
        _inGameMenuCoordinator.SocialRefreshRequested += InGameMenuCoordinator_SocialRefreshRequested;
        _inGameMenuCoordinator.SocialConversationRequested += InGameMenuCoordinator_SocialConversationRequested;
        _inGameMenuCoordinator.SocialChannelRequested += InGameMenuCoordinator_SocialChannelRequested;
        _inGameMenuCoordinator.SocialMessageRequested += InGameMenuCoordinator_SocialMessageRequested;
        _inGameMenuCoordinator.SocialAttachmentRequested += InGameMenuCoordinator_SocialAttachmentRequested;
        _inGameMenuCoordinator.ChatAttachmentActionRequested += InGameMenuCoordinator_ChatAttachmentActionRequested;
        _inGameMenuCoordinator.FriendSearchRequested += InGameMenuCoordinator_FriendSearchRequested;
        _inGameMenuCoordinator.FriendActionRequested += InGameMenuCoordinator_FriendActionRequested;
        _inGameMenuCoordinator.FriendPresenceChanged += InGameMenuCoordinator_FriendPresenceChanged;
        _inGameMenuCoordinator.ProfileRequested += InGameMenuCoordinator_ProfileRequested;
        _inGameMenuCoordinator.RoomRefreshRequested += InGameMenuCoordinator_RoomRefreshRequested;
        _inGameMenuCoordinator.RoomJoinRequested += InGameMenuCoordinator_RoomJoinRequested;
        _inGameMenuCoordinator.RoomCreateRequested += InGameMenuCoordinator_RoomCreateRequested;
        _inGameMenuCoordinator.RoomLeaveRequested += InGameMenuCoordinator_RoomLeaveRequested;
        _inGameMenuCoordinator.RoomMessageRequested += InGameMenuCoordinator_RoomMessageRequested;
        _inGameMenuCoordinator.RoomAttachmentRequested += InGameMenuCoordinator_RoomAttachmentRequested;
        _inGameMenuCoordinator.RoomInvitationActionRequested += InGameMenuCoordinator_RoomInvitationActionRequested;
        InitializeInGameMenuPreferences();
        UiMotion.InitializeGlobalInteractions();
        InitializePlayerActivityDesktopNotifications();
        InputManager.Current.PreProcessInput += TrackAppInteraction;
        InitializePartyLobbyShell();
        InitializeFriendCenter();
        InitializeFleetChat();
        InitializeLocalGameEventJournal();
        _temporaryEntitlementTimer.Tick += TemporaryEntitlementTimer_Tick;
        _entitlementRefreshTimer.Tick += async (_, _) => await RefreshAccountEntitlementsAsync();
        _appStatsClientId = LoadOrCreateAppStatsClientId();
        InitializeLocationDataContribution();
        _relayClient = new StarBridgeRelayClient(
            _networkClient,
            () => NetworkServerUrlBox.Text,
            () => NetworkServerKeyBox.Password,
            () => _authToken,
            () => CanSynchronizeUserData);
        _personalProfileRepository = new PersonalProfileRemoteRepository(_relayClient);
        InitializeDualAxisPrivacyEditor();
        _appUpdateService = new AppUpdateService(
            _networkClient,
            BuildNetworkUri,
            this,
            text => UpdateStatusText.Text = text,
            isEnabled => CheckUpdateButton.IsEnabled = isEnabled,
            this);
        var appDisplayTitle = GetAppDisplayTitle();
        Title = appDisplayTitle;
        WindowTitleText.Text = appDisplayTitle;
        PlayersList.ItemsSource = _players;
        SpecifiedVisibilityMembersList.ItemsSource = _specifiedVisibilityMembers;
        InitializeFleetRosterSearch();
        InitializeFleetMemberAcceptanceScenarios();
        InitializeFleetProfileAcceptanceScenarios();
        FindFleetResults.ItemsSource = _networkFleets;
        OwnedShipsList.ItemsSource = _ownedShips;
        PersonalHangarDistributionLegend.ItemsSource = _personalHangarDistributionRows;
        PersonalHangarPreviewList.ItemsSource = _personalHangarPreviewRows;
        FleetShipInventoryList.ItemsSource = _fleetShipInventory;
        FleetShipDatabaseList.ItemsSource = _fleetShipDatabaseRows;
        PublishTaskShipList.ItemsSource = _publishTaskShipOptions;
        PublishTaskRallyBox.ItemsSource = PublishTaskLocationSuggestions;
        UpdateFleetShipFilterButtons();
        UpdateFleetShipSortHeaderIndicators();
        FleetTaskHistoryList.ItemsSource = _fleetTaskHistory;
        FleetActionPlanList.ItemsSource = _fleetActionPlans;
        FleetEventLogList.ItemsSource = _fleetEventLogs;
        FleetEventActionPlanList.ItemsSource = _fleetEventActionPlanRows;
        FleetNotificationCenterList.ItemsSource = _fleetNotificationCenterItems;
        FleetMemberTimelineList.ItemsSource = _fleetMemberTimelineItems;
        FleetSystemRoleGroupList.ItemsSource = _fleetSystemRoleGroups;
        FleetCustomRoleGroupList.ItemsSource = _fleetCustomRoleGroups;
        FleetRolePermissionGroupsList.ItemsSource = _fleetSelectedRolePermissionGroups;
        FleetMemberManagementList.ItemsSource = _fleetMemberRows;
        FleetApplicationList.ItemsSource = _fleetApplications;
        FleetInviteList.ItemsSource = _fleetInviteRows;
        ManageProfileSystemOptionsList.ItemsSource = _manageFleetSystemOptions;
        ManageFleetTimeZoneBox.ItemsSource = _fleetTimeZoneOptions;
        ManageFleetExternalContactsList.ItemsSource = _fleetExternalContacts;
        CreateFleetSelectedTagsList.ItemsSource = _createFleetSelectedTags;
        ManageProfileSelectedTagsList.ItemsSource = _manageProfileSelectedTags;
        FindFleetFilterSelectedTagsList.ItemsSource = _findFleetFilterSelectedTags;
        FindFleetAppliedFiltersList.ItemsSource = _findFleetAppliedFilterLabels;
        ManageTagDraftPreviewList.ItemsSource = _manageTagDraftPreviewRows;
        LoadFleetTimeZoneOptions();
        LoadAllowedFleetSystemOptions();
        InitializeFleetActivityTimeSelectors();

        _isLoadingSettings = true;
        var config = DesktopAppConfig.Load();
        _applicationBehaviorSettings = (System.Windows.Application.Current as App)?.BehaviorSettings ??
                                       ApplicationBehaviorSettingsStore.Load();
        var hasSavedSession = !string.IsNullOrWhiteSpace(config.AuthToken);
        _logPath = config.LogPath;
        _localPlayer = config.PlayerName;
        _localPlayerId = config.PlayerId;
        _accountName = config.AccountName;
        _authToken = hasSavedSession ? config.AuthToken : null;
        _accountId = hasSavedSession ? config.AccountId : null;
        _fleetStateCachedAtUtc = config.FleetStateCachedAtUtc;
        if (hasSavedSession)
        {
            _accountSessionCoordinator.Begin(
                default,
                new AccountSessionIdentity(_accountId, _accountName));
        }
        _avatarPath = config.AvatarPath;
        _callsign = config.Callsign;
        BindGameplayStatisticsOwner();
        _allowEmailNotifications = FleetActionFeatureSettingsLocked ? false : config.AllowEmailNotifications;
        _syncPrivacySettings = ApplyFleetActionSettingsLock(SyncPrivacySettings.Load());
        _playerEventSharingSettings = PlayerEventSharingSettingsStore.Load();
        ReloadDualAxisPrivacySettings();
        _notificationSettings = ApplyFleetActionSettingsLock(NotificationSettings.Load());
        _notificationSettings = _notificationSettings with
        {
            EnableEmailNotifications = _allowEmailNotifications && _notificationSettings.EnableEmailNotifications
        };
        _language = "zh";
        LoadOverlayPresetEntries();
        _activeOverlayPreset = NormalizeOverlayPresetId(DesktopAppConfig.LoadActiveOverlayPreset());
        _overlaySettings = ApplyOverlayFeatureLocks(OverlayDisplaySettings.Parse(
            DesktopAppConfig.LoadOverlayPresetSettings(_activeOverlayPreset) ??
            DesktopAppConfig.LoadOverlaySettings() ??
            config.OverlaySettings));
        _localPlayReminderSettings = LocalPlayReminderSettingsStore.Load(
            _overlaySettings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder));
        LoadOverlayLayout(
            DesktopAppConfig.LoadOverlayPresetLayout(_activeOverlayPreset) ??
            DesktopAppConfig.LoadOverlayLayout() ??
            config.OverlayLayout);
        CaptureOverlayEditorSavedSnapshot();
        ApplyOverlaySettingsToControls();
        ApplyLocalPlayReminderSettingsToControls();
        ApplyLanguageToControls();
        OverlayHotkeyBox.Text = string.IsNullOrWhiteSpace(config.OverlayHotkey)
            ? "Ctrl+Shift+O"
            : config.OverlayHotkey;
        OverlayGlobalHotkeyEnabledCheck.IsChecked = config.EnableOverlayGlobalHotkey;
        NetworkServerUrlBox.Text = NormalizeNetworkServerUrl(config.NetworkServerUrl);
        NetworkServerKeyBox.Password = config.NetworkServerKey ?? "";
        CallsignBox.Text = _callsign ?? "";
        if (!string.IsNullOrWhiteSpace(config.FleetStateJson))
        {
            LoadFleetState(config.FleetStateJson);
        }
        if (hasSavedSession)
        {
            BeginStartupDataGate(_accountSessionCoordinator.Capture());
        }
        else
        {
            RefreshStartupDataGatePresentation();
        }
        RefreshAccountPanel();
        RenderCachedIdentity();
        EnsureAvatarStoredAsUserAsset();
        LoadAvatarPreview();
        LoadOwnedShips();
        InitializePersonalProfileEditor();
        ApplySyncPrivacySettingsToControls();
        ApplyPlayerEventSharingSettingsToControls();
        if (_syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Offline)
        {
            _partyRoomRefreshTimer?.Stop();
        }
        ApplyNotificationSettingsToControls();
        ApplyApplicationBehaviorSettingsToControls();
        ShowPersonalSection(PersonalSection.Profile);
        _isLoadingSettings = false;

        RefreshFleetHeader();
        UpdateFleetEntryPanels();
        Loaded += (_, _) =>
        {
            RenderOverlayEditor();
            ApplyOverlayEditorChromeState();
            SetActiveOverlaySettingsSection("overview");
            if (!string.IsNullOrWhiteSpace(_logPath) && File.Exists(_logPath))
            {
                StartWatching(_logPath);
            }

            _ = RunStartupAndGameplayConsentFlowAsync();
            _ = RegisterAppInstallStatsAsync();
            _ = RefreshHomeStatsAsync();
            _ = RefreshPartyRoomsFromServerAsync();
            RefreshHomeDashboard();
        };
        _gameProcessTimer.Tick += (_, _) => UpdateLocalOnlineStateFromGameProcess();
        _gameProcessTimer.Start();
        _networkSyncTimer.Tick += async (_, _) => await NetworkAutoSyncAsync();
        _presenceHeartbeatTimer.Tick += async (_, _) => await SendPresenceHeartbeatAsync();
        _networkPlayerRealtimePullTimer.Tick += async (_, _) => await NetworkPlayerRealtimePullAsync();
        _networkRealtimePushTimer.Tick += async (_, _) => await FlushRealtimeNetworkSnapshotPushAsync();
        _profileSyncDebounceTimer.Tick += async (_, _) =>
        {
            _profileSyncDebounceTimer.Stop();
            await FlushProfileSyncDebouncedAsync();
        };
        _fleetClockTimer.Tick += (_, _) =>
        {
            RefreshFleetClockDisplays();
            if (ReferenceEquals(MainTabs.SelectedItem, HomeTab))
            {
                RefreshHomeDashboard();
            }
        };
        _fleetClockTimer.Start();
        _relayLatencyTimer.Tick += async (_, _) => await MeasureRelayLatencyAsync();
        _appStatsTimer.Tick += async (_, _) => await SendAppStatsHeartbeatAsync();
        if (_syncPrivacySettings.PresenceVisibilityMode != PlayerPresenceVisibilityMode.Offline)
        {
            _relayLatencyTimer.Start();
            _ = MeasureRelayLatencyAsync();
        }

        if (_syncPrivacySettings.PresenceVisibilityMode == PlayerPresenceVisibilityMode.Online)
        {
            _appStatsTimer.Start();
        }
        RefreshFleetClockDisplays();
        AppendOutput("请选择 Star Citizen 的 Game.log 开始读取。");
        RefreshHeaderStatusBar();
        OpenDefaultStartupPage();
    }

    private void MainWindow_ContentRendered(object? sender, EventArgs e)
    {
        ContentRendered -= MainWindow_ContentRendered;
        QueueStartupUpdateCheck();
        QueueInGameMenuPreparation();
    }

    private void QueueStartupUpdateCheck()
    {
        if (_startupUpdateCheckQueued)
        {
            return;
        }

        _startupUpdateCheckQueued = true;
        Dispatcher.BeginInvoke(
            DispatcherPriority.ContextIdle,
            new Action(() =>
            {
                _ = _appUpdateService.CheckForInstallerUpdateAsync(
                    silent: true,
                    currentVersion: GetAppUpdateVersion());
            }));
    }

    protected override void OnSourceInitialized(EventArgs e)
    {
        base.OnSourceInitialized(e);
        MainWindowPlacementService.FitInitialWindow(this);
        _hotkeySource = HwndSource.FromHwnd(new WindowInteropHelper(this).Handle);
        _hotkeySource?.AddHook(MainWindowProc);
        RegisterOverlayHotkey();
    }

    private void FindFleetNav_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = FindFleetTab;
        SetActiveNav(FindFleetNavButton);
        QueueMainPageReveal(previousTab);
        if (IsLoggedIn)
        {
            _ = PullNetworkFleetsAsync(silent: true);
        }
    }

    private void MyFleetNav_Click(object sender, RoutedEventArgs e)
    {
        NavigateToMyFleet();
    }

    private void OpenDefaultStartupPage()
    {
        if (_hasFleet)
        {
            NavigateToMyFleet();
            return;
        }

        NavigateToPartyLobby(animate: false, showGuideHint: false);
    }

    private void MySquadNav_Click(object sender, RoutedEventArgs e)
    {
        NavigateToPartyLobby(animate: true, showGuideHint: true);
    }

    private void NavigateToPartyLobby(bool animate, bool showGuideHint)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = MySquadTab;
        _partyRoomChatUnreadCount = 0;
        RefreshNavigationActivityBadges();
        SetActiveNav(MySquadNavButton);
        if (animate && !ReferenceEquals(previousTab, MainTabs.SelectedItem))
        {
            QueueMainPageReveal(previousTab);
        }

        if (showGuideHint && IsLoggedIn)
        {
            ShowOneTimeGuideHint(
                "party-lobby-page",
                "组队大厅",
                "这里用于寻找临时队友；舰队内的长期协作关系仍由成员、聊天与权限管理承载。");
        }
    }

    private async void OverlayNav_Click(object sender, RoutedEventArgs e)
    {
        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = OverlayEditTab;
        SetActiveNav(OverlayNavButton);
        QueueMainPageReveal(previousTab);
        await OfferOverlaySettingsGuideAsync();
    }

    private void PersonalNav_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        if (_isPersonalProfileVisitorMode)
        {
            ExitPersonalProfileVisitorMode(restoreReturnTab: false);
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = PersonalTab;
        SetActiveNav(PersonalNavButton);
        QueueMainPageReveal(previousTab);
    }

    private void HeaderSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.AppSettings);
        ShowPersonalDashboardSection(PersonalDashboardSection.AppSettings);
        QueueMainPageReveal(previousTab);
        NotifyGuidedTourAction(GuideStep.OpenAccountMenu);
    }

    private void OpenPersonalIdentitySettings_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.Profile);
        ShowPersonalDashboardSection(PersonalDashboardSection.Identity);
        QueueMainPageReveal(previousTab);
    }

    private async void HeaderInboxButton_Click(object sender, RoutedEventArgs e)
    {
        await ShowNotificationCenterAsync();
    }

    private void QueueMainPageReveal(object? previousTab)
    {
        if (ReferenceEquals(previousTab, MainTabs.SelectedItem) ||
            (MainTabs.SelectedItem as TabItem)?.Content is not FrameworkElement content)
        {
            return;
        }

        var previousIndex = MainTabs.Items.IndexOf(previousTab);
        var direction = previousIndex >= 0 && previousIndex > MainTabs.SelectedIndex
            ? UiMotionRevealDirection.FromLeft
            : UiMotionRevealDirection.FromRight;
        Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => UiMotion.RevealContent(content, direction)));
    }

    private void QueueFleetSectionReveal()
    {
        FrameworkElement? content = FleetSubTabs.SelectedItem switch
        {
            _ when FleetSubTabs.SelectedItem == AllPlayersTab => FleetMembersDirectorySplitPanel,
            TabItem tab => tab.Content as FrameworkElement,
            _ => null
        };

        if (content is not null)
        {
            Dispatcher.BeginInvoke(
                DispatcherPriority.Loaded,
                new Action(() => UiMotion.RevealContent(content, UiMotionRevealDirection.FromRight)));
        }
    }

    private enum FleetInfoUpdateScope
    {
        Profile,
        RoleGroups,
        Logo,
        Banner,
        Description,
        EmailNotifications
    }

    private void PartyLobbyUnavailable_Click(object sender, RoutedEventArgs e)
    {
        StarBridgeMessageBox.Show(
            this,
            "组队大厅暂时不可用，请稍后重试。",
            "组队大厅",
            MessageBoxButton.OK,
            MessageBoxImage.Information);
    }

    private void PersonalSectionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender == PersonalProfileSectionButton)
        {
            ShowPersonalSection(PersonalSection.Profile);
        }
        else if (sender == PersonalAppSettingsSectionButton)
        {
            ShowPersonalSection(PersonalSection.AppSettings);
        }
        else if (sender == PersonalDataSyncSectionButton)
        {
            ShowPersonalSection(PersonalSection.DataSync);
        }
        else if (sender == PersonalNotificationsSectionButton)
        {
            ShowPersonalSection(PersonalSection.Notifications);
        }
    }

    private void ShowPersonalSection(PersonalSection section)
    {
        if (PersonalProfileSectionPanel is null)
        {
            return;
        }

        PersonalProfileSectionPanel.Visibility = section == PersonalSection.Profile
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalAppAndNotificationSectionGrid.Visibility =
            section is PersonalSection.AppSettings or PersonalSection.Notifications
                ? Visibility.Visible
                : Visibility.Collapsed;
        PersonalAppSettingsSectionPanel.Visibility = section is PersonalSection.AppSettings or PersonalSection.Notifications
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalNotificationsSectionPanel.Visibility = section is PersonalSection.AppSettings or PersonalSection.Notifications
            ? Visibility.Visible
            : Visibility.Collapsed;
        PersonalDataSyncSectionPanel.Visibility = Visibility.Visible;

        Grid.SetColumn(PersonalAppSettingsSectionPanel, 0);
        Grid.SetColumnSpan(PersonalAppSettingsSectionPanel, 1);
        Grid.SetColumn(PersonalNotificationsSectionPanel, 1);
        Grid.SetColumnSpan(PersonalNotificationsSectionPanel, 1);
        PersonalAppSettingsSectionPanel.Margin = new Thickness(0, 0, 5, 0);
        PersonalNotificationsSectionPanel.Margin = new Thickness(5, 0, 0, 0);

        var activeButton = section switch
        {
            PersonalSection.AppSettings => PersonalAppSettingsSectionButton,
            PersonalSection.DataSync => PersonalDataSyncSectionButton,
            PersonalSection.Notifications => PersonalNotificationsSectionButton,
            _ => PersonalProfileSectionButton
        };
        UiMotion.ApplyNavigationSelection(
            [
                PersonalProfileSectionButton,
                PersonalAppSettingsSectionButton,
                PersonalDataSyncSectionButton,
                PersonalNotificationsSectionButton
            ],
            activeButton);
    }

    private void PersonalDashboardRailButton_Click(object sender, RoutedEventArgs e)
    {
        var activeButton = sender as System.Windows.Controls.Button;
        var section = activeButton switch
        {
            _ when ReferenceEquals(activeButton, PersonalDashboardAppSettingsButton) => PersonalDashboardSection.AppSettings,
            _ when ReferenceEquals(activeButton, PersonalDashboardSyncButton) => PersonalDashboardSection.SyncPrivacy,
            _ when ReferenceEquals(activeButton, PersonalDashboardHangarButton) => PersonalDashboardSection.Hangar,
            _ when ReferenceEquals(activeButton, PersonalDashboardNotificationButton) => PersonalDashboardSection.Notifications,
            _ when ReferenceEquals(activeButton, PersonalDashboardSecurityButton) => PersonalDashboardSection.SecurityFeedback,
            _ => PersonalDashboardSection.Identity
        };

        ShowPersonalDashboardSection(section);
        if (section == PersonalDashboardSection.Identity)
        {
            NotifyGuidedTourAction(GuideStep.OpenIdentitySettings);
        }
    }

    private void ShowPersonalDashboardSection(PersonalDashboardSection section)
    {
        var activeButton = section switch
        {
            PersonalDashboardSection.AppSettings => PersonalDashboardAppSettingsButton,
            PersonalDashboardSection.SyncPrivacy => PersonalDashboardSyncButton,
            PersonalDashboardSection.Hangar => PersonalDashboardHangarButton,
            PersonalDashboardSection.Notifications => PersonalDashboardNotificationButton,
            PersonalDashboardSection.SecurityFeedback => PersonalDashboardSecurityButton,
            _ => PersonalDashboardIdentityButton
        };

        SetPersonalDashboardRailActive(activeButton);
        SetPersonalDashboardSectionVisibility(PersonalDashboardIdentitySection, section == PersonalDashboardSection.Identity);
        SetPersonalDashboardSectionVisibility(PersonalDashboardAppSettingsSection, section == PersonalDashboardSection.AppSettings);
        SetPersonalDashboardSectionVisibility(PersonalDashboardSyncSection, section == PersonalDashboardSection.SyncPrivacy);
        SetPersonalDashboardSectionVisibility(PersonalDashboardHangarSection, section == PersonalDashboardSection.Hangar);
        SetPersonalDashboardSectionVisibility(PersonalDashboardNotificationSection, section == PersonalDashboardSection.Notifications);
        SetPersonalDashboardSectionVisibility(PersonalDashboardSecuritySection, section == PersonalDashboardSection.SecurityFeedback);
        if (section == PersonalDashboardSection.AppSettings)
        {
            RefreshPersonalApplicationSettings();
        }
        else if (section == PersonalDashboardSection.SyncPrivacy)
        {
            _ = RefreshPrivateVisibilityGroupsAsync();
        }
    }

    private static void SetPersonalDashboardSectionVisibility(FrameworkElement section, bool isVisible)
    {
        section.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;

        if (!isVisible)
        {
            return;
        }

        Grid.SetRow(section, 0);
        Grid.SetColumn(section, 0);
        Grid.SetRowSpan(section, 3);
        Grid.SetColumnSpan(section, 2);
        section.Margin = new Thickness(0);
        section.Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => UiMotion.RevealContent(section, UiMotionRevealDirection.FromRight)));
    }

    private void SetPersonalDashboardRailActive(System.Windows.Controls.Button? activeButton)
    {
        System.Windows.Controls.Button?[] buttons =
        [
            PersonalDashboardIdentityButton,
            PersonalDashboardAppSettingsButton,
            PersonalDashboardSyncButton,
            PersonalDashboardHangarButton,
            PersonalDashboardNotificationButton,
            PersonalDashboardSecurityButton
        ];

        UiMotion.ApplyNavigationSelection(buttons, activeButton);
    }

    private void BrandLogo_MouseLeftButtonUp(object sender, MouseButtonEventArgs e)
    {
        OpenHomePage();
    }

    private void HelpSupportButton_Click(object sender, RoutedEventArgs e)
    {
        OpenHelpSupportPage();
    }

    private void AboutAppButton_Click(object sender, RoutedEventArgs e)
    {
        OpenHelpSupportPage();
    }

    private void FeedbackButton_Click(object sender, RoutedEventArgs e)
    {
        OpenHelpSupportPage();
    }

    private void OpenHelpSupportPage()
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        MainTabs.SelectedItem = SupportTab;
        SetActiveNav(null);
        ShowHelpSupportSection("version", HelpSupportVersionButton, animate: false);
    }

    private void HelpSupportSectionButton_Click(object sender, RoutedEventArgs e)
    {
        if (sender is not System.Windows.Controls.Button button)
        {
            return;
        }

        ShowHelpSupportSection(button.CommandParameter as string ?? "version", button, animate: true);
    }

    private void ShowHelpSupportSection(
        string topic,
        System.Windows.Controls.Button? activeButton,
        bool animate)
    {
        var showGuide = string.Equals(topic, "guide", StringComparison.Ordinal);
        var showLogRecognition = string.Equals(topic, "log-recognition", StringComparison.Ordinal);
        var showPrivacy = string.Equals(topic, "privacy", StringComparison.Ordinal);
        var showFeedback = string.Equals(topic, "feedback", StringComparison.Ordinal);
        var showVersion = string.Equals(topic, "version", StringComparison.Ordinal);

        HelpSupportGuideSection.Visibility = showGuide ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportLogRecognitionSection.Visibility = showLogRecognition ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportPrivacySection.Visibility = showPrivacy ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportFeedbackSection.Visibility = showFeedback ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportVersionSection.Visibility = showVersion ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportStatsSection.Visibility = showVersion ? Visibility.Visible : Visibility.Collapsed;
        HelpSupportActionSectionsHost.Visibility = showFeedback || showVersion
            ? Visibility.Visible
            : Visibility.Collapsed;

        Grid.SetColumn(HelpSupportFeedbackSection, 0);
        Grid.SetColumnSpan(HelpSupportFeedbackSection, 3);
        Grid.SetColumn(HelpSupportVersionSection, 0);
        Grid.SetColumnSpan(HelpSupportVersionSection, 3);

        UiMotion.ApplyNavigationSelection(
            [
                HelpSupportGuideButton,
                HelpSupportLogRecognitionButton,
                HelpSupportFeedbackButton,
                HelpSupportPrivacyButton,
                HelpSupportVersionButton
            ],
            activeButton);
        HelpSupportScrollViewer.ScrollToTop();

        if (!animate)
        {
            return;
        }

        FrameworkElement activeSection = showGuide
            ? HelpSupportGuideSection
            : showLogRecognition
                ? HelpSupportLogRecognitionSection
                : showPrivacy
                    ? HelpSupportPrivacySection
                    : HelpSupportActionSectionsHost;
        activeSection.Dispatcher.BeginInvoke(
            DispatcherPriority.Loaded,
            new Action(() => UiMotion.RevealContent(activeSection, UiMotionRevealDirection.FromRight)));
    }

    private async void HelpGuideAccountButton_Click(object sender, RoutedEventArgs e)
    {
        if (!IsLoggedIn)
        {
            await ShowLoginDialogAsync();
            if (IsLoggedIn)
            {
                await AutoConnectNetworkAsync();
            }

            return;
        }

        OpenPersonalIdentitySettings_Click(sender, e);
    }

    private void HelpGuideDiagnosticsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.AppSettings);
        ShowPersonalDashboardSection(PersonalDashboardSection.SecurityFeedback);
        QueueMainPageReveal(previousTab);
    }

    private void HelpGuideFeedbackButton_Click(object sender, RoutedEventArgs e)
    {
        ShowHelpSupportSection("feedback", HelpSupportFeedbackButton, animate: true);
    }

    private void HelpSupportBackToSettingsButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(null);
    }

    private void OfficialBinaryLicenseButton_Click(object sender, RoutedEventArgs e)
    {
        var terms = _testBuildNoticeStore.ReadCurrentTerms();
        if (string.IsNullOrWhiteSpace(terms))
        {
            StarBridgeMessageBox.Show(
                this,
                "当前安装目录中没有找到《官方客户端许可条款》。请重新安装官方完整版本，或前往官方 GitHub 仓库查看 LICENSES/OFFICIAL-BINARY-LICENSE.txt。",
                "无法读取客户端许可",
                MessageBoxButton.OK,
                MessageBoxImage.Warning);
            return;
        }

        StarBridgeMessageBox.ShowAcknowledgement(
            this,
            terms,
            "官方客户端许可条款",
            "关闭",
            MessageBoxImage.Information);
    }

    private async void CheckUpdateButton_Click(object sender, RoutedEventArgs e)
    {
        await CheckForUpdatesAsync();
    }

    private Task CheckForUpdatesAsync()
    {
        return CheckUpdateButton.IsEnabled
            ? _appUpdateService.CheckForInstallerUpdateAsync(silent: false, currentVersion: GetAppUpdateVersion())
            : Task.CompletedTask;
    }

    public Task<bool> ConfirmUpdateAsync(UpdateManifest manifest, string currentVersion, string updateMode)
    {
        _updateConfirmationSource = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _updateOverlayCanClose = false;

        Dispatcher.Invoke(() =>
        {
            var notes = string.IsNullOrWhiteSpace(manifest.Notes) ? "无版本说明。" : manifest.Notes.Trim();
            UpdateOverlayTitleText.Text = $"发现新版本 V{manifest.Version}";
            UpdateOverlayVersionText.Text = $"当前版本 V{currentVersion}  ->  新版本 V{manifest.Version}";
            UpdateOverlayModeText.Text = $"更新方式：{updateMode}";
            UpdateOverlayNotesText.Text = notes;
            UpdateOverlayStatusText.Text = "确认后将开始下载更新。更新期间会锁定应用操作；下载完成后星海舰桥可能会自动关闭并重启。";
            UpdateOverlayProgressBar.IsIndeterminate = false;
            UpdateOverlayProgressBar.Value = 0;
            UpdateOverlayProgressText.Text = "0%";
            UpdateOverlayCancelButton.Visibility = Visibility.Visible;
            UpdateOverlayCancelButton.IsEnabled = true;
            UpdateOverlayPrimaryButton.Visibility = Visibility.Visible;
            UpdateOverlayPrimaryButton.IsEnabled = true;
            UpdateOverlayPrimaryButton.Content = "立即更新";
            UpdateProgressOverlay.Visibility = Visibility.Visible;
        });

        return _updateConfirmationSource.Task;
    }

    public void ReportProgress(string status, long? percent)
    {
        Dispatcher.Invoke(() =>
        {
            UpdateOverlayStatusText.Text = status;
            UpdateOverlayCancelButton.Visibility = Visibility.Collapsed;
            UpdateOverlayPrimaryButton.Visibility = Visibility.Collapsed;
            UpdateOverlayProgressBar.IsIndeterminate = percent is null;
            UpdateProgressOverlay.Visibility = Visibility.Visible;
            if (percent is null)
            {
                UpdateOverlayProgressText.Text = "下载中";
                return;
            }

            var clamped = Math.Clamp(percent.Value, 0, 100);
            UpdateOverlayProgressBar.Value = clamped;
            UpdateOverlayProgressText.Text = $"{clamped}%";
            UpdateProgressOverlay.Visibility = Visibility.Visible;
        });
    }

    public void ReportCompleted(string status)
    {
        Dispatcher.Invoke(() =>
        {
            UpdateOverlayStatusText.Text = status;
            UpdateOverlayProgressBar.IsIndeterminate = false;
            UpdateOverlayProgressBar.Value = 100;
            UpdateOverlayProgressText.Text = "100%";
            UpdateOverlayCancelButton.Visibility = Visibility.Collapsed;
            UpdateOverlayPrimaryButton.Visibility = Visibility.Collapsed;
        });
    }

    public Task<bool> ConfirmRestartAsync(string status)
    {
        _updateConfirmationSource = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);
        _updateOverlayCanClose = false;

        Dispatcher.Invoke(() =>
        {
            UpdateOverlayTitleText.Text = "应用即将重启";
            UpdateOverlayVersionText.Text = "更新文件已准备完成";
            UpdateOverlayModeText.Text = "确认后将关闭并重启应用";
            UpdateOverlayNotesText.Text = "应用将会重启以完成更新。请确认当前操作已经保存，再继续完成更新。";
            UpdateOverlayStatusText.Text = status;
            UpdateOverlayProgressBar.IsIndeterminate = false;
            UpdateOverlayProgressBar.Value = 100;
            UpdateOverlayProgressText.Text = "完成";
            UpdateOverlayCancelButton.Content = "稍后";
            UpdateOverlayCancelButton.Visibility = Visibility.Visible;
            UpdateOverlayCancelButton.IsEnabled = true;
            UpdateOverlayPrimaryButton.Content = "确认并重启";
            UpdateOverlayPrimaryButton.Visibility = Visibility.Visible;
            UpdateOverlayPrimaryButton.IsEnabled = true;
            UpdateProgressOverlay.Visibility = Visibility.Visible;
        });

        return _updateConfirmationSource.Task;
    }

    public void ReportFailed(string status)
    {
        Dispatcher.Invoke(() =>
        {
            _updateOverlayCanClose = true;
            UpdateOverlayStatusText.Text = status;
            UpdateOverlayProgressBar.IsIndeterminate = false;
            UpdateOverlayCancelButton.Visibility = Visibility.Collapsed;
            UpdateOverlayPrimaryButton.Content = "关闭";
            UpdateOverlayPrimaryButton.Visibility = Visibility.Visible;
            UpdateOverlayPrimaryButton.IsEnabled = true;
            UpdateProgressOverlay.Visibility = Visibility.Visible;
        });
    }

    private void UpdateOverlayPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        if (_updateConfirmationSource is not null)
        {
            var source = _updateConfirmationSource;
            _updateConfirmationSource = null;
            UpdateOverlayPrimaryButton.Visibility = Visibility.Collapsed;
            UpdateOverlayCancelButton.Visibility = Visibility.Collapsed;
            UpdateOverlayStatusText.Text = "正在准备更新...";
            source.TrySetResult(true);
            return;
        }

        if (_updateOverlayCanClose)
        {
            UpdateProgressOverlay.Visibility = Visibility.Collapsed;
            _updateOverlayCanClose = false;
        }
    }

    private void UpdateOverlayCancelButton_Click(object sender, RoutedEventArgs e)
    {
        if (_updateConfirmationSource is null)
        {
            return;
        }

        var source = _updateConfirmationSource;
        _updateConfirmationSource = null;
        UpdateProgressOverlay.Visibility = Visibility.Collapsed;
        source.TrySetResult(false);
    }

    private Task<bool> ShowAppConfirmationAsync(
        string title,
        string message,
        string detail,
        string confirmText,
        string cancelText,
        bool danger = true,
        bool showCancel = true,
        string footerText = "此操作会同步到舰队。")
    {
        _appConfirmationSource?.TrySetResult(false);
        _appConfirmationSource = new TaskCompletionSource<bool>(TaskCreationOptions.RunContinuationsAsynchronously);

        AppConfirmOverlay.Title = title;
        AppConfirmMessageText.Text = message;
        AppConfirmDetailText.Text = detail;
        AppConfirmPrimaryButton.Content = confirmText;
        AppConfirmCancelButton.Content = cancelText;
        AppConfirmFooterText.Text = footerText;
        AppConfirmPrimaryButton.Style = (Style)FindResource(
            danger ? "BridgeModalDangerButtonStyle" : "BridgeDirectoryPrimaryButtonStyle");
        AppConfirmPrimaryButton.IsDefault = !danger;
        AppConfirmCancelButton.Visibility = showCancel ? Visibility.Visible : Visibility.Collapsed;
        AppConfirmOverlay.Show();
        if (showCancel)
        {
            AppConfirmCancelButton.Focus();
        }
        else
        {
            AppConfirmPrimaryButton.Focus();
        }

        return _appConfirmationSource.Task;
    }

    private Task<bool> ShowAppNoticeAsync(
        string title,
        string message,
        string detail,
        string confirmText = "知道了")
    {
        return ShowAppConfirmationAsync(
            title,
            message,
            detail,
            confirmText,
            "",
            danger: false,
            showCancel: false,
            footerText: "操作已完成。");
    }

    private void AppConfirmPrimaryButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteAppConfirmation(confirmed: true);
    }

    private void AppConfirmCancelButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteAppConfirmation(confirmed: false);
    }

    private void CompleteAppConfirmation(bool confirmed)
    {
        var source = _appConfirmationSource;
        _appConfirmationSource = null;
        AppConfirmOverlay.Hide();
        source?.TrySetResult(confirmed);
        SchedulePendingOverlayAppearanceUnlockNotice();
    }

    private async void SendFeedbackButton_Click(object sender, RoutedEventArgs e)
    {
        var message = FeedbackMessageBox.Text.Trim();
        if (string.IsNullOrWhiteSpace(message))
        {
            FeedbackStatusText.Text = "请先填写反馈内容。";
            FeedbackStatusText.Foreground = FindBrush("StatusWarningBrush", Brushes.Orange);
            return;
        }

        FeedbackStatusText.Text = "正在发送反馈...";
        FeedbackStatusText.Foreground = FindBrush("StatusInfoBrush", Brushes.DeepSkyBlue);
        try
        {
            var request = new FeedbackRequest(
                FeedbackContactBox.Text.Trim(),
                _localPlayer,
                _callsign,
                message);
            var response = await PostNetworkJsonAsync("api/feedback", request);
            if (!response.IsSuccessStatusCode)
            {
                FeedbackStatusText.Text = response.StatusCode == HttpStatusCode.NotFound
                    ? "发送反馈失败：当前服务器未更新反馈接口，请联系管理员更新服务器。"
                    : FormatActionFailure("发送反馈", await ReadResponseErrorAsync(response));
                FeedbackStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
                return;
            }

            FeedbackMessageBox.Clear();
            FeedbackStatusText.Text = "反馈已发送，感谢。";
            FeedbackStatusText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        }
        catch (Exception ex)
        {
            FeedbackStatusText.Text = UserFacingError.Describe(ex, "反馈未发送，请检查网络后重试。");
            FeedbackStatusText.Foreground = FindBrush("StatusDangerBrush", Brushes.IndianRed);
        }
    }

    private void CopyFeedbackQqGroupButton_Click(object sender, RoutedEventArgs e)
    {
        const string groupNumber = "534268220";
        System.Windows.Clipboard.SetText(groupNumber);
        FeedbackStatusText.Text = $"QQ 反馈群号 {groupNumber} 已复制。";
        FeedbackStatusText.Foreground = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
    }

    private void NetworkTestNav_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        MainTabs.SelectedItem = MonitorTab;
        SetActiveNav(null);
    }

    private bool IsLoggedIn => !string.IsNullOrWhiteSpace(_authToken);

    private PlayerPresenceSharingDecision GetPresenceSharingDecision() =>
        PlayerPresence.DecideSharing(_localPresence, _syncPrivacySettings.PresenceVisibilityMode);

    private bool CanUseNightShadow =>
        CanUseOverlaySkin(OverlaySkin.NightShadow);

    private bool CanUseOverlaySkin(OverlaySkin skin)
    {
        var profile = OverlaySkinCatalog.Get(skin);
        if (profile.Entitlement is null)
        {
            return true;
        }

        return IsLoggedIn &&
               OverlaySkinCatalog.CanUse(skin, EnumerateActiveOverlayEntitlements());
    }

    private IEnumerable<string> EnumerateActiveOverlayEntitlements()
    {
        foreach (var entitlement in _accountEntitlements)
        {
            yield return entitlement;
        }

        var now = DateTimeOffset.UtcNow;
        foreach (var pair in _temporaryEntitlements)
        {
            if (pair.Value > now)
            {
                yield return pair.Key;
            }
        }
    }

    private bool EnsureLoggedIn(string message)
    {
        if (IsLoggedIn)
        {
            return true;
        }

        if (!TryLeaveOverlayEditorTab())
        {
            return false;
        }

        LoginStatusText.Text = message;
        NetworkStatusText.Text = "浏览模式：请先登录";
        RefreshHeaderStatusBar();
        MainTabs.SelectedItem = PersonalTab;
        SetActiveNav(PersonalNavButton);
        _ = ShowLoginDialogAsync();
        return false;
    }

    private IdentityInitializationStatus GetIdentityInitializationStatus()
    {
        return IdentityInitialization.GetStatus(_logPath, _localPlayer, _localPlayerId);
    }

    private bool EnsureIdentityInitialized(string action)
    {
        var status = GetIdentityInitializationStatus();
        if (status.IsComplete)
        {
            return true;
        }

        if (!TryLeaveOverlayEditorTab())
        {
            return false;
        }

        LoginStatusText.Text = $"需要先完成身份初始化，才能{action}。";
        NetworkStatusText.Text = "请选择 Game.log，并确认玩家身份标识。";
        RefreshHeaderStatusBar();
        MainTabs.SelectedItem = SettingsTab;
        SetActiveNav(HeaderSettingsButton);
        ShowPersonalSection(PersonalSection.Profile);
        ShowPersonalDashboardSection(PersonalDashboardSection.Identity);

        var dialog = new GuideHintWindow(
            "需要身份初始化",
            $"{status.DetailText}\n\n完成后即可{action}。")
        {
            Owner = this
        };
        dialog.ShowDialog();
        return false;
    }

    private void ApplyAuthResponse(AuthResponse auth, bool refreshDependentData = true)
    {
        var previousAccount = _accountName;
        var previousAccountId = _accountId;
        var incomingAccount = auth.Email ?? auth.UserName;
        var transition = _accountSessionCoordinator.Begin(
            new AccountSessionIdentity(previousAccountId, previousAccount),
            new AccountSessionIdentity(auth.AccountId, incomingAccount));
        BeginInGameWorkspaceAccountSession(transition.Lease, signedIn: true);
        var sameAccount = !transition.AccountChanged;
        var previousEntitlements = _accountEntitlements.ToArray();
        var previousTemporaryEntitlements = _temporaryEntitlements.ToDictionary(
            pair => pair.Key,
            pair => pair.Value,
            StringComparer.OrdinalIgnoreCase);

        if (transition.AccountChanged)
        {
            _isAccountTransition = true;
            try
            {
                ResetAccountAvatarState();
                ResetAccountScopedState("正在加载新账号的组织通讯…");
            }
            finally
            {
                _isAccountTransition = false;
            }
        }

        _authenticationExpired = false;
        _pendingFleetApplicationCodes.Clear();
        _accountName = incomingAccount;
        _accountId = auth.AccountId;
        _authToken = auth.Token;
        ReloadDualAxisPrivacySettings();
        _accountEntitlements.Clear();
        foreach (var entitlement in auth.Entitlements ?? [])
        {
            if (!string.IsNullOrWhiteSpace(entitlement))
            {
                _accountEntitlements.Add(entitlement.Trim());
            }
        }
        _temporaryEntitlements.Clear();
        foreach (var grant in auth.TemporaryEntitlements ?? [])
        {
            if (!string.IsNullOrWhiteSpace(grant.Entitlement) && grant.ExpiresAt > DateTimeOffset.UtcNow)
            {
                _temporaryEntitlements[grant.Entitlement.Trim()] = grant.ExpiresAt;
            }
        }
        _callsign = auth.Callsign;
        _gameIdVisibilityPreference = GameIdVisibilityPolicy.Normalize(
            auth.Callsign,
            auth.GameName ?? _localPlayer,
            auth.GameIdVisibilityLocations);
        ApplyGameIdVisibilityToEditor();
        UpdateIdentityBindingFromAuth(auth, showPrompt: IsLoaded);
        RefreshDirectMessagePrivacyAuthenticationState();

        BindGameplayStatisticsOwner();
        if (IsLoaded)
        {
            ShowGameplayDataConsentIfNeeded();
        }

        RestoreAccountAvatarFromServer(auth.AvatarImageData);

        _allowEmailNotifications = FleetActionFeatureSettingsLocked ? false : auth.AllowEmailNotifications;
        CallsignBox.Text = _callsign ?? "";
        EmailNotificationsCheck.IsChecked = _allowEmailNotifications;
        ApplyOverlayEntitlementState();
        ScheduleTemporaryEntitlementRefresh();
        _entitlementRefreshTimer.Start();
        RefreshPersonalApplicationSettings();
        BeginPersonalProfileAccountSession(sameAccount);
        RefreshAccountPanel();

        foreach (var profile in OverlaySkinCatalog.All.Where(profile => profile.Entitlement is not null))
        {
            var entitlement = profile.Entitlement!;
            var previouslyCouldUse = sameAccount &&
                ((previousEntitlements ?? []).Any(value =>
                     value.Equals(entitlement, StringComparison.OrdinalIgnoreCase)) ||
                 (previousTemporaryEntitlements.TryGetValue(entitlement, out var previousExpiry) &&
                  previousExpiry > DateTimeOffset.UtcNow));
            var gainedPermanent = OverlayAppearanceUnlockPolicy.IsNewPermanentUnlock(
                previousAccount,
                _accountName,
                previousEntitlements,
                _accountEntitlements,
                entitlement);
            if (gainedPermanent)
            {
                QueueOverlayAppearanceUnlockNotice(profile.Id, isPermanent: true, expiresAt: null);
            }
            else if (!previouslyCouldUse &&
                     CanUseOverlaySkin(profile.Id) &&
                     _temporaryEntitlements.TryGetValue(entitlement, out var expiresAt))
            {
                QueueOverlayAppearanceUnlockNotice(profile.Id, isPermanent: false, expiresAt);
            }
        }

        if (refreshDependentData)
        {
            _ = RefreshPartyRoomsFromServerAsync();
        }
    }

    private async Task RefreshAccountEntitlementsAsync()
    {
        if (!IsLoggedIn || _isRefreshingEntitlements)
        {
            return;
        }

        var session = _accountSessionCoordinator.Capture();
        _isRefreshingEntitlements = true;
        try
        {
            using var response = await _relayClient.GetAsync("api/auth/session");
            if (!_accountSessionCoordinator.IsCurrent(session))
            {
                return;
            }
            if (response.StatusCode == HttpStatusCode.NotFound)
            {
                _entitlementRefreshTimer.Stop();
                return;
            }

            if (HandleAuthorizationFailure(response.StatusCode, "外观资格刷新", silent: true) ||
                !response.IsSuccessStatusCode)
            {
                return;
            }

            var auth = await response.Content.ReadFromJsonAsync<AuthResponse>();
            if (auth is not null && !string.IsNullOrWhiteSpace(auth.Token))
            {
                ApplyAuthResponse(auth, refreshDependentData: false);
            }
        }
        catch
        {
            // Entitlement refresh is opportunistic and must not interrupt normal synchronization.
        }
        finally
        {
            _isRefreshingEntitlements = false;
        }
    }

    private void QueueOverlayAppearanceUnlockNotice(
        OverlaySkin skin,
        bool isPermanent,
        DateTimeOffset? expiresAt)
    {
        var profile = OverlaySkinCatalog.Get(skin);
        if (profile.Entitlement is null)
        {
            return;
        }

        var acknowledgementKey = OverlayAppearanceUnlockPolicy.BuildAcknowledgementKey(
            _accountName,
            profile.Entitlement,
            isPermanent ? null : expiresAt);
        if (_acknowledgedEntitlementNotices.Contains(acknowledgementKey) ||
            !_queuedOverlayAppearanceUnlockKeys.Add(acknowledgementKey))
        {
            return;
        }

        _pendingOverlayAppearanceUnlockNotices.Enqueue(new OverlayAppearanceUnlockNotice(
            skin,
            profile.Entitlement,
            acknowledgementKey,
            isPermanent,
            expiresAt));
        SchedulePendingOverlayAppearanceUnlockNotice();
    }

    private void SchedulePendingOverlayAppearanceUnlockNotice()
    {
        Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(async () =>
        {
            await TryShowPendingOverlayAppearanceUnlockNoticeAsync();
        }));
    }

    private async Task TryShowPendingOverlayAppearanceUnlockNoticeAsync()
    {
        if (_isShowingOverlayAppearanceUnlockNotice ||
            _isLoginDialogOpen ||
            _appConfirmationSource is not null ||
            _pendingOverlayAppearanceUnlockNotices.Count == 0)
        {
            return;
        }

        var notice = _pendingOverlayAppearanceUnlockNotices.Dequeue();
        _isShowingOverlayAppearanceUnlockNotice = true;
        try
        {
            var useNow = await ShowOverlayAppearanceUnlockNoticeAsync(notice);
            if (IsLoggedIn)
            {
                _acknowledgedEntitlementNotices.Add(notice.AcknowledgementKey);
                DesktopAppConfig.SaveAcknowledgedEntitlementNotices(_acknowledgedEntitlementNotices);
            }

            if (useNow)
            {
                ApplyOverlayAppearanceFromUnlockNotice(notice.Skin);
            }
        }
        finally
        {
            _queuedOverlayAppearanceUnlockKeys.Remove(notice.AcknowledgementKey);
            _isShowingOverlayAppearanceUnlockNotice = false;
            SchedulePendingOverlayAppearanceUnlockNotice();
        }
    }

    private Task<bool> ShowOverlayAppearanceUnlockNoticeAsync(OverlayAppearanceUnlockNotice notice)
    {
        _overlayAppearanceUnlockSource?.TrySetResult(false);
        _overlayAppearanceUnlockSource = new TaskCompletionSource<bool>(
            TaskCreationOptions.RunContinuationsAsynchronously);

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var profile = OverlaySkinCatalog.Get(notice.Skin);
        OverlayAppearanceUnlockEyebrowText.Text = zh ? "游戏浮层外观已解锁" : "OVERLAY APPEARANCE UNLOCKED";
        OverlayAppearanceUnlockTitleText.Text = zh ? "已获得新外观" : "New appearance unlocked";
        OverlayAppearanceUnlockNameText.Text = profile.DisplayName(_language);
        OverlayAppearanceUnlockStatusText.Text = notice.IsPermanent
            ? zh ? "永久解锁" : "Permanently unlocked"
            : zh
                ? $"临时解锁至 {notice.ExpiresAt?.ToLocalTime():yyyy-MM-dd HH:mm}"
                : $"Unlocked until {notice.ExpiresAt?.ToLocalTime():yyyy-MM-dd HH:mm}";
        OverlayAppearanceUnlockMessageText.Text = zh
            ? $"“{profile.DisplayNameZh}”外观已同步到当前账号，并立即解除使用限制。"
            : $"{profile.DisplayNameEn} is now available on this account.";
        OverlayAppearanceUnlockDetailText.Text = zh
            ? "你可以立即应用到当前浮层，或稍后在“游戏浮层 > 外观风格”中选择。"
            : "Apply it to the current Overlay now, or choose it later under Overlay > Appearance.";
        OverlayAppearanceUnlockFooterText.Text = _isOverlayEditorLayoutDirty
            ? zh ? "立即使用会加入本轮未保存更改。" : "Use now adds it to the current unsaved changes."
            : zh ? "资格已绑定到当前服务器账号。" : "The entitlement is linked to this server account.";
        OverlayAppearanceUnlockConfirmButton.Content = zh ? "确定" : "Done";
        OverlayAppearanceUnlockUseNowButton.Content = zh ? "立即使用" : "Use now";
        UiMotion.ShowModal(OverlayAppearanceUnlockOverlay, OverlayAppearanceUnlockCard);
        OverlayAppearanceUnlockUseNowButton.Focus();
        return _overlayAppearanceUnlockSource.Task;
    }

    private void OverlayAppearanceUnlockCloseButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteOverlayAppearanceUnlockNotice(useNow: false);
    }

    private void OverlayAppearanceUnlockConfirmButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteOverlayAppearanceUnlockNotice(useNow: false);
    }

    private void OverlayAppearanceUnlockUseNowButton_Click(object sender, RoutedEventArgs e)
    {
        CompleteOverlayAppearanceUnlockNotice(useNow: true);
    }

    private void CompleteOverlayAppearanceUnlockNotice(bool useNow, bool scheduleNext = true)
    {
        var source = _overlayAppearanceUnlockSource;
        _overlayAppearanceUnlockSource = null;
        UiMotion.HideModal(OverlayAppearanceUnlockOverlay, OverlayAppearanceUnlockCard);
        source?.TrySetResult(useNow);
        if (scheduleNext)
        {
            SchedulePendingOverlayAppearanceUnlockNotice();
        }
    }

    private void ApplyOverlayAppearanceFromUnlockNotice(OverlaySkin skin)
    {
        if (!CanUseOverlaySkin(skin) || _overlaySettings.Skin == skin)
        {
            return;
        }

        var hadUnsavedChanges = _isOverlayEditorLayoutDirty;
        PushOverlayEditorUndoState();
        _overlaySettings = ApplyOverlayFeatureLocks(_overlaySettings with
        {
            Skin = skin,
            RequestedSkin = skin
        });
        ApplyOverlayEntitlementState();
        if (hadUnsavedChanges)
        {
            MarkOverlayEditorLayoutDirty();
        }
        else
        {
            MarkOverlayEditorLayoutSaved();
        }

        SaveCurrentConfig();
        RefreshOverlayWindow();
        RefreshOverlayOverviewSummary();
    }

    private static bool IsAuthorizationFailure(HttpStatusCode? statusCode)
    {
        return statusCode is HttpStatusCode.Unauthorized or HttpStatusCode.Forbidden;
    }

    private bool HandleAuthorizationFailure(HttpStatusCode? statusCode, string context, bool silent = false)
    {
        if (!IsAuthorizationFailure(statusCode))
        {
            return false;
        }

        StopNetworkSyncTimers();
        _authenticationExpired = true;
        ClearAuthenticatedLocalState();
        SaveCurrentConfig(clearSavedSession: true);
        RefreshAccountPanel();
        UpdateFleetEntryPanels();
        RenderState();
        LoginStatusText.Text = "登录已失效，请重新登录";
        NetworkStatusText.Text = $"{context}失败：登录已失效，本地资料已保留";
        RefreshHeaderStatusBar();
        if (!silent)
        {
            AppendOutput($"NETWORK | auth expired during {context}; local profile and fleet cache retained");
        }

        return true;
    }

    private bool HandleAuthorizationFailure(Exception exception, string context, bool silent = false)
    {
        return exception is HttpRequestException httpException &&
               HandleAuthorizationFailure(httpException.StatusCode, context, silent);
    }

    private void RefreshHeaderAvatarPresenceDot()
    {
        if (HeaderAvatarOnlineDot is null)
        {
            return;
        }

        HeaderAvatarOnlineDot.Fill = IsLoggedIn
            ? PlayerPresencePresentation.LocalBrush(
                _localPresence,
                _syncPrivacySettings.PresenceVisibilityMode)
            : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
    }

    private void RefreshAccountPanel()
    {
        if (AccountNameText is null)
        {
            return;
        }

        _isRefreshingAccountPanel = true;
        try
        {
            HeaderAuthenticationButton.Visibility = IsLoggedIn
                ? Visibility.Collapsed
                : Visibility.Visible;
            HeaderAuthenticationStateText.Text = _authenticationExpired
                ? "登录已失效"
                : "当前为浏览模式";
            HeaderFriendCenterButton.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            HeaderInboxButton.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            HeaderAvatarHost.Visibility = Visibility.Visible;
            HeaderProfileMenuItem.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            HeaderAccountSafetyMenuItem.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            HeaderMyReportsMenuItem.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            PersonalAccountSafetyButton.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            HeaderLoginMenuItem.Header = IsLoggedIn ? "切换账号" : "登录 / 注册";
            HeaderLogoutMenuItem.Visibility = IsLoggedIn
                ? Visibility.Visible
                : Visibility.Collapsed;
            RefreshOverlayLocalModeNoticeVisibility();

            if (!IsLoggedIn)
            {
                HeaderAccountMenuNameText.Text = "星海舰桥访客";
                HeaderAccountMenuStateText.Text = _authenticationExpired
                    ? "登录已失效 · 可重新登录"
                    : "浏览模式 · 可配置 Game.log";
            }

            RefreshHeaderAvatarPresenceDot();

            if (IsLoggedIn)
            {
                var maskedAccount = MaskAccountForDisplay(_accountName);
                HeaderAccountMenuNameText.Text = GetPersonalDisplayName();
                HeaderAccountMenuStateText.Text = string.IsNullOrWhiteSpace(maskedAccount)
                    ? "已登录"
                    : $"{maskedAccount} · 已登录";
                AccountNameText.Text = GetPersonalDisplayName();
                AccountModeText.Text = _syncPrivacySettings.PresenceVisibilityMode switch
                {
                    PlayerPresenceVisibilityMode.Invisible => "隐身模式：可浏览在线内容，不上传即时状态",
                    PlayerPresenceVisibilityMode.Offline => "离线模式：即时同步已暂停，游玩时长仅在本地记录",
                    _ => "已连接星海舰桥服务器，可同步舰队与玩家状态"
                };
                LoginButton.Content = "切换账号";
                LogoutButton.IsEnabled = true;
                LoginStatusText.Text = string.IsNullOrWhiteSpace(maskedAccount)
                    ? "已登录"
                    : $"{maskedAccount} · 已登录";
                CallsignBox.IsReadOnly = false;
                CallsignBox.IsEnabled = true;
                CallsignBox.Text = _callsign ?? "";
                EmailNotificationsCheck.IsEnabled = !FleetActionFeatureSettingsLocked;
                EmailNotificationsCheck.IsChecked = _allowEmailNotifications;
                ChooseAvatarButton.IsEnabled = true;
                OpenHangarReaderButton.IsEnabled = true;
                ClearShipDatabaseButton.IsEnabled = true;
                RenderCachedIdentity();
                LoadAvatarPreview();
                LoadOwnedShips();
                return;
            }

            AccountNameText.Text = _authenticationExpired ? GetPersonalDisplayName() : "访客模式";
            AccountModeText.Text = _authenticationExpired
                ? "登录已失效，本地资料已保留；重新登录后恢复同步"
                : "只能浏览，无法同步或管理舰队";
            LoginButton.Content = "登录 / 注册";
            LogoutButton.IsEnabled = false;
            LoginStatusText.Text = _authenticationExpired ? "登录已失效" : "未登录";
            CallsignBox.IsReadOnly = true;
            CallsignBox.IsEnabled = false;
            CallsignBox.Text = _authenticationExpired ? _callsign ?? "" : "";
            EmailNotificationsCheck.IsEnabled = false;
            EmailNotificationsCheck.IsChecked = false;
            GameNameText.Text = _authenticationExpired && !string.IsNullOrWhiteSpace(_localPlayer)
                ? _localPlayer
                : "请登录后查看";
            PlayerIdText.Text = _authenticationExpired && !string.IsNullOrWhiteSpace(_localPlayerId)
                ? _localPlayerId
                : "请登录后查看";
            ProfileStatusText.Text = _authenticationExpired ? "离线资料" : "浏览模式";
            ChooseAvatarButton.IsEnabled = false;
            OpenHangarReaderButton.IsEnabled = false;
            ClearShipDatabaseButton.IsEnabled = false;
            LoadAvatarPreview();
            LoadOwnedShips();
        }
        finally
        {
            _isRefreshingAccountPanel = false;
            RefreshBridgeShellAccountState();
            RefreshHeaderStatusBar();
        }
    }

    private void RefreshPersonalIdentityConsole()
    {
        if (PersonalMaskedEmailText is null)
        {
            return;
        }

        var mutedBrush = FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
        var normalBrush = FindBrush("PrimaryTextBrush", Brushes.AliceBlue);
        var successBrush = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        var warningBrush = FindBrush("StatusWarningBrush", Brushes.Orange);

        var maskedAccount = MaskAccountForDisplay(_accountName);
        PersonalMaskedEmailText.Text = IsLoggedIn && !string.IsNullOrWhiteSpace(maskedAccount)
            ? maskedAccount
            : "未登录";
        PersonalDisplayNameText.Text = !string.IsNullOrWhiteSpace(_callsign)
            ? _callsign!
            : GetPersonalDisplayName();
        PersonalLoginStateText.Text = IsLoggedIn ? "已登录" : "未登录";
        PersonalLoginStateText.Foreground = IsLoggedIn ? successBrush : mutedBrush;
        PersonalHeaderBindingText.Text = GetIdentityBindingSummaryText();
        PersonalHeaderBindingText.Foreground = CanSynchronizeUserData
            ? successBrush
            : warningBrush;

        PersonalGameProcessText.Text = _isGameProcessRunning ? "运行中" : "未检测到游戏进程";
        PersonalGameProcessText.Foreground = _isGameProcessRunning ? successBrush : warningBrush;
        if (ProfileStatusText is not null)
        {
            ProfileStatusText.Text = !IsLoggedIn
                ? "未登录"
                : PlayerPresencePresentation.FormatLocal(
                    _localPresence,
                    _syncPrivacySettings.PresenceVisibilityMode,
                    _language);
            ProfileStatusText.Foreground = !IsLoggedIn
                ? mutedBrush
                : PlayerPresencePresentation.LocalBrush(
                    _localPresence,
                    _syncPrivacySettings.PresenceVisibilityMode);
        }

        PersonalServerRegionText.Text = GetGameServerRegionDisplay();
        PersonalServerRegionText.Foreground = IsGameServerRegionCurrent() ? successBrush : mutedBrush;
        PersonalShardText.Text = IsGameServerRegionCurrent()
            ? _gameServerShard
            : _isGameProcessRunning ? "等待 Join PU" : "未连接";
        PersonalShardText.Foreground = IsGameServerRegionCurrent() ? normalBrush : mutedBrush;

        var local = string.IsNullOrWhiteSpace(_localPlayer)
            ? null
            : _players.FirstOrDefault(player => player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        var rawShip = local?.RawShip ?? local?.Ship;
        var formattedShip = string.IsNullOrWhiteSpace(rawShip)
            ? null
            : FormatShipForUser(rawShip);
        PersonalCurrentShipText.Text = PlayerSessionStatePresentation.ResolveShip(
            _localPresence,
            _localPresence == PlayerPresenceKind.InGame && IsGameServerRegionCurrent(),
            formattedShip);

        PersonalOverlayStatusText.Text = IsOverlayRunning ? "已开启" : "未开启";
        PersonalOverlayStatusText.Foreground = IsOverlayRunning ? successBrush : mutedBrush;
        PersonalOverlayHotkeyText.Text = string.IsNullOrWhiteSpace(OverlayHotkeyBox.Text) ? "未设置" : OverlayHotkeyBox.Text;
        PersonalOverlayModeText.Text = GetOverlayPresetDisplayName(_activeOverlayPreset);
        PersonalOverlayTrayModeText.Text = _overlaySettings.EnableTrayMode ? "已启用" : "未启用";
        PersonalOverlayTrayModeText.Foreground = _overlaySettings.EnableTrayMode ? successBrush : mutedBrush;

        PersonalConfigPathText.Text = DesktopAppConfig.ConfigDirectory;
        PersonalCachePathText.Text = GetLocalImageCacheDirectory();
        PersonalVersionText.Text = GetAppVersion();
        PersonalServerAddressText.Text = NormalizeNetworkServerUrl(NetworkServerUrlBox.Text);

        PersonalRightAccountText.Text = IsLoggedIn ? "已登录" : "未登录";
        PersonalRightAccountText.Foreground = IsLoggedIn ? successBrush : mutedBrush;
        PersonalRightLogText.Text = string.IsNullOrWhiteSpace(_logPath)
            ? "未选择"
            : File.Exists(_logPath) ? "已连接" : "路径待确认";
        PersonalRightLogText.Foreground = string.IsNullOrWhiteSpace(_logPath) ? mutedBrush : normalBrush;
        PersonalLogMonitorText.Text = GetPersonalLogMonitorText();
        PersonalLogMonitorText.Foreground = GetPersonalLogMonitorBrush(mutedBrush, normalBrush, successBrush, warningBrush);
        PersonalLogLastReadText.Text = _lastGameLogReadAt == DateTimeOffset.MinValue
            ? "无读取记录"
            : _lastGameLogReadAt.LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss", CultureInfo.CurrentCulture);
        PersonalLogLastReadText.Foreground = _lastGameLogReadAt == DateTimeOffset.MinValue ? mutedBrush : normalBrush;
        PersonalRightGameProcessText.Text = _isGameProcessRunning ? "运行中" : "未检测到游戏进程";
        PersonalRightGameProcessText.Foreground = _isGameProcessRunning ? successBrush : mutedBrush;
        PersonalRightServerText.Text = IsGameServerRegionCurrent()
            ? _gameServerRegion
            : _isGameProcessRunning ? "等待确认" : "未连接";
        PersonalRightServerText.Foreground = IsGameServerRegionCurrent() ? successBrush : mutedBrush;
        PersonalRightSyncText.Text = IsLoggedIn ? GetNetworkSyncStatusText() : "等待登录";
        PersonalRightSyncText.Foreground = IsLoggedIn ? successBrush : mutedBrush;
        RefreshPersonalRightEmailReminderStatus();
        PersonalRightOverlayText.Text = IsOverlayRunning ? "已开启" : "未开启";
        PersonalRightOverlayText.Foreground = IsOverlayRunning ? successBrush : mutedBrush;
        RefreshPersonalHeaderFleetCard();
        RefreshPersonalProfileHeaderIdentity();
        RefreshPersonalConnectionHealth(successBrush, warningBrush, mutedBrush);
    }

    private void RefreshPersonalRightEmailReminderStatus()
    {
        if (PersonalRightEmailText is null)
        {
            return;
        }

        var mutedBrush = FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
        var normalBrush = FindBrush("PrimaryTextBrush", Brushes.AliceBlue);
        var successBrush = FindBrush("StatusSuccessBrush", Brushes.SpringGreen);
        var warningBrush = FindBrush("StatusWarningBrush", Brushes.Orange);
        var accentBrush = FindBrush("AccentBrush", Brushes.DeepSkyBlue);

        var (text, foreground, dot) = ResolveEmailReminderStatus(
            normalBrush,
            successBrush,
            warningBrush,
            mutedBrush,
            accentBrush);

        PersonalRightEmailText.Text = text;
        PersonalRightEmailText.Foreground = foreground;
        if (PersonalRightEmailDot is not null)
        {
            PersonalRightEmailDot.Fill = dot;
        }
    }

    private (string Text, System.Windows.Media.Brush Foreground, System.Windows.Media.Brush Dot) ResolveEmailReminderStatus(
        System.Windows.Media.Brush normalBrush,
        System.Windows.Media.Brush successBrush,
        System.Windows.Media.Brush warningBrush,
        System.Windows.Media.Brush mutedBrush,
        System.Windows.Media.Brush accentBrush)
    {
        if (!IsLoggedIn)
        {
            return ("等待登录", mutedBrush, mutedBrush);
        }

        if (FleetActionFeatureSettingsLocked)
        {
            return ("开发中", mutedBrush, mutedBrush);
        }

        if (!_allowEmailNotifications ||
            !_notificationSettings.EnableEmailNotifications ||
            _notificationSettings.EmailHourlyLimit == 0)
        {
            return ("已关闭", mutedBrush, mutedBrush);
        }

        if (_notificationSettings.EmailOnlyCritical)
        {
            return (_notificationSettings.NotificationCooldownSeconds > 0
                ? $"冷却 {FormatNotificationCooldown(_notificationSettings.NotificationCooldownSeconds)} · {FormatEmailReminderLimitDetail()}"
                : FormatEmailReminderLimitDetail(), warningBrush, warningBrush);
        }

        if (_notificationSettings.NotificationCooldownSeconds > 0)
        {
            return ($"冷却 {FormatNotificationCooldown(_notificationSettings.NotificationCooldownSeconds)} · {FormatEmailReminderLimitDetail()}", normalBrush, accentBrush);
        }

        return ($"已开启 · {FormatEmailReminderLimitDetail()}", successBrush, successBrush);
    }

    private string FormatEmailReminderLimitDetail()
    {
        if (_notificationSettings.EmailHourlyLimit > 0)
        {
            return $"{_notificationSettings.EmailHourlyLimit} 封/小时";
        }

        return "邮件关闭";
    }

    private string GetPersonalLogMonitorText()
    {
        if (string.IsNullOrWhiteSpace(_logPath))
        {
            return "未选择";
        }

        if (!File.Exists(_logPath))
        {
            return "路径待确认";
        }

        return _watcher is null ? "已选择" : "监听中";
    }

    private System.Windows.Media.Brush GetPersonalLogMonitorBrush(
        System.Windows.Media.Brush mutedBrush,
        System.Windows.Media.Brush normalBrush,
        System.Windows.Media.Brush successBrush,
        System.Windows.Media.Brush warningBrush)
    {
        if (string.IsNullOrWhiteSpace(_logPath))
        {
            return mutedBrush;
        }

        if (!File.Exists(_logPath))
        {
            return warningBrush;
        }

        return _watcher is null ? normalBrush : successBrush;
    }

    private void RefreshPersonalConnectionHealth(
        System.Windows.Media.Brush successBrush,
        System.Windows.Media.Brush warningBrush,
        System.Windows.Media.Brush mutedBrush)
    {
        var hasIdentity = IsLoggedIn && !string.IsNullOrWhiteSpace(_localPlayer);
        SetHealthCheck(
            PersonalIdentityHealthResultText,
            PersonalIdentityHealthHintText,
            hasIdentity ? "正常" : "等待识别",
            hasIdentity
                ? "登录身份与识别玩家一致。"
                : "选择游戏日志并进入游戏后完成身份比对。",
            hasIdentity ? successBrush : mutedBrush);

        var logPathSelected = !string.IsNullOrWhiteSpace(_logPath);
        var logPathValid = logPathSelected && File.Exists(_logPath!);
        SetHealthCheck(
            PersonalLogHealthResultText,
            PersonalLogHealthHintText,
            logPathValid ? "正常" : "需要检查",
            logPathValid
                ? "游戏日志路径有效，正在读取最新内容。"
                : "请选择有效的 StarCitizen\\LIVE\\Game.log。",
            logPathValid ? successBrush : warningBrush);

        SetHealthCheck(
            PersonalGameHealthResultText,
            PersonalGameHealthHintText,
            _isGameProcessRunning ? "正常" : "等待游戏启动",
            _isGameProcessRunning
                ? "游戏进程已检测到，可继续确认服务器信息。"
                : "启动游戏后可识别服务器与飞船。",
            _isGameProcessRunning ? successBrush : warningBrush);

        var puReady = IsGameServerRegionCurrent();
        SetHealthCheck(
            PersonalPuHealthResultText,
            PersonalPuHealthHintText,
            puReady ? "正常" : "等待确认",
            puReady
                ? "已确认所在服务器、区域与当前会话信息。"
                : "进入服务器后显示所在服务器、区域与当前飞船。",
            puReady ? successBrush : warningBrush);

        SetHealthCheck(
            PersonalSyncPolicyHealthResultText,
            PersonalSyncPolicyHealthHintText,
            "正常",
            "仅同步允许公开的状态信息。",
            successBrush);
    }

    private static void SetHealthCheck(
        TextBlock resultText,
        TextBlock hintText,
        string result,
        string hint,
        System.Windows.Media.Brush resultBrush)
    {
        resultText.Text = result;
        resultText.Foreground = resultBrush;
        hintText.Text = hint;
    }

    private void PersonalRightSidebarScroll_SizeChanged(object sender, SizeChangedEventArgs e)
    {
        ApplyPersonalRightSidebarCompactMode(e.NewSize.Height < 1100);
        UpdatePersonalConsoleActivityVisibleItems();
    }

    private void ApplyPersonalRightSidebarCompactMode(bool compact)
    {
        if (PersonalAppStatusPanel is null ||
            _isPersonalRightSidebarCompact == compact)
        {
            return;
        }

        _isPersonalRightSidebarCompact = compact;

        var panelPadding = compact ? new Thickness(8) : new Thickness(14);
        var titleSize = compact ? 13 : 16;
        var firstItemTop = compact ? 6 : 12;
        var itemGap = compact ? 4 : 8;
        var buttonHeight = compact ? 28 : 30;

        PersonalAppStatusPanel.Padding = panelPadding;
        PersonalQuickActionsPanel.Padding = panelPadding;
        PersonalActivityPanel.Padding = panelPadding;
        PersonalAppStatusPanel.MinHeight = compact ? 104 : 150;
        PersonalQuickActionsPanel.MinHeight = compact ? 104 : 120;
        PersonalActivityPanel.MinHeight = compact ? 166 : 150;

        PersonalAppStatusTitleText.FontSize = titleSize;
        PersonalQuickActionsTitleText.FontSize = titleSize;
        PersonalActivityTitleText.FontSize = titleSize;

        SetButtonMetrics(PersonalQuickSelectLogButton, buttonHeight, new Thickness(0, firstItemTop, 0, 0));
        SetButtonMetrics(PersonalQuickReadHangarButton, buttonHeight, new Thickness(0, itemGap, 0, 0));
        SetButtonMetrics(PersonalQuickOverlayButton, buttonHeight, new Thickness(0, itemGap, 0, 0));

        PersonalActivityItemsScroll.Margin = new Thickness(0, firstItemTop, 0, 0);
        PersonalActivityItemsScroll.MaxHeight = compact ? 132 : 136;
        PersonalActivityLoginItem.Margin = new Thickness(0);
        PersonalActivityLogItem.Margin = new Thickness(0, itemGap, 0, 0);
        PersonalActivityHangarItem.Margin = new Thickness(0, itemGap, 0, 0);
        PersonalActivityOverlayItem.Margin = new Thickness(0, itemGap, 0, 0);
        PersonalActivityOverlayItem.Visibility = Visibility.Visible;
        UpdatePersonalConsoleActivityVisibleItems();
    }

    private void UpdatePersonalConsoleActivityVisibleItems()
    {
        if (PersonalConsoleRightSidebarScroll is null ||
            PersonalConsoleActivityPanel is null ||
            PersonalConsoleActivityItemsPanel is null)
        {
            return;
        }

        var availableHeight = PersonalConsoleRightSidebarScroll.ActualHeight;
        if (availableHeight <= 0)
        {
            return;
        }

        var usedHeight = 0d;
        var activityChrome = PersonalConsoleActivityPanel.Padding.Top +
                             PersonalConsoleActivityPanel.Padding.Bottom +
                             (PersonalConsoleActivityTitleText?.ActualHeight > 0 ? PersonalConsoleActivityTitleText.ActualHeight : 19) +
                             PersonalConsoleActivityItemsPanel.Margin.Top +
                             10;

        var visibleSidebarHeight = availableHeight;
        var contentGrid = PersonalConsoleActivityPanel.Parent as Grid;
        if (contentGrid is not null)
        {
            foreach (var child in contentGrid.Children.OfType<FrameworkElement>())
            {
                if (ReferenceEquals(child, PersonalConsoleActivityPanel))
                {
                    continue;
                }

                if (child.Visibility == Visibility.Visible)
                {
                    usedHeight += child.ActualHeight + child.Margin.Top + child.Margin.Bottom;
                }
            }
        }

        var availableForItems = visibleSidebarHeight - usedHeight - activityChrome - PersonalConsoleActivityPanel.Margin.Top - PersonalConsoleActivityPanel.Margin.Bottom;
        if (availableForItems >= 0 && availableForItems < PersonalConsoleActivityItemHeight)
        {
            availableForItems = PersonalConsoleActivityItemHeight;
        }

        var stride = PersonalConsoleActivityItemHeight + PersonalConsoleActivityItemGap;
        var visibleCount = (int)Math.Floor((availableForItems + PersonalConsoleActivityItemGap) / stride);
        visibleCount = Math.Clamp(visibleCount, PersonalConsoleActivityMinItems, PersonalConsoleActivityMaxItems);
        SetPersonalConsoleActivityVisibleCount(visibleCount);
    }

    private void SetPersonalConsoleActivityVisibleCount(int visibleCount)
    {
        var items = new Border?[]
        {
            PersonalConsoleActivityLoginItem,
            PersonalConsoleActivityLogItem,
            PersonalConsoleActivityHangarItem,
            PersonalConsoleActivityOverlayItem,
            PersonalConsoleActivityConfigItem
        };

        for (var index = 0; index < items.Length; index++)
        {
            if (items[index] is not { } item)
            {
                continue;
            }

            item.Height = PersonalConsoleActivityItemHeight;
            item.Margin = index == 0
                ? new Thickness(0)
                : new Thickness(0, PersonalConsoleActivityItemGap, 0, 0);
            item.Visibility = index < visibleCount ? Visibility.Visible : Visibility.Collapsed;
        }

        PersonalConsoleActivityPanel.MinHeight =
            PersonalConsoleActivityPanel.Padding.Top +
            PersonalConsoleActivityPanel.Padding.Bottom +
            (PersonalConsoleActivityTitleText?.ActualHeight > 0 ? PersonalConsoleActivityTitleText.ActualHeight : 19) +
            PersonalConsoleActivityItemsPanel.Margin.Top +
            visibleCount * PersonalConsoleActivityItemHeight +
            Math.Max(0, visibleCount - 1) * PersonalConsoleActivityItemGap;
    }

    private static void SetButtonMetrics(System.Windows.Controls.Button button, double height, Thickness margin)
    {
        button.Height = height;
        button.Margin = margin;
    }

    private string GetPersonalDisplayName()
    {
        if (!string.IsNullOrWhiteSpace(_callsign))
        {
            return _callsign!;
        }

        if (!string.IsNullOrWhiteSpace(_localPlayer))
        {
            return _localPlayer!;
        }

        return IsLoggedIn ? "星海舰桥账号" : "访客模式";
    }

    private static string MaskAccountForDisplay(string? account)
    {
        if (string.IsNullOrWhiteSpace(account))
        {
            return string.Empty;
        }

        var trimmed = account.Trim();
        var atIndex = trimmed.IndexOf('@');
        if (atIndex <= 0 || atIndex == trimmed.Length - 1)
        {
            return trimmed;
        }

        var local = trimmed[..atIndex];
        var visibleLocal = local.Length <= 4
            ? local[..1]
            : local[..Math.Min(local.Length, 4)];
        return $"{visibleLocal}****{trimmed[atIndex..]}";
    }

    private void NavigateToMyFleet()
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        var previousTab = MainTabs.SelectedItem;
        var previousSection = FleetSubTabs.SelectedItem;
        MainTabs.SelectedItem = FleetTab;
        FleetSubTabs.SelectedItem = AllPlayersTab;
        UpdateFleetEntryPanels();
        RefreshFleetMainContentView();
        SetActiveNav(MyFleetNavButton);
        if (!ReferenceEquals(previousTab, MainTabs.SelectedItem))
        {
            QueueMainPageReveal(previousTab);
        }
        else if (!ReferenceEquals(previousSection, FleetSubTabs.SelectedItem))
        {
            QueueFleetSectionReveal();
        }
    }

    private void FleetFindButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        MainTabs.SelectedItem = FindFleetTab;
        SetActiveNav(FindFleetNavButton);
    }

    private void FleetCreateButton_Click(object sender, RoutedEventArgs e)
    {
        if (!TryLeaveOverlayEditorTab())
        {
            return;
        }

        if (!EnsureLoggedIn("创建组织需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("创建组织"))
        {
            return;
        }

        _isCreatingFleet = true;
        MainTabs.SelectedItem = FleetTab;
        SetActiveNav(MyFleetNavButton);
        UpdateFleetEntryPanels();
        PrepareCreateFleetDefaults();
        LoadCreateFleetLogoPreview();
        LoadCreateFleetBannerPreview();
        CreateFleetNameBox.Focus();
    }

    private void CreateFleetCancel_Click(object sender, RoutedEventArgs e)
    {
        if (!_hasFleet)
        {
            _createFleetLogoPath = null;
            _fleetBannerPath = null;
            _fleetBannerSourcePath = null;
            LoadCreateFleetLogoPreview();
            LoadCreateFleetBannerPreview();
            LoadFleetHeaderBannerPreview();
            SaveCurrentConfig();
        }

        _isCreatingFleet = false;
        UpdateFleetEntryPanels();
    }

    private async void CreateFleetSubmit_Click(object sender, RoutedEventArgs e)
    {
        if (!EnsureLoggedIn("创建组织需要先登录星海舰桥账号。"))
        {
            return;
        }

        if (!EnsureIdentityInitialized("创建组织"))
        {
            return;
        }

        if (!ValidateCreateFleetForm())
        {
            return;
        }

        var selectedLogoPath = _createFleetLogoPath;
        var normalizedName = CreateFleetNameBox.Text.Trim();
        var normalizedCode = NormalizeCreateFleetCode(CreateFleetCodeBox.Text);
        var activeFrom = NormalizeFleetActivityClockText(CreateFleetOnlineFromBox.Text, DefaultFleetActivityStartTime);
        var activeTo = NormalizeFleetActivityClockText(CreateFleetOnlineToBox.Text, DefaultFleetActivityEndTime);
        var selectedTagIds = GetCreateFleetSelectedTagIds();
        var selectedSystemIds = GetCreateFleetSelectedSystemIds();

        if (!string.IsNullOrWhiteSpace(selectedLogoPath) &&
            !ValidateRequiredFleetImagePayload("舰队标志", selectedLogoPath, FleetSyncImageMaxBytes))
        {
            CreateFleetValidationText.Text = "所选舰队标志无法用于同步，请重新选择图片。";
            return;
        }

        CreateFleetCodeBox.Text = normalizedCode;
        CreateFleetSubmitButton.IsEnabled = false;
        _isCreatingFleet = true;
        _fleetName = normalizedName;
        _fleetCode = normalizedCode;
        _fleetChiefCommander = FormatCommanderName(_callsign, _localPlayer);
        _fleetDeputyCommander = "Unassigned";
        _fleetDescription = NormalizeFleetDescription(CreateFleetIntroBox.Text);
        _fleetType = BuildCreateFleetTypeSummary(selectedTagIds);
        _fleetJoinPolicy = GetCreateFleetJoinPolicy();
        _fleetLanguage = "zh-CN";
        _fleetTimeZoneId = GetCreateFleetTimeZoneId();
        _fleetActivityWindows.Clear();
        _fleetActivityWindows.Add(new FleetActivityWindowDraft(
            AllFleetActivityDayIds(),
            activeFrom,
            activeTo,
            ShouldFleetActivityEndNextDay(activeFrom, activeTo, false)));
        UpdateFleetActivitySummaries();
        SetManageProfileSelectedTagIds(selectedTagIds);
        SetSelectedFleetSystemIds(selectedSystemIds);
        _fleetRecruitingEnabled = !_fleetJoinPolicy.Equals("Invite", StringComparison.OrdinalIgnoreCase);
        _fleetRecruitingTarget = "所有玩家";
        _fleetPublicListingEnabled = true;
        _manageShowDescriptionPublic = true;
        _fleetPublicShowTags = true;
        _fleetPublicShowActiveSystems = true;
        _fleetPublicShowActivityTime = true;
        _fleetLogoPath = selectedLogoPath;
        _fleetEmailNotificationsEnabled = false;
        _fleetNoticeTitle = "";
        _fleetNoticeContent = "";
        _fleetNoticePublishedAt = null;
        ResetFleetAnnouncements();

        NetworkStatusText.Text = "正在创建组织并等待服务器确认...";
        CreateFleetValidationText.Text = "";
        var createSnapshot = BuildLocalFleetSnapshot(includeDirectoryImages: true, includeRepeatedImages: false);
        var confirmedFleet = await PushFleetDirectorySnapshotAsync(
            createSnapshot,
            silent: false,
            markPendingOnFailure: false);
        if (confirmedFleet is null)
        {
            _hasFleet = false;
            _isCreatingFleet = true;
            CreateFleetSubmitButton.IsEnabled = true;
            CreateFleetValidationText.Text = string.IsNullOrWhiteSpace(NetworkStatusText.Text)
                ? "创建组织失败：服务器没有确认组织数据，请检查网络或稍后重试。"
                : NetworkStatusText.Text.Replace("发布舰队失败", "创建组织失败", StringComparison.Ordinal);
            UpdateFleetEntryPanels();
            return;
        }

        _hasFleet = true;
        _isCreatingFleet = false;
        MarkFleetMembershipChanged();
        _fleetDirectorySyncPending = false;
        _createFleetLogoPath = null;
        CreateFleetSubmitButton.IsEnabled = true;
        MergeNetworkFleetState(confirmedFleet);
        LocalFleetText.Text = $"{_fleetName} [{_fleetCode}]";
        RefreshFleetHeader();
        UpdateFleetEntryPanels();
        SaveCurrentConfig();

        var pushedLocal = await PushLocalSnapshotAsync(silent: true, pushFleetDirectory: false);
        await PullNetworkFleetsAsync(silent: true);

        NetworkStatusText.Text = pushedLocal
            ? "舰队已创建并同步。"
            : "舰队已创建，正在同步本机状态。";
        ShowOneTimeGuideHint(
            "fleet-created-commander",
            "组织负责人引导",
            "舰队已经创建。下一步建议前往“管理舰队”设置公告、行动计划、任务、成员权限和舰船数据库，再邀请成员加入。");
    }

    private void RollBackFailedFleetCreate(string? selectedLogoPath, string failureText)
    {
        _hasFleet = false;
        _isCreatingFleet = true;
        _fleetJoinedAtUtc = DateTimeOffset.MinValue;
        _fleetDirectorySyncPending = false;
        _fleetMembershipChangedAtUtc = DateTimeOffset.MinValue;
        _lastFleetDirectorySyncAttemptAtUtc = DateTimeOffset.MinValue;
        _fleetName = "No Fleet";
        _fleetCode = "N/A";
        _fleetChiefCommander = "Unassigned";
        _fleetDeputyCommander = "Unassigned";
        _fleetDescription = "";
        _fleetType = "Combat";
        _fleetJoinPolicy = "Open";
        _fleetActiveTime = DefaultFleetActiveTimeText;
        _fleetLogoPath = null;
        _fleetBannerPath = null;
        _fleetBannerSourcePath = null;
        _fleetEmailNotificationsEnabled = true;
        _createFleetLogoPath = selectedLogoPath;
        LocalFleetText.Text = "未加入组织";
        CreateFleetValidationText.Text = string.IsNullOrWhiteSpace(failureText)
            ? "创建失败：服务器没有确认舰队创建。请检查登录状态和网络连接后重试。"
            : failureText;
        RefreshFleetHeader();
        UpdateFleetEntryPanels();
        LoadCreateFleetLogoPreview();
        LoadCreateFleetBannerPreview();
        RenderState();
        RefreshOverlayWindow();
    }

    private void CreateFleetField_TextChanged(object sender, TextChangedEventArgs e)
    {
        if (CreateFleetValidationText is null)
        {
            return;
        }

        ValidateCreateFleetForm(showRequiredErrors: false);
    }

    private void CreateFleetField_SelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (CreateFleetValidationText is null)
        {
            return;
        }

        ValidateCreateFleetForm(showRequiredErrors: false);
    }

    private void PrepareCreateFleetDefaults()
    {
        if (CreateFleetTimeZoneBox is not null)
        {
            if (_fleetTimeZoneOptions.Count == 0)
            {
                LoadFleetTimeZoneOptions();
            }

            if (!ReferenceEquals(CreateFleetTimeZoneBox.ItemsSource, _fleetTimeZoneOptions))
            {
                CreateFleetTimeZoneBox.ItemsSource = _fleetTimeZoneOptions;
            }

            if (CreateFleetTimeZoneBox.SelectedValue is null)
            {
                var localTimeZoneId = TimeZoneInfo.Local.Id;
                var selectedOption = _fleetTimeZoneOptions.FirstOrDefault(option =>
                                         option.Id.Equals(localTimeZoneId, StringComparison.OrdinalIgnoreCase)) ??
                                     FindFleetTimeZoneOptionBySameOffset(localTimeZoneId) ??
                                     _fleetTimeZoneOptions.FirstOrDefault(option =>
                                         option.Id.Equals("China Standard Time", StringComparison.OrdinalIgnoreCase)) ??
                                     _fleetTimeZoneOptions.FirstOrDefault();

                if (selectedOption is not null)
                {
                    CreateFleetTimeZoneBox.SelectedValue = selectedOption.Id;
                }
            }
        }

        if (CreateFleetLanguageBox is not null && CreateFleetLanguageBox.SelectedIndex < 0)
        {
            CreateFleetLanguageBox.SelectedIndex = 0;
        }

        RefreshCreateFleetSelectedTags();
    }

    private void RefreshAuthenticationRequiredViews()
    {
        var visibility = IsLoggedIn
            ? Visibility.Collapsed
            : Visibility.Visible;

        if (FindFleetLoginRequiredPanel is not null)
        {
            FindFleetLoginRequiredPanel.Visibility = visibility;
        }

        if (FleetLoginRequiredPanel is not null)
        {
            FleetLoginRequiredPanel.Visibility = visibility;
        }

        if (PartyLobbyLoginRequiredPanel is not null)
        {
            PartyLobbyLoginRequiredPanel.Visibility = visibility;
        }
    }

    private void UpdateFleetEntryPanels()
    {
        RefreshAuthenticationRequiredViews();

        if (FleetEmptyPanel is null || FleetCreatePanel is null)
        {
            return;
        }

        FleetCreatePanel.Visibility = IsLoggedIn && !_hasFleet && _isCreatingFleet
            ? Visibility.Visible
            : Visibility.Collapsed;
        FleetEmptyPanel.Visibility = IsLoggedIn && !_hasFleet && !_isCreatingFleet
            ? Visibility.Visible
            : Visibility.Collapsed;

        if (FleetSubTabs is not null)
        {
            FleetSubTabs.Visibility = IsLoggedIn && _hasFleet
                ? Visibility.Visible
                : Visibility.Collapsed;
        }

        RefreshOverlayWindow();
    }

    private bool ValidateCreateFleetForm(bool showRequiredErrors = true)
    {
        var name = CreateFleetNameBox.Text.Trim();
        var code = NormalizeCreateFleetCode(CreateFleetCodeBox.Text);
        var activeFrom = CreateFleetOnlineFromBox.Text.Trim();
        var activeTo = CreateFleetOnlineToBox.Text.Trim();
        var nameValid = IsRsiFleetNameText(name);
        var codeValid = IsRsiFleetIdentifierText(code);
        var activeFromValid = IsValidTime24(activeFrom);
        var activeToValid = IsValidTime24(activeTo);
        var selectedTagCount = GetCreateFleetSelectedTagIds().Length;
        var selectedSystemCount = GetCreateFleetSelectedSystemIds().Length;

        var message = "";
        if (showRequiredErrors && string.IsNullOrWhiteSpace(name))
        {
            message = "请输入舰队名称。";
        }
        else if (showRequiredErrors && string.IsNullOrWhiteSpace(code))
        {
            message = "请输入舰队简称。";
        }
        else if (!string.IsNullOrWhiteSpace(name) && !nameValid)
        {
            message = "舰队名称需为 4-32 位，仅允许英文、数字、空格、短横线和下划线。";
        }
        else if (!string.IsNullOrWhiteSpace(code) && !codeValid)
        {
            message = "组织识别码需为 3-10 位，仅允许大写英文和数字。";
        }
        else if (!activeFromValid || !activeToValid)
        {
            message = "活动时间段必须使用 24 小时制 HH:mm，例如 19:00 到 22:00。";
        }
        else if (selectedTagCount > MaxManageFleetTags)
        {
            message = $"组织标签最多选择 {MaxManageFleetTags.ToString(CultureInfo.InvariantCulture)} 个。";
        }
        else if (selectedSystemCount == 0)
        {
            message = "请至少选择一个主要活跃星系。";
        }

        CreateFleetValidationText.Text = message;
        return string.IsNullOrWhiteSpace(message) &&
               !string.IsNullOrWhiteSpace(name) &&
               !string.IsNullOrWhiteSpace(code) &&
               nameValid &&
               codeValid &&
               activeFromValid &&
               activeToValid &&
               selectedTagCount <= MaxManageFleetTags &&
               selectedSystemCount > 0;
    }

    private static string NormalizeCreateFleetCode(string? value) =>
        (value ?? string.Empty).Trim().ToUpperInvariant();

    private static bool IsRsiFleetNameText(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        value = value.Trim();
        return value.Length is >= 4 and <= 32 &&
               value.All(character =>
                   character is >= 'A' and <= 'Z' ||
                   character is >= 'a' and <= 'z' ||
                   character is >= '0' and <= '9' ||
                   character is '-' or '_' or ' ');
    }

    private static bool IsRsiFleetIdentifierText(string value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        value = NormalizeCreateFleetCode(value);
        return value.Length is >= 3 and <= 10 &&
               value.All(character =>
                   character is >= 'A' and <= 'Z' ||
                   character is >= '0' and <= '9');
    }

    private string GetCreateFleetJoinPolicy()
    {
        return FindVisualChildren<System.Windows.Controls.RadioButton>(this)
                   .FirstOrDefault(radio => radio.GroupName == "FleetJoinPolicy" && radio.IsChecked == true)
                   ?.Tag
                   ?.ToString() ??
               "Open";
    }

    private string GetCreateFleetTimeZoneId()
    {
        return CreateFleetTimeZoneBox?.SelectedValue?.ToString()
               ?? TimeZoneInfo.Local.Id;
    }

    private string[] GetCreateFleetSelectedTagIds()
    {
        var tagIds = _createFleetSelectedTagIds
            .Where(IsKnownFleetTagId)
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(MaxManageFleetTags)
            .ToArray();

        return tagIds;
    }

    private string[] GetCreateFleetSelectedSystemIds()
    {
        var systemIds = new[]
            {
                CreateFleetSystemStantonCheck,
                CreateFleetSystemPyroCheck,
                CreateFleetSystemNyxCheck
            }
            .Where(checkBox => checkBox?.IsChecked == true)
            .Select(checkBox => checkBox?.Tag?.ToString() ?? "")
            .Where(id => AllowedFleetSystemAssets.Any(system =>
                system.Id.Equals(id, StringComparison.OrdinalIgnoreCase)))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();

        return systemIds.Length == 0
            ? ["stanton"]
            : systemIds;
    }

    private static string BuildCreateFleetTypeSummary(IEnumerable<string> tagIds)
    {
        return FleetProfilePayloadBuilder.BuildTagSummary(
            tagIds,
            id => FleetTagDefinitions.FirstOrDefault(tag =>
                tag.Id.Equals(id, StringComparison.OrdinalIgnoreCase))?.Name,
            MaxManageFleetTags);
    }

    private static bool IsEnglishFleetText(string value, bool allowSpaces)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return true;
        }

        return value.All(character =>
            character is >= 'A' and <= 'Z' ||
            character is >= 'a' and <= 'z' ||
            character is >= '0' and <= '9' ||
            character is '-' or '_' ||
            allowSpaces && character == ' ');
    }

    private static bool IsValidTime24(string value)
    {
        if (value.Length != 5 || value[2] != ':')
        {
            return false;
        }

        return int.TryParse(value[..2], out var hour) &&
               int.TryParse(value[3..], out var minute) &&
               hour is >= 0 and <= 23 &&
               minute is >= 0 and <= 59;
    }

    private string? GetSelectedRadioContent(string groupName)
    {
        return FindVisualChildren<System.Windows.Controls.RadioButton>(this)
            .FirstOrDefault(radio => radio.GroupName == groupName && radio.IsChecked == true)
            ?.Content
            ?.ToString();
    }

    private static IEnumerable<T> FindVisualChildren<T>(DependencyObject parent)
        where T : DependencyObject
    {
        if (parent is null)
        {
            yield break;
        }

        for (var index = 0; index < VisualTreeHelper.GetChildrenCount(parent); index++)
        {
            var child = VisualTreeHelper.GetChild(parent, index);
            if (child is T typedChild)
            {
                yield return typedChild;
            }

            foreach (var descendant in FindVisualChildren<T>(child))
            {
                yield return descendant;
            }
        }
    }

    private void SetActiveNav(System.Windows.Controls.Button? activeButton)
    {
        UiMotion.ApplyNavigationSelection(
            [
                FindFleetNavButton,
                MyFleetNavButton,
                MySquadNavButton,
                OverlayNavButton,
                PersonalNavButton,
                HeaderSettingsButton,
                HeaderFriendCenterButton
            ],
            activeButton);

        var routeTarget = activeButton switch
        {
            _ when ReferenceEquals(activeButton, FindFleetNavButton) => FindFleetNavButton,
            _ when ReferenceEquals(activeButton, MyFleetNavButton) => MyFleetNavButton,
            _ when ReferenceEquals(activeButton, MySquadNavButton) => MySquadNavButton,
            _ when ReferenceEquals(activeButton, OverlayNavButton) => OverlayNavButton,
            _ => null
        };
        UiMotion.MoveRouteSignal(MainNavigationHost, MainNavigationRouteSignal, routeTarget);
    }

    protected override void OnClosed(EventArgs e)
    {
        _gameplayStatisticsRecorder.Stop(DateTimeOffset.UtcNow);
        _locationDataContributionSyncTimer.Stop();
        if (_isOverlayEditorFullScreen)
        {
            ExitOverlayEditorFullScreen();
        }

        _inGameMenuCoordinator.Dispose();
        _inGameMenuCoordinator.ActionRequested -= InGameMenuCoordinator_ActionRequested;
        _inGameMenuCoordinator.Closed -= InGameMenuCoordinator_Closed;
        _inGameMenuCoordinator.SocialRefreshRequested -= InGameMenuCoordinator_SocialRefreshRequested;
        _inGameMenuCoordinator.SocialConversationRequested -= InGameMenuCoordinator_SocialConversationRequested;
        _inGameMenuCoordinator.SocialChannelRequested -= InGameMenuCoordinator_SocialChannelRequested;
        _inGameMenuCoordinator.SocialMessageRequested -= InGameMenuCoordinator_SocialMessageRequested;
        _inGameMenuCoordinator.SocialAttachmentRequested -= InGameMenuCoordinator_SocialAttachmentRequested;
        _inGameMenuCoordinator.ChatAttachmentActionRequested -= InGameMenuCoordinator_ChatAttachmentActionRequested;
        _inGameMenuCoordinator.FriendSearchRequested -= InGameMenuCoordinator_FriendSearchRequested;
        _inGameMenuCoordinator.FriendActionRequested -= InGameMenuCoordinator_FriendActionRequested;
        _inGameMenuCoordinator.FriendPresenceChanged -= InGameMenuCoordinator_FriendPresenceChanged;
        _inGameMenuCoordinator.ProfileRequested -= InGameMenuCoordinator_ProfileRequested;
        _inGameMenuCoordinator.RoomRefreshRequested -= InGameMenuCoordinator_RoomRefreshRequested;
        _inGameMenuCoordinator.RoomJoinRequested -= InGameMenuCoordinator_RoomJoinRequested;
        _inGameMenuCoordinator.RoomCreateRequested -= InGameMenuCoordinator_RoomCreateRequested;
        _inGameMenuCoordinator.RoomLeaveRequested -= InGameMenuCoordinator_RoomLeaveRequested;
        _inGameMenuCoordinator.RoomMessageRequested -= InGameMenuCoordinator_RoomMessageRequested;
        _inGameMenuCoordinator.RoomAttachmentRequested -= InGameMenuCoordinator_RoomAttachmentRequested;
        _inGameMenuCoordinator.RoomInvitationActionRequested -= InGameMenuCoordinator_RoomInvitationActionRequested;
        UnregisterOverlayHotkey();
        _gameCompatibleHotkeyListener.Dispose();
        _hotkeySource?.RemoveHook(MainWindowProc);
        _hotkeySource = null;
        CloseOverlayWindow();
        _watcher?.Dispose();
        InputManager.Current.PreProcessInput -= TrackAppInteraction;
        _gameProcessTimer.Stop();
        StopNetworkSyncTimers();
        _profileSyncDebounceTimer.Stop();
        _fleetClockTimer.Stop();
        _relayLatencyTimer.Stop();
        _relayRecoveryNoticeCts?.Cancel();
        _relayRecoveryNoticeCts?.Dispose();
        _relayRecoveryNoticeCts = null;
        _appStatsTimer.Stop();
        DisposeFriendCenter();
        DisposeFleetChat();
        DisposePlayerActivityDesktopNotifications();
        base.OnClosed(e);
    }

    protected override void OnPreviewKeyDown(System.Windows.Input.KeyEventArgs e)
    {
        if (FleetShipDetailsOverlay.Visibility == Visibility.Visible && e.Key == Key.Escape)
        {
            CloseFleetShipDetailsOverlay();
            e.Handled = true;
            return;
        }

        if (_isOverlayEditorFullScreen && e.Key == Key.Escape)
        {
            if (!TryExitOverlayEditorFullScreen())
            {
                e.Handled = true;
                return;
            }

            ApplyOverlayEditorChromeState();
            RenderOverlayEditor();
            e.Handled = true;
            return;
        }

        base.OnPreviewKeyDown(e);
    }

    private void SelectLog_Click(object sender, RoutedEventArgs e)
    {
        var dialog = new OpenFileDialog
        {
            Title = "Select Star Citizen Game.log",
            Filter = "Star Citizen Game.log|Game.log|Log files (*.log)|*.log|All files (*.*)|*.*",
            CheckFileExists = true
        };

        if (dialog.ShowDialog(this) != true)
        {
            return;
        }

        if (StartWatching(dialog.FileName))
        {
            NotifyGuidedTourAction(GuideStep.SelectLog);
        }
    }

    private void QuickScanLog_Click(object sender, RoutedEventArgs e)
    {
        if (QuickScanLogAndStart())
        {
            NotifyGuidedTourAction(GuideStep.SelectLog);
        }
    }

    private bool QuickScanLogAndStart()
    {
        var logPath = IdentityInitialization.FindDefaultGameLog();
        if (string.IsNullOrWhiteSpace(logPath))
        {
            NetworkStatusText.Text = "快速扫描未找到 Game.log";
            RefreshOnboardingSupportPanel();

            var dialog = new GuideHintWindow(
                "未找到 Game.log",
                "没有在各磁盘的 StarCitizen\\LIVE\\Game.log 找到日志。请确认游戏安装位置，或点击“选择日志”手动选择。")
            {
                Owner = this
            };
            dialog.ShowDialog();
            return false;
        }

        if (!StartWatching(logPath))
        {
            return false;
        }

        NetworkStatusText.Text = $"已扫描到 Game.log：{logPath}";
        RefreshOnboardingSupportPanel();
        RefreshHeaderStatusBar();
        return true;
    }

    private bool StartWatching(string logPath)
    {
        var validation = LogFileSelectionGuard.ValidateGameLogPath(logPath);
        if (!validation.IsValid)
        {
            NetworkStatusText.Text = validation.Status;
            AppendOutput(validation.Status);
            RefreshOnboardingSupportPanel();
            RefreshHeaderStatusBar();

            var dialog = new GuideHintWindow(validation.Title, validation.Detail)
            {
                Owner = this
            };
            dialog.ShowDialog();
            return false;
        }

        _watcher?.Dispose();
        _logPath = logPath;
        LogPathBox.Text = logPath;
        SaveCurrentConfig(clearSavedSession: true);
        ClearGameServerRegion();
        AppendOutput($"正在读取日志：{Path.GetFileName(logPath)}");

        _quantumTravelContext.Reset();
        QuantumTravelLogRecovery.ReplayInto(
            _quantumTravelContext,
            logPath,
            QuantumContextReplayMaxBytes,
            QuantumContextReplayMaxLines);

        foreach (var line in GameLogInitialReplayReader.ReadTailLines(logPath, InitialGameLogReplayMaxBytes, InitialGameLogReplayMaxLines))
        {
            var fleetEvent = _parser.TryParse(line);
            if (fleetEvent is not null || CouldUpdateGameServerFromLine(line))
            {
                ApplyLine(line, output: false, fleetEvent);
            }
        }

        RenderState();
        RefreshOnboardingSupportPanel();
        RefreshHeaderStatusBar();

        _watcher = new GameLogWatcher(logPath, replayExistingLines: false, line =>
        {
            var fleetEvent = _parser.TryParse(line);
            if (fleetEvent is null && !CouldUpdateGameServerFromLine(line))
            {
                return;
            }

            Dispatcher.BeginInvoke(
                () => ApplyLine(line, output: true, fleetEvent),
                DispatcherPriority.Background);
        });
        _watcher.Start();
        StartLocationHistoryScanIfAllowed();
        _ = RefreshGameServerFromLogSnapshotAfterStartAsync();
        return true;
    }

    private async Task RefreshGameServerFromLogSnapshotAfterStartAsync()
    {
        await Dispatcher.Yield(DispatcherPriority.Background);

        try
        {
            var result = await RefreshGameServerFromLogSnapshotAsync();
            if (!result.Changed)
            {
                return;
            }

            RefreshHeaderStatusBar();
            RefreshPersonalIdentityConsole();
            RenderState();

            if (result.Found || result.Cleared)
            {
                AppendOutput(result.Message);
            }
        }
        catch (Exception ex)
        {
            AppendOutput($"Startup game server refresh skipped: {ex.Message}");
        }
    }

    private void ApplyLine(string line, bool output, FleetEvent? parsedFleetEvent = null)
    {
        _lastGameLogReadAt = DateTimeOffset.Now;
        var gameServerChanged = TryUpdateGameServerFromLine(line, output);
        var fleetEvent = parsedFleetEvent ?? _parser.TryParse(line);
        if (fleetEvent is null)
        {
            if (gameServerChanged)
            {
                RefreshPersonalIdentityConsole();
                if (output)
                {
                    RecordLocalGameServerEvent();
                }
                RefreshHeaderStatusBar();
                if (output)
                {
                    AppendOutput(FormatGameServerChangeMessage());
                }

                QueueRealtimeNetworkSnapshotPush();
            }

            return;
        }

        if (fleetEvent.Player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase) &&
            !string.IsNullOrWhiteSpace(_localPlayer))
        {
            fleetEvent = fleetEvent with { Player = _localPlayer };
        }

        fleetEvent = FleetEventShipNormalizer.Normalize(fleetEvent);
        fleetEvent = _quantumTravelContext.Resolve(fleetEvent);
        ObserveLocationDataContribution(fleetEvent);
        var oneShotEvent = IsOneShotGameLogEvent(fleetEvent.Type);

        if (output && oneShotEvent && IsLocalPlayer(fleetEvent.Player))
        {
            BindGameplayStatisticsOwner();
            RefreshGameplayStatisticsPresentation();
            CaptureSharedLifeEvent(fleetEvent);
        }

        if (!oneShotEvent && fleetEvent.Type == FleetEventType.PlayerOnline)
        {
            ObserveDetectedGameIdentity(fleetEvent.Player);
            _localPlayerId = fleetEvent.PlayerId;
            BindGameplayStatisticsOwner();
            if (IsLoaded)
            {
                ShowGameplayDataConsentIfNeeded();
            }
            if (IsLoggedIn)
            {
                GameNameText.Text = _localPlayer;
                PlayerIdText.Text = string.IsNullOrWhiteSpace(_localPlayerId)
                    ? "Unknown"
                    : _localPlayerId;
                ProfileStatusText.Text = "游戏中";
            }
            SaveCurrentConfig();
            LoadOwnedShips();
            RefreshOnboardingSupportPanel();
            RefreshHeaderStatusBar();
        }

        if (!oneShotEvent)
        {
            _fleetState.Apply(fleetEvent);
            RenderState();
            if (ShouldQueueRealtimeNetworkSnapshotPush(fleetEvent, gameServerChanged))
            {
                QueueRealtimeNetworkSnapshotPush();
            }
        }

        RefreshPersonalIdentityConsole();
        if (gameServerChanged)
        {
            RefreshHeaderStatusBar();
        }

        if (output)
        {
            RecordLocalGameLogEvent(fleetEvent);
            QueueOneShotGameLogEventNotification(fleetEvent);
            var userMessage = FormatLogEventForUser(fleetEvent);
            if (!string.IsNullOrWhiteSpace(userMessage))
            {
                AppendOutput(userMessage);
            }

            if (gameServerChanged)
            {
                RecordLocalGameServerEvent();
                AppendOutput(FormatGameServerChangeMessage());
            }
        }
    }

    private string FormatGameServerChangeMessage()
    {
        return IsGameServerRegionCurrent()
            ? $"游戏服务器：{_gameServerRegion} / {_gameServerShard}"
            : "已离开服务器，服务器信息已清空。";
    }

    private static bool IsOneShotGameLogEvent(FleetEventType eventType)
    {
        return eventType is FleetEventType.PlayerDowned
            or FleetEventType.PlayerDied
            or FleetEventType.PlayerRevived
            or FleetEventType.PlayerRespawned;
    }

    private void CaptureSharedLifeEvent(FleetEvent fleetEvent)
    {
        if (!_playerEventSharingSettings.Allows(PlayerSharedEventTypes.Life) ||
            !IsLocalPlayer(fleetEvent.Player) ||
            !CanPublishRealtimePlayerSync())
        {
            return;
        }

        var now = DateTimeOffset.UtcNow;
        _sharedLifeEvents.RemoveAll(sharedEvent => now - sharedEvent.OccurredAt > TimeSpan.FromMinutes(2));
        _sharedLifeEvents.Add(new NetworkPlayerSharedEventSnapshot(
            Guid.NewGuid().ToString("N"),
            fleetEvent.Type.ToString(),
            now));
        if (_sharedLifeEvents.Count > 8)
        {
            _sharedLifeEvents.RemoveRange(0, _sharedLifeEvents.Count - 8);
        }
        QueueRealtimeNetworkSnapshotPush();
    }

    private void QueueOneShotGameLogEventNotification(FleetEvent fleetEvent)
    {
        if (!IsOneShotGameLogEvent(fleetEvent.Type) ||
            _overlayWindow is null ||
            !_overlaySettings.ShowEventNotifications ||
            !OverlayGameEventNotificationPolicy.ShouldQueue(
                fleetEvent.Type,
                _overlaySettings.EventNotificationTypes))
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var player = FormatPlayerForUser(fleetEvent.Player);
        var notification = OverlayGameEventNotificationPolicy.Create(
            fleetEvent.Type,
            player,
            zh,
            fleetEvent.LifeContext);
        if (notification is null)
        {
            return;
        }

        _overlayWindow.QueueGameEventNotification(
            notification.EventType,
            notification.Title,
            notification.Detail,
            notification.Important,
            notification.Positive);
    }

    private void QueueLocalPlaySessionReminderIfDue(
        DateTimeOffset now,
        DateTimeOffset? gameProcessStartedAtUtc)
    {
        if (!_localPlaySessionReminder.Observe(_isGameProcessRunning, now, gameProcessStartedAtUtc) ||
            !_localPlayReminderSettings.Enabled ||
            _overlayWindow is not { IsVisible: true } ||
            !_overlaySettings.ShowEventNotifications ||
            !_overlaySettings.EventNotificationTypes.HasFlag(OverlayEventNotificationTypes.LocalPlayReminder))
        {
            return;
        }

        var zh = _language.Equals("zh", StringComparison.OrdinalIgnoreCase);
        var continuousPlayTime = _localPlaySessionReminder.GetContinuousPlayTime(now);
        var copy = LocalPlayReminderCopyCatalog.Pick(
            zh,
            DateTimeOffset.Now,
            continuousPlayTime,
            _lastLocalPlayReminderCopyIndex);
        _lastLocalPlayReminderCopyIndex = copy.Index;
        _overlayWindow.QueueGameEventNotification(
            OverlayEventNotificationTypes.LocalPlayReminder,
            LocalPlayReminderCopyCatalog.FormatDisplayTitle(copy.Title, continuousPlayTime, zh),
            copy.Detail,
            important: false,
            positive: true);
        _localPlaySessionReminder.MarkReminderShown(now);
    }

    private void RenderState()
    {
        RefreshLocalPresence(
            DateTimeOffset.UtcNow,
            refreshUi: false,
            queueNetworkPush: false);
        var localSharedPresence = GetLocalFleetPresencePrivacyProjection();
        if (!string.IsNullOrWhiteSpace(_localPlayer))
        {
            _fleetState.SetPlayerOnlineState(
                _localPlayer,
                PlayerPresence.IsOnline(_localPresence),
                DateTimeOffset.Now);
        }

        _fleetState.RefreshShipInferences(DateTimeOffset.Now);
        var nextPlayers = new List<PlayerRow>();
        var localServerShard = _localPresence == PlayerPresenceKind.InGame && IsGameServerRegionCurrent()
            ? _gameServerShard
            : null;

        foreach (var player in _fleetState.Players)
        {
            _networkSnapshots.TryGetValue(player.Name, out var networkSnapshot);
            var isLocalPlayer = networkSnapshot is not null
                ? IsLocalNetworkSnapshot(networkSnapshot)
                : !string.IsNullOrWhiteSpace(_localPlayer) &&
                  player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase);
            var displayPlayerName = isLocalPlayer
                ? _localPlayer ?? player.Name
                : networkSnapshot?.Name ?? player.Name;
            if (_hasFleet &&
                !isLocalPlayer &&
                networkSnapshot is not null &&
                !IsSameFleet(networkSnapshot.Fleet))
            {
                continue;
            }

            var liveStatus = isLocalPlayer
                ? PlayerPresence.ToWireValue(_localPresence)
                : NormalizeNetworkLiveStatus(networkSnapshot?.LiveStatus, player.Online);
            var presence = isLocalPlayer
                ? _localPresence
                : PlayerPresencePresentation.Resolve(liveStatus, player.Online ? "Online" : "Offline");
            var online = PlayerPresence.IsOnline(presence);
            var rawShip = ShipNameLocalizer.ResolveCode(player.Ship);
            var shipConfidence = player.ShipConfidence;
            var locationConfidence = player.LocationConfidence;
            var rawLocation = FormatRawLocation(player.Location, player.NavigationTarget);
            if (!isLocalPlayer && networkSnapshot is not null)
            {
                rawShip = ShipNameLocalizer.ResolveCode(networkSnapshot.Ship);
                shipConfidence = string.IsNullOrWhiteSpace(networkSnapshot.ShipConfidence)
                    ? "Low"
                    : networkSnapshot.ShipConfidence!;
                locationConfidence = string.IsNullOrWhiteSpace(networkSnapshot.LocationConfidence)
                    ? "Low"
                    : networkSnapshot.LocationConfidence!;
                rawLocation = !string.IsNullOrWhiteSpace(networkSnapshot.Location)
                    ? FormatRawLocation(networkSnapshot.Location!, "")
                    : rawLocation;
            }

            var playerCallsign = isLocalPlayer
                ? DisplayCallsign(_callsign, displayPlayerName)
                : DisplayCallsign(networkSnapshot?.Callsign, displayPlayerName);
            var isFleetCommander = IsFleetCommander(displayPlayerName, playerCallsign);
            var serverShard = isLocalPlayer && IsGameServerRegionCurrent()
                ? _gameServerShard
                : networkSnapshot?.ServerShard;
            var serverRegion = isLocalPlayer && IsGameServerRegionCurrent()
                ? _gameServerRegion
                : networkSnapshot?.ServerRegion;
            bool? hasServerSession = presence != PlayerPresenceKind.InGame
                ? false
                : isLocalPlayer
                    ? IsGameServerRegionCurrent()
                    : PlayerSessionStatePresentation.HasRecognizedValue(serverShard) ||
                      PlayerSessionStatePresentation.HasRecognizedValue(serverRegion)
                        ? true
                        : networkSnapshot is not null
                            ? false
                            : null;
            var inferredLocation = FormatLocationInference(rawLocation, locationConfidence);
            var displayShip = ShipDisplayNamePresentation.ResolveChinese(
                PlayerSessionStatePresentation.ResolveShip(
                    presence,
                    hasServerSession,
                    rawShip),
                ShipDisplayNamePresentation.UnknownShip);
            var displayLocation = PlayerSessionStatePresentation.ResolveLocation(
                presence,
                hasServerSession,
                inferredLocation);
            var sharedOnlineStatus = isLocalPlayer
                ? localSharedPresence.Online ? "Online" : "Offline"
                : null;
            var sharedLiveStatus = isLocalPlayer ? localSharedPresence.LiveStatus : null;
            // The current user always sees the locally resolved session phase in their own UI.
            // Outbound fleet snapshots apply the privacy projection separately before publishing.
            var sharedShip = isLocalPlayer
                ? displayShip
                : null;
            var sharedLocation = isLocalPlayer
                ? displayLocation
                : null;
            var serverRelationship = FleetServerRelationship.Resolve(
                presence,
                isLocalPlayer,
                serverShard,
                _localPresence,
                localServerShard);
            nextPlayers.Add(new PlayerRow(
                displayPlayerName,
                online ? "Online" : "Offline",
                displayShip,
                FormatShipInference(displayShip, shipConfidence),
                displayLocation,
                playerCallsign,
                isLocalPlayer ? _avatarPath : networkSnapshot?.AvatarImageData,
                GetInitials(displayPlayerName),
                GetFleetRole(displayPlayerName, playerCallsign, isFleetCommander),
                GetFleetNameBrush(displayPlayerName),
                rawShip,
                shipConfidence,
                locationConfidence,
                rawLocation,
                isLocalPlayer,
                CanShowMemberActionsForCurrentUser(),
                serverShard,
                serverRegion,
                liveStatus,
                GetFleetRoleBrush(displayPlayerName, playerCallsign),
                isLocalPlayer ? _accountId : networkSnapshot?.AccountId,
                sharedOnlineStatus,
                sharedLiveStatus,
                sharedShip,
                sharedLocation,
                isLocalPlayer
                    ? _playerEventSharingSettings.ToWireValue()
                    : networkSnapshot?.SharedEventTypes ?? (int)PlayerSharedEventTypes.All,
                hasServerSession,
                isFleetCommander,
                GetFleetConfiguredRoleColorBrush(displayPlayerName, playerCallsign, isFleetCommander),
                HasFleetPosition: isFleetCommander ||
                                  GetFleetPermission(displayPlayerName, playerCallsign)?.PermissionEnabled == true)
            {
                ResolvedServerRelationship = serverRelationship
            });
        }

        SynchronizeFleetMemberRows(nextPlayers);

        var onlineMemberCount = _players.Count(player => IsOnlineStatus(player.SharedOnlineStatusValue));
        TotalMembersText.Text = _players.Count.ToString();
        OnlineMembersText.Text = $"{onlineMemberCount} / {_players.Count}";
        RefreshFleetShipInventory();
        RefreshFleetHeader();
        RefreshFleetMemberManagement();
        RefreshFleetApplications();
        RefreshOverlayWindow();
        ProcessPlayerActivityDesktopNotifications();
        RefreshFriendPresenceFromFleetSnapshots();

        var local = _players.FirstOrDefault(player =>
            player.Name.Equals(_localPlayer, StringComparison.OrdinalIgnoreCase));
        if (local is not null)
        {
            var shipText = FormatUnknownForUser(local.Ship);
            var locationText = local.Location;
            var statusText = local.Status.Equals("Online", StringComparison.OrdinalIgnoreCase)
                ? "在线"
                : "离线";
            ShipStateText.Text =
                $"飞船：{shipText}{Environment.NewLine}" +
                $"{locationText}{Environment.NewLine}" +
                $"状态：{statusText}";
        }

        RefreshHeaderStatusBar();
    }

    private static string FormatShipInference(string ship, string confidence)
    {
        if (PlayerSessionStatePresentation.IsSessionStateText(ship))
        {
            return ship.Trim();
        }

        if (string.IsNullOrWhiteSpace(ship) ||
            ship.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return "飞船：未知";
        }

        return confidence.Equals("Low", StringComparison.OrdinalIgnoreCase)
            ? $"可能在：{ship}"
            : $"飞船：{ship}";
    }

    private string FormatLocationInference(string location, string? confidence)
    {
        var displayLocation = FormatLocationForUser(location);
        if (displayLocation.Equals("未知", StringComparison.OrdinalIgnoreCase))
        {
            return "地点：未知星域";
        }

        return confidence switch
        {
            { } value when value.Equals("High", StringComparison.OrdinalIgnoreCase) => $"地点：{displayLocation}",
            { } value when value.Equals("Medium", StringComparison.OrdinalIgnoreCase) => $"可能在：{displayLocation}",
            { } value when value.Equals("Low", StringComparison.OrdinalIgnoreCase) => $"可能离开：{displayLocation}",
            _ => $"可能离开：{displayLocation}"
        };
    }

    private static int LocationEvidenceScoreFromConfidence(string? confidence)
    {
        return confidence switch
        {
            { } value when value.Equals("High", StringComparison.OrdinalIgnoreCase) => 85,
            { } value when value.Equals("Medium", StringComparison.OrdinalIgnoreCase) => 55,
            { } value when value.Equals("Low", StringComparison.OrdinalIgnoreCase) => 20,
            _ => 15
        };
    }

    private string GetFleetRole(string playerName, string? callsign, bool? isFleetCommander = null)
    {
        if (isFleetCommander ?? IsFleetCommander(playerName, callsign))
        {
            return "组织负责人";
        }

        var permission = GetFleetPermission(playerName, callsign);
        return permission is not null && permission.PermissionEnabled
            ? NormalizeRoleTitle(permission.RoleTitle)
            : "成员";
    }

    private System.Windows.Media.Brush GetFleetNameBrush(string playerName)
    {
        if (IsFleetCommander(playerName, IsLocalPlayer(playerName) ? _callsign : null))
        {
            return FindBrush("FleetCommanderNameBrush", Brushes.Gold);
        }

        var permission = GetFleetPermission(playerName);
        return permission is not null && permission.PermissionEnabled
            ? FindBrush("PrimaryTextBrush", Brushes.White)
            : FindBrush("PrimaryTextBrush", Brushes.White);
    }

    private System.Windows.Media.Brush GetFleetRoleBrush(string playerName, string? callsign)
    {
        if (IsFleetCommander(playerName, callsign))
        {
            return FindBrush("FleetCommanderNameBrush", Brushes.Gold);
        }

        var permission = GetFleetPermission(playerName, callsign);
        if (permission is not null && permission.PermissionEnabled)
        {
            var roleKey = NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle);
            if (_fleetRoleGroupDefinitions.TryGetValue(roleKey, out var role))
            {
                return StatusPalette.BrushFromHex(role.Color, StatusPalette.InfoBrush);
            }

            return StatusPalette.InfoBrush;
        }

        return FindBrush("MutedTextBrush", Brushes.LightGray);
    }

    private System.Windows.Media.Brush? GetFleetConfiguredRoleColorBrush(
        string playerName,
        string? callsign,
        bool isFleetCommander)
    {
        var roleKey = FleetCommanderRoleGroupKey;
        if (!isFleetCommander)
        {
            var permission = GetFleetPermission(playerName, callsign);
            if (permission is null || !permission.PermissionEnabled)
            {
                return null;
            }

            roleKey = NormalizeRoleGroupKey(permission.RoleGroupKey, permission.RoleTitle);
        }

        return _fleetRoleGroupDefinitions.TryGetValue(roleKey, out var role)
            ? StatusPalette.TryBrushFromHex(role.Color)
            : null;
    }

    private LocalFleetMemberPermission? GetFleetPermission(string? playerName, string? callsign = null)
    {
        var aliases = EnumerateIdentityAliases(playerName, callsign).ToHashSet(StringComparer.OrdinalIgnoreCase);
        foreach (var alias in aliases)
        {
            if (_fleetMemberPermissions.TryGetValue(alias, out var direct))
            {
                return direct;
            }
        }

        return _fleetMemberPermissions.Values.FirstOrDefault(permission =>
            aliases.Contains(permission.GameName) ||
            (!string.IsNullOrWhiteSpace(permission.Callsign) && aliases.Contains(permission.Callsign)) ||
            aliases.Contains(FormatCommanderName(permission.Callsign, permission.GameName)));
    }

    private LocalFleetMemberPermission? GetCurrentUserFleetPermission()
    {
        foreach (var alias in EnumerateLocalIdentities())
        {
            var permission = GetFleetPermission(alias);
            if (permission is not null)
            {
                return permission;
            }
        }

        return null;
    }

    private bool HasCurrentUserFleetPermission(Func<LocalFleetMemberPermission, bool> predicate)
    {
        if (IsCurrentUserFleetCommander())
        {
            return true;
        }

        var permission = GetCurrentUserFleetPermission();
        return permission is not null &&
               permission.PermissionEnabled &&
               predicate(permission);
    }

    private bool CanCurrentUserOpenFleetManagement()
    {
        return _hasFleet &&
               (IsCurrentUserFleetCommander() ||
                CanCurrentUserEditAnyFleetProfileField() ||
                CanCurrentUserManageAnnouncements() ||
                CanCurrentUserInviteFleetMembers() ||
                CanCurrentUserReviewFleetApplications() ||
                CanCurrentUserViewFleetLogs());
    }

    private bool CanCurrentUserManageFleetInfo()
    {
        return HasCurrentUserFleetPermission(permission => permission.CanManageFleetInfo) ||
               CanCurrentUserEditFleetProfile() ||
               CanCurrentUserEditFleetAvatar() ||
               CanCurrentUserEditFleetBanner();
    }

    private bool HasCurrentUserFleetPermissionId(string permissionId)
    {
        if (string.IsNullOrWhiteSpace(permissionId))
        {
            return false;
        }

        if (IsCurrentUserFleetCommander())
        {
            return true;
        }

        var permission = GetCurrentUserFleetPermission();
        if (permission is null || !permission.PermissionEnabled)
        {
            return false;
        }

        var normalizedPermissionId = permissionId.Trim();
        if ((permission.ExtraDeniedPermissions ?? []).Any(id => id.Equals(normalizedPermissionId, StringComparison.OrdinalIgnoreCase)))
        {
            return false;
        }

        var permissionIds = ResolveRoleGroupPermissionIds(permission.RoleGroupKey, permission.ExtraAllowedPermissions);
        if (permissionIds.Any(id => id.Equals(normalizedPermissionId, StringComparison.OrdinalIgnoreCase)))
        {
            return true;
        }

        return normalizedPermissionId switch
        {
            "fleet.profile.edit" or "fleet.avatar.edit" or
            "members.review" or "audit.view"
                => permission.CanManageFleetInfo,
            "members.remove" => permission.CanRemoveMembers,
            "tasks.publish" or "tasks.plan" => permission.CanPublishTasks || permission.CanPublishPlans,
            _ => false
        };
    }

    private bool CanCurrentUserEditFleetProfile()
    {
        return HasCurrentUserFleetPermissionId(FleetPermissionPolicy.EditFleetProfile);
    }

    private bool CanCurrentUserManageAnnouncements()
    {
        return HasCurrentUserFleetPermissionId(FleetPermissionPolicy.ManageAnnouncements);
    }

    private bool CanCurrentUserEditFleetAvatar()
    {
        return HasCurrentUserFleetPermissionId("fleet.avatar.edit");
    }

    private bool CanCurrentUserEditFleetBanner()
    {
        return false;
    }

    private bool CanCurrentUserEditAnyFleetProfileField()
    {
        return CanCurrentUserEditFleetProfile() ||
               CanCurrentUserEditFleetAvatar() ||
               CanCurrentUserEditFleetBanner();
    }

    private bool CanCurrentUserInviteFleetMembers()
    {
        return CanCurrentUserGenerateFleetInvite();
    }

    private bool CanCurrentUserReviewFleetApplications()
    {
        return HasCurrentUserFleetPermissionId("members.review");
    }

    private bool CanCurrentUserViewFleetLogs()
    {
        return HasCurrentUserFleetPermissionId("audit.view") ||
               HasCurrentUserFleetPermissionId("audit.delete");
    }

    private bool CanCurrentUserDeleteFleetLogs()
    {
        return HasCurrentUserFleetPermissionId("audit.delete");
    }

    private bool CanCurrentUserPublishTasks()
    {
        return HasCurrentUserFleetPermission(permission => permission.CanPublishTasks);
    }

    private bool CanCurrentUserPublishPlans()
    {
        return HasCurrentUserFleetPermission(permission => permission.CanPublishPlans);
    }

    private bool CanCurrentUserRemoveMembers()
    {
        return HasCurrentUserFleetPermission(permission => permission.CanRemoveMembers);
    }

    private void RefreshFleetManagementPermissions()
    {
        if (ManageFleetTab is null)
        {
            return;
        }

        var canOpenManagement = CanCurrentUserOpenFleetManagement();
        ManageFleetTab.Visibility = canOpenManagement ? Visibility.Visible : Visibility.Collapsed;
        if (ManageFleetRailButton is not null)
        {
            ManageFleetRailButton.Visibility = canOpenManagement ? Visibility.Visible : Visibility.Collapsed;
        }

        if (!canOpenManagement)
        {
            if (FleetSubTabs is not null &&
                ReferenceEquals(FleetSubTabs.SelectedItem, ManageFleetTab) &&
                AllPlayersTab is not null)
            {
                FleetSubTabs.SelectedItem = AllPlayersTab;
                RefreshFleetMainContentView();
            }

            if (MainTabs is not null && MainTabs.SelectedItem == ManageFleetTab)
            {
                MainTabs.SelectedItem = FleetTab;
                SetActiveNav(MyFleetNavButton);
            }

            RefreshFleetRailHeaders();
            return;
        }

        var canEditAnyProfileField = CanCurrentUserEditAnyFleetProfileField();
        var canEditProfile = CanCurrentUserEditFleetProfile();
        var canInviteMembers = CanCurrentUserInviteFleetMembers();
        var canReviewApplications = CanCurrentUserReviewFleetApplications();
        var canViewFleetLogs = CanCurrentUserViewFleetLogs();
        var canPublishTasks = CanCurrentUserPublishTasks();
        var canPublishPlans = CanCurrentUserPublishPlans();
        var isCommander = IsCurrentUserFleetCommander();

        SetManageFleetTabVisibility(ManageFleetOverviewTab, true);
        SetManageFleetTabVisibility(ManageFleetNoticeTab, CanCurrentUserManageAnnouncements());
        SetManageFleetTabVisibility(ManageFleetProfileTab, canEditAnyProfileField);
        SetManageFleetTabVisibility(ManageFleetNotificationsTab, false);
        SetManageFleetTabVisibility(FleetApplicationsTab, canInviteMembers || canReviewApplications);
        SetManageFleetTabVisibility(ManageFleetTaskTab, EnableFleetActionManagementUi && canPublishTasks);
        SetManageFleetTabVisibility(ManageFleetPlanTab, EnableFleetActionManagementUi && canPublishPlans);
        SetManageFleetTabVisibility(ManageFleetMembersTab, isCommander);
        SetManageFleetTabVisibility(ManageFleetLogTab, canViewFleetLogs);
        SetManageFleetTabVisibility(ManageFleetShipsTab, canEditProfile || isCommander);
        SetManageFleetTabVisibility(ManageFleetDisbandTab, isCommander);
        SelectFirstVisibleManageFleetTab();
        RefreshManageSettingsNavigation();
        RefreshFleetInvites();
        RefreshFleetRailHeaders();
    }

    private static void SetManageFleetTabVisibility(TabItem? tab, bool isVisible)
    {
        if (tab is not null)
        {
            tab.Visibility = isVisible ? Visibility.Visible : Visibility.Collapsed;
        }
    }

    private void SelectFirstVisibleManageFleetTab()
    {
        if (ManageFleetTabs is null)
        {
            return;
        }

        if (ManageFleetTabs.SelectedItem is TabItem selected &&
            selected.Visibility == Visibility.Visible)
        {
            return;
        }

        foreach (var item in ManageFleetTabs.Items.OfType<TabItem>())
        {
            if (item.Visibility == Visibility.Visible)
            {
                ManageFleetTabs.SelectedItem = item;
                return;
            }
        }
    }

    private IEnumerable<string> EnumerateLocalIdentities()
    {
        return EnumerateIdentityAliases(_localPlayer, _callsign)
            .Concat(EnumerateIdentityAliases(_accountName, null));
    }

    private static IEnumerable<string> EnumerateIdentityAliases(string? playerName, string? callsign)
    {
        foreach (var value in new[] { playerName, callsign })
        {
            if (string.IsNullOrWhiteSpace(value))
            {
                continue;
            }

            var trimmed = value.Trim();
            yield return trimmed;

            var gameName = GetGameNameFromDisplayName(trimmed);
            if (!string.IsNullOrWhiteSpace(gameName))
            {
                yield return gameName;
            }

            var displayCallsign = GetCallsignFromDisplayName(trimmed);
            if (!string.IsNullOrWhiteSpace(displayCallsign))
            {
                yield return displayCallsign;
            }
        }

        if (!string.IsNullOrWhiteSpace(playerName) && !string.IsNullOrWhiteSpace(callsign))
        {
            yield return FormatCommanderName(callsign, playerName);
        }
    }

    private static string NormalizeRoleTitle(string? value)
    {
        var role = string.IsNullOrWhiteSpace(value) ? "授权成员" : value.Trim();
        var builder = new StringBuilder();
        var weight = 0;
        foreach (var character in role)
        {
            var nextWeight = IsCjk(character) ? 2 : 1;
            if (weight + nextWeight > 14)
            {
                break;
            }

            builder.Append(character);
            weight += nextWeight;
        }

        return builder.Length == 0 ? "授权成员" : builder.ToString();
    }

    private static string NormalizeRoleGroupKey(string? key, string? roleTitle = null)
    {
        var value = key?.Trim();
        if (!string.IsNullOrWhiteSpace(value))
        {
            return value;
        }

        var role = NormalizeRoleTitle(roleTitle);
        if (role.Equals("组织负责人", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("舰队指挥官", StringComparison.OrdinalIgnoreCase))
        {
            return "fleet_commander";
        }

        if (role.Equals("组织副负责人", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("舰队副指挥官", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("副指挥官", StringComparison.OrdinalIgnoreCase) ||
            role.Equals("副官", StringComparison.OrdinalIgnoreCase))
        {
            return "fleet_deputy_commander";
        }

        return role.Equals("成员", StringComparison.OrdinalIgnoreCase) ||
               role.Equals("基础成员", StringComparison.OrdinalIgnoreCase)
            ? ""
            : $"custom_{SanitizeRoleGroupKey(role)}";
    }

    private static string NormalizeRoleDisplayTitle(string? roleTitle, string? roleGroupKey = null)
    {
        var key = NormalizeRoleGroupKey(roleGroupKey, roleTitle);
        return key switch
        {
            "fleet_commander" => "组织负责人",
            "fleet_deputy_commander" => "组织副负责人",
            "" => "基础成员",
            _ => NormalizeRoleTitle(roleTitle)
        };
    }

    private static bool IsFleetCommanderRole(string? roleGroupKey, string? roleTitle = null)
    {
        return NormalizeRoleGroupKey(roleGroupKey, roleTitle).Equals("fleet_commander", StringComparison.OrdinalIgnoreCase);
    }

    private string ResolveRoleGroupKeyFromDisplayName(string? displayName)
    {
        var title = NormalizeRoleTitle(displayName);
        if (title.Equals("基础成员", StringComparison.OrdinalIgnoreCase) ||
            title.Equals("成员", StringComparison.OrdinalIgnoreCase) ||
            title.Equals("普通成员", StringComparison.OrdinalIgnoreCase))
        {
            return "";
        }

        return _fleetSystemRoleGroups
                   .Concat(_fleetCustomRoleGroups)
                   .FirstOrDefault(role => role.DisplayName.Equals(title, StringComparison.OrdinalIgnoreCase))
                   ?.Key
               ?? NormalizeRoleGroupKey(null, title);
    }

    private static string SanitizeRoleGroupKey(string value)
    {
        var builder = new StringBuilder();
        foreach (var character in value.Trim().ToLowerInvariant())
        {
            if (char.IsLetterOrDigit(character))
            {
                builder.Append(character);
            }
            else if (character is '-' or '_' or ' ')
            {
                builder.Append('_');
            }
        }

        return builder.Length == 0 ? Guid.NewGuid().ToString("N")[..8] : builder.ToString();
    }

    private bool IsFleetCommander(string playerName, string? callsign)
    {
        return playerName.Equals(GetGameNameFromDisplayName(_fleetChiefCommander), StringComparison.OrdinalIgnoreCase) ||
               (!string.IsNullOrWhiteSpace(callsign) &&
                callsign.Equals(GetCallsignFromDisplayName(_fleetChiefCommander), StringComparison.OrdinalIgnoreCase));
    }

    private static System.Windows.Media.Brush FindBrush(string key, System.Windows.Media.Brush fallback)
    {
        return System.Windows.Application.Current.TryFindResource(key) as System.Windows.Media.Brush ?? fallback;
    }

    private static string FormatRawLocation(string location, string navigationTarget)
    {
        if (string.IsNullOrWhiteSpace(location))
        {
            return "Unknown";
        }

        var separator = location.IndexOf(" -> ", StringComparison.Ordinal);
        return separator > 0
            ? location[..separator].Trim()
            : location.Trim();
    }

    private static string RemoveServerDetailFromLocation(string location)
    {
        if (string.IsNullOrWhiteSpace(location) ||
            location.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return "Unknown";
        }

        var trimmed = location.Trim();
        if (trimmed.Contains("shard", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("pub_", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Contains("server", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("US East", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("US West", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("Europe", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("Asia", StringComparison.OrdinalIgnoreCase) ||
            trimmed.Equals("Australia", StringComparison.OrdinalIgnoreCase))
        {
            return "Unknown";
        }

        return trimmed;
    }

    private string FormatLocation(string location)
    {
        return LocationNameLocalizer.DisplayName(location, _language);
    }

    private string FormatLogEventForUser(FleetEvent fleetEvent)
    {
        var player = FormatPlayerForUser(fleetEvent.Player);
        return fleetEvent.Type switch
        {
            FleetEventType.PlayerOnline => $"已识别玩家：{player}",
            FleetEventType.PlayerOffline => $"{player} 已离线",
            FleetEventType.PlayerEnteredShip => $"{player} 进入飞船：{FormatShipForUser(fleetEvent.Ship)}",
            FleetEventType.PlayerExitedShip => $"{player} 离开飞船：{FormatShipForUser(fleetEvent.Ship)}",
            FleetEventType.PlayerControllingShip => $"{player} 进入驾驶位：{FormatShipForUser(fleetEvent.Ship)}",
            FleetEventType.PlayerStoppedDrivingShip => $"{player} 离开驾驶位：{FormatShipForUser(fleetEvent.Ship)}",
            FleetEventType.PlayerLocationChanged => FormatLocationChangeForUser(player, fleetEvent),
            FleetEventType.PlayerNavigationTargetChanged => FormatNavigationTargetForUser(player, fleetEvent),
            FleetEventType.PlayerDowned => FormatDownedForUser(player, fleetEvent.LifeContext),
            FleetEventType.PlayerDied => $"{player} 已死亡，等待重生",
            FleetEventType.PlayerRevived => $"{player} 已被救起，恢复行动",
            FleetEventType.PlayerRespawned => $"{player} 已重生",
            FleetEventType.CombatStateChanged => $"{player} 状态：{FormatCombatStateForUser(fleetEvent.CombatState)}",
            FleetEventType.NetworkStateChanged => null,
            FleetEventType.PlayerShipControlSignal => null,
            _ => null
        } ?? string.Empty;
    }

    private static string FormatDownedForUser(string player, LifeEventContext lifeContext)
    {
        return lifeContext == LifeEventContext.SafeZoneMedicalResponse
            ? $"{player} 在安全区倒地，本地救援已响应"
            : $"{player} 已失去行动能力，等待救援";
    }

    private string FormatLocationChangeForUser(string player, FleetEvent fleetEvent)
    {
        var location = fleetEvent.Location;
        if (IsQuantumArrivalPlaceholder(location))
        {
            location = _fleetState.Players
                .FirstOrDefault(candidate => candidate.Name.Equals(fleetEvent.Player, StringComparison.OrdinalIgnoreCase))
                ?.Location;
            return $"{player} 抵达：{FormatLocationForUser(location)}";
        }

        return $"{player} 位置更新：{FormatLocationForUser(location)}";
    }

    private string FormatNavigationTargetForUser(string player, FleetEvent fleetEvent)
    {
        var location = FormatLocationForUser(fleetEvent.Location);
        var target = FormatLocationForUser(fleetEvent.NavigationTarget);
        var hasLocation = !location.Equals("未知", StringComparison.OrdinalIgnoreCase);
        var hasTarget = !target.Equals("未知", StringComparison.OrdinalIgnoreCase);

        if (hasLocation && hasTarget)
        {
            return $"{player} 设置导航：{location} → {target}";
        }

        if (hasTarget)
        {
            return $"{player} 设置导航目标：{target}";
        }

        if (hasLocation)
        {
            return $"{player} 当前位置：{location}";
        }

        return string.Empty;
    }

    private string FormatShipForUser(string? ship)
    {
        return ShipDisplayNamePresentation.ResolveChinese(
            ship,
            ShipDisplayNamePresentation.UnknownShip);
    }

    private string FormatLocationForUser(string? location)
    {
        if (string.IsNullOrWhiteSpace(location) ||
            location.Equals("None", StringComparison.OrdinalIgnoreCase) ||
            location.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return "未知";
        }

        var rawLocation = FormatRawLocation(location, "");
        return FormatUnknownForUser(FormatLocation(rawLocation));
    }

    private static string FormatPlayerForUser(string? player)
    {
        return string.IsNullOrWhiteSpace(player) ||
               player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase)
            ? "本地玩家"
            : player.Trim();
    }

    private static string FormatUnknownForUser(string? value)
    {
        return string.IsNullOrWhiteSpace(value) ||
               value.Equals("Unknown", StringComparison.OrdinalIgnoreCase) ||
               value.Equals("None", StringComparison.OrdinalIgnoreCase)
            ? "未知"
            : value.Trim();
    }

    private static string FormatCombatStateForUser(string? combatState)
    {
        return combatState switch
        {
            null or "" => "待命",
            "Combat" => "战斗中",
            "Idle" => "待命",
            _ => combatState
        };
    }

    private static bool IsQuantumArrivalPlaceholder(string? location)
    {
        return location?.Equals("Arrived - awaiting location confirmation", StringComparison.OrdinalIgnoreCase) == true;
    }

    private bool TryUpdateGameServerFromLine(string line, bool isRealtimeLine)
    {
        if (IsGameServerLogoutLine(line, hasKnownServer: !string.IsNullOrWhiteSpace(_gameServerShard)))
        {
            return ClearGameServerRegion();
        }

        var shard = TryExtractGameServerShard(line);
        if (string.IsNullOrWhiteSpace(shard))
        {
            return false;
        }

        if (!isRealtimeLine &&
            !_isGameProcessRunning &&
            !StarCitizenProcessProbe.IsRunning())
        {
            return false;
        }

        var region = MapGameServerRegion(shard);
        _gameServerObservedAtUtc = DateTimeOffset.UtcNow;
        if (string.Equals(_gameServerShard, shard, StringComparison.OrdinalIgnoreCase) &&
            string.Equals(_gameServerRegion, region, StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        _gameServerShard = shard;
        _gameServerRegion = region;
        return true;
    }

    private static string? TryExtractGameServerShard(string line)
    {
        var match = JoinPuShardRegex.Match(line);
        if (!match.Success)
        {
            match = UpdateShardIdRegex.Match(line);
        }

        if (!match.Success)
        {
            match = GenericGameServerShardRegex.Match(line);
        }

        if (!match.Success)
        {
            return null;
        }

        var shard = match.Groups["shard"].Value.Trim();
        return string.IsNullOrWhiteSpace(shard) ? null : shard;
    }

    internal static bool IsGameServerLogoutLine(string line, bool hasKnownServer)
    {
        if (GameServerDisconnectRegex.IsMatch(line))
        {
            return true;
        }

        return hasKnownServer && GameServerReturnedToFrontendRegex.IsMatch(line);
    }

    private static bool CouldUpdateGameServerFromLine(string line)
    {
        return IsGameServerLogoutLine(line, hasKnownServer: true) ||
               !string.IsNullOrWhiteSpace(TryExtractGameServerShard(line));
    }

    private async Task<GameServerLogRefreshResult> RefreshGameServerFromLogSnapshotAsync()
    {
        UpdateLocalOnlineStateFromGameProcess();

        var logPath = string.IsNullOrWhiteSpace(_logPath)
            ? LogPathBox.Text
            : _logPath;
        var validation = LogFileSelectionGuard.ValidateGameLogPath(logPath);
        if (!validation.IsValid)
        {
            return new GameServerLogRefreshResult(false, false, false, "", "", validation.Status);
        }

        if (!_isGameProcessRunning)
        {
            var cleared = ClearGameServerRegion();
            return new GameServerLogRefreshResult(false, cleared, cleared, "", "", "未检测到游戏进程，服务器信息已保持隐藏。");
        }

        var snapshot = await Task.Run(() => TryFindLatestGameServerShardInLog(logPath!));
        if (snapshot is null)
        {
            return new GameServerLogRefreshResult(false, false, false, "", "", "未在当前 Game.log 中找到服务器记录。");
        }

        if (snapshot.IsLoggedOut || string.IsNullOrWhiteSpace(snapshot.Shard))
        {
            var cleared = ClearGameServerRegion();
            _lastGameLogReadAt = DateTimeOffset.Now;
            return new GameServerLogRefreshResult(
                Found: false,
                Changed: cleared,
                Cleared: cleared,
                Region: "",
                Shard: "",
                Message: "Game.log 显示已离开服务器，服务器信息已清空。");
        }

        var region = MapGameServerRegion(snapshot.Shard);
        var changed = !string.Equals(_gameServerShard, snapshot.Shard, StringComparison.OrdinalIgnoreCase) ||
                      !string.Equals(_gameServerRegion, region, StringComparison.OrdinalIgnoreCase) ||
                      _gameServerObservedAtUtc == DateTimeOffset.MinValue;

        _gameServerShard = snapshot.Shard;
        _gameServerRegion = region;
        _gameServerObservedAtUtc = DateTimeOffset.UtcNow;
        _lastGameLogReadAt = DateTimeOffset.Now;

        return new GameServerLogRefreshResult(
            Found: true,
            Changed: changed,
            Cleared: false,
            Region: region,
            Shard: snapshot.Shard,
            Message: $"已从 Game.log 回扫确认服务器：{region} / {snapshot.Shard}");
    }

    private static GameServerLogSnapshot? TryFindLatestGameServerShardInLog(string path)
    {
        string? latestShard = null;
        var latestWasLogout = false;
        var matchedLines = 0;

        using var stream = new FileStream(
            path,
            FileMode.Open,
            FileAccess.Read,
            FileShare.ReadWrite | FileShare.Delete);
        using var reader = new StreamReader(stream, Encoding.UTF8, detectEncodingFromByteOrderMarks: true);

        while (reader.ReadLine() is { } line)
        {
            if (IsGameServerLogoutLine(line, hasKnownServer: !string.IsNullOrWhiteSpace(latestShard)))
            {
                latestShard = null;
                latestWasLogout = true;
                matchedLines++;
                continue;
            }

            var shard = TryExtractGameServerShard(line);
            if (string.IsNullOrWhiteSpace(shard))
            {
                continue;
            }

            latestShard = shard;
            latestWasLogout = false;
            matchedLines++;
        }

        return matchedLines <= 0
            ? null
            : new GameServerLogSnapshot(latestShard, latestWasLogout, matchedLines);
    }

    private bool IsGameServerRegionCurrent()
    {
        return _isGameProcessRunning &&
               !string.IsNullOrWhiteSpace(_gameServerShard) &&
               _gameServerObservedAtUtc != DateTimeOffset.MinValue;
    }

    private bool ExpireGameServerRegionIfNeeded()
    {
        if (string.IsNullOrWhiteSpace(_gameServerShard) &&
            _gameServerObservedAtUtc == DateTimeOffset.MinValue &&
            _gameServerRegion.Equals("未知", StringComparison.OrdinalIgnoreCase))
        {
            return false;
        }

        if (!_isGameProcessRunning ||
            _gameServerObservedAtUtc == DateTimeOffset.MinValue)
        {
            return ClearGameServerRegion();
        }

        return false;
    }

    private bool ClearGameServerRegion()
    {
        var hadServerRegion = !string.IsNullOrWhiteSpace(_gameServerShard) ||
                              _gameServerObservedAtUtc != DateTimeOffset.MinValue ||
                              !_gameServerRegion.Equals("未知", StringComparison.OrdinalIgnoreCase);

        _gameServerShard = "";
        _gameServerRegion = "未知";
        _gameServerObservedAtUtc = DateTimeOffset.MinValue;
        return hadServerRegion;
    }

    private static string MapGameServerRegion(string shard)
        => GameServerRegionPresentation.ResolveRegion(shard) ?? "未知";

    private void RefreshHeaderStatusBar()
    {
        if (HeaderAccountStatusText is null)
        {
            return;
        }

        HeaderAccountStatusText.Text = IsLoggedIn
            ? CompactHeaderText(
                !string.IsNullOrWhiteSpace(_callsign) ? _callsign! :
                string.IsNullOrWhiteSpace(_accountName) ? "已登录" : _accountName!,
                18)
            : "未登录";
        HeaderAccountStatusText.Foreground = IsLoggedIn
            ? FindBrush("StatusSuccessBrush", Brushes.MediumSpringGreen)
            : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);

        var connectionStatus = GetHeaderConnectionStatus();
        HeaderSyncStatusText.Text = connectionStatus;
        HeaderSyncStatusText.Foreground = connectionStatus is "连接正常" or "同步中"
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : connectionStatus == "连接异常"
                ? FindBrush("StatusDangerBrush", Brushes.IndianRed)
                : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
        if (_lastAnimatedHeaderConnectionStatus is null)
        {
            _lastAnimatedHeaderConnectionStatus = connectionStatus;
        }
        else if (!string.Equals(
                     _lastAnimatedHeaderConnectionStatus,
                     connectionStatus,
                     StringComparison.Ordinal))
        {
            _lastAnimatedHeaderConnectionStatus = connectionStatus;
            UiMotion.SweepSignal(HeaderSyncStatusChip, HeaderSyncRouteSignal);
        }

        HeaderGameProcessStatusText.Text = _isGameProcessRunning ? "运行中" : "未运行";
        HeaderGameProcessStatusText.Foreground = _isGameProcessRunning
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);

        var serverRegionCurrent = IsGameServerRegionCurrent();
        HeaderGameServerRegionText.Text = GetGameServerRegionDisplay();
        HeaderGameServerRegionText.Foreground = serverRegionCurrent
            ? FindBrush("StatusSuccessBrush", Brushes.SpringGreen)
            : FindBrush("StatusDisabledBrush", Brushes.LightSlateGray);
        HeaderGameServerRegionText.ToolTip = serverRegionCurrent
            ? $"服务器区域：{_gameServerRegion}（本次游戏会话实时确认）"
            : _isGameProcessRunning
                ? "等待本次游戏会话的 Join PU 日志确认服务器区域"
                : "服务器区域仅在游戏运行并实时识别 Join PU 后显示";
        RefreshPersonalIdentityConsole();
        RefreshOnboardingSupportPanel();
        if (ReferenceEquals(MainTabs.SelectedItem, HomeTab))
        {
            RefreshHomeDashboard();
        }

    }


    private void AppendOutput(string message)
    {
        if (OutputBox is null)
        {
            return;
        }

        OutputBox.AppendText(message + Environment.NewLine);
        OutputBox.ScrollToEnd();
    }

    private static void LogOverlayPerformance(string operation, Stopwatch stopwatch, bool force = false)
    {
        stopwatch.Stop();
        if (!force &&
            stopwatch.ElapsedMilliseconds < OverlaySlowOperationThresholdMs &&
            !OverlayHwndDiagnostics.IsVerboseDiagnosticsEnabled)
        {
            return;
        }

        App.WriteDiagnosticLog($"overlay-perf operation={operation} elapsedMs={stopwatch.Elapsed.TotalMilliseconds:F1}");
    }

    // Shared by multiple MainWindow partials. This used to live in the overlay
    // editor file even though the in-game snapshot builder also depended on it;
    // keeping it on the root partial prevents either feature from owning the seam.
    private static string FirstNonEmpty(params string?[] values) =>
        values.FirstOrDefault(value => !string.IsNullOrWhiteSpace(value))?.Trim() ?? "";



















}
