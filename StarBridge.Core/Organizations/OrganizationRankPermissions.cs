namespace StarBridge.Core.Organizations;

public static class OrganizationRankPermissions
{
    public static IReadOnlyList<OrganizationRankPermission> Defaults { get; } = Array.AsReadOnly(new[]
    {
        new OrganizationRankPermission(2, true, false, true), new(3, true, false, true),
        new(4, false, false, false), new(5, false, false, false)
    });

    public static bool Valid(IReadOnlyList<OrganizationRankPermission>? rows) => rows is null ||
        rows.Count == 4 && rows.All(r => r is not null && r.RankValue is >= 2 and <= 5) &&
        rows.Select(r => r.RankValue).Distinct().Count() == 4;

    public static bool Allows(OrganizationAuthorizationSnapshot policy, int rank, string capability)
    {
        var row = (policy.RankPermissions ?? Defaults).SingleOrDefault(r => r.RankValue == rank);
        return row is not null && capability switch
        {
            OrganizationCapabilityCatalog.ManageAnnouncements => row.Announcements,
            OrganizationCapabilityCatalog.ManageRally => row.Rally,
            OrganizationCapabilityCatalog.ViewAudit => row.Audit,
            _ => false
        };
    }
}
