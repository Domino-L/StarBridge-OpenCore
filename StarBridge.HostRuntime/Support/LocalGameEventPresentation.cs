using StarBridge.Core.Events;

namespace StarBridge.HostRuntime.Support;

/// <summary>WPF's event wording, shared without WPF or a second name catalog.
/// Callers supply their existing ship/location presentation and resolved arrival target.</summary>
public static class LocalGameEventPresentation
{
    public static LocalGameEventRecord Process(bool running) => new(
        LocalGameEventCategories.Session,
        running ? "GameStarted" : "GameStopped",
        running ? "检测到 Star Citizen 启动" : "检测到 Star Citizen 退出",
        "来源：本机进程监控");

    public static string Title(FleetEvent e, Func<string?, string> ship,
        Func<string?, string> location, string? arrivalTarget = null)
    {
        var player = string.IsNullOrWhiteSpace(e.Player) ||
            e.Player.Equals("LocalPlayer", StringComparison.OrdinalIgnoreCase)
            ? "本地玩家" : e.Player.Trim();
        return e.Type switch
        {
            FleetEventType.PlayerOnline => $"已识别玩家：{player}",
            FleetEventType.PlayerOffline => $"{player} 已离线",
            FleetEventType.PlayerEnteredShip => $"{player} 进入飞船：{ship(e.Ship)}",
            FleetEventType.PlayerExitedShip => $"{player} 离开飞船：{ship(e.Ship)}",
            FleetEventType.PlayerControllingShip => $"{player} 进入驾驶位：{ship(e.Ship)}",
            FleetEventType.PlayerStoppedDrivingShip => $"{player} 离开驾驶位：{ship(e.Ship)}",
            FleetEventType.PlayerLocationChanged => Location(player, e, location, arrivalTarget),
            FleetEventType.PlayerNavigationTargetChanged => Navigation(player, e, location),
            FleetEventType.PlayerDowned => e.LifeContext == LifeEventContext.SafeZoneMedicalResponse
                ? $"{player} 在安全区倒地，本地救援已响应" : $"{player} 已失去行动能力，等待救援",
            FleetEventType.PlayerDied => $"{player} 已死亡，等待重生",
            FleetEventType.PlayerRevived => $"{player} 已被救起，恢复行动",
            FleetEventType.PlayerRespawned => $"{player} 已重生",
            FleetEventType.CombatStateChanged => $"{player} 状态：{e.CombatState switch
                { null or "" or "Idle" => "待命", "Combat" => "战斗中", _ => e.CombatState }}",
            _ => string.Empty
        };
    }

    public static string Detail(FleetEvent e) => e.Type switch
    {
        FleetEventType.PlayerEnteredShip or FleetEventType.PlayerExitedShip or
            FleetEventType.PlayerControllingShip or FleetEventType.PlayerStoppedDrivingShip =>
            string.IsNullOrWhiteSpace(e.Ship) ? "" : $"原始舰船标识：{e.Ship}",
        FleetEventType.PlayerLocationChanged or FleetEventType.PlayerNavigationTargetChanged =>
            string.IsNullOrWhiteSpace(e.Location) ? "" : $"原始地点标识：{e.Location}",
        _ => string.IsNullOrWhiteSpace(e.Player) ? "" : $"玩家：{e.Player}"
    };

    private static string Location(string player, FleetEvent e, Func<string?, string> name, string? arrival)
    {
        if (e.Location?.Equals("Arrived - awaiting location confirmation", StringComparison.OrdinalIgnoreCase) == true)
        {
            var target = name(arrival ?? e.NavigationTarget);
            return target.Equals("未知", StringComparison.OrdinalIgnoreCase)
                ? $"{player} 已结束量子航行，等待当前位置确认"
                : $"{player} 已抵达导航目标：{target}，等待当前位置确认";
        }
        return $"{player} 位置更新：{name(e.Location)}";
    }

    private static string Navigation(string player, FleetEvent e, Func<string?, string> name)
    {
        var origin = name(e.Location);
        var target = name(e.NavigationTarget);
        var hasOrigin = !origin.Equals("未知", StringComparison.OrdinalIgnoreCase);
        var hasTarget = !target.Equals("未知", StringComparison.OrdinalIgnoreCase);
        if (hasOrigin && hasTarget) return $"{player} 设置导航：{origin} → {target}";
        if (hasTarget) return $"{player} 设置导航目标：{target}";
        return hasOrigin ? $"{player} 当前位置：{origin}" : string.Empty;
    }
}
