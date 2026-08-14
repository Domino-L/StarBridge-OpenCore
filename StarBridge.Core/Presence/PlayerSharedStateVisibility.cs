namespace StarBridge.Core.Presence;

public static class PlayerSharedStateVisibility
{
    public const string PrivateScope = "Private";
    public const string AdminOnlyScope = "AdminOnly";
    public const string SpecifiedMembersScope = "SpecifiedMembers";
    public const string FleetScope = "Fleet";
    public const int MaxSpecifiedMembers = 100;

    public static string NormalizeScope(string? scope)
    {
        var normalized = (scope ?? "")
            .Trim()
            .Replace(" ", "", StringComparison.Ordinal)
            .Replace("-", "", StringComparison.Ordinal)
            .Replace("_", "", StringComparison.Ordinal)
            .ToUpperInvariant();
        if (normalized.Length == 0)
        {
            return FleetScope;
        }

        return normalized switch
        {
            "PRIVATE" or "SELF" => PrivateScope,
            "ADMIN" or "ADMINONLY" or "MANAGER" or "MANAGERONLY" => AdminOnlyScope,
            // Legacy Squad is deliberately mapped to an empty publisher-owned list,
            // never back to a shared grouping container.
            "SQUAD" or "SQUADONLY" or "SPECIFIED" or "SPECIFIEDMEMBER" or "SPECIFIEDMEMBERS" => SpecifiedMembersScope,
            "FLEET" => FleetScope,
            _ => PrivateScope
        };
    }

    public static string[] NormalizeSpecifiedMemberAccountIds(IEnumerable<string?>? accountIds) =>
        (accountIds ?? [])
        .Select(accountId => (accountId ?? "").Trim())
        .Where(accountId => accountId.Length > 0)
        .Distinct(StringComparer.OrdinalIgnoreCase)
        .Take(MaxSpecifiedMembers)
        .ToArray();

    public static bool IncludesAccount(IEnumerable<string?>? accountIds, string? accountId)
    {
        var normalizedAccountId = (accountId ?? "").Trim();
        return normalizedAccountId.Length > 0 &&
               NormalizeSpecifiedMemberAccountIds(accountIds)
                   .Contains(normalizedAccountId, StringComparer.OrdinalIgnoreCase);
    }
}
