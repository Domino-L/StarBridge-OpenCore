using System.Security.Cryptography;
using System.Text.Json;
using System.Text.RegularExpressions;

namespace StarBridge.HostRuntime.Hangar;

/// <summary>Only exact-hash images already present in this Flutter bundle may cross the Bridge.</summary>
public sealed class ShipBundledMediaCatalog
{
    private readonly Dictionary<string, string> _assets = new(StringComparer.Ordinal);
    private readonly Dictionary<string, string> _thumbnails = new(StringComparer.Ordinal);
    public ShipBundledMediaCatalog(string? manifest, string assetsRoot)
    {
        if (manifest is null || manifest.Length > 1024 * 1024) return;
        try
        {
            using var document = JsonDocument.Parse(manifest);
            var root = document.RootElement;
            if (root.GetProperty("schemaVersion").GetInt32() != 1 ||
                root.GetProperty("distributionScope").GetString() != "local-test-only") return;
            var rows = root.GetProperty("files");
            if (rows.GetArrayLength() > 1000) return;
            var directory = new DirectoryInfo(Path.GetFullPath(assetsRoot));
            for (var current = directory; current is not null; current = current.Parent)
                if ((current.Attributes & FileAttributes.ReparsePoint) != 0) return;
            var seen = new HashSet<string>(StringComparer.Ordinal);
            foreach (var row in rows.EnumerateArray())
            {
                var key = row.GetProperty("key").GetString()!;
                var file = row.GetProperty("file").GetString()!;
                var hash = row.GetProperty("sha256").GetString()!;
                if (!Regex.IsMatch(key, "^[a-z0-9_-]{1,100}$") ||
                    !Regex.IsMatch(file, "^catalog-[a-z0-9_-]+\\.(jpg|jpeg|png|webp)$") ||
                    !Regex.IsMatch(hash, "^[A-Fa-f0-9]{64}$") || !seen.Add(key))
                { _assets.Clear(); _thumbnails.Clear(); return; }
                if (Verified(directory.FullName, file, hash)) _assets.Add(key, "assets/ships/" + file);
                if (row.TryGetProperty("thumbnailFile", out var thumbnail))
                {
                    var squareFile = thumbnail.GetString()!;
                    var squareHash = row.GetProperty("thumbnailSha256").GetString()!;
                    if (!Regex.IsMatch(squareFile, "^catalog-square-[a-z0-9_-]+\\.(jpg|jpeg|png|webp)$") ||
                        !Regex.IsMatch(squareHash, "^[A-Fa-f0-9]{64}$"))
                    { _assets.Clear(); _thumbnails.Clear(); return; }
                    if (Verified(directory.FullName, squareFile, squareHash))
                        _thumbnails.Add(key, "assets/ships/" + squareFile);
                }
            }
        }
        catch (Exception error) when (error is JsonException or IOException or UnauthorizedAccessException
            or ArgumentException or InvalidOperationException or KeyNotFoundException or FormatException)
        { _assets.Clear(); _thumbnails.Clear(); }
    }
    public string? Find(string? key) => key is null ? null : _assets.GetValueOrDefault(key);
    public string? FindThumbnail(string? key) => key is null ? null : _thumbnails.GetValueOrDefault(key);

    private static bool Verified(string directory, string file, string hash)
    {
        var path = Path.Combine(directory, file);
        var info = new FileInfo(path);
        if (!info.Exists || (info.Attributes & FileAttributes.ReparsePoint) != 0 ||
            info.Length <= 0 || info.Length > 4 * 1024 * 1024) return false;
        using var stream = File.OpenRead(path);
        return Convert.ToHexString(SHA256.HashData(stream)).Equals(hash, StringComparison.OrdinalIgnoreCase);
    }
}
