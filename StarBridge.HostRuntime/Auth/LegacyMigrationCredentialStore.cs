using System.IO;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;

namespace StarBridge.HostRuntime.Auth;

public sealed record LegacyMigrationCredential(
    string AccountId,
    string? AccountName,
    string AuthToken,
    DateTimeOffset CapturedAtUtc);

public interface ILegacyMigrationCredentialStore
{
    void Save(LegacyMigrationCredential credential);
    LegacyMigrationCredential? Load();
    void Delete();
}

public sealed class WindowsLegacyMigrationCredentialStore : ILegacyMigrationCredentialStore
{
    private static readonly byte[] Entropy =
        Encoding.UTF8.GetBytes("StarBridge.LegacyMigrationCredential.v1");

    private readonly string _storePath;

    public WindowsLegacyMigrationCredentialStore(string? storePath = null)
    {
        _storePath = storePath ?? Path.Combine(
            StarBridge.HostRuntime.HostDataRoot.CurrentRoot,
            "legacy-migration-credential.dat");
    }

    public void Save(LegacyMigrationCredential credential)
    {
        ArgumentNullException.ThrowIfNull(credential);
        ArgumentException.ThrowIfNullOrWhiteSpace(credential.AccountId);
        ArgumentException.ThrowIfNullOrWhiteSpace(credential.AuthToken);

        var plaintext = JsonSerializer.SerializeToUtf8Bytes(credential);
        var encrypted = ProtectedData.Protect(plaintext, Entropy, DataProtectionScope.CurrentUser);
        Directory.CreateDirectory(Path.GetDirectoryName(_storePath)!);
        var temporaryPath = _storePath + ".tmp";
        File.WriteAllBytes(temporaryPath, encrypted);
        File.Move(temporaryPath, _storePath, true);
    }

    public LegacyMigrationCredential? Load()
    {
        try
        {
            if (!File.Exists(_storePath))
            {
                return null;
            }

            var encrypted = File.ReadAllBytes(_storePath);
            var plaintext = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
            var credential = JsonSerializer.Deserialize<LegacyMigrationCredential>(plaintext);
            return credential is not null &&
                   !string.IsNullOrWhiteSpace(credential.AccountId) &&
                   !string.IsNullOrWhiteSpace(credential.AuthToken)
                ? credential
                : null;
        }
        catch (Exception exception) when (exception is CryptographicException or JsonException or IOException)
        {
            return null;
        }
    }

    public void Delete()
    {
        if (File.Exists(_storePath))
        {
            File.Delete(_storePath);
        }
    }
}
