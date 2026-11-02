namespace StarBridge.HostRuntime.Auth;

// Native-private snapshot of one selected credential, never a Bridge payload.
// Selection, encrypted version and secret are captured in one writer lease.
internal sealed record ScmResumeCredential(string AccountKey, string RefreshToken,
    ScmCredentialRetirementStamp Version);

public sealed partial class WindowsTokenVault
{
    internal ScmResumeCredential? CaptureResumeCredential(string authority)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(authority);
        using var writer = OpenWriter();
        var values = ReadVault(strict: true);
        if (!values.TryGetValue(ActiveAccountEntry, out var active)) return null;
        var key = Unprotect(active);
        if (key is null) throw new System.IO.InvalidDataException("Credential selection cannot be read.");
        if (!key.StartsWith(authority + ":", StringComparison.Ordinal)) return null;
        var version = RetirementStamp(values, key);
        if (!values.TryGetValue(StorageKey(key), out var encoded) && !values.TryGetValue(key, out encoded))
            throw new System.IO.InvalidDataException("Selected credential is missing.");
        var secret = Unprotect(encoded);
        if (string.IsNullOrWhiteSpace(secret)) throw new System.IO.InvalidDataException("Selected credential cannot be read.");
        return new(key, secret, version);
    }

    // A response to an old refresh must not overwrite a newer login, including
    // a newer credential for the same account. Preserve all unrelated entries.
    internal ScmCredentialRetirementStamp? RotateResumeCredential(ScmResumeCredential original,
        string refreshToken, Func<bool> current)
    {
        ArgumentNullException.ThrowIfNull(original);
        ArgumentNullException.ThrowIfNull(current);
        ArgumentException.ThrowIfNullOrWhiteSpace(refreshToken);
        ValidateRetirementStamp(original.Version);
        if (!IsRetirementBoundTo(original.Version) || !current()) return null;
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var entries = RetirementEntries(old, original.Version.OwnerKey);
        var active = old.GetValueOrDefault(ActiveAccountEntry);
        if (original.Version.OwnerKey != Hash(original.AccountKey) ||
            EntriesHash(entries) != original.Version.EntriesHash ||
            (active is null ? null : Hash(active)) != original.Version.ActiveEntryHash || !current()) return null;
        var next = new Dictionary<string, string>(old, StringComparer.Ordinal);
        next.Remove(original.AccountKey);
        next[StorageKey(original.AccountKey)] = Protect(refreshToken);
        next[ActiveAccountEntry] = Protect(original.AccountKey);
        if (!WriteVault(old, next, current)) return null;
        return RetirementStamp(next, original.AccountKey);
    }
}
