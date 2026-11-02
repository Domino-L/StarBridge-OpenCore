using StarBridge.HostRuntime.Auth;

namespace StarBridge.HostRuntime.Profiles;

/// <summary>
/// Pure preview projection. Callers must bind the result to the current owner,
/// preview ticket and local revision before saving; this performs no I/O.
/// Source favorite references are never copied into the current inventory.
/// </summary>
public static class SelectedLocalProfileImport
{
    public static LocalProfileContent Project(LocalProfileContent current,
        LocalProfileContent imported, LegacyProfileImportSelection selection)
    {
        selection.Validate();
        LocalPersonalProfileStore.Validate(current);
        LocalPersonalProfileStore.Validate(imported);
        var modules = current.Modules.ToList();
        foreach (var id in selection.Modules)
        {
            var source = imported.Modules.SingleOrDefault(m => m.Id == id)
                ?? throw new LocalProfileException("profile_local.import_source_missing");
            var index = modules.FindIndex(m => m.Id == id);
            if (index >= 0 && !selection.ReplaceModules.Contains(id, StringComparer.Ordinal))
                throw new LocalProfileException("profile_local.import_replacement_required");
            if (id == "favorite-ships" && current.FavoriteShipIds is { Count: > 0 } &&
                current.Modules.All(m => m.FavoriteShipIds is null))
                // Old aggregate-only layouts do not identify the module owning
                // each ship. Do not guess or silently drop their selections.
                throw new LocalProfileException("profile_local.import_reselection_required");
            var next = source with
            {
                IsVisible = index >= 0 && modules[index].IsVisible,
                Position = index >= 0 ? modules[index].Position : -1,
                FavoriteShipIds = id == "favorite-ships"
                    ? index >= 0 ? modules[index].FavoriteShipIds?.ToArray() ?? [] : []
                    : null
            };
            if (next.FavoriteShipIds?.Count > next.Span)
                throw new LocalProfileException("profile_local.import_reselection_required");
            if (index >= 0) modules[index] = next;
            else modules.Add(next);
        }
        var result = current with
        {
            CallSign = selection.UseLegacyCallSign ? imported.CallSign : current.CallSign,
            Modules = modules,
            // Avatar image belongs to the remote profile, not this local style.
            PlayStyle = selection.Modules.Contains("skilled-roles", StringComparer.Ordinal)
                ? imported.PlayStyle?.Copy() : current.PlayStyle,
            FavoriteShipIds = selection.Modules.Contains("favorite-ships", StringComparer.Ordinal) &&
                current.FavoriteShipIds is null ? [] : current.FavoriteShipIds
        };
        LocalPersonalProfileStore.Validate(result);
        return result;
    }
}
