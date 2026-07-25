namespace StarBridge.Desktop;

internal enum OverlaySkinPublicationState
{
    Released,
    Archived
}

internal sealed record OverlaySkinPresentation(
    string SummaryZh,
    string SummaryEn,
    IReadOnlyList<string> TraitsZh,
    IReadOnlyList<string> TraitsEn,
    string PreviewSurface,
    string PreviewPrimary,
    string PreviewSecondary)
{
    public string Summary(string language) =>
        language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? SummaryZh
            : SummaryEn;

    public IReadOnlyList<string> Traits(string language) =>
        language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? TraitsZh
            : TraitsEn;
}

internal sealed record OverlaySkinProfile(
    OverlaySkin Id,
    string DisplayNameZh,
    string DisplayNameEn,
    OverlayVisualTheme DefaultTheme,
    bool LocksTheme,
    OverlayStartupTransitionStyle StartupTransition,
    string? Entitlement,
    bool SupportsBloom,
    OverlaySkinRenderKind RenderKind,
    OverlaySkin FallbackSkin,
    OverlaySkinPresentation Presentation,
    OverlaySkinPublicationState PublicationState)
{
    public string DisplayName(string language) =>
        language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? DisplayNameZh
            : DisplayNameEn;

    public bool IsReleased => PublicationState == OverlaySkinPublicationState.Released;

    public bool IsArchived => PublicationState == OverlaySkinPublicationState.Archived;
}

internal sealed record OverlaySkinResolution(
    OverlaySkin RequestedSkin,
    OverlaySkin EffectiveSkin,
    OverlaySkinProfile Profile,
    OverlayDisplaySettings Settings,
    bool IsAvailable);

internal static partial class OverlaySkinCatalog
{
    public const string NightShadowEntitlement = "overlay.skin.night-shadow";
    public const string VerdictEntitlement = "overlay.skin.verdict";

    private static readonly IReadOnlyList<OverlaySkinProfile> Profiles = BuildProfiles();

    private static IReadOnlyList<OverlaySkinProfile> BuildProfiles()
    {
        List<OverlaySkinProfile> profiles =
        [
            new(
            OverlaySkin.Default,
            "舰队标准",
            "Fleet Standard",
            OverlayVisualTheme.Default,
            LocksTheme: false,
            OverlayStartupTransitionStyle.BridgeTerminal,
            Entitlement: null,
            SupportsBloom: false,
            OverlaySkinRenderKind.Default,
            OverlaySkin.Default,
            new OverlaySkinPresentation(
                "清晰直线导轨与高密度舰队信息，可跟随当前飞船厂商切换配色。",
                "Crisp rails and dense fleet information with optional manufacturer color matching.",
                ["厂商配色", "精密导轨", "高信息密度"],
                ["Manufacturer colors", "Precision rails", "Dense information"],
                "#081722",
                "#29AFFF",
                "#69CCFF"),
            OverlaySkinPublicationState.Released),
            new(
            OverlaySkin.LagrangeWeave,
            "拉格朗日织网",
            "Lagrange Weave",
            OverlayVisualTheme.LagrangeWeave,
            LocksTheme: true,
            OverlayStartupTransitionStyle.LagrangeWeaveEquilibrium,
            Entitlement: null,
            SupportsBloom: true,
            OverlaySkinRenderKind.LagrangeWeave,
            OverlaySkin.Default,
            new OverlaySkinPresentation(
                "以平衡点、连接织网与几何融合表现模块关系，适合强调全局态势。",
                "Equilibrium points, connected meshes, and fused geometry emphasize the wider tactical picture.",
                ["平衡点", "连接织网", "模块融合"],
                ["Equilibrium points", "Connected mesh", "Module fusion"],
                "#071215",
                "#B7FF58",
                "#48D8C8"),
            OverlaySkinPublicationState.Archived)
        ];

        RegisterAdditionalProfiles(profiles);

        var duplicateIds = profiles
            .GroupBy(profile => profile.Id)
            .Where(group => group.Count() > 1)
            .Select(group => group.Key)
            .ToArray();
        if (duplicateIds.Length > 0)
        {
            throw new InvalidOperationException(
                $"Duplicate overlay appearance IDs: {string.Join(", ", duplicateIds)}");
        }

        return profiles.AsReadOnly();
    }

    static partial void RegisterAdditionalProfiles(List<OverlaySkinProfile> profiles);

    private static readonly IReadOnlyDictionary<OverlaySkin, OverlaySkinProfile> ProfilesById =
        Profiles.ToDictionary(profile => profile.Id);

    public static IReadOnlyList<OverlaySkinProfile> All => Profiles;

    public static IEnumerable<OverlaySkinProfile> Released =>
        Profiles.Where(profile => profile.IsReleased);

    public static OverlaySkinProfile Get(OverlaySkin skin) =>
        ProfilesById.TryGetValue(skin, out var profile)
            ? profile
            : ProfilesById[OverlaySkin.Default];

    public static OverlaySkinProfile? FindByEntitlement(string? entitlement)
    {
        if (string.IsNullOrWhiteSpace(entitlement))
        {
            return null;
        }

        return Profiles.FirstOrDefault(profile =>
            profile.Entitlement?.Equals(
                entitlement.Trim(),
                StringComparison.OrdinalIgnoreCase) == true);
    }

    public static bool CanUse(OverlaySkin skin, IEnumerable<string>? entitlements)
    {
        if (!ProfilesById.TryGetValue(skin, out var profile))
        {
            return false;
        }

        var entitlement = profile.Entitlement;
        return profile.IsReleased &&
               (entitlement is null ||
               (entitlements ?? []).Any(value =>
                   entitlement.Equals(value?.Trim(), StringComparison.OrdinalIgnoreCase)));
    }

    public static OverlaySkinResolution Resolve(
        OverlayDisplaySettings requested,
        IEnumerable<string>? entitlements)
    {
        var archivedRequest = ContainsArchivedAppearanceRequest(requested);
        var requestedSkin = ResolveRequestedSkin(requested);
        var requestedProfile = Get(requestedSkin);
        var available = CanUse(requestedSkin, entitlements);
        var effectiveSkin = available
            ? requestedSkin
            : requestedProfile.FallbackSkin;
        var profile = Get(effectiveSkin);
        var effectiveRequest = requested with { RequestedSkin = requestedSkin };
        if (archivedRequest)
        {
            effectiveRequest = effectiveRequest with
            {
                Theme = Get(OverlaySkin.Default).DefaultTheme,
                AutoThemeByShip = false
            };
        }

        if (!available && requestedProfile.LocksTheme)
        {
            effectiveRequest = effectiveRequest with
            {
                Theme = profile.DefaultTheme,
                AutoThemeByShip = false
            };
        }

        var settings = ApplyLocks(
            effectiveRequest,
            profile);
        return new OverlaySkinResolution(
            requestedSkin,
            effectiveSkin,
            profile,
            settings,
            available);
    }

    public static OverlayDisplaySettings ApplyLocks(
        OverlayDisplaySettings settings,
        OverlaySkin skin)
    {
        var profile = Get(skin);
        if (!profile.IsReleased)
        {
            profile = Get(profile.FallbackSkin);
            settings = settings with
            {
                RequestedSkin = profile.Id,
                Theme = profile.DefaultTheme,
                AutoThemeByShip = false
            };
        }

        return ApplyLocks(settings, profile);
    }

    private static OverlayDisplaySettings ApplyLocks(
        OverlayDisplaySettings settings,
        OverlaySkinProfile profile)
    {
        settings = settings with
        {
            Skin = profile.Id,
            StartupTransitionFollowOverlayTheme = true,
            StartupTransitionStyle = profile.StartupTransition
        };

        return profile.LocksTheme
            ? settings with
            {
                Theme = profile.DefaultTheme,
                AutoThemeByShip = false
            }
            : settings;
    }

    private static OverlaySkin ResolveRequestedSkin(OverlayDisplaySettings settings)
    {
        if (settings.Skin != OverlaySkin.Default &&
            settings.Skin != settings.EffectiveRequestedSkin &&
            IsSelectable(settings.Skin))
        {
            return settings.Skin;
        }

        if (settings.EffectiveRequestedSkin != OverlaySkin.Default &&
            IsSelectable(settings.EffectiveRequestedSkin))
        {
            return settings.EffectiveRequestedSkin;
        }

        return Profiles.FirstOrDefault(profile =>
                   profile.DefaultTheme == settings.Theme &&
                   profile.IsReleased)?.Id
               ?? OverlaySkin.Default;
    }

    private static bool IsSelectable(OverlaySkin skin) =>
        ProfilesById.TryGetValue(skin, out var profile) &&
        profile.IsReleased;

    private static bool ContainsArchivedAppearanceRequest(OverlayDisplaySettings settings) =>
        Get(settings.Skin).IsArchived ||
        Get(settings.EffectiveRequestedSkin).IsArchived ||
        Profiles.Any(profile =>
            profile.DefaultTheme == settings.Theme &&
            profile.IsArchived);
}
