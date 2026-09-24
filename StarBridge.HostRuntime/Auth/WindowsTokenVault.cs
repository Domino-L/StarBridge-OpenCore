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

public sealed class WindowsTokenVault : ITokenVault
{
    private const string ActiveAccountEntry = "__active_account";
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.ScmOAuth.RefreshToken.v1");
    private readonly string _vaultPath;

    public WindowsTokenVault(string? vaultPath = null)
    {
        _vaultPath = vaultPath ?? Path.Combine(
            StarBridge.HostRuntime.HostDataRoot.CurrentRoot,
            "scm-token-vault.json");
    }

    public void SaveRefreshToken(string accountKey, string refreshToken)
    {
        ArgumentException.ThrowIfNullOrWhiteSpace(accountKey);
        ArgumentException.ThrowIfNullOrWhiteSpace(refreshToken);
        var values = ReadVault();
        values.Remove(accountKey);
        values[StorageKey(accountKey)] = Protect(refreshToken);
        values[ActiveAccountEntry] = Protect(accountKey);
        WriteVault(values);
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
        var values = ReadVault();
        var removed = values.Remove(StorageKey(accountKey)) | values.Remove(accountKey);
        if (values.TryGetValue(ActiveAccountEntry, out var encoded) &&
            string.Equals(Unprotect(encoded), accountKey, StringComparison.Ordinal))
        {
            removed = values.Remove(ActiveAccountEntry) || removed;
        }
        if (removed)
        {
            WriteVault(values);
        }
    }

    private static string StorageKey(string accountKey) =>
        "account:" + Convert.ToHexString(SHA256.HashData(Encoding.UTF8.GetBytes(accountKey)));

    private static string Protect(string value)
    {
        var protectedBytes = ProtectedData.Protect(
            Encoding.UTF8.GetBytes(value),
            Entropy,
            DataProtectionScope.CurrentUser);
        return Convert.ToBase64String(protectedBytes);
    }

    private static string? Unprotect(string encoded)
    {
        try
        {
            var bytes = ProtectedData.Unprotect(
                Convert.FromBase64String(encoded),
                Entropy,
                DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch (Exception exception) when (exception is CryptographicException or FormatException)
        {
            return null;
        }
    }

    private Dictionary<string, string> ReadVault()
    {
        try
        {
            return File.Exists(_vaultPath)
                ? JsonSerializer.Deserialize<Dictionary<string, string>>(File.ReadAllText(_vaultPath)) ?? []
                : [];
        }
        catch (JsonException)
        {
            return [];
        }
    }

    private void WriteVault(Dictionary<string, string> values)
    {
        Directory.CreateDirectory(Path.GetDirectoryName(_vaultPath)!);
        var temporaryPath = _vaultPath + ".tmp";
        File.WriteAllText(temporaryPath, JsonSerializer.Serialize(values));
        File.Move(temporaryPath, _vaultPath, true);
    }
}
