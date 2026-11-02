using StarBridge.Core.Overlay;

namespace StarBridge.HostRuntime.Overlay;

/// <summary>
/// What each module asked to show, for naming only. An unavailable resolved source
/// carries no id, so this mirrors the resolver's precedence (module binding, else the
/// temporary/preset/account choice, including the resolver's own automatic fallback)
/// without changing it. It never selects, reads or authorizes a source.
/// </summary>
internal sealed class OverlayModuleSourceRequests
{
    private readonly IReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding> _modules;
    private readonly IReadOnlyList<OverlaySourceBinding> _chat;
    private readonly IReadOnlySet<OverlaySourceModule> _own;
    private readonly Func<string, string?>? _communityName;
    private readonly bool _signedOut;
    private readonly bool _roomAbsent;

    private OverlayModuleSourceRequests(IReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding> modules,
        IReadOnlyList<OverlaySourceBinding> chat, IReadOnlySet<OverlaySourceModule> own,
        Func<string, string?>? communityName, bool signedOut, bool roomAbsent)
    {
        _modules = modules;
        _chat = chat;
        _own = own;
        _communityName = communityName;
        _signedOut = signedOut;
        _roomAbsent = roomAbsent;
    }

    internal static OverlayModuleSourceRequests From(OverlayPresetSources preset, OverlaySourceResolutionContext context,
        OverlaySourceBinding? temporaryChoice, OverlayModuleSourcePlan plan, Func<string, string?>? communityName,
        bool signedOut, bool roomAbsent)
    {
        var inherited = plan.PresetBindingUnavailable ? OverlaySourceBinding.Automatic :
            temporaryChoice ?? (preset.Binding.Mode == OverlaySourceMode.None ? context.AccountChoice : preset.Binding);
        var modules = new Dictionary<OverlaySourceModule, OverlaySourceBinding>();
        var own = new HashSet<OverlaySourceModule>();
        foreach (var module in Enum.GetValues<OverlaySourceModule>())
        {
            var binding = preset.Modules.GetValueOrDefault(module, OverlaySourceBinding.Follow);
            if (binding.Mode != OverlaySourceMode.None) own.Add(module);
            modules[module] = binding.Mode == OverlaySourceMode.None ? inherited : binding;
        }
        if (preset.ChatSources.Count > 0)
        {
            own.Add(OverlaySourceModule.Chat);
            modules[OverlaySourceModule.Chat] = preset.ChatSources[0];
        }
        return new(modules, preset.ChatSources, own, communityName, signedOut, roomAbsent);
    }

    internal InformationOverlayModuleContent Describe(OverlaySourceModule module,
        InformationOverlayModuleContent content, string ownerKey) =>
        content with { Display = new(Name(content, _modules[module], ownerKey), _own.Contains(module), _signedOut, _roomAbsent) };

    // Aligned with OverlayModuleSourcePlan.ChatSources, which keeps the preset order.
    internal InformationOverlayModuleContent DescribeChat(int index, InformationOverlayModuleContent content, string ownerKey) =>
        content with { Display = new(Name(content, index < _chat.Count ? _chat[index] : null, ownerKey), true, _signedOut, _roomAbsent) };

    private string? Name(InformationOverlayModuleContent content, OverlaySourceBinding? requested, string ownerKey)
    {
        // Available content is named by its own validated receipt.
        if (content.Snapshot is { } snapshot) return Text(snapshot.Room?.Title ?? snapshot.Community?.Name);
        if (content.Source.Available || content.Source.UnavailableReason == "module_hidden" ||
            requested is not { Mode: OverlaySourceMode.Community, CommunityCode: { } code } ||
            requested.OwnerKey != ownerKey || _communityName is null) return null;
        try { return Text(_communityName(code)); }
        catch { return null; } // A failed directory lookup names nothing.
    }

    private static string? Text(string? value) => string.IsNullOrWhiteSpace(value) ? null : value.Trim();
}
