using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class OverlayFleetSourceTests
{
    private static readonly DateTimeOffset Now = DateTimeOffset.UtcNow;
    private static OverlaySourceResolutionContext Context => new("owner", 1, Now, OverlaySourceBinding.Automatic,
        new(OverlaySourceMode.Room, "room", "owner", 1, Now.AddSeconds(40)), "community",
        new Dictionary<string, OverlaySourceLease> { ["community"] = new(OverlaySourceMode.Community, "community", "owner", 1, Now.AddSeconds(40)) })
    { Fleet = new(OverlaySourceMode.Fleet, "fleet", "owner", 1, Now.AddSeconds(40)) };
    private static readonly OverlaySourceBinding Fleet = new(OverlaySourceMode.Fleet);
    private static void Check(bool value, string message) { if (!value) throw new Exception(message); }

    internal static void RunAll()
    {
        var policy = new OverlayPresetSources(Fleet, true,
            new Dictionary<OverlaySourceModule, OverlaySourceBinding> { [OverlaySourceModule.Members] = Fleet }, [Fleet, new(OverlaySourceMode.Room)]);
        var encoded = OverlayPresetSourcesCodec.Serialize(policy);
        Check(OverlayPresetSourcesCodec.Serialize(OverlayPresetSourcesCodec.Parse(encoded)) == encoded, "Fleet binding/module/chat codec round-trips.");
        Console.WriteLine("PASS fleet source codec round-trip");
        var old = OverlayPresetSourcesCodec.Serialize(OverlayPresetSources.Default);
        Check(OverlayPresetSourcesCodec.Parse(old).Binding.Mode == OverlaySourceMode.None, "Old v2 files still load without fleet.");
        Check(OverlayPresetSourcesCodec.FromLegacy(OverlayScenePreference.Fleet).Binding.Mode == OverlaySourceMode.None, "Legacy migration remains unchanged.");
        Console.WriteLine("PASS old source files and legacy mapping");
        var plan = OverlayModuleSourceResolver.Resolve(policy, Context);
        Check(plan.PresetSource.Mode == OverlaySourceMode.Fleet && plan.Modules[OverlaySourceModule.Members].Mode == OverlaySourceMode.Fleet &&
            plan.ResourceKeys.Count == 2, "Fleet modules share one resource.");
        Console.WriteLine("PASS fleet preset and module resolution");
        var absent = Context with { Fleet = null };
        plan = OverlayModuleSourceResolver.Resolve(new(Fleet), absent);
        Check(!plan.PresetSource.Available && plan.PresetSource.Mode == OverlaySourceMode.Fleet && !plan.PresetBindingUnavailable &&
            plan.Modules.Values.All(source => source.Mode == OverlaySourceMode.Fleet && !source.Available), "Fixed fleet never falls back to a room or organization.");
        Check(!OverlayModuleSourceResolver.Resolve(new(Fleet), Context with { Now = Now.AddMinutes(1) }).PresetSource.Available, "Expired fleet lease fails closed.");
        Check(!OverlayModuleSourceResolver.Resolve(new(Fleet), Context with { Generation = 2 }).PresetSource.Available, "Old fleet generation fails closed.");
        Console.WriteLine("PASS unavailable fleet isolation and scope");
        plan = OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context, Fleet);
        Check(plan.PresetSource.Mode == OverlaySourceMode.Fleet, "Temporary fleet overrides the preset.");
        Console.WriteLine("PASS temporary fleet selection");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context).PresetSource.Mode == OverlaySourceMode.Room &&
            OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context with { CurrentRoom = null }).PresetSource.Mode == OverlaySourceMode.Community &&
            OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context with { CurrentRoom = null, FocusedCommunityCode = null }).PresetSource.Mode == OverlaySourceMode.Local,
            "Unfocused auto never discovers the fleet.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context with { FocusedFleet = true }).PresetSource.Mode == OverlaySourceMode.Room,
            "Existing room priority is unchanged.");
        Check(OverlayModuleSourceResolver.Resolve(OverlayPresetSources.Default, Context with { FocusedFleet = true, CurrentRoom = null }).PresetSource.Mode == OverlaySourceMode.Fleet,
            "Explicit page focus supplies fleet auto source.");
        Console.WriteLine("PASS automatic ordering and focused fleet");
        Check(OverlayModuleSourceResolver.RequestsFleetRefresh(new(Fleet), absent, [OverlaySourceModule.Members]) &&
            !OverlayModuleSourceResolver.RequestsFleetRefresh(OverlayPresetSources.Default, Context, [OverlaySourceModule.Members]) &&
            !OverlayModuleSourceResolver.RequestsFleetRefresh(new(Fleet), Context, []) &&
            OverlayModuleSourceResolver.RequestedCommunities(new(Fleet), Context, [OverlaySourceModule.Members]).Count == 0,
            "Fleet demand recovers an absent lease without reading other organizations.");
        Console.WriteLine("PASS fleet read intent and hidden modules");
        var transfer = OverlayPresetSourcesCodec.ForTransfer(policy);
        Check(transfer.Sources.Binding.Mode == OverlaySourceMode.Fleet && transfer.Sources.ChatSources.Any(source => source.Mode == OverlaySourceMode.Fleet) &&
            !transfer.Sources.AutoSwitch, "Transfer preserves the identity-free fleet source without enabling auto switching.");
        Console.WriteLine("PASS fleet preset transfer");
        var organizations = Enumerable.Range(0, 8).ToDictionary(i => "org" + i, i =>
            new OverlaySourceLease(OverlaySourceMode.Community, "org" + i, "owner", 1, Now.AddSeconds(40)));
        var crowded = new OverlayPresetSources(Fleet, chatSources: organizations.Keys.Select(code => new OverlaySourceBinding(OverlaySourceMode.Community, code, "owner")).ToArray());
        var budget = new OverlayModuleSourceBudget();
        var crowdedContext = Context with { Communities = organizations };
        try { budget.Resolve(crowded, crowdedContext); throw new Exception("Fleet did not consume its source budget."); }
        catch (OverlaySourceLimitException) { }
        Check(budget.RequiresFleetConfirmation("owner", 1), "Fleet participates in membership confirmation under a latched budget.");
        budget.ConfirmFleet("owner", 1, false);
        Check(budget.Resolve(crowded, crowdedContext with { Fleet = null }).ResourceKeys.Count == 8, "Confirmed fleet departure releases the source budget.");
        Console.WriteLine("PASS fleet source budget and departure");
        Console.WriteLine("PASS Core fleet: 9 cases, 0 failed");
    }
}
