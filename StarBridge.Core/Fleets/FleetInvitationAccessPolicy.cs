namespace StarBridge.Core.Fleets;

public static class FleetInvitationAccessPolicy
{
    public const string AllMembers = "all_members";
    public const string Management = "management";
    public const string Commander = "commander";

    public static string Normalize(string? value)
    {
        var normalized = value?.Trim().ToLowerInvariant();
        return normalized switch
        {
            Management => Management,
            Commander => Commander,
            _ => AllMembers
        };
    }

    public static bool Allows(
        string? policy,
        bool isFleetMember,
        bool isCommander,
        bool hasManagementAccess)
    {
        if (!isFleetMember)
        {
            return false;
        }

        return Normalize(policy) switch
        {
            Commander => isCommander,
            Management => isCommander || hasManagementAccess,
            _ => true
        };
    }
}
