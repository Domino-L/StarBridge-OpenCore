using System.IO;

namespace StarBridge.HostRuntime.Auth;

public sealed partial class WindowsTokenVault
{
    // Capture no refresh secret. The later commit must still match this selection
    // and its encrypted entry version before it may retire the former account.
    internal ScmCredentialRetirementStamp? CaptureSelectedCredentialVersion()
    {
        using var writer = OpenWriter();
        var values = ReadVault(strict: true);
        if (!values.TryGetValue(ActiveAccountEntry, out var active)) return null;
        var key = Unprotect(active) ?? throw new InvalidDataException("Credential selection cannot be read.");
        return RetirementStamp(values, key);
    }

    internal ScmCredentialRetirementStamp SaveSignInCredential(string accountKey, string refreshToken,
        ScmCredentialRetirementStamp? previous, out string cleanup)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(refreshToken);
        if (accountKey.Length > 2048 || accountKey.Any(char.IsControl))
            throw new ArgumentException("Credential owner key is invalid.", nameof(accountKey));
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var next = new Dictionary<string, string>(old, StringComparer.Ordinal);
        var active = old.GetValueOrDefault(ActiveAccountEntry);
        var oldKey = active is null ? null : Unprotect(active);
        cleanup = "not-required";
        var removed = false;
        if (active is not null && oldKey != accountKey)
        {
            // Compare BEFORE changing active: its protected bytes are part of the
            // original receipt. A later writer's A is never ours to delete.
            if (oldKey is not null && previous is not null && previous.VaultBinding == RetirementBinding &&
                previous.OwnerKey == Hash(oldKey) && previous.ActiveEntryHash == Hash(active) &&
                previous.EntriesHash == EntriesHash(RetirementEntries(old, previous.OwnerKey)))
            {
                foreach (var entry in RetirementEntries(old, previous.OwnerKey)) next.Remove(entry.Key);
                removed = true;
                cleanup = "completed";
            }
            else cleanup = "version-conflict";
        }
        Select(next);
        try
        {
            if (!WriteVault(old, next)) throw new IOException("Credential vault changed before commit.");
        }
        catch (Exception error) when (removed && error is IOException or UnauthorizedAccessException)
        {
            // A cleanup write failure must not turn a successful authorization
            // into a failed login if saving B alone can still commit. Re-read
            // under this SAME lease; never restore stale entries over a writer.
            old = ReadVault(strict: true);
            next = new Dictionary<string, string>(old, StringComparer.Ordinal);
            Select(next);
            if (!WriteVault(old, next)) throw new IOException("Credential vault changed before commit.");
            cleanup = "deferred";
        }
        return RetirementStamp(next, accountKey);

        void Select(Dictionary<string, string> values)
        {
            values.Remove(accountKey);
            values[StorageKey(accountKey)] = Protect(refreshToken);
            values[ActiveAccountEntry] = Protect(accountKey);
        }
    }

    // Startup privacy sweep. Read selection and delete only unselected entries
    // under the shared writer lease, leaving selected bytes exactly unchanged.
    internal void CleanupUnselectedCredentials()
    {
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var active = old.GetValueOrDefault(ActiveAccountEntry);
        var key = active is null ? null : Unprotect(active);
        if (active is not null && key is null) throw new InvalidDataException("Credential selection cannot be read.");
        var next = new Dictionary<string, string>(old, StringComparer.Ordinal);
        foreach (var entry in old)
            if (entry.Key != ActiveAccountEntry && (key is null || entry.Key != key && entry.Key != StorageKey(key)))
                next.Remove(entry.Key);
        if (next.Count != old.Count && !WriteVault(old, next)) throw new IOException("Credential vault changed before cleanup.");
    }
}
