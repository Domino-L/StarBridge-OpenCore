using StarBridge.Core.Fleets;

internal static class LegacyManageFleetInfoTests
{
    internal static void Run()
    {
        var expected = new[] { "audit.view", "fleet.avatar.edit", "fleet.banner.edit", "fleet.profile.edit", "members.review" };
        if (!FleetPermissionPolicy.LegacyManageFleetInfoPermissions.Order(StringComparer.Ordinal).SequenceEqual(expected))
            throw new Exception("Legacy manage coverage changed unexpectedly");
        foreach (var permission in expected)
        {
            if (!FleetPermissionPolicy.LegacyGrants(permission.ToUpperInvariant(), true, false, false, false) ||
                FleetPermissionPolicy.LegacyGrants(permission, false, true, true, true))
                throw new Exception("Legacy manage flag semantics changed");
        }
        if (FleetPermissionPolicy.LegacyGrants("fleet.background.edit", true, false, false, false) ||
            !FleetPermissionPolicy.LegacyGrants("members.remove", false, true, false, false))
            throw new Exception("Adjacent legacy permissions changed");
        Console.WriteLine("PASS canonical legacy manage permission coverage and flag isolation");
    }
}
