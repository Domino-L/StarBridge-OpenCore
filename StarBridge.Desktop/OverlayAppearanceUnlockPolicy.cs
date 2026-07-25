namespace StarBridge.Desktop;

internal static class OverlayAppearanceUnlockPolicy
{
    public static bool IsNewPermanentUnlock(
        string? previousAccount,
        string? currentAccount,
        IEnumerable<string>? previousEntitlements,
        IEnumerable<string>? currentEntitlements,
        string entitlement)
    {
        var sameAccount = !string.IsNullOrWhiteSpace(previousAccount) &&
                          previousAccount.Equals(currentAccount, StringComparison.OrdinalIgnoreCase);
        var previouslyOwned = sameAccount && Contains(previousEntitlements, entitlement);
        return !previouslyOwned && Contains(currentEntitlements, entitlement);
    }

    public static string BuildAcknowledgementKey(
        string? account,
        string entitlement,
        DateTimeOffset? temporaryExpiry = null)
    {
        var normalizedAccount = string.IsNullOrWhiteSpace(account)
            ? "unknown-account"
            : account.Trim().ToLowerInvariant();
        var normalizedEntitlement = entitlement.Trim().ToLowerInvariant();
        return temporaryExpiry.HasValue
            ? $"{normalizedAccount}|{normalizedEntitlement}|temporary:{temporaryExpiry.Value.ToUnixTimeSeconds()}"
            : $"{normalizedAccount}|{normalizedEntitlement}|permanent";
    }

    private static bool Contains(IEnumerable<string>? entitlements, string entitlement)
    {
        return (entitlements ?? []).Any(value =>
            value.Equals(entitlement, StringComparison.OrdinalIgnoreCase));
    }
}
