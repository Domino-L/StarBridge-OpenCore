using System.Security.Cryptography;
using System.Text;

namespace StarBridge.Desktop;

public static class LocalSecretProtector
{
    private const string Prefix = "dpapi:v1:";
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.Desktop.LocalSecrets.v1");

    public static string? Protect(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (IsProtected(value))
        {
            return value;
        }

        var bytes = Encoding.UTF8.GetBytes(value);
        var protectedBytes = ProtectedData.Protect(bytes, Entropy, DataProtectionScope.CurrentUser);
        return Prefix + Convert.ToBase64String(protectedBytes);
    }

    public static string? Unprotect(string? value)
    {
        if (string.IsNullOrWhiteSpace(value))
        {
            return null;
        }

        if (!IsProtected(value))
        {
            return value;
        }

        try
        {
            var payload = Convert.FromBase64String(value[Prefix.Length..]);
            var bytes = ProtectedData.Unprotect(payload, Entropy, DataProtectionScope.CurrentUser);
            return Encoding.UTF8.GetString(bytes);
        }
        catch (CryptographicException)
        {
            return null;
        }
        catch (FormatException)
        {
            return null;
        }
    }

    public static bool IsProtected(string? value) =>
        value?.StartsWith(Prefix, StringComparison.Ordinal) == true;
}
