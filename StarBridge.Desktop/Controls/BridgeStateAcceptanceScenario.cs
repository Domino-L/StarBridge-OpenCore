#if DEBUG
namespace StarBridge.Desktop.Controls;

internal sealed record BridgeStateAcceptanceDescriptor(
    BridgeStateKind State,
    string Title,
    string Description,
    string ActionText,
    bool? MotionEnabledOverride);

internal static class BridgeStateAcceptanceCatalog
{
    internal static BridgeStateAcceptanceDescriptor Resolve(string scenario) => scenario switch
    {
        "loading" => new(
            BridgeStateKind.Loading,
            "正在同步服务器数据",
            "验收加载环、文案与禁止操作状态。",
            string.Empty,
            null),
        "empty" => new(
            BridgeStateKind.Empty,
            "当前没有可显示的数据",
            "验收空状态的图标、层级与主操作区域。",
            string.Empty,
            null),
        "error" => new(
            BridgeStateKind.Error,
            "无法同步服务器数据",
            "检查网络后重试；已有本地设置不会受到影响。",
            "重试",
            null),
        "timeout" => new(
            BridgeStateKind.Error,
            "同步等待时间过长",
            "本次同步已终止，可以立即重试。",
            "重试",
            null),
        "no-permission" => new(
            BridgeStateKind.AccessDenied,
            "当前账号没有查看权限",
            "联系组织管理者确认账号权限。",
            string.Empty,
            null),
        "cached-offline" => new(
            BridgeStateKind.OfflineCache,
            "当前离线，显示的是本地缓存",
            "恢复连接后会自动同步。",
            "重试",
            null),
        "reduced-motion" => new(
            BridgeStateKind.Loading,
            "正在同步 · 减少动态效果",
            "加载仍在继续，环保持静止，数据门不会因此卡住。",
            string.Empty,
            false),
        _ => throw new ArgumentOutOfRangeException(nameof(scenario), scenario, null)
    };
}
#endif
