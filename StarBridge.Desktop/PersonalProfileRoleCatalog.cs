namespace StarBridge.Desktop;

internal sealed record PersonalProfileRoleCategory(
    string Id,
    string Name,
    string Description,
    string AccentHex);

internal sealed record PersonalProfileRoleDefinition(
    string Id,
    string CategoryId,
    string Name,
    string Description);

internal static class PersonalProfileRoleCatalog
{
    public const int MaxSelected = 5;

    public static readonly PersonalProfileRoleCategory[] Categories =
    [
        new("command", "指挥协同", "负责组织、沟通和行动节奏。", "#D9A23B"),
        new("ship", "舰船操作", "承担舰船驾驶、武器与工程席位。", "#29AFFF"),
        new("air-combat", "空中战斗", "专注舰载机与空中作战任务。", "#E08A92"),
        new("ground-combat", "地面战斗", "承担地面、载具与登舰作战。", "#F15B65"),
        new("recon", "探索侦察", "负责扫描、侦察和路径规划。", "#75C9D6"),
        new("industry", "工业生产", "参与采集、生产与货物流转。", "#D6B56A"),
        new("medical", "医疗救援", "提供医疗、搜救和伤员转运。", "#42CF7C"),
        new("logistics", "后勤保障", "负责补给、维修和资源调度。", "#9A8FD8")
    ];

    public static readonly PersonalProfileRoleDefinition[] Roles =
    [
        new("fleet-command", "command", "舰队指挥", "统筹舰队目标、队形与整体行动。"),
        new("squad-command", "command", "小队指挥", "组织小队成员并执行舰队指令。"),
        new("action-coordination", "command", "行动协调", "衔接成员、资源与行动时间。"),
        new("navigator", "command", "领航员", "规划航线、集结点与转场路径。"),

        new("pilot", "ship", "驾驶员", "负责舰船航行、机动与安全操控。"),
        new("copilot", "ship", "副驾驶", "协助航行、系统管理与任务执行。"),
        new("gunner", "ship", "炮手", "操作舰载炮塔并协同锁定目标。"),
        new("ship-engineer", "ship", "舰船工程师", "管理舰船能源、损伤与系统状态。"),
        new("remote-weapon-operator", "ship", "远程武器操作员", "操作远程炮塔、导弹与武器系统。"),

        new("fighter-pilot", "air-combat", "战斗机驾驶员", "执行制空、护航与近距空战。"),
        new("interceptor-pilot", "air-combat", "拦截机驾驶员", "快速拦截并限制高价值目标。"),
        new("bomber-pilot", "air-combat", "轰炸机驾驶员", "执行对舰与重目标打击。"),
        new("carrier-pilot", "air-combat", "舰载机驾驶员", "执行舰载起降与编队协同。"),

        new("assault-trooper", "ground-combat", "突击队员", "推进战线并完成近中距离作战。"),
        new("sniper", "ground-combat", "狙击手", "提供远距离观察与精确火力。"),
        new("heavy-gunner", "ground-combat", "重武器手", "使用重武器压制人员或载具目标。"),
        new("boarding-specialist", "ground-combat", "登舰队员", "执行登舰、清舱与设施控制。"),
        new("vehicle-driver", "ground-combat", "载具驾驶员", "驾驶地面载具并支援地面行动。"),

        new("scout", "recon", "侦察员", "前出观察环境、目标与威胁。"),
        new("route-planner", "recon", "路径规划", "选择安全高效的航线与行动路径。"),
        new("scanner-operator", "recon", "扫描操作员", "使用扫描系统定位目标与资源。"),
        new("intel-observer", "recon", "情报观察员", "汇总现场信息并形成行动判断。"),

        new("mining-operator", "industry", "采矿操作员", "完成矿物勘探、开采与协同作业。"),
        new("salvage-operator", "industry", "打捞操作员", "执行残骸处理与材料回收。"),
        new("cargo-specialist", "industry", "货运专员", "管理装卸、舱单与货运流程。"),
        new("trader", "industry", "贸易专员", "规划交易路线并评估货物价值。"),
        new("resource-processor", "industry", "资源处理员", "负责资源整理、加工与交付。"),

        new("medic", "medical", "医疗兵", "在行动现场提供基础医疗救治。"),
        new("search-and-rescue", "medical", "搜救人员", "定位、接近并撤离受困成员。"),
        new("casualty-transport", "medical", "伤员转运", "将伤员安全转移至医疗设施。"),
        new("field-medic", "medical", "战地救护", "在高风险环境中稳定和救治伤员。"),

        new("supply-specialist", "logistics", "补给人员", "准备弹药、物资与行动补给。"),
        new("maintenance-engineer", "logistics", "维修工程师", "维修舰船、载具及关键设备。"),
        new("ship-dispatcher", "logistics", "舰船调度", "协调舰船、乘员与出动顺序。"),
        new("transport-driver", "logistics", "运输驾驶员", "承担人员、载具或物资运输。")
    ];

    private static readonly IReadOnlyDictionary<string, PersonalProfileRoleDefinition> RolesById =
        Roles.ToDictionary(role => role.Id, StringComparer.OrdinalIgnoreCase);

    private static readonly IReadOnlyDictionary<string, PersonalProfileRoleDefinition> RolesByName =
        Roles.ToDictionary(role => role.Name, StringComparer.OrdinalIgnoreCase);

    private static readonly IReadOnlyDictionary<string, PersonalProfileRoleCategory> CategoriesById =
        Categories.ToDictionary(category => category.Id, StringComparer.OrdinalIgnoreCase);

    public static PersonalProfileRoleDefinition? FindRole(string? idOrName)
    {
        if (string.IsNullOrWhiteSpace(idOrName))
        {
            return null;
        }

        var value = idOrName.Trim();
        return RolesById.TryGetValue(value, out var byId)
            ? byId
            : RolesByName.GetValueOrDefault(value);
    }

    public static PersonalProfileRoleCategory? FindCategory(string? categoryId) =>
        string.IsNullOrWhiteSpace(categoryId)
            ? null
            : CategoriesById.GetValueOrDefault(categoryId);

    public static string[] NormalizeRoleIds(IEnumerable<string>? values)
    {
        var normalized = new List<string>();
        foreach (var value in values ?? [])
        {
            var role = FindRole(value);
            if (role is null || normalized.Contains(role.Id, StringComparer.OrdinalIgnoreCase))
            {
                continue;
            }

            normalized.Add(role.Id);
            if (normalized.Count == MaxSelected)
            {
                break;
            }
        }

        return normalized.ToArray();
    }
}
