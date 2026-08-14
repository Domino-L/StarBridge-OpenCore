using System.Security.Cryptography;

namespace StarBridge.Desktop;

public enum PartyRoomEligibility
{
    Everyone,
    HostFriends,
    SameFleet,
    InviteOnly
}

public enum PartyRoomLanguage
{
    Chinese,
    English,
    Bilingual
}

public sealed record PartyRoomTagNode(
    string Id,
    string Name,
    IReadOnlyList<PartyRoomTagNode> Children)
{
    public bool HasChildren => Children.Count > 0;
}

public sealed record PartyRoomContextTag(string Id, string Name);

public sealed record PartyRoomContextTagGroup(
    string Id,
    string Name,
    IReadOnlyList<PartyRoomContextTag> Tags);

public static class PartyRoomTagCatalog
{
    public const int Version = 3;

    public static IReadOnlyList<PartyRoomTagNode> GameplayRoots { get; } =
    [
        Node("combat", "战斗",
            Node("pve", "PVE",
                Node("pve_bounty", "飞船赏金"),
                Node("pve_ship_combat_mission", "飞船战斗任务"),
                Node("pve_outlaw_bounty", "违法飞船赏金"),
                Node("pve_bunker", "地堡清剿"),
                Node("pve_settlement_clearance", "定居点清剿"),
                Node("pve_combined_combat", "综合战斗任务")),
            Node("pvp", "PVP",
                Node("pvp_dogfight", "舰船狗斗"),
                Node("pvp_fleet_combat", "多舰对抗"),
                Node("pvp_fps", "FPS 对抗"),
                Node("pvp_player_bounty", "玩家赏金"),
                Node("pvp_piracy", "海盗劫掠")),
            Node("combat_pve_pvp", "PVE/PVP",
                Node("combat_pyro_contested_zone", "派罗争夺区"),
                Node("combat_security_post_raid", "突袭安保站"))),
        Node("industry", "工业",
            Node("industry_mining", "采矿与精炼",
                Node("industry_hand_mining", "徒手采矿"),
                Node("industry_vehicle_mining", "地面载具采矿"),
                Node("industry_ship_mining", "单舰采矿"),
                Node("industry_cooperative_mining", "多舰协同采矿")),
            Node("industry_salvage", "打捞",
                Node("industry_hull_scraping", "船体刮取"),
                Node("industry_structural_salvage", "结构打捞"),
                Node("industry_component_recovery", "部件回收"),
                Node("industry_cooperative_salvage", "多船协同打捞")),
            Node("industry_repair_engineering", "维修与工程",
                Node("industry_hull_repair", "船体维修"),
                Node("industry_ship_engineering", "船内工程"),
                Node("industry_combat_repair", "战损抢修"),
                Node("industry_engineering_cooperation", "工程协作"))),
        Node("logistics", "物流与贸易",
            Node("logistics_contract", "货运合约",
                Node("logistics_local_cargo", "本地货运"),
                Node("logistics_multi_stop_cargo", "多站点货运"),
                Node("logistics_interstellar_cargo", "跨星系货运"),
                Node("logistics_industrial_cargo", "工业货运")),
            Node("logistics_trade", "商品贸易",
                Node("logistics_legal_trade", "合法贸易"),
                Node("logistics_high_value_trade", "高价值贸易"),
                Node("logistics_grey_trade", "灰色贸易"),
                Node("logistics_smuggling", "走私")),
            Node("logistics_cargo_operations", "货物作业",
                Node("logistics_loading", "装卸协作"),
                Node("logistics_convoy", "商队运输"),
                Node("logistics_vehicle_transport", "载具运输")),
            Node("logistics_delivery", "配送任务",
                Node("logistics_box_delivery", "箱件配送"),
                Node("logistics_multi_point_delivery", "多点配送"),
                Node("logistics_recovery_delivery", "回收与交付"))),
        Node("support", "救援与支援",
            Node("support_medical", "医疗",
                Node("support_field_treatment", "现场救治"),
                Node("support_combat_medic", "战地医疗"),
                Node("support_casualty_transport", "伤员转运")),
            Node("support_search_rescue", "搜索救援",
                Node("support_player_rescue_beacon", "玩家救援信标"),
                Node("support_rescue_mission", "搜救任务"),
                Node("support_stranded_rescue", "受困人员救援"),
                Node("support_personnel_recovery", "人员回收")),
            Node("support_ship_service", "舰船服务",
                Node("support_refueling", "舰船加油"),
                Node("support_towing", "牵引回收"),
                Node("support_field_repair", "现场维修"),
                Node("support_ammo_resupply", "弹药与物资补给")),
            Node("support_escort_security", "护航安保",
                Node("support_cargo_escort", "货运护航"),
                Node("support_industry_escort", "工业护航"),
                Node("support_fleet_security", "舰队安保"),
                Node("support_anti_piracy_patrol", "反海盗巡逻"))),
        Node("exploration", "探索与调查",
            Node("exploration_exploration", "探索",
                Node("exploration_space", "太空探索"),
                Node("exploration_planetary", "行星探索"),
                Node("exploration_interstellar", "跨星系远征"),
                Node("exploration_landmark", "地标探索")),
            Node("exploration_recon", "侦察",
                Node("exploration_route_recon", "路线勘察"),
                Node("exploration_frontier_recon", "前沿侦察"),
                Node("exploration_target_recon", "目标侦察"),
                Node("exploration_resource_recon", "资源侦察")),
            Node("exploration_investigation", "调查",
                Node("exploration_missing_person", "失踪人员调查"),
                Node("exploration_wreck", "残骸调查"),
                Node("exploration_cave_search", "洞穴搜索"),
                Node("exploration_evidence_recovery", "证据回收"))),
        Node("arena", "竞技场 AC",
            Node("arena_pve", "PVE",
                Node("arena_pirate_swarm", "海盗潮"),
                Node("arena_endless_vanduul_swarm", "无尽剜度潮")),
            Node("arena_ship", "舰船竞技",
                Node("arena_duel", "单挑"),
                Node("arena_duo", "双人对抗"),
                Node("arena_squadron_battle", "中队战"),
                Node("arena_ship_battle_royale", "舰船大逃杀")),
            Node("arena_fps", "FPS 竞技",
                Node("arena_elimination", "歼灭战"),
                Node("arena_control_point", "控制点"),
                Node("arena_gun_game", "武器晋级"),
                Node("arena_kill_collect", "击杀收集")),
            Node("arena_racing", "竞速",
                Node("arena_ship_racing", "舰船竞速"),
                Node("arena_hover_racing", "悬浮载具竞速")),
            Node("arena_free_training", "自由训练",
                Node("arena_free_flight", "自由飞行"),
                Node("arena_ship_familiarization", "舰船熟悉"),
                Node("arena_loadout_test", "武器配装测试"),
                Node("arena_multicrew_training", "多人船员训练"))),
        Node("social", "社交与休闲",
            Node("social_sightseeing", "观光摄影",
                Node("social_city_sightseeing", "城市观光"),
                Node("social_space_sightseeing", "太空观光"),
                Node("social_screenshot_photography", "截图摄影")),
            Node("social_gathering", "玩家聚会",
                Node("social_ship_show", "舰船展会"),
                Node("social_vehicle_meet", "载具聚会"),
                Node("social_free_gathering", "自由聚会")),
            Node("social_roleplay", "角色扮演",
                Node("social_fleet_roleplay", "舰队角色扮演"),
                Node("social_law_roleplay", "执法角色扮演"),
                Node("social_outlaw_roleplay", "法外角色扮演")),
            Node("social_beginner", "新手活动",
                Node("social_first_flight", "首次飞行"),
                Node("social_basic_mission", "基础任务"),
                Node("social_mechanics_tutorial", "机制教学"),
                Node("social_ship_experience", "舰船体验"))),
        Node("special", "特殊任务与活动",
            Node("special_stanton", "斯坦顿星系",
                Node("special_stanton_asd_onyx", "ASD玛瑙设施"),
                Node("special_stanton_laser_mining_station", "激光采矿站"),
                Node("special_stanton_siege_orison", "奥里森之围（尚未开始）")),
            Node("special_pyro", "派罗星系",
                Node("special_pyro_asd_stormbreaker", "ASD风暴突破者")),
            Node("special_nyx", "尼克斯星系",
                Node("special_nyx_qv_station", "QV空间站"),
                Node("special_nyx_qv_breaker_yard", "QV碎岩站"),
                Node("special_nyx_strike_group", "战术打击群"))),
        Node("undecided", "不知道玩啥")
    ];

    public static IReadOnlyList<PartyRoomContextTagGroup> ContextGroups { get; } =
    [
        new("pace", "队伍节奏",
        [
            new("pace_departing_now", "马上出发"),
            new("pace_casual", "休闲慢玩"),
            new("pace_efficient", "高效推进"),
            new("pace_short_session", "短时任务"),
            new("pace_long_session", "长线游玩")
        ]),
        new("experience", "经验氛围",
        [
            new("experience_beginner_friendly", "新手友好"),
            new("experience_teaching", "带新教学"),
            new("experience_first_try", "首次尝试"),
            new("experience_familiar", "熟悉机制"),
            new("experience_hardcore", "硬核协作"),
            new("experience_roleplay", "角色扮演")
        ]),
        new("need", "当前缺口",
        [
            new("need_pilot", "缺飞行员"),
            new("need_gunner", "缺炮手"),
            new("need_ground", "缺地面战斗"),
            new("need_medic", "缺医疗"),
            new("need_engineer", "缺工程"),
            new("need_escort", "缺护航"),
            new("need_cargo", "缺运输"),
            new("need_scout", "缺侦察")
        ])
    ];

    private static readonly IReadOnlyDictionary<string, PartyRoomTagNode> GameplayById =
        Flatten(GameplayRoots).ToDictionary(entry => entry.Node.Id, entry => entry.Node, StringComparer.OrdinalIgnoreCase);

    private static readonly IReadOnlyDictionary<string, string?> GameplayParentById =
        Flatten(GameplayRoots).ToDictionary(entry => entry.Node.Id, entry => entry.ParentId, StringComparer.OrdinalIgnoreCase);

    private static readonly IReadOnlyDictionary<string, string> LegacyGameplayIds =
        new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
        {
            ["pve_space_combat"] = "pve_ship_combat_mission",
            ["pve_beacon"] = "support_player_rescue_beacon",
            ["pve_mercenary"] = "pve_combined_combat",
            ["pve_ground_combat"] = "pve_bunker",
            ["pve_clearance"] = "pve_settlement_clearance",
            ["pve_defense"] = "pve_bunker",
            ["pve_combined_mission"] = "pve_combined_combat",
            ["pve_multistage"] = "pve_combined_combat",
            ["pve_space_ground"] = "pve_combined_combat",
            ["pvp_space_combat"] = "pvp",
            ["pvp_interdiction"] = "pvp_fleet_combat",
            ["pvp_ground_combat"] = "pvp_fps",
            ["pvp_control_point"] = "arena_control_point",
            ["pvp_outlaw"] = "pvp_piracy",
            ["pvp_privateering"] = "pvp_piracy",
            ["industry_gathering"] = "industry_mining",
            ["industry_maintenance"] = "industry_repair_engineering",
            ["industry_engineering"] = "industry_ship_engineering",
            ["industry_repair"] = "industry_hull_repair",
            ["industry_resupply"] = "support_ammo_resupply",
            ["logistics_cargo"] = "logistics_contract",
            ["logistics_hauling"] = "logistics_local_cargo",
            ["logistics_trading"] = "logistics_legal_trade",
            ["logistics_passenger"] = "logistics_vehicle_transport",
            ["logistics_transport"] = "logistics_vehicle_transport",
            ["logistics_shuttle"] = "logistics_vehicle_transport",
            ["support_exploration"] = "exploration_exploration",
            ["support_deep_space"] = "exploration_space",
            ["support_scouting"] = "exploration_recon",
            ["support_route_survey"] = "exploration_route_recon",
            ["support_rescue"] = "support_search_rescue",
            ["support_recovery"] = "support_personnel_recovery",
            ["mixed"] = "combat_pve_pvp",
            ["mixed_security"] = "support_escort_security",
            ["mixed_escort"] = "support_cargo_escort",
            ["mixed_guard"] = "support_fleet_security",
            ["mixed_anti_piracy"] = "support_anti_piracy_patrol",
            ["mixed_large_operation"] = "combat_pve_pvp",
            ["mixed_fleet_operation"] = "combat_pve_pvp",
            ["mixed_multi_party"] = "combat_pve_pvp",
            ["mixed_campaign"] = "combat_pve_pvp",
            ["mixed_open_conflict"] = "combat_pve_pvp",
            ["mixed_pve_pvp"] = "combat_pve_pvp",
            ["mixed_resource_conflict"] = "combat_pyro_contested_zone",
            ["other"] = "social",
            ["other_competition"] = "arena",
            ["other_racing"] = "arena_racing",
            ["other_arena"] = "arena",
            ["other_social"] = "social",
            ["other_free_play"] = "social_free_gathering",
            ["other_roleplay"] = "social_roleplay",
            ["other_sightseeing"] = "social_sightseeing",
            ["other_beginner"] = "social_beginner",
            ["other_beginner_mission"] = "social_basic_mission",
            ["other_first_experience"] = "social_mechanics_tutorial"
        };

    private static readonly IReadOnlyDictionary<string, PartyRoomContextTag> ContextById =
        ContextGroups.SelectMany(group => group.Tags)
            .ToDictionary(tag => tag.Id, tag => tag, StringComparer.OrdinalIgnoreCase);

    public static string NormalizeGameplayId(string id) =>
        LegacyGameplayIds.TryGetValue(id, out var replacement) ? replacement : id;

    public static bool TryGetGameplayNode(string id, out PartyRoomTagNode node) =>
        GameplayById.TryGetValue(NormalizeGameplayId(id), out node!);

    public static bool TryGetContextTag(string id, out PartyRoomContextTag tag) =>
        ContextById.TryGetValue(id, out tag!);

    public static IReadOnlyList<PartyRoomTagNode> GetGameplayPath(string id)
    {
        id = NormalizeGameplayId(id);
        if (!GameplayById.ContainsKey(id))
        {
            return [];
        }

        var result = new List<PartyRoomTagNode>();
        string? currentId = id;
        while (!string.IsNullOrWhiteSpace(currentId) && GameplayById.TryGetValue(currentId, out var current))
        {
            result.Add(current);
            currentId = GameplayParentById[current.Id];
        }

        result.Reverse();
        return result;
    }

    public static string GetGameplayPathText(string id) =>
        string.Join(" / ", GetGameplayPath(id).Select(node => node.Name));

    public static string GetCompactGameplayText(string id)
    {
        var path = GetGameplayPath(id);
        return path.Count switch
        {
            0 => id,
            1 => path[0].Name,
            2 => $"{path[0].Name} · {path[1].Name}",
            _ => $"{path[0].Name} · {path[1].Name} · {path[^1].Name}"
        };
    }

    public static string GetGameplayRootName(string id) =>
        GetGameplayPath(id).FirstOrDefault()?.Name ?? id;

    public static bool IsNodeOrDescendantOf(string nodeId, string ancestorId)
    {
        var path = GetGameplayPath(nodeId);
        return path.Any(node => node.Id.Equals(ancestorId, StringComparison.OrdinalIgnoreCase));
    }

    public static bool AreOnSameBranch(string leftId, string rightId) =>
        IsNodeOrDescendantOf(leftId, rightId) || IsNodeOrDescendantOf(rightId, leftId);

    public static IReadOnlyList<string> NormalizeGameplaySelection(IEnumerable<string> selectedIds, string addedId)
    {
        addedId = NormalizeGameplayId(addedId);
        if (!GameplayById.ContainsKey(addedId))
        {
            return selectedIds
                .Select(NormalizeGameplayId)
                .Where(GameplayById.ContainsKey)
                .Distinct(StringComparer.OrdinalIgnoreCase)
                .ToArray();
        }

        var result = selectedIds
            .Select(NormalizeGameplayId)
            .Where(id => GameplayById.ContainsKey(id) && !AreOnSameBranch(id, addedId))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToList();
        result.Add(addedId);
        return result;
    }

    private static PartyRoomTagNode Node(string id, string name, params PartyRoomTagNode[] children) =>
        new(id, name, children);

    private static IEnumerable<(PartyRoomTagNode Node, string? ParentId)> Flatten(
        IEnumerable<PartyRoomTagNode> nodes,
        string? parentId = null)
    {
        foreach (var node in nodes)
        {
            yield return (node, parentId);
            foreach (var child in Flatten(node.Children, node.Id))
            {
                yield return child;
            }
        }
    }
}

public sealed record PartyRoomDisplayTag(
    string Id,
    string CategoryId,
    string Text,
    bool IsPrimary,
    string Foreground,
    string Background,
    string BorderBrush);

public static class PartyRoomTagPresentation
{
    private const string NeutralForeground = "#8DA3B1";
    private const string NeutralBackground = "#0E1821";
    private const string NeutralBorder = "#273B48";

    private static readonly IReadOnlyDictionary<string, TagPalette> GameplayRootPalettes =
        new Dictionary<string, TagPalette>(StringComparer.OrdinalIgnoreCase)
        {
            ["combat"] = new("#FF9AA2", "#321D25", "#85434D"),
            ["industry"] = new("#F2CA68", "#302816", "#78622E"),
            ["logistics"] = new("#8BBEFF", "#18283A", "#45688D"),
            ["support"] = new("#75D9A3", "#173024", "#3D795B"),
            ["exploration"] = new("#6FD5E7", "#142D34", "#3C7280"),
            ["arena"] = new("#C09CF4", "#292039", "#674F8C"),
            ["social"] = new("#F0A7D4", "#30202D", "#76506C"),
            ["special"] = new("#FFB878", "#34251A", "#835D3E")
        };

    private static readonly TagPalette FallbackGameplayPalette =
        new("#B8C5CE", "#222C34", "#50616D");

    public static IReadOnlyList<PartyRoomDisplayTag> Create(
        IEnumerable<string>? gameplayTagNodeIds,
        IEnumerable<string>? contextTagIds)
    {
        var gameplayPaths = (gameplayTagNodeIds ?? [])
            .Select(PartyRoomTagCatalog.GetGameplayPath)
            .Where(path => path.Count > 0)
            .ToArray();
        var result = new List<PartyRoomDisplayTag>();
        var addedIds = new HashSet<string>(StringComparer.OrdinalIgnoreCase);

        foreach (var path in gameplayPaths)
        {
            var selected = path[^1];
            if (addedIds.Add(selected.Id))
            {
                result.Add(CreateGameplay(path));
            }
        }

        foreach (var id in contextTagIds ?? [])
        {
            if (addedIds.Add(id) && PartyRoomTagCatalog.TryGetContextTag(id, out var tag))
            {
                result.Add(CreateSecondary(tag.Id, tag.Name));
            }
        }

        return result;
    }

    private static PartyRoomDisplayTag CreateGameplay(IReadOnlyList<PartyRoomTagNode> path)
    {
        var root = path[0];
        var palette = GameplayRootPalettes.GetValueOrDefault(root.Id, FallbackGameplayPalette);

        return new(
            path[^1].Id,
            root.Id.ToLowerInvariant(),
            string.Join(" · ", path.Select(node => node.Name)),
            true,
            palette.Foreground,
            palette.Background,
            palette.Border);
    }

    private static PartyRoomDisplayTag CreateSecondary(string id, string text) =>
        new(id, "other", text, false, NeutralForeground, NeutralBackground, NeutralBorder);

    private sealed record TagPalette(string Foreground, string Background, string Border);
}

public sealed record PartyRoomCreateDraft(
    string Title,
    string Goal,
    IReadOnlyList<string> GameplayTagNodeIds,
    IReadOnlyList<string> ContextTagIds,
    int Capacity,
    bool IsPublic,
    PartyRoomEligibility Eligibility,
    PartyLobbyAdmissionMode AdmissionMode,
    bool PasswordEnabled,
    string Password,
    PartyLobbyVoiceRequirement VoiceRequirement,
    PartyRoomLanguage Language,
    int? RecruitmentDurationMinutes,
    int AutoDisbandHours);

public sealed record PartyRoomCreationResult(
    PartyLobbyRoomCard? Room,
    IReadOnlyList<string> Errors)
{
    public bool IsSuccess => Room is not null && Errors.Count == 0;
}

public static class PartyRoomCreation
{
    public static PartyRoomCreationResult Create(
        PartyRoomCreateDraft draft,
        PartyLobbyMemberPreview host,
        DateTimeOffset now)
    {
        var title = draft.Title.Trim();
        var goal = draft.Goal.Trim();
        var gameplayIds = draft.GameplayTagNodeIds
            .Select(PartyRoomTagCatalog.NormalizeGameplayId)
            .Where(id => PartyRoomTagCatalog.TryGetGameplayNode(id, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var contextIds = draft.ContextTagIds
            .Where(id => PartyRoomTagCatalog.TryGetContextTag(id, out _))
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .ToArray();
        var errors = Validate(draft, title, goal, gameplayIds, contextIds);
        if (errors.Count > 0)
        {
            return new(null, errors);
        }

        var tags = gameplayIds
            .Select(PartyRoomTagCatalog.GetCompactGameplayText)
            .Concat(contextIds.Select(id => PartyRoomTagCatalog.TryGetContextTag(id, out var tag) ? tag.Name : id))
            .ToArray();
        var hostDisplay = string.IsNullOrWhiteSpace(host.GameId) ||
                          host.Callsign.Equals(host.GameId, StringComparison.OrdinalIgnoreCase)
            ? host.Callsign
            : $"{host.Callsign} ({host.GameId})";
        var room = new PartyLobbyRoomCard(
            Guid.NewGuid().ToString("N"),
            title,
            goal,
            hostDisplay,
            PartyRoomTagCatalog.GetGameplayRootName(gameplayIds[0]),
            tags,
            1,
            draft.Capacity,
            draft.VoiceRequirement,
            draft.AdmissionMode,
            draft.IsPublic,
            draft.PasswordEnabled,
            [host with { IsHost = true }],
            now)
        {
            RoomCode = Convert.ToHexString(RandomNumberGenerator.GetBytes(3)),
            Eligibility = draft.Eligibility,
            Language = draft.Language,
            RecruitmentClosesAt = draft.RecruitmentDurationMinutes.HasValue
                ? now.AddMinutes(draft.RecruitmentDurationMinutes.Value)
                : null,
            ExpiresAt = now.AddHours(draft.AutoDisbandHours),
            GameplayTagNodeIds = gameplayIds,
            ContextTagIds = contextIds,
            TagCatalogVersion = PartyRoomTagCatalog.Version
        };

        return new(room, []);
    }

    private static List<string> Validate(
        PartyRoomCreateDraft draft,
        string title,
        string goal,
        IReadOnlyList<string> gameplayIds,
        IReadOnlyList<string> contextIds)
    {
        var errors = new List<string>();
        if (title.Length is < 2 or > 32)
        {
            errors.Add("房间名需要 2–32 个字符。");
        }

        if (goal.Length > 120)
        {
            errors.Add("组队目标最多 120 个字符。");
        }

        if (gameplayIds.Count is < 1 or > 3)
        {
            errors.Add("请选择 1–3 条玩法路径。");
        }
        else if (gameplayIds.SelectMany((id, index) => gameplayIds.Skip(index + 1)
                     .Select(other => PartyRoomTagCatalog.AreOnSameBranch(id, other)))
                 .Any(onSameBranch => onSameBranch))
        {
            errors.Add("同一玩法路径不能同时选择父级和子级。");
        }

        if (contextIds.Count > 3 || gameplayIds.Count + contextIds.Count > 5)
        {
            errors.Add("附加标签最多 3 个，全部标签合计最多 5 个。");
        }

        if (draft.Capacity is < 2 or > 16)
        {
            errors.Add("人数上限需要在 2–16 人之间。");
        }

        if (draft.PasswordEnabled && draft.Password.Trim().Length is < 4 or > 32)
        {
            errors.Add("房间密码需要 4–32 个字符。");
        }

        if (draft.RecruitmentDurationMinutes is <= 0)
        {
            errors.Add("招募时长必须大于 0，或选择不限时。");
        }

        if (draft.AutoDisbandHours is not (1 or 2 or 4 or 6 or 12 or 24))
        {
            errors.Add("请选择有效的自动解散时间。");
        }

        if (draft.RecruitmentDurationMinutes.HasValue &&
            draft.RecruitmentDurationMinutes.Value > draft.AutoDisbandHours * 60)
        {
            errors.Add("招募截止时间不能晚于房间自动解散时间。");
        }

        return errors;
    }
}
