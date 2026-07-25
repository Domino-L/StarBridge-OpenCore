namespace StarBridge.Core.Fleets;

public static class FleetPermissionPolicy
{
    public const string EditFleetProfile = "fleet.profile.edit";
    public const string ManageAnnouncements = "announcements.manage";
    public const string AnnouncementPermissionSchemaMarker = "schema.announcements-manage.v1";
    public const string RetiredInviteMembers = "members.invite";

    public static bool UsesAnnouncementPermissionSchema(IEnumerable<IEnumerable<string>?> rolePermissions)
    {
        return rolePermissions.Any(permissions =>
            (permissions ?? []).Any(id =>
                !string.IsNullOrWhiteSpace(id) &&
                (id.Equals(ManageAnnouncements, StringComparison.OrdinalIgnoreCase) ||
                 id.Equals(AnnouncementPermissionSchemaMarker, StringComparison.OrdinalIgnoreCase))));
    }

    public static string[] NormalizeRolePermissions(
        IEnumerable<string>? permissions,
        bool migrateLegacyProfileManagers)
    {
        var normalized = (permissions ?? [])
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => id.Trim())
            .Where(id => !id.Equals(RetiredInviteMembers, StringComparison.OrdinalIgnoreCase))
            .ToHashSet(StringComparer.OrdinalIgnoreCase);

        if (migrateLegacyProfileManagers && normalized.Contains(EditFleetProfile))
        {
            normalized.Add(ManageAnnouncements);
        }

        normalized.Add(AnnouncementPermissionSchemaMarker);
        return normalized
            .OrderBy(id => id, StringComparer.OrdinalIgnoreCase)
            .ToArray();
    }
}
