using System.Diagnostics;
using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace StarBridge.HostRuntime.Auth;

// Host-private, opaque storage identity and exact encrypted-entry versions.
// No account key, token, endpoint or filesystem path belongs in this receipt.
// It is not evidence of publication withdrawal, session exit or local readiness.
internal sealed record ScmCredentialRetirementStamp(
    [property: JsonRequired] string VaultBinding,
    [property: JsonRequired] string OwnerKey,
    [property: JsonRequired] string? EntriesHash,
    [property: JsonRequired] string? ActiveEntryHash);

public sealed partial class WindowsTokenVault
{
    private string RetirementBinding => Hash(_vaultPath.ToUpperInvariant());
    internal bool IsRetirementBoundTo(ScmCredentialRetirementStamp expected) => expected.VaultBinding == RetirementBinding;
    private static string Hash(string text) => Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(text)));

    // The lease excludes other writers; it is not a failure signal. Another
    // instance, process or file scanner holds it only briefly, and failing at once
    // could lose a refresh token the server has already rotated. Bounded so that a
    // stuck holder still surfaces as the same storage failure.
    private static readonly TimeSpan FileTurnBudget = TimeSpan.FromSeconds(2);

    private FileStream OpenWriter()
    {
        CheckPath(_vaultPath); CheckPath(_vaultPath + ".lock");
        Directory.CreateDirectory(Path.GetDirectoryName(_vaultPath)!);
        CheckPath(_vaultPath); CheckPath(_vaultPath + ".lock");
        var waited = Stopwatch.StartNew();
        for (var delay = 1; ; delay = Math.Min(delay * 2, 50))
        {
            try { return new(_vaultPath + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None); }
            catch (IOException error) when (IsSharingConflict(error) && waited.Elapsed < FileTurnBudget) { }
            Thread.Sleep(delay);
            CheckPath(_vaultPath); CheckPath(_vaultPath + ".lock");
        }
    }

    // Readers take no lease, so the commit must never expose a gap.
    private bool CommitTemporary(string temporary, Func<bool> unchanged) =>
        StoreFileCommit.Replace(temporary, _vaultPath, unchanged, "Credential vault commit did not complete.");

    private static bool IsSharingConflict(Exception error) => StoreFileCommit.IsSharingConflict(error);

    private static void CheckPath(string path)
    {
        for (var node = Path.GetFullPath(path); node is not null; node = Path.GetDirectoryName(node))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(node); }
            catch (FileNotFoundException) { continue; }
            catch (DirectoryNotFoundException) { continue; }
            if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Credential vault path is not a regular local path.");
        }
    }

    private static KeyValuePair<string, string>[] RetirementEntries(Dictionary<string, string> values, string ownerKey) =>
        values.Where(entry => entry.Key != ActiveAccountEntry && (entry.Key == "account:" + ownerKey || Hash(entry.Key) == ownerKey))
            .OrderBy(entry => entry.Key, StringComparer.Ordinal).ToArray();

    private static string? EntriesHash(KeyValuePair<string, string>[] entries) => entries.Length == 0 ? null :
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(entries)));

    private ScmCredentialRetirementStamp RetirementStamp(Dictionary<string, string> values, string accountKey)
    {
        var ownerKey = Hash(accountKey);
        var entries = RetirementEntries(values, ownerKey);
        foreach (var entry in entries)
            if (Unprotect(entry.Value) is not { Length: > 0 }) throw new InvalidDataException("Credential entry cannot be verified.");
        var active = values.GetValueOrDefault(ActiveAccountEntry);
        if (active is not null && (Unprotect(active) != accountKey || entries.Length == 0) || active is null && entries.Length != 0)
            throw new InvalidDataException("Credential selection cannot be verified.");
        return new(RetirementBinding, ownerKey, EntriesHash(entries), active is null ? null : Hash(active));
    }

    // Explicit native-owner preparation only. Normal startup never calls this.
    internal ScmCredentialRetirementStamp CaptureRetirement(string accountKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        using var writer = OpenWriter();
        return RetirementStamp(ReadVault(strict: true), accountKey);
    }

    internal bool IsRetirementCurrent(ScmCredentialRetirementStamp expected)
    {
        ValidateRetirementStamp(expected);
        if (expected.VaultBinding != RetirementBinding) return false;
        var values = ReadVault(strict: true);
        var entries = RetirementEntries(values, expected.OwnerKey);
        var active = values.GetValueOrDefault(ActiveAccountEntry);
        return EntriesHash(entries) == expected.EntriesHash && (active is null ? null : Hash(active)) == expected.ActiveEntryHash;
    }

    internal bool IsRetirementCleared(ScmCredentialRetirementStamp expected)
    {
        ValidateRetirementStamp(expected);
        if (expected.VaultBinding != RetirementBinding) return false;
        var values = ReadVault(strict: true);
        return RetirementEntries(values, expected.OwnerKey).Length == 0 && !values.ContainsKey(ActiveAccountEntry);
    }

    // Exact version compare and clear under the same writer lease as login / refresh.
    // Missing original entries are idempotent only when no new selected login exists.
    // This method does not unprotect or restore credentials, revoke remotely or start OAuth.
    internal bool TryClearRetirement(ScmCredentialRetirementStamp expected, Func<bool> current, Action? afterClear = null)
    {
        ArgumentNullException.ThrowIfNull(current);
        ValidateRetirementStamp(expected);
        if (expected.VaultBinding != RetirementBinding || !current()) return false;
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var entries = RetirementEntries(old, expected.OwnerKey);
        var active = old.GetValueOrDefault(ActiveAccountEntry);
        if (entries.Length != 0 || active is not null)
        {
            if (EntriesHash(entries) != expected.EntriesHash || (active is null ? null : Hash(active)) != expected.ActiveEntryHash || !current())
                return false;
            var next = new Dictionary<string, string>(old, StringComparer.Ordinal);
            foreach (var entry in entries) next.Remove(entry.Key);
            next.Remove(ActiveAccountEntry);
            if (!WriteVault(old, next, current)) return false;
            // Report an actually committed local clear to the original OAuth
            // owner even if cancellation follows the commit. It must retain
            // that fact for its own retry; absence alone cannot recreate it.
            if (afterClear is null) return true;
        }
        if (!current()) return false;
        // A mode commit may follow actual deletion while this same writer lease
        // still excludes a new login. A failed commit leaves the original clear
        // idempotent; it never restores authorization or acknowledges the mode.
        afterClear?.Invoke();
        return true;
    }

    // Some auth-only resume failures retain the original credential for an
    // explicit retry. Observe rejection without deleting it, while excluding a
    // concurrent login from inheriting the earlier authorization decision.
    internal bool ObserveCurrentRetirement(ScmCredentialRetirementStamp expected, Func<bool> current, Action observe)
    {
        ArgumentNullException.ThrowIfNull(current);
        ArgumentNullException.ThrowIfNull(observe);
        ValidateRetirementStamp(expected);
        if (expected.VaultBinding != RetirementBinding || !current()) return false;
        using var writer = OpenWriter();
        if (!IsRetirementCurrent(expected) || !current()) return false;
        observe();
        return current() && IsRetirementCurrent(expected);
    }

    internal static void ValidateRetirementStamp(ScmCredentialRetirementStamp value)
    {
        static bool Digest(string? text) => text is { Length: 64 } && text.All(char.IsAsciiHexDigit);
        if (value is null || !Digest(value.VaultBinding) || !Digest(value.OwnerKey) ||
            value.EntriesHash is not null && !Digest(value.EntriesHash) || value.ActiveEntryHash is not null && !Digest(value.ActiveEntryHash) ||
            (value.EntriesHash is null) != (value.ActiveEntryHash is null))
            throw new InvalidDataException("Credential retirement stamp is invalid.");
    }
}
