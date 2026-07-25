namespace StarBridge.Desktop;

public static class FleetRoleGroupSnapshotFactory
{
    public static NetworkFleetRoleGroupSnapshot[] Build(IEnumerable<LocalFleetRoleGroup> roleGroups)
    {
        ArgumentNullException.ThrowIfNull(roleGroups);

        return roleGroups
            .Select(role => new NetworkFleetRoleGroupSnapshot(
                role.Key,
                role.DisplayName,
                role.Description,
                role.Color,
                role.SortOrder,
                role.IsSystem,
                role.IsEnabled,
                role.MemberCount,
                role.Permissions,
                role.CreatedAt,
                role.UpdatedAt))
            .ToArray();
    }
}
