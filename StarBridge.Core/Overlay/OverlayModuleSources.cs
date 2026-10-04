namespace StarBridge.Core.Overlay;

using System.Collections.ObjectModel;

public enum OverlaySourceMode { None, Auto, Room, Community, Local, Fleet }
public enum OverlaySourceModule { Notice, Overview, Members, Chat, Events }

/// <summary>A display request, never a grant. OwnerKey is an opaque account/environment key.</summary>
public sealed record OverlaySourceBinding
{
    public OverlaySourceMode Mode { get; }
    public string? CommunityCode { get; }
    public string? OwnerKey { get; }

    public OverlaySourceBinding(OverlaySourceMode mode, string? communityCode = null, string? ownerKey = null)
    {
        if (!Enum.IsDefined(mode) || (mode == OverlaySourceMode.Community
                ? !ValidKey(communityCode) || !ValidKey(ownerKey)
                : communityCode is not null || ownerKey is not null))
            throw new ArgumentException("Invalid overlay source binding.");
        Mode = mode;
        CommunityCode = communityCode;
        OwnerKey = ownerKey;
    }

    internal static bool ValidKey(string? value) => !string.IsNullOrWhiteSpace(value) &&
        value.Length <= 256 && value == value.Trim() && !value.Any(char.IsControl);
    public static OverlaySourceBinding Follow { get; } = new(OverlaySourceMode.None);
    public static OverlaySourceBinding Automatic { get; } = new(OverlaySourceMode.Auto);
}

/// <summary>Immutable preset policy. Missing module entries mean follow the effective preset source.</summary>
public sealed class OverlayPresetSources
{
    public OverlaySourceBinding Binding { get; }
    public bool AutoSwitch { get; }
    public IReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding> Modules { get; }
    public IReadOnlyList<OverlaySourceBinding> ChatSources { get; }

    public OverlayPresetSources(OverlaySourceBinding binding, bool autoSwitch = false,
        IReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding>? modules = null,
        IReadOnlyList<OverlaySourceBinding>? chatSources = null)
    {
        ArgumentNullException.ThrowIfNull(binding);
        if (binding.Mode == OverlaySourceMode.Local || binding.Mode == OverlaySourceMode.Fleet ||
            autoSwitch && binding.Mode is not (OverlaySourceMode.Room or OverlaySourceMode.Community))
            throw new ArgumentException("Invalid preset source policy.");
        var copy = new Dictionary<OverlaySourceModule, OverlaySourceBinding>();
        foreach (var (module, source) in modules ?? new Dictionary<OverlaySourceModule, OverlaySourceBinding>())
        {
            if (!Enum.IsDefined(module) || source is null ||
                source.Mode is OverlaySourceMode.Local or OverlaySourceMode.Fleet)
                throw new ArgumentException("Invalid module source policy.");
            copy.Add(module, source);
        }
        Binding = binding;
        AutoSwitch = autoSwitch;
        Modules = new ReadOnlyDictionary<OverlaySourceModule, OverlaySourceBinding>(copy);
        var chat = (chatSources ?? []).ToArray();
        if (chat.Length > OverlayModuleSourceResolver.MaximumSources ||
            chat.Any(s => s is null || s.Mode is not (OverlaySourceMode.Room or OverlaySourceMode.Community)) ||
            chat.Distinct().Count() != chat.Length)
            throw new ArgumentException("Invalid chat source selection.");
        ChatSources = Array.AsReadOnly(chat.OrderBy(s => s.Mode).ThenBy(s => s.CommunityCode, StringComparer.Ordinal)
            .ThenBy(s => s.OwnerKey, StringComparer.Ordinal).ToArray());
    }

    public static OverlayPresetSources Default { get; } = new(OverlaySourceBinding.Follow);
}

/// <summary>Host-supplied evidence. This does not replace per-field privacy checks on content.</summary>
public sealed record OverlaySourceLease(OverlaySourceMode Mode, string Id, string OwnerKey,
    long Generation, DateTimeOffset ValidUntil)
{
    public bool IsValidFor(string owner, long generation, DateTimeOffset now) =>
        Mode is OverlaySourceMode.Room or OverlaySourceMode.Community &&
        OverlaySourceBinding.ValidKey(Id) && OwnerKey == owner && Generation == generation && now < ValidUntil;
}

public sealed record OverlaySourceResolutionContext(
    string OwnerKey, long Generation, DateTimeOffset Now,
    OverlaySourceBinding AccountChoice, OverlaySourceLease? CurrentRoom,
    string? FocusedCommunityCode, IReadOnlyDictionary<string, OverlaySourceLease> Communities);

public sealed record OverlayResolvedSource(OverlaySourceMode Mode, string? Id, bool Available,
    string? UnavailableReason = null)
{
    // Unavailable sources must never be used as resource read keys.
    public string? ResourceKey => Available ? $"{Mode}:{Id ?? ""}" : null;
}

public sealed record OverlayModuleSourcePlan(
    string OwnerKey, long Generation, OverlayResolvedSource PresetSource,
    IReadOnlyDictionary<OverlaySourceModule, OverlayResolvedSource> Modules,
    bool PresetBindingUnavailable, IReadOnlyList<string> ResourceKeys)
{
    public IReadOnlyList<OverlayResolvedSource> ChatSources { get; init; } = [];
    public IEnumerable<OverlayResolvedSource> AllSources => Modules.Values.Concat(ChatSources);
}

/// <summary>One resolver for account choices, presets and modules. No I/O, caches or fallback grants.</summary>
public static class OverlayModuleSourceResolver
{
    public const int MaximumSources = 8;

    public static IReadOnlyCollection<OverlaySourceModule> VisibleModules(OverlayDisplaySettings settings) =>
        Array.AsReadOnly(Enum.GetValues<OverlaySourceModule>().Where(module => module switch
        {
            OverlaySourceModule.Notice => settings.ShowNotice,
            OverlaySourceModule.Overview => settings.ShowSquads,
            OverlaySourceModule.Members => settings.ShowMembers,
            OverlaySourceModule.Chat => settings.ShowChat,
            OverlaySourceModule.Events => settings.ShowEventNotifications,
            _ => false
        }).ToArray());

    public static OverlayModuleSourcePlan Resolve(OverlayPresetSources preset,
        OverlaySourceResolutionContext context, OverlaySourceBinding? temporaryChoice = null,
        IReadOnlyCollection<OverlaySourceModule>? activeModules = null)
    {
        ArgumentNullException.ThrowIfNull(preset);
        ArgumentNullException.ThrowIfNull(context);
        if (!OverlaySourceBinding.ValidKey(context.OwnerKey) || context.Generation < 0 ||
            activeModules?.Any(module => !Enum.IsDefined(module)) == true ||
            context.AccountChoice.Mode is OverlaySourceMode.None or OverlaySourceMode.Fleet ||
            temporaryChoice?.Mode is OverlaySourceMode.None or OverlaySourceMode.Fleet)
            throw new ArgumentException("Invalid source resolution context.");

        var choice = temporaryChoice ?? (preset.Binding.Mode == OverlaySourceMode.None
            ? context.AccountChoice : preset.Binding);
        var resolved = ResolveOne(choice, context);
        var fallback = temporaryChoice is null && preset.Binding.Mode == OverlaySourceMode.Community && !resolved.Available;
        if (fallback) resolved = Automatic(context);

        var modules = new Dictionary<OverlaySourceModule, OverlayResolvedSource>();
        foreach (var module in Enum.GetValues<OverlaySourceModule>())
        {
            var source = preset.Modules.GetValueOrDefault(module, OverlaySourceBinding.Follow);
            var selected = source.Mode == OverlaySourceMode.None ? resolved : ResolveOne(source, context);
            modules.Add(module, activeModules is not null && !activeModules.Contains(module)
                ? selected with { Available = false, UnavailableReason = "module_hidden" } : selected);
        }
        var chat = preset.ChatSources.Select(binding => ResolveOne(binding, context))
            .Select(source => activeModules is not null && !activeModules.Contains(OverlaySourceModule.Chat)
                ? source with { Available = false, UnavailableReason = "module_hidden" } : source).ToArray();
        if (chat.Length > 0) modules[OverlaySourceModule.Chat] = chat[0];
        var keys = modules.Values.Concat(chat).Select(source => source.ResourceKey).OfType<string>()
            .Distinct(StringComparer.Ordinal).Order(StringComparer.Ordinal).ToArray();
        if (keys.Length > MaximumSources)
            throw new OverlaySourceLimitException(keys);
        return new(context.OwnerKey, context.Generation, resolved,
            new ReadOnlyDictionary<OverlaySourceModule, OverlayResolvedSource>(modules),
            fallback, Array.AsReadOnly(keys)) { ChatSources = Array.AsReadOnly(chat) };
    }

    /// <summary>Refresh intent is not display authority. In particular an explicit
    /// room or automatic choice still needs the shared directory when its old lease
    /// expires. Reuse the display resolver for precedence, fallback and budget checks.</summary>
    public static bool RequestsRoomRefresh(OverlayPresetSources preset,
        OverlaySourceResolutionContext context, IReadOnlyCollection<OverlaySourceModule> activeModules,
        OverlaySourceBinding? temporaryChoice = null)
    {
        var plan = Resolve(preset, context, temporaryChoice, activeModules);
        var inherited = plan.PresetBindingUnavailable ? OverlaySourceBinding.Automatic :
            temporaryChoice ?? (preset.Binding.Mode == OverlaySourceMode.None ? context.AccountChoice : preset.Binding);
        return activeModules.Any(module =>
        {
            if (module == OverlaySourceModule.Chat && preset.ChatSources.Count > 0)
                return preset.ChatSources.Any(binding => binding.Mode == OverlaySourceMode.Room);
            var binding = preset.Modules.GetValueOrDefault(module, OverlaySourceBinding.Follow);
            if (binding.Mode == OverlaySourceMode.None) binding = inherited;
            return binding.Mode is OverlaySourceMode.Room or OverlaySourceMode.Auto;
        });
    }

    /// <summary>Organization read intent, not a grant or display plan. Expired
    /// bindings still require an authenticated membership/read attempt to recover.
    /// Hidden modules and bindings owned by a different account never request I/O.</summary>
    public static IReadOnlyList<string> RequestedCommunities(OverlayPresetSources preset,
        OverlaySourceResolutionContext context, IReadOnlyCollection<OverlaySourceModule> activeModules,
        OverlaySourceBinding? temporaryChoice = null)
    {
        var plan = Resolve(preset, context, temporaryChoice, activeModules);
        var inherited = temporaryChoice ?? (preset.Binding.Mode == OverlaySourceMode.None ? context.AccountChoice : preset.Binding);
        var codes = new HashSet<string>(StringComparer.Ordinal);
        void Add(OverlaySourceBinding binding)
        {
            if (binding.Mode == OverlaySourceMode.Community && binding.OwnerKey == context.OwnerKey)
                codes.Add(binding.CommunityCode!);
            else if (binding.Mode == OverlaySourceMode.Auto && !Valid(context.CurrentRoom, OverlaySourceMode.Room, context) &&
                context.FocusedCommunityCode is { } focused) codes.Add(focused);
        }
        foreach (var module in activeModules)
        {
            if (module == OverlaySourceModule.Chat && preset.ChatSources.Count > 0)
            {
                foreach (var source in preset.ChatSources) Add(source);
                continue;
            }
            var binding = preset.Modules.GetValueOrDefault(module, OverlaySourceBinding.Follow);
            if (binding.Mode != OverlaySourceMode.None) Add(binding);
            else
            {
                Add(inherited);
                if (plan.PresetBindingUnavailable) Add(OverlaySourceBinding.Automatic);
            }
        }
        return Array.AsReadOnly(codes.Order(StringComparer.Ordinal).ToArray());
    }

    private static OverlayResolvedSource ResolveOne(OverlaySourceBinding choice, OverlaySourceResolutionContext context) =>
        choice.Mode switch
        {
            OverlaySourceMode.Auto => Automatic(context),
            OverlaySourceMode.Local => new(OverlaySourceMode.Local, null, true),
            OverlaySourceMode.Room => Valid(context.CurrentRoom, OverlaySourceMode.Room, context)
                ? new(OverlaySourceMode.Room, context.CurrentRoom!.Id, true)
                : new(OverlaySourceMode.Room, null, false, "room_unavailable"),
            OverlaySourceMode.Community => choice.OwnerKey == context.OwnerKey &&
                context.Communities.TryGetValue(choice.CommunityCode!, out var lease) &&
                lease.Id == choice.CommunityCode && Valid(lease, OverlaySourceMode.Community, context)
                    ? new(OverlaySourceMode.Community, lease.Id, true)
                    : new(OverlaySourceMode.Community, null, false, "community_unavailable"),
            _ => throw new ArgumentException("Unsupported source choice.")
        };

    private static bool Valid(OverlaySourceLease? lease, OverlaySourceMode mode, OverlaySourceResolutionContext context) =>
        lease?.Mode == mode && lease.IsValidFor(context.OwnerKey, context.Generation, context.Now);

    private static OverlayResolvedSource Automatic(OverlaySourceResolutionContext context)
    {
        if (Valid(context.CurrentRoom, OverlaySourceMode.Room, context))
            return new(OverlaySourceMode.Room, context.CurrentRoom!.Id, true);
        if (context.FocusedCommunityCode is { } code && context.Communities.TryGetValue(code, out var lease) &&
            lease.Id == code && Valid(lease, OverlaySourceMode.Community, context))
            return new(OverlaySourceMode.Community, code, true);
        return new(OverlaySourceMode.Local, null, true);
    }
}

public sealed class OverlaySourceLimitException : InvalidOperationException
{
    public IReadOnlyList<string> ResourceKeys { get; }
    public OverlaySourceLimitException(IReadOnlyCollection<string>? resourceKeys = null) : base("overlay.sources_limit_exceeded")
    { ResourceKeys = Array.AsReadOnly(resourceKeys?.ToArray() ?? []); }
}
