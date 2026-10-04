using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

internal sealed partial class OverlayCommunitySource
{
    private sealed record SourceSelection(string? BindingId, string? TemporaryId, string? ActualId, string Status,
        IReadOnlyDictionary<string, string?>? ResolvedSourceIds = null);

    // Shares the native display resolver, but does not capture content or issue
    // leases. Picker labels are not authority and do not clear the source budget.
    private SourceSelection? ReadSourceSelection()
    {
        if (_scope.Owner is null || _moduleDemand() is not { Sources: { } policy } demand) return null;
        var context = CaptureResolutionContext(_scope.Owner, _scope.Generation, _moduleRoomLease());
        if (context is null) return new(null, null, null, "unavailable");
        string? Id(OverlaySourceBinding? source) => source?.Mode switch
        {
            OverlaySourceMode.Auto => "auto",
            OverlaySourceMode.Room => "room",
            OverlaySourceMode.Community => source.OwnerKey == context.OwnerKey &&
                _catalog.Any(row => row.Code == source.CommunityCode) ? "org:" + source.CommunityCode : "missing",
            _ => null
        };
        var temporary = demand.TemporarySource?.ForScope(context.OwnerKey, context.Generation);
        var plan = OverlayModuleSourceResolver.Resolve(policy, context, temporary, activeModules: []);
        string? ResolvedId(OverlayResolvedSource source) => source.Available ? source.Mode switch
        {
            OverlaySourceMode.Room => "room",
            OverlaySourceMode.Community => "org:" + source.Id,
            OverlaySourceMode.Local => "local",
            _ => null
        } : null;
        // Preview metadata only. Resolve choices through the same Core function
        // as native modules; Flutter must not reimplement automatic priority or
        // infer grants from the directory. No content fetch or lease renewal.
        string? ResolveChoice(OverlaySourceBinding choice) => ResolvedId(OverlayModuleSourceResolver.Resolve(
            new(OverlaySourceBinding.Automatic, modules: new Dictionary<OverlaySourceModule, OverlaySourceBinding>
            { [OverlaySourceModule.Notice] = choice }), context, activeModules: [OverlaySourceModule.Notice]).Modules[OverlaySourceModule.Notice]);
        var resolutions = new Dictionary<string, string?>
        { ["auto"] = ResolveChoice(OverlaySourceBinding.Automatic), ["room"] = ResolveChoice(new(OverlaySourceMode.Room)) };
        foreach (var target in _catalog)
            resolutions["org:" + target.Code] = ResolveChoice(new(OverlaySourceMode.Community, target.Code, context.OwnerKey));
        var actual = ResolvedId(plan.PresetSource);
        return new(Id(policy.Binding), Id(temporary), actual,
            plan.PresetBindingUnavailable ? "bindingUnavailable" : actual == "local" ? "local" : actual is null ? "unavailable" : "ready", resolutions);
    }
}
