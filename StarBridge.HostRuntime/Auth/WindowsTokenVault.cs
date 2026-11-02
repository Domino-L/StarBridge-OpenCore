using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.IO;

namespace StarBridge.HostRuntime.Auth;

public interface ITokenVault
{
    void SaveRefreshToken(string accountKey, string refreshToken);
    string? LoadRefreshToken(string accountKey);
    string? LoadActiveAccountKey();
    void DeleteRefreshToken(string accountKey);
}

public sealed partial class WindowsTokenVault : ITokenVault
{
    private const string ActiveAccountEntry = "__active_account";
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.ScmOAuth.RefreshToken.v1");
    private readonly string _vaultPath;

    public WindowsTokenVault(string? vaultPath = null)
    {
        _vaultPath = Path.GetFullPath(vaultPath ?? Path.Combine(
            StarBridge.HostRuntime.HostDataRoot.CurrentRoot,
            "scm-token-vault.json"));
    }

    public void SaveRefreshToken(string accountKey, string refreshToken)
        => _ = SaveRefreshTokenWithRetirement(accountKey, refreshToken);

    // The receipt describes precisely the bytes committed by this writer, not
    // a later read that might accidentally adopt another login's credential.
    internal ScmCredentialRetirementStamp SaveRefreshTokenWithRetirement(string accountKey, string refreshToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(refreshToken);
        if (accountKey.Length > 2048 || accountKey.Any(char.IsControl)) throw new ArgumentException("Credential owner key is invalid.", nameof(accountKey));
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var values = new Dictionary<string, string>(old, StringComparer.Ordinal);
        values.Remove(accountKey);
        values[StorageKey(accountKey)] = Protect(refreshToken);
        values[ActiveAccountEntry] = Protect(accountKey);
        if (!WriteVault(old, values)) throw new IOException("Credential vault changed before commit.");
        return RetirementStamp(values, accountKey);
    }

    public string? LoadRefreshToken(string accountKey)
    {
        var values = ReadVault();
        if (!values.TryGetValue(StorageKey(accountKey), out var encoded) &&
            !values.TryGetValue(accountKey, out encoded))
        {
            return null;
        }
        return Unprotect(encoded);
    }

    public string? LoadActiveAccountKey() =>
        ReadVault().TryGetValue(ActiveAccountEntry, out var encoded) ? Unprotect(encoded) : null;

    public void DeleteRefreshToken(string accountKey)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        using var writer = OpenWriter();
        var old = ReadVault(strict: true);
        var values = new Dictionary<string, string>(old, StringComparer.Ordinal);
        var removed = values.Remove(StorageKey(accountKey)) | values.Remove(accountKey);
        if (values.TryGetValue(ActiveAccountEntry, out var encoded) &&
            string.Equals(Unprotect(encoded), accountKey, StringComparison.Ordinal))
        {
            removed = values.Remove(ActiveAccountEntry) || removed;
        }
        if (removed)
        {
            if (!WriteVault(old, values)) throw new IOException("Credential vault changed before commit.");
        }
    }

    private static string StorageKey(string accountKey) =>
        "account:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(accountKey)));

    private static string Protect(string value)
    {
        var clear = Encoding.UTF8.GetBytes(value);
        try { return Convert.ToBase64String(ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser)); }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    private static string? Unprotect(string encoded)
    {
        try
        {
            var bytes = ProtectedData.Unprotect(
                Convert.FromBase64String(encoded),
                Entropy,
                DataProtectionScope.CurrentUser);
            try { return Encoding.UTF8.GetString(bytes); }
            finally { CryptographicOperations.ZeroMemory(bytes); }
        }
        catch (Exception exception) when (exception is CryptographicException or FormatException)
        {
            return null;
        }
    }

    private Dictionary<string, string> ReadVault(bool strict = false)
    {
        try
        {
            CheckPath(_vaultPath);
            FileStream file;
            try { file = new(_vaultPath, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete); }
            catch (FileNotFoundException) { return new(StringComparer.Ordinal); }
            catch (DirectoryNotFoundException) { return new(StringComparer.Ordinal); }
            using var source = file;
            if (source.Length is <= 0 or > 1_048_576) throw new InvalidDataException("Credential vault size is invalid.");
            var clear = new byte[(int)source.Length];
            source.ReadExactly(clear);
            if (source.ReadByte() != -1) throw new IOException("Credential vault changed while reading.");
            using var json = JsonDocument.Parse(clear);
            if (json.RootElement.ValueKind != JsonValueKind.Object) throw new JsonException("Credential vault must be an object.");
            var values = new Dictionary<string, string>(StringComparer.Ordinal);
            foreach (var property in json.RootElement.EnumerateObject())
            {
                if (values.Count >= 256 || property.Name.Length is <= 0 or > 2048 || property.Name.Any(char.IsControl) ||
                    property.Value.ValueKind != JsonValueKind.String || property.Value.GetString() is not { Length: > 0 and <= 65536 } value ||
                    !values.TryAdd(property.Name, value)) throw new JsonException("Credential vault entries are invalid.");
            }
            return values;
        }
        catch (JsonException) when (!strict)
        {
            return [];
        }
        catch (JsonException error) when (strict)
        {
            throw new InvalidDataException("Credential vault entries cannot be verified.", error);
        }
    }

    private bool WriteVault(Dictionary<string, string> old, Dictionary<string, string> values, Func<bool>? current = null)
    {
        string? temporary = null;
        try
        {
            if (current?.Invoke() == false) return false;
            CheckPath(_vaultPath);
            if (values.Count > 256 || values.Any(entry => entry.Key.Length is <= 0 or > 2048 || entry.Key.Any(char.IsControl) ||
                    entry.Value.Length is <= 0 or > 65536)) throw new InvalidDataException("Credential vault entries are invalid.");
            var bytes = JsonSerializer.SerializeToUtf8Bytes(values);
            if (bytes.Length > 1_048_576) throw new InvalidDataException("Credential vault size is invalid.");
            temporary = _vaultPath + "." + Guid.NewGuid().ToString("N") + ".tmp";
            CheckPath(temporary);
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None, 4096, FileOptions.WriteThrough))
            { file.Write(bytes); file.Flush(true); }
            CheckPath(_vaultPath); CheckPath(temporary);
            var before = ReadVault(strict: true);
            if (current?.Invoke() == false || old.Count != before.Count ||
                old.Any(entry => !before.TryGetValue(entry.Key, out var value) || value != entry.Value)) return false;
            if (current?.Invoke() == false) return false;
            var final = ReadVault(strict: true);
            if (old.Count != final.Count || old.Any(entry => !final.TryGetValue(entry.Key, out var value) || value != entry.Value)) return false;
            var committing = temporary;
            return CommitTemporary(committing, () =>
            {
                // A wait may outlast these checks; every further attempt repeats them.
                if (current?.Invoke() == false) return false;
                CheckPath(_vaultPath); CheckPath(committing);
                var waited = ReadVault(strict: true);
                return old.Count == waited.Count && old.All(entry => waited.TryGetValue(entry.Key, out var value) && value == entry.Value);
            });
        }
        finally
        {
            if (temporary is not null)
                try { CheckPath(temporary); File.Delete(temporary); } catch (IOException) { } catch (UnauthorizedAccessException) { }
        }
    }
}
