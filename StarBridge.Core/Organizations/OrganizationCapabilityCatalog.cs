using StarBridge.Core.Fleets;

namespace StarBridge.Core.Organizations;

public static class OrganizationCapabilityCatalog
{
    public const string ManageAnnouncements = FleetPermissionPolicy.ManageAnnouncements;
    public const string ViewAudit = "audit.view";
    public const string ManageRoles = "organization.roles.manage";
    public const string ManageRally = "rally.manage";
    public static IReadOnlyList<string> Legacy { get; } = Array.AsReadOnly(new[] { ManageAnnouncements, ViewAudit, ManageRoles });
    public static IReadOnlyList<string> Implemented { get; } = Array.AsReadOnly(new[] { ManageAnnouncements, ViewAudit, ManageRoles, ManageRally });
    public static bool IsSupported(string capability) => Implemented.Contains(capability, StringComparer.Ordinal);
}
