namespace StarBridge.Desktop;

internal static class PersonalProfilePlayStyleCatalog
{
    public const int MaximumSelectedPerGroup = 3;
    public const int MaximumStoredPerGroup = 8;

    public static readonly string[] ParticipationInterests =
    [
        "舰队行动",
        "小队任务",
        "PVE 战斗",
        "PVP 战斗",
        "赏金任务",
        "地面行动",
        "跑商运输",
        "采矿",
        "打捞",
        "探索",
        "竞速",
        "休闲社交"
    ];

    public static readonly string[] SupportCapabilities =
    [
        "战术指挥",
        "驾驶",
        "炮手",
        "医疗救援",
        "后勤补给",
        "工程维修",
        "侦察导航",
        "人员运输",
        "任务教学",
        "舰船共享"
    ];

    public static string[] Normalize(IEnumerable<string>? values) =>
        (values ?? [])
        .Select(value => (value ?? "").Trim())
        .Where(value => value.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(MaximumStoredPerGroup)
        .ToArray();

    public static string[] NormalizeSelection(IEnumerable<string>? values) =>
        Normalize(values)
        .Take(MaximumSelectedPerGroup)
        .ToArray();
}
