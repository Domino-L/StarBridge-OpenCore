using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

public sealed record OverlayPresetTrigger(string OwnerKey, long Generation, string Source);

internal sealed partial class OverlayCommunitySource
{
    internal OverlayPresetTrigger? CurrentPresetTrigger()
    {
        lock (_sync)
        {
            CheckScope();
            var scope = _scope;
            if (_disposed || _choiceFailed || scope.Owner is null) return null;
            var source = ReadPresetTrigger(false);
            return source is null || _owner() != scope ? null :
                new(OverlaySceneChoiceStore.Hash(scope.Owner), scope.Generation, source);
        }
    }
    // Called inside the scoped Bridge read lock. Preset bindings are deliberately
    // excluded: switching the preset must not recursively change its own trigger.
    private string? ReadPresetTrigger(bool catalogFailed)
    {
        var room = _presetRoomTrigger();
        if (!room.Known) return null;
        if (room.Room is not null) return "room:" + room.Room;
        if (catalogFailed || _catalogAt == default || _now() - _catalogAt >= TimeSpan.FromSeconds(30) || _scope.Owner is null) return null;
        var context = PeekResolutionContext(_scope.Owner, _scope.Generation, null);
        if (context is null) return null;
        var resolved = OverlayModuleSourceResolver.Resolve(new(OverlaySourceBinding.Follow), context, activeModules: []).PresetSource;
        if (resolved.Mode == OverlaySourceMode.Community && resolved.Available) return "org:" + resolved.Id;
        // Do not interpret a temporary roster gap as a source change. A fresh
        // complete directory can confirm removal; display still expires normally.
        var intended = _choice.Mode == "community" ? _choice.Code :
            _choice.Mode == "auto" ? _focusedModuleCommunity : null;
        return intended is not null && _catalog.Any(target => target.Code == intended) ? null : "local";
    }
}
