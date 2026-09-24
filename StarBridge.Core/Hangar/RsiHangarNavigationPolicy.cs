namespace StarBridge.Core.Hangar;

public enum HangarNavigationAction { Start, NextPage, RecheckFirstPage }

/// <summary>
/// Narrow navigation allowlist, not authorization to start a scan. The caller must
/// also own an active, user-started operation and validate account/document generation.
/// No click coordinates, arbitrary URL/script, form submission or account mutations.
/// </summary>
public static class RsiHangarNavigationPolicy
{
    public static bool Allows(HangarNavigationAction action, Uri? current, Uri target)
    {
        if (!TryGetPage(target, out var destination)) return false;
        if (action == HangarNavigationAction.Start) return current is null && destination == 1;
        if (!TryGetPage(current, out var source)) return false;
        return action switch {
            HangarNavigationAction.NextPage => destination == source + 1,
            HangarNavigationAction.RecheckFirstPage => destination == 1,
            _ => false
        };
    }

    public static bool TryGetPage(Uri? address, out int page)
    {
        page = 1;
        if (address is null || !address.IsAbsoluteUri || address.AbsoluteUri.Length > 2048 ||
            address.Scheme != "https" || address.Port != 443 || address.UserInfo.Length != 0 || address.Fragment.Length != 0 ||
            !string.Equals(address.IdnHost, "robertsspaceindustries.com", StringComparison.OrdinalIgnoreCase) ||
            address.AbsolutePath is not ("/account/pledges" or "/en/account/pledges")) return false;
        // Uri.Query normalizes percent-encoded unreserved characters (e.g. %32).
        // Validate the supplied spelling too; the allowlist only needs literal keys/digits.
        var queryStart = address.OriginalString.IndexOf('?');
        if (queryStart < 0) return true;
        var query = address.OriginalString[(queryStart + 1)..];
        if (query.Length > 256) return false;
        var fields = new HashSet<string>(StringComparer.Ordinal);
        foreach (var pair in query.Split('&'))
        {
            var parts = pair.Split('=');
            if (parts.Length != 2 || !fields.Add(parts[0])) return false;
            if (parts[0] == "product-type" && parts[1].Length == 0) continue;
            if (parts[0] != "page" || parts[1].Length is < 1 or > 3 || parts[1][0] == '0' ||
                parts[1].Any(c => c is < '0' or > '9') || !int.TryParse(parts[1], out page) || page > 100) return false;
        }
        return true;
    }
}
