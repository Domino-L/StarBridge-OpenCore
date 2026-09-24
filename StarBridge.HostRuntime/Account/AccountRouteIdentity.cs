namespace StarBridge.HostRuntime.Account;

using System.Security.Cryptography;
using System.Text;

internal readonly record struct AccountRouteIdentity(
    string Environment,
    string Authority,
    string Subject,
    string LegacyAccountId)
{
    internal static AccountRouteIdentity Create(
        string? environment,
        string? authority,
        string? subject,
        string? legacyAccountId) => new(
        NormalizeRouteDimension(environment),
        NormalizeRouteDimension(authority),
        NormalizeOpaqueIdentifier(subject),
        NormalizeOpaqueIdentifier(legacyAccountId));

    internal bool IsAuthenticated => Subject.Length > 0;

    internal string CacheNamespace
    {
        get
        {
            if (!IsAuthenticated)
            {
                return "local";
            }

            // The SCM route is the stable network identity. LegacyAccountId is
            // only a one-time migration lookup and must not split or rotate the
            // account cache after link state changes.
            var value = string.Join('\n', Environment, Authority, Subject);
            return "account:" + Convert.ToHexString(
                SHA256.HashData(Encoding.UTF8.GetBytes(value))).ToLowerInvariant();
        }
    }

    private static string NormalizeRouteDimension(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "" : value.Trim().ToUpperInvariant();

    // OAuth/OIDC subjects are opaque, case-sensitive identifiers. Folding their
    // case would both reject a valid SCM profile during strict publication and
    // allow two distinct subjects to share one local account-cache namespace.
    private static string NormalizeOpaqueIdentifier(string? value) =>
        string.IsNullOrWhiteSpace(value) ? "" : value.Trim();
}
