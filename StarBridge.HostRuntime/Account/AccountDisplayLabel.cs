namespace StarBridge.HostRuntime.Account;

internal static class AccountDisplayLabel
{
    // S2 presentation rule. Never expose the full login email to UI snapshots.
    internal static string? Mask(string? account)
    {
        var value = account?.Trim();
        if (string.IsNullOrEmpty(value)) return null;
        var at = value.IndexOf('@');
        if (at <= 0 || at == value.Length - 1) return value;
        var visible = at <= 4 ? 1 : 4;
        return value[..visible] + "****" + value[at..];
    }
}
