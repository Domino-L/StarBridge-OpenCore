namespace StarBridge.Desktop;

internal enum OverlaySkinPublicationState
{
    Released,
    InDevelopment,
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
    OverlaySkinPublicationState PublicationState,
    bool PreviewReady = false,
    double EventEnterDurationMs = 430,
    double EventExitDurationMs = 320,
    double StartupFocusHandoffMs = 0)
{
    public string DisplayName(string language) =>
        language.Equals("zh", StringComparison.OrdinalIgnoreCase)
            ? DisplayNameZh
            : DisplayNameEn;

    public bool IsReleased => PublicationState == OverlaySkinPublicationState.Released;

    public bool IsArchived => PublicationState == OverlaySkinPublicationState.Archived;

    // Preview visibility never grants runtime use or a commercial entitlement.
    public bool IsPreviewAvailable => IsReleased || (!IsArchived && PreviewReady);
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
            OverlaySkin.Visor,
            "面罩投影",
            "Visor Projection",
            OverlayVisualTheme.Default,
            LocksTheme: false,
            OverlayStartupTransitionStyle.BridgeTerminal,
            Entitlement: null,
            SupportsBloom: false,
            OverlaySkinRenderKind.Visor,
            OverlaySkin.Default,
            new OverlaySkinPresentation(
                "像头盔面罩上的投影：两侧微微偏转、淡淡发光，信息贴着画面边缘，不挡游戏自己的界面。",
                "Projected like a helmet visor: slightly tilted sides and a soft glow along the screen edges, clear of the game's own HUD.",
                ["面罩投影", "贴边摆放", "跟随舰船配色"],
                ["Visor projection", "Edge layout", "Manufacturer colors"],
                "#081722",
                "#53BEFF",
                "#EBF7FF"),
            OverlaySkinPublicationState.Released)
        ];

        RegisterAdditionalProfiles(profiles);
        RegisterInstalledProfiles(profiles);
        ConfigureOptionalProfiles(profiles);

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
    static partial void RegisterInstalledProfiles(List<OverlaySkinProfile> profiles);
    static partial void ConfigureOptionalProfiles(List<OverlaySkinProfile> profiles);

    private static readonly IReadOnlyDictionary<OverlaySkin, OverlaySkinProfile> ProfilesById =
        Profiles.ToDictionary(profile => profile.Id);

    /// <summary>
    /// 0.7.3 overlay v2 (user, 11-07: "之前的外观都暂时隐藏 只留面罩这一个"; "藏，等之后做v2"): these
    /// appearances stay registered, listed and entitled, and a saved choice of one is kept, but the overlay
    /// draws the visor until each is redone for v2. Listing and qualification are unchanged on purpose.
    /// </summary>
    public static readonly IReadOnlySet<OverlaySkin> HiddenUntilV2 = new HashSet<OverlaySkin>
    {
        OverlaySkin.Default, OverlaySkin.NightShadow, OverlaySkin.Verdict, OverlaySkin.HajiCitizen,
    };

    public static bool IsHiddenUntilV2(OverlaySkin skin) => HiddenUntilV2.Contains(skin);

    /// <summary>
    /// What the overlay draws (never what is saved): <see cref="Resolve"/>, then a hidden appearance becomes the
    /// visor. Saving, importing and exporting keep using <see cref="Resolve"/>, so a saved choice is never
    /// rewritten to the visor and resolving again still finds it.
    /// </summary>
    public static OverlaySkinResolution ResolveForDrawing(OverlayDisplaySettings requested, IEnumerable<string>? entitlements)
    {
        var resolution = Resolve(requested, entitlements);
        if (!IsHiddenUntilV2(resolution.EffectiveSkin)) return resolution;
        var visor = Get(OverlaySkin.Visor);
        return resolution with { EffectiveSkin = OverlaySkin.Visor, Profile = visor, Settings = ForDrawing(resolution.Settings, requested) };
    }

    /// <summary>
    /// Settings as drawn while their appearance is hidden: the visor's own look and startup, and the user's
    /// palette unless it is a hidden appearance's locked palette (that palette would start that appearance's
    /// own startup and colours). Drawing only; never saved.
    /// </summary>
    public static OverlayDisplaySettings ForDrawing(OverlayDisplaySettings settings, OverlayDisplaySettings? requested = null)
    {
        if (!IsHiddenUntilV2(settings.Skin)) return settings;
        var visor = Get(OverlaySkin.Visor);
        var wanted = requested ?? settings;
        return ApplyLocks(settings with
        {
            Skin = OverlaySkin.Visor,
            Theme = HiddenLockedThemes.Contains(wanted.Theme) ? visor.DefaultTheme : wanted.Theme,
            AutoThemeByShip = wanted.AutoThemeByShip,
        }, visor);
    }

    /// <summary>
    /// The locked palettes of the hidden appearances. Fixed here rather than read from the registered profiles,
    /// so a build without the optional appearances still recognises an old saved palette.
    /// </summary>
    public static readonly IReadOnlySet<OverlayVisualTheme> HiddenLockedThemes = new HashSet<OverlayVisualTheme>
    {
        OverlayVisualTheme.NightShadow, OverlayVisualTheme.Verdict,
    };

    /// <summary>A palette as drawn by an appearance that does not lock one: a hidden appearance's palette becomes the visor's.</summary>
    public static OverlayVisualTheme DrawnTheme(OverlayVisualTheme theme) =>
        HiddenLockedThemes.Contains(theme) ? Get(OverlaySkin.Visor).DefaultTheme : theme;

    public static IReadOnlyList<OverlaySkinProfile> All => Profiles;

    public static IEnumerable<OverlaySkinProfile> Released =>
        Profiles.Where(profile => profile.IsReleased);

    public static IEnumerable<OverlaySkinProfile> Listed =>
        Profiles.Where(profile => !profile.IsArchived);

    /// <summary>
    /// The manufacturer palette for a ship ("根据当前舰船自动切换主题"): its code (or name) by its maker; Default when the
    /// ship is not known. Shared by the old main window and the native overlay runtime.
    /// </summary>
    public static OverlayVisualTheme ThemeForShip(string? shipCode)
    {
        var code = ShipNameLocalizer.ResolveCode(shipCode);
        if (string.IsNullOrWhiteSpace(code) ||
            code.Equals("Unknown", StringComparison.OrdinalIgnoreCase))
        {
            return OverlayVisualTheme.Default;
        }

        var normalizedCode = code.ToUpperInvariant();
        var manufacturerCode = normalizedCode.Split('_', 2)[0];

        return manufacturerCode switch
        {
            "ANVL" => OverlayVisualTheme.Anvil,
            "DRAK" => OverlayVisualTheme.Drake,
            "ARGO" => OverlayVisualTheme.Argo,
            "MRAI" or "MIRAI" => OverlayVisualTheme.Mirai,
            "MISC" when normalizedCode.Contains("RAZOR", StringComparison.OrdinalIgnoreCase) => OverlayVisualTheme.Mirai,
            "MISC" => OverlayVisualTheme.Musashi,
            "CRUS" => OverlayVisualTheme.Crusader,
            "AEGS" => OverlayVisualTheme.Aegis,
            "RSI" => OverlayVisualTheme.Rsi,
            "ORIG" => OverlayVisualTheme.Origin,
            "GAMA" => OverlayVisualTheme.Gatac,
            "XIAN" when normalizedCode.Contains("RAILEN", StringComparison.OrdinalIgnoreCase) => OverlayVisualTheme.Gatac,
            "XIAN" or "AOPOA" or "AOPA" => OverlayVisualTheme.Aopoa,
            "ESPR" => OverlayVisualTheme.Esperia,
            _ => OverlayVisualTheme.Default
        };
    }

    /// <summary>
    /// Settings as drawn with "switch the palette by the current ship" on (user, 11-10: "浮层应该保留船厂颜色/根据当前飞船自动
    /// 切换颜色"): the palette of the ship the game log identifies for the local player, Default when none is known. An
    /// appearance with a fixed palette keeps it. Off, the chosen palette stays.
    /// </summary>
    public static OverlayDisplaySettings WithShipTheme(OverlayDisplaySettings settings, string? currentShip)
    {
        if (!settings.AutoThemeByShip || Get(settings.Skin).LocksTheme) return settings;
        return settings with { Theme = ThemeForShip(currentShip) };
    }

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
        var requestedSkin = ResolveRequestedSkin(requested);
        var unavailableRequest = ContainsUnavailableAppearanceRequest(requested, requestedSkin);
        var requestedProfile = Get(requestedSkin);
        var available = !unavailableRequest && CanUse(requestedSkin, entitlements);
        var effectiveSkin = available
            ? requestedSkin
            : requestedProfile.FallbackSkin;
        var profile = Get(effectiveSkin);
        var effectiveRequest = requested with { RequestedSkin = requestedSkin };
        if (unavailableRequest)
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

    private static bool ContainsUnavailableAppearanceRequest(
        OverlayDisplaySettings settings,
        OverlaySkin requestedSkin)
    {
        if (settings.Skin != OverlaySkin.Default &&
            requestedSkin == settings.Skin &&
            settings.Skin != settings.EffectiveRequestedSkin &&
            IsSelectable(settings.Skin))
        {
            return false;
        }

        return !ProfilesById.ContainsKey(settings.Skin) ||
               !ProfilesById.ContainsKey(settings.EffectiveRequestedSkin) ||
               !Get(settings.Skin).IsReleased ||
               !Get(settings.EffectiveRequestedSkin).IsReleased ||
               Profiles.Any(profile =>
                   profile.DefaultTheme != OverlayVisualTheme.Default &&
                   profile.DefaultTheme == settings.Theme &&
                   !profile.IsReleased);
    }
}
