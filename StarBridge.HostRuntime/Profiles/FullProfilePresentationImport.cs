using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Hangar;

namespace StarBridge.HostRuntime.Profiles;

/// <summary>Display-only mapping. Never creates, transfers or removes inventory instances.</summary>
internal static class FullProfilePresentationImport
{
    internal static LocalProfileContent Project(LegacyProfileMigrationView view, LocalHangarSnapshot? hangar)
    {
        var presentation = view.Presentation;
        var content = presentation?.Content;
        if (view.Choices is not { Version: 2, UseLegacyCallSign: true, NeedsReselection.Length: 0 } choices ||
            presentation is null || content is null || content.Modules is null || content.FavoriteShipCodes is null ||
            content.SkilledRoles is null || content.SupportCapabilities is null || content.ParticipationInterests is null ||
            !choices.Modules.SequenceEqual(content.Modules.Select(m => m.Id)) ||
            !choices.ReplaceModules.SequenceEqual(choices.Modules) || view.SelectedContent is not null)
            throw new LocalProfileException("profile_local.invalid_request");
        var ids = new List<string>();
        foreach (var code in content.FavoriteShipCodes)
        {
            if (hangar is null || hangar.Partial || hangar.Revision <= 0)
                throw new LocalProfileException("profile_local.import_reselection_required");
            var matches = hangar.Ships.Concat(hangar.FormerShips ?? [])
                .Where(s => s.Id == code || s.PledgeKey == code).Select(s => s.Id).Distinct().ToArray();
            if (matches.Length != 1 || ids.Contains(matches[0]))
                throw new LocalProfileException("profile_local.import_reselection_required");
            ids.Add(matches[0]);
        }
        var modules = content.Modules.OrderBy(m => m.Order)
            .Select(m => new LocalProfileLayout(m.Id, m.Span, m.IsVisible, m.Position,
                m.Id == "favorite-ships" ? ids.ToArray() : null)).ToArray();
        if (ids.Count > 0 && !modules.Any(m => m.Id == "favorite-ships"))
            throw new LocalProfileException("profile_local.import_reselection_required");
        var rhythm = content.ActivityRhythm switch
        {
            "休闲" => "casual", "稳定活跃" => "regular", "高频活跃" => "intensive",
            "周末为主" => "weekends", "不固定" => "irregular",
            _ => throw new LocalProfileException("profile_local.invalid_request")
        };
        if (content.ShowOnlineTime && (content.AvailabilityWindows is not { Length: > 0 } ||
            string.IsNullOrWhiteSpace(content.AvailabilityTimeZoneId)))
            throw new LocalProfileException("profile_local.invalid_request");
        // The local schedule cannot represent saved-but-hidden windows. Reject rather than discard them.
        if (!content.ShowOnlineTime && content.AvailabilityWindows is { Length: > 0 })
            throw new LocalProfileException("profile_local.import_reselection_required");
        var windows = content.ShowOnlineTime ? content.AvailabilityWindows!.Select(w =>
            new LocalProfileTimeWindow(w.Days, w.StartTime, w.EndTime)).ToArray() : [];
        var result = new LocalProfileContent(presentation.CallSign, content.Introduction, presentation.AvatarStyle,
            presentation.WallpaperId, modules, ids, new(content.SkilledRoles, content.ParticipationInterests,
                content.SupportCapabilities), new(content.AvailabilityTimeZoneId ?? "", rhythm, windows), true);
        LocalPersonalProfileStore.Validate(result);
        return result;
    }
}
