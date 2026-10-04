namespace StarBridge.HostRuntime.Settings;

using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using System.Text.Json.Serialization;

// Account-local preference and ONE last address, never a browsing history or part
// of the device UI preferences/shareable presets. No legacy file migration.
internal sealed class MenuBrowserResumeStore(string root)
{
    internal sealed record Snapshot([property: JsonRequired] long Revision = 0,
        [property: JsonRequired] bool Enabled = true, [property: JsonRequired] string? Url = null);
    private sealed record Document([property: JsonRequired] int Version,
        [property: JsonRequired] string Owner, [property: JsonRequired] Snapshot Value);
    private readonly string _directory = Path.Combine(Path.GetFullPath(root), "menu-browser-resume-v1");
    private static readonly JsonSerializerOptions Json = new(JsonSerializerDefaults.Web)
    { UnmappedMemberHandling = JsonUnmappedMemberHandling.Disallow };

    internal static bool ValidOwner(string? owner) => owner is { Length: 64 } && owner.All(c => c is >= '0' and <= '9' or >= 'A' and <= 'F');
    internal static bool ValidUrl(string? url) => url is { Length: > 0 and <= 4096 } &&
        url == url.Trim() && !url.Any(c => char.IsControl(c) || char.IsWhiteSpace(c)) && !url.Contains('\\') &&
        Uri.TryCreate(url, UriKind.Absolute, out var uri) && uri.Scheme is "https" or "http" &&
        !string.IsNullOrWhiteSpace(uri.Host) && !uri.Host.Contains('%') && string.IsNullOrEmpty(uri.UserInfo);
    private string PathFor(string owner)
    {
        if (!ValidOwner(owner)) throw new ArgumentException("Invalid browser owner");
        return Path.Combine(_directory, owner + ".bin");
    }
    private static byte[] Entropy(string owner) => Encoding.UTF8.GetBytes("StarBridge.menu-browser-resume.v1:" + owner);
    private static void Safe(string path)
    {
        for (var current = Path.GetFullPath(path); current is not null; current = Path.GetDirectoryName(current))
            if ((File.Exists(current) || Directory.Exists(current)) &&
                File.GetAttributes(current).HasFlag(FileAttributes.ReparsePoint)) throw new IOException("Linked browser storage path");
    }
    internal Snapshot Read(string owner)
    {
        var path = PathFor(owner); Safe(path);
        if (!File.Exists(path)) return new();
        using var stream = new FileStream(path, FileMode.Open, FileAccess.Read, FileShare.Read);
        if (stream.Length is <= 0 or > 32768) throw new InvalidDataException();
        var encrypted = new byte[(int)stream.Length]; stream.ReadExactly(encrypted);
        var clear = ProtectedData.Unprotect(encrypted, Entropy(owner), DataProtectionScope.CurrentUser);
        try
        {
            using var document = JsonDocument.Parse(clear);
            Unique(document.RootElement);
            var data = JsonSerializer.Deserialize<Document>(clear, Json);
            if (data is null || data.Version != 1 || data.Owner != owner || data.Value is null ||
                data.Value.Revision < 0 || (!data.Value.Enabled && data.Value.Url is not null) ||
                (data.Value.Url is not null && !ValidUrl(data.Value.Url))) throw new InvalidDataException();
            return data.Value;
        }
        finally { CryptographicOperations.ZeroMemory(clear); }
    }
    private static void Unique(JsonElement value)
    {
        if (value.ValueKind != JsonValueKind.Object) return;
        var keys = new HashSet<string>(StringComparer.Ordinal);
        foreach (var field in value.EnumerateObject())
        { if (!keys.Add(field.Name)) throw new InvalidDataException(); Unique(field.Value); }
    }
    internal Snapshot SetConsent(string owner, long revision, bool enabled, Func<bool> current) =>
        Write(owner, revision, current, old => new(checked(old.Revision + 1), enabled, enabled ? old.Url : null));
    internal Snapshot Remember(string owner, long revision, string url, Func<bool> current)
    {
        if (!ValidUrl(url)) throw new ArgumentException("Invalid browser address");
        return Write(owner, revision, current, old => old.Enabled
            ? old with { Url = url }
            : throw new ApplicationPreferencesException("menuBrowserResume.disabled", "Address saving is disabled"));
    }
    private Snapshot Write(string owner, long revision, Func<bool> current, Func<Snapshot, Snapshot> change)
    {
        if (revision < 0 || revision == long.MaxValue) throw new ArgumentException("Invalid browser revision");
        var path = PathFor(owner); Safe(path); Safe(_directory); Safe(path + ".lock");
        if (!current()) throw new OperationCanceledException();
        Directory.CreateDirectory(_directory);
        using var guard = new FileStream(path + ".lock", FileMode.OpenOrCreate, FileAccess.Write, FileShare.None);
        var old = Read(owner);
        if (old.Revision != revision) throw new ApplicationPreferencesException("menuBrowserResume.revision_conflict", "Browser preference changed", true);
        var next = change(old);
        if (old == next)
        { if (!current()) throw new OperationCanceledException(); return old; }
        var clear = JsonSerializer.SerializeToUtf8Bytes(new Document(1, owner, next), Json);
        byte[] encrypted;
        try { encrypted = ProtectedData.Protect(clear, Entropy(owner), DataProtectionScope.CurrentUser); }
        finally { CryptographicOperations.ZeroMemory(clear); }
        var temporary = Path.Combine(_directory, Guid.NewGuid().ToString("N") + ".tmp");
        try
        {
            using (var stream = new FileStream(temporary, FileMode.CreateNew, FileAccess.Write, FileShare.None))
            { stream.Write(encrypted); stream.Flush(true); }
            // Generation and owner are rechecked after disk I/O, before commit.
            if (!current()) throw new OperationCanceledException();
            File.Move(temporary, path, true);
            return next;
        }
        finally { if (File.Exists(temporary)) File.Delete(temporary); }
    }
}
