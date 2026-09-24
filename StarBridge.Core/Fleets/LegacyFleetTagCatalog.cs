namespace StarBridge.Core.Fleets;

/// <summary>The existing WPF tag catalog, not the future community-tag migration.</summary>
public static class LegacyFleetTagCatalog
{
    public const int MaxSelection = 5;
    public static IReadOnlyList<LegacyFleetTagCategory> Categories { get; } =
        Array.AsReadOnly<LegacyFleetTagCategory>(
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
        ]);
    public static IReadOnlyList<LegacyFleetTag> Tags { get; } =
        Array.AsReadOnly<LegacyFleetTag>(
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
        ]);
}

public sealed record LegacyFleetTagCategory(string Id, string Name, string AccentHex, string Description);
public sealed record LegacyFleetTag(string Id, string Name, string CategoryId, string Description);
