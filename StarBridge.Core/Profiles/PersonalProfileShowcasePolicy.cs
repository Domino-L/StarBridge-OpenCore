using System.Text.Json.Serialization;
using System.Text.RegularExpressions;

namespace StarBridge.Core.Profiles;

public sealed record PersonalProfileShowcaseContract(
    [property: JsonRequired] string Id,
    [property: JsonRequired] bool IsVisible);

public sealed record PersonalProfilePublicAchievementContract(string Id, DateTimeOffset EarnedAt);

/// <summary>Additive single-column layout; legacy module policy remains independent.</summary>
public static class PersonalProfileShowcasePolicy
{
    public const int MaximumShowcases = 64;
    public const int MaximumAchievements = 9;

    // Keep numbered favorites aligned with Host LocalProfileModulePolicy.IsFavorite.
    public static bool IsShowcaseId(string? id) => id is
        "favorite-ships" or "hangar-summary" or "skilled-roles" or "achievements" or
        "gameplay-time" or "trade-card" or "organizations" ||
        id is not null && Regex.IsMatch(id, @"\Afavorite-ships-[1-9][0-9]{0,3}\z", RegexOptions.CultureInvariant);

    public static bool IsAchievementId(string? id) => id is not null &&
        Regex.IsMatch(id, @"\A[a-z0-9][a-z0-9-]{0,63}\z", RegexOptions.CultureInvariant);

    public static PersonalProfileShowcaseContract[]? NormalizeShowcases(IEnumerable<PersonalProfileShowcaseContract>? values) =>
        values?.Where(value => value is not null)
            .Select(value => value with { Id = (value.Id ?? "").Trim().ToLowerInvariant() })
            .Where(value => IsShowcaseId(value.Id))
            .DistinctBy(value => value.Id, StringComparer.Ordinal)
            .Take(MaximumShowcases).ToArray();

    public static string[]? NormalizeAchievements(IEnumerable<string>? values) =>
        values?.Where(IsAchievementId).Distinct(StringComparer.Ordinal).Take(MaximumAchievements).ToArray();

    public static bool ValidShowcases(IReadOnlyList<PersonalProfileShowcaseContract>? values) => values is null ||
        values.Count <= MaximumShowcases && values.All(value => value is not null && IsShowcaseId(value.Id)) &&
        values.Select(value => value.Id).Distinct(StringComparer.Ordinal).Count() == values.Count;

    public static bool ValidAchievements(IReadOnlyList<string>? values) => values is null ||
        values.Count <= MaximumAchievements && values.All(IsAchievementId) &&
        values.Distinct(StringComparer.Ordinal).Count() == values.Count;

    public const int MaximumFavoriteExtra = 1;

    /// <summary>Same instance id grammar as module favoriteShipIds (32 hex).</summary>
    public static bool IsShipInstanceId(string? id) => id is { Length: 32 } && Guid.TryParseExact(id, "N", out _);

    /// <summary>Drops malformed ids and ids a favourite module already shows.</summary>
    public static string[]? NormalizeFavoriteExtra(IEnumerable<string>? values,
        IEnumerable<PersonalProfileModuleContract>? modules)
    {
        if (values is null) return null;
        var used = ModuleSelections(modules);
        return values.Where(IsShipInstanceId).Where(id => !used.Contains(id))
            .Distinct(StringComparer.OrdinalIgnoreCase).Take(MaximumFavoriteExtra).ToArray();
    }

    public static bool ValidFavoriteExtra(IReadOnlyList<string>? values,
        IEnumerable<PersonalProfileModuleContract>? modules)
    {
        if (values is null) return true;
        var used = ModuleSelections(modules);
        return values.Count <= MaximumFavoriteExtra && values.All(IsShipInstanceId) &&
            !values.Any(used.Contains) &&
            values.Distinct(StringComparer.OrdinalIgnoreCase).Count() == values.Count;
    }

    // Per-module fourth ships (user 11-06 "every module", fav-per-module-073/PLAN.md). Same rules as the
    // HK PersonalProfileContent: keys are favourite modules the page holds ("favorite-ships" always),
    // values ship instances no module shows and no other entry repeats. Null = server predates the field.
    public const string FavoriteShipsModule = "favorite-ships";
    public const int MaximumFavoriteModules = 3;

    public static bool IsFavoriteModule(string? id) => id == FavoriteShipsModule ||
        id is not null && Regex.IsMatch(id, @"\Afavorite-ships-[1-9][0-9]{0,3}\z", RegexOptions.CultureInvariant);

    private static List<string> FavoriteModulesHeld(IEnumerable<PersonalProfileModuleContract>? modules,
        IEnumerable<PersonalProfileShowcaseContract>? showcases)
    {
        var held = new List<string>();
        foreach (var id in (modules ?? []).Where(module => module is not null).Select(module => (module.Id ?? "").Trim().ToLowerInvariant())
            .Concat((showcases ?? []).Where(showcase => showcase is not null).Select(showcase => (showcase.Id ?? "").Trim().ToLowerInvariant())))
            if (IsFavoriteModule(id) && !held.Contains(id, StringComparer.Ordinal)) held.Add(id);
        // HK CX-HK-BUNDLE3-R P2: only modules the page holds; a page that never laid out its modules
        // shows the default "favorite-ships", so it alone keeps that implicit entry.
        if (held.Count == 0) held.Add(FavoriteShipsModule);
        return held;
    }

    public static Dictionary<string, string>? NormalizeFavoriteExtras(IReadOnlyDictionary<string, string>? values,
        IEnumerable<PersonalProfileModuleContract>? modules, IEnumerable<PersonalProfileShowcaseContract>? showcases)
    {
        if (values is null) return null;
        var held = FavoriteModulesHeld(modules, showcases);
        var used = ModuleSelections(modules);
        var candidates = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var (key, value) in values)
            if (key is not null && value is not null) candidates.TryAdd(key.Trim().ToLowerInvariant(), value);
        var result = new Dictionary<string, string>(StringComparer.Ordinal);
        foreach (var module in held)
        {
            if (!candidates.TryGetValue(module, out var id) || !IsShipInstanceId(id) || !used.Add(id)) continue;
            result[module] = id;
            if (result.Count == Math.Max(MaximumFavoriteModules, held.Count)) break;
        }
        return result;
    }

    public static bool ValidFavoriteExtras(IReadOnlyDictionary<string, string>? values,
        IEnumerable<PersonalProfileModuleContract>? modules, IEnumerable<PersonalProfileShowcaseContract>? showcases)
    {
        if (values is null) return true;
        var held = FavoriteModulesHeld(modules, showcases);
        var used = ModuleSelections(modules);
        return values.Count <= Math.Max(MaximumFavoriteModules, held.Count) &&
            values.All(pair => held.Contains(pair.Key, StringComparer.Ordinal) && IsShipInstanceId(pair.Value) && used.Add(pair.Value));
    }

    private static HashSet<string> ModuleSelections(IEnumerable<PersonalProfileModuleContract>? modules) =>
        new((modules ?? []).Where(module => module is not null)
            .SelectMany(module => module.FavoriteShipIds ?? []).Where(id => id is not null),
            StringComparer.OrdinalIgnoreCase);
}
