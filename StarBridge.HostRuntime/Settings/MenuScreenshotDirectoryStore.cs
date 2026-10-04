namespace StarBridge.HostRuntime.Settings;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

// A device-local destination, not an account document or a shareable menu
// preference. Only the native folder picker may supply a non-default path.
internal sealed class MenuScreenshotDirectoryStore(string root)
{
    internal sealed record Snapshot([property: JsonRequired] long Revision = 0,
        [property: JsonRequired] string? Directory = null);
    private sealed record Document([property: JsonRequired] int Version,
        [property: JsonRequired] Snapshot Value);
    private readonly string _folder = Path.Combine(Path.GetFullPath(root), "menu-screenshot-directory-v1");
    private string FilePath => Path.Combine(_folder, "settings.bin");
    private static readonly byte[] Entropy = Encoding.UTF8.GetBytes("StarBridge.menu-screenshot-directory.v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    internal static bool ValidDirectory(string? path) => path is { Length: > 0 and <= 32767 } &&
        path == path.Trim() && !path.Any(char.IsControl) && Path.IsPathFullyQualified(path) &&
        !path.StartsWith(@"\\?\", StringComparison.Ordinal) &&
        !path.StartsWith(@"\\.\", StringComparison.Ordinal) &&
        Path.GetFullPath(path) == path;

    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
        {
            FileAttributes attributes;
            try { attributes = File.GetAttributes(current); }
            catch (FileNotFoundException) { continue; }
            catch (DirectoryNotFoundException) { continue; }
            if (attributes.HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked screenshot preference storage");
        }
    }

    internal Snapshot Read()
    {
        Safe(FilePath);
        FileStream source;
        try { source = new FileStream(FilePath, FileMode.Open, FileAccess.Read, FileShare.Read); }
        catch (FileNotFoundException) { return new(); }
        catch (DirectoryNotFoundException) { return new(); }
        using var stream = source;
        if (stream.Length is <= 0 or > 262144) throw new InvalidDataException();
        var encrypted = new byte[(int)stream.Length]; stream.ReadExactly(encrypted);
        var clear = ProtectedData.Unprotect(encrypted, Entropy, DataProtectionScope.CurrentUser);
        try
        {
            using var json = JsonDocument.Parse(clear); Unique(json.RootElement);
            var data = JsonSerializer.Deserialize<Document>(clear, Json);
            if (data is null || data.Version != 1 || data.Value is null || data.Value.Revision < 0 ||
                (data.Value.Directory is not null && !ValidDirectory(data.Value.Directory))) throw new InvalidDataException();
            return data.Value;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }

    private static void Unique(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return;
        var seen = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in value.EnumerateObject())
        { if (!seen.Add(field.Name)) throw new InvalidDataException(); Unique(field.Value); }
    }

    internal Snapshot Save(long revision, string? directory, Func<bool> current)
    {
        if (revision < 0 || revision == long.MaxValue || (directory is not null && !ValidDirectory(directory)))
            throw new ArgumentException("Invalid screenshot directory preference");
        Safe(FilePath); Safe(_folder); Safe(FilePath + ".lock");
        if (!current()) throw new OperationCanceledException();
        System.IO.Directory.CreateDirectory(_folder);
        using var guard = new FileStream(FilePath + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        var old = Read();
        if (old.Revision != revision) throw new ApplicationPreferencesException(
            "menuScreenshotDirectory.revision_conflict", "Screenshot directory changed", true);
        if (old.Directory == directory)
        { if (!current()) throw new OperationCanceledException(); return old; }
        var next = new Snapshot(checked(old.Revision + 1), directory);
        var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, next), Json);
        byte[] encrypted;
        try { encrypted = ProtectedData.Protect(clear, Entropy, DataProtectionScope.CurrentUser); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        var temporary = Path.Combine(_folder, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(encrypted); stream.Flush(true); }
            if (!current()) throw new OperationCanceledException();
            File.Move(temporary, FilePath, true);
            return next;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
