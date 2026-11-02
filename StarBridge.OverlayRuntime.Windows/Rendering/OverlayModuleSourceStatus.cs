using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Overlay;

namespace StarBridge.Desktop;

internal enum OverlayModuleEmptyKind { Unavailable, Syncing }

/// <summary>
/// A module's own status, never content. The headline always shows on one line.
/// Detail and Hint show only when Expanded: the first large visible module with this
/// problem explains it in full (members, then chat, then overview); other modules
/// carry the headline alone, so the same explanation never repeats across the HUD.
/// </summary>
internal sealed record OverlayModuleEmptyState(string Headline, OverlayModuleEmptyKind Kind = OverlayModuleEmptyKind.Unavailable)
{
    internal string? Detail { get; init; }
    internal string? Hint { get; init; }
    internal bool Expanded { get; init; }
}

[Flags]
internal enum OverlayModuleFlags { None = 0, Notice = 1, Overview = 2, Members = 4, Chat = 8, Events = 16 }

/// <summary>
/// HUD copy for module sources. It names only what Host named for this read. An
/// unavailable source is explained as itself; its text never borrows another source.
/// </summary>
internal static class OverlayModuleSourceCopy
{
    private enum Script { Simplified, Traditional, English }

    private static Script Of(string language) => language is "zh-Hant" or "zh-TW" ? Script.Traditional :
        language.StartsWith("zh", StringComparison.OrdinalIgnoreCase) ? Script.Simplified : Script.English;

    private static string T(Script script, string simplified, string traditional, string english) => script switch
    {
        Script.Simplified => simplified,
        Script.Traditional => traditional,
        _ => english
    };

    /// <summary>Trailing title label: room title, organization name or local.</summary>
    internal static string? Label(OverlaySourceMode mode, string? name, string language)
    {
        var script = Of(language);
        return mode switch
        {
            OverlaySourceMode.Room => name ?? T(script, "当前房间", "目前房間", "Current room"),
            OverlaySourceMode.Community => name ?? T(script, "组织", "組織", "Organization"),
            OverlaySourceMode.Fleet => name ?? T(script, "主舰队", "主艦隊", "Main fleet"),
            OverlaySourceMode.Local => T(script, "本地", "本地", "Local"),
            _ => null
        };
    }

    internal static string JoinLabels(IEnumerable<string> labels, string language) =>
        string.Join(Of(language) == Script.English ? ", " : "、", labels.Distinct(StringComparer.Ordinal));

    internal static OverlayModuleEmptyState? Unavailable(OverlaySourceModule module, OverlayResolvedSource source,
        InformationOverlayModuleSourceDisplay display, string language)
    {
        if (source.Available || source.UnavailableReason == "module_hidden") return null;
        var script = Of(language);
        if (display.SignedOut && source.Mode is OverlaySourceMode.Room or OverlaySourceMode.Community)
            return new(T(script, "登录后可显示组织和房间", "登入後可顯示組織和房間", "Sign in to show organizations and rooms"))
            {
                Detail = T(script, "现在只显示你自己的信息。", "目前只顯示你自己的資訊。", "Only your own information is shown for now.")
            };
        // Only Host's confirmed absence is "not in a room"; a lapsed room lease is unreachable.
        if (source.Mode == OverlaySourceMode.Room && source.UnavailableReason == "room_unavailable" && display.RoomAbsent)
            return new(T(script, "你现在不在房间里", "你目前不在房間裡", "You are not in a room")) { Detail = RoomDetail(module, script) };
        if (source.Mode is OverlaySourceMode.Room or OverlaySourceMode.Community)
        {
            var name = display.Name ?? (source.Mode == OverlaySourceMode.Room
                ? T(script, "当前房间", "目前房間", "The current room")
                : T(script, "该组织", "該組織", "This organization"));
            return new(T(script, $"{name} 暂时连不上", $"{name} 暫時連不上", $"{name} can't be reached right now"))
            {
                Detail = T(script, "会自动重试，不需要操作。", "會自動重試，不需要操作。", "Retrying automatically. Nothing to do.")
            };
        }
        return Generic(language);
    }

    /// <summary>No module source could be read at all; nothing specific to name.</summary>
    internal static OverlayModuleEmptyState Generic(string language) =>
        new(T(Of(language), "信息暂不可用", "資訊暫不可用", "Information unavailable"));

    internal static OverlayModuleEmptyState MultiChatUnavailable(string language) =>
        new(T(Of(language), "所选聊天来源暂不可用", "所選聊天來源暫不可用", "Selected chat sources unavailable"));

    internal static OverlayModuleEmptyState Syncing(string? label, string language)
    {
        var script = Of(language);
        return new(string.IsNullOrWhiteSpace(label)
            ? T(script, "正在同步…", "正在同步…", "Syncing…")
            : T(script, $"正在同步 {label}…", $"正在同步 {label}…", $"Syncing {label}…"), OverlayModuleEmptyKind.Syncing);
    }

    /// <summary>Where the source is changed. The in-game menu is named by its actual hotkey.</summary>
    internal static string SwitchHint(string? menuHotkey, string language)
    {
        var script = Of(language);
        return string.IsNullOrWhiteSpace(menuHotkey)
            ? T(script, "主程序 › 信息浮层 可换来源", "主程式 › 資訊浮層 可換來源", "Change the source in the app › Information overlay")
            : T(script, $"{menuHotkey} › 信息浮层 可换来源", $"{menuHotkey} › 資訊浮層 可換來源", $"{menuHotkey} › Information overlay to change source");
    }

    private static string RoomDetail(OverlaySourceModule module, Script script) => module switch
    {
        OverlaySourceModule.Members => T(script, "加入房间后这里会显示房间成员。", "加入房間後這裡會顯示房間成員。", "Room members appear here after you join a room."),
        OverlaySourceModule.Chat => T(script, "加入房间后这里会显示房间聊天。", "加入房間後這裡會顯示房間聊天。", "Room chat appears here after you join a room."),
        OverlaySourceModule.Overview => T(script, "加入房间后这里会显示房间概况。", "加入房間後這裡會顯示房間概況。", "The room overview appears here after you join a room."),
        _ => T(script, "加入房间后这里会显示房间信息。", "加入房間後這裡會顯示房間資訊。", "Room information appears here after you join a room.")
    };

    /// <summary>
    /// One full explanation per distinct problem, in the first large visible module
    /// (members, then chat as a list, then overview). A barrage draws no panel, and
    /// notice and events stay one line. Syncing states are never expanded.
    /// </summary>
    internal static OverlayModulePresentation ExplainOnce(OverlayModulePresentation modules, bool chatIsPanel, string hint)
    {
        var explained = new HashSet<string>(StringComparer.Ordinal);
        OverlayModuleScene Expand(OverlayModuleScene scene, bool large)
        {
            if (!large || scene.EmptyMessage is not { Kind: OverlayModuleEmptyKind.Unavailable, Detail: not null } state ||
                !explained.Add(state.Headline)) return scene;
            return scene with { EmptyMessage = state with { Expanded = true, Hint = hint } };
        }
        var members = Expand(modules.Members, large: true);
        var chat = Expand(modules.Chat, chatIsPanel);
        var overview = Expand(modules.Overview, large: true);
        return modules with { Members = members, Chat = chat, Overview = overview };
    }
}
