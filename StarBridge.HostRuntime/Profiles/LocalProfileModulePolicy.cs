using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Profiles;

/// <summary>Capacity and global uniqueness apply to hidden modules too.</summary>
internal static class LocalProfileModulePolicy
{
    public static bool IsFavorite(string id) => id == "favorite-ships" ||
        Regex.IsMatch(id, @"\Afavorite-ships-[1-9][0-9]{0,3}\z", RegexOptions.CultureInvariant);

    public static void Validate(LocalProfileContent? content)
    {
        if (content?.Modules is not { } modules || modules.Count > 64 ||
            modules.Any(m => m is null || m.Id is null ||
                (!IsFavorite(m.Id) && m.Id is not ("hangar-summary" or "skilled-roles")) ||
                m.Span is < 1 or > 3 || m.Position is < -1 or > 191) ||
            modules.Select(m => m.Id).Distinct(StringComparer.Ordinal).Count() != modules.Count)
            Invalid();
        var assignments = content!.Modules.Where(m => m.FavoriteShipIds is not null).ToArray();
        var used = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var module in assignments)
        {
            if (!IsFavorite(module.Id) || module.FavoriteShipIds!.Count > module.Span) Invalid();
            foreach (var id in module.FavoriteShipIds!)
                if (!Guid.TryParseExact(id, "N", out _) || !used.Add(id)) Invalid();
        }
        if (content.FavoriteShipIds is { } all)
        {
            if (all.Count > (assignments.Length == 0 ? 12 : 192) ||
                all.Distinct(StringComparer.OrdinalIgnoreCase).Count() != all.Count ||
                all.Any(id => !Guid.TryParseExact(id, "N", out _))) Invalid();
            if (assignments.Length > 0 && !used.SetEquals(all)) Invalid();
        }
        else if (assignments.Length > 0) Invalid();
    }

    private static void Invalid() => throw new LocalProfileException("profile_local.invalid_request");
}
