using System.Security.Cryptography;

namespace StarBridge.HostRuntime.Account;

internal sealed partial class OfflineAccountStore
{
    // Shared byte protection/publication for display resources. The original
    // account document remains the only owner/mode selection authority.
    private static byte[]? ReadProtectedBytes(string path, byte[] entropy, int limit)
    {
        Safe(path);
        if (!File.Exists(path)) return null;
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read | FileShare.Delete);
        if (stream.Length is <= 0 || stream.Length > limit) throw new InvalidDataException();
        var encrypted = new byte[(int)stream.Length];
        stream.ReadExactly(encrypted);
        if (stream.ReadByte() != -1) throw new InvalidDataException();
        var clear = ProtectedData.Unprotect(encrypted, entropy, DataProtectionScope.CurrentUser);
        if (clear.Length <= limit) return clear;
        CryptographicOperations.ZeroMemory(clear);
        throw new InvalidDataException();
    }

    private static bool PublishProtectedBytes(string path, byte[] clear, byte[] entropy, int limit, Func<bool> current)
    {
        byte[] encrypted;
        try
        {
            if (clear.Length > limit - 1024) throw new InvalidDataException();
            encrypted = ProtectedData.Protect(clear, entropy, DataProtectionScope.CurrentUser);
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
        if (encrypted.Length > limit) throw new InvalidDataException();
        var temporary = path + "." + Guid.NewGuid().ToString("N") + ".tmp";
        var created = false;
        try
        {
            Safe(path);
            using (var file = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None,
                4096, FileOptions.WriteThrough))
            { created = true; file.Write(encrypted); file.Flush(true); }
            Safe(path);
            if (!current()) return false;
            File.Move(temporary, path, overwrite: true);
            return true;
        }
        finally { if (created && File.Exists(temporary)) File.Delete(temporary); }
    }
}
