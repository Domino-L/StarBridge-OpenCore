namespace StarBridge.Core.State;

internal static class ShipIdentityCanonicalizer
{
    private const string F8RuntimeAliasPrefix = "anvlf8clightning";
    private const string F8CanonicalPrefix = "anvllightningf8c";

    public static string ComparisonKey(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return "";
        }

        var normalized = new string(value
            .Where(char.IsLetterOrDigit)
            .Select(char.ToLowerInvariant)
            .ToArray());

        // Game.log can identify the same F8C as ANVL_F8C_Lightning when
        // control is acquired and ANVL_Lightning_F8C when it is released.
        // Keep this alias explicit: sorting arbitrary ship-name tokens would
        // risk merging distinct variants that merely contain the same words.
        if (normalized.StartsWith(F8RuntimeAliasPrefix, StringComparison.Ordinal))
        {
            return F8CanonicalPrefix + normalized[F8RuntimeAliasPrefix.Length..];
        }

        return normalized;
    }
}
