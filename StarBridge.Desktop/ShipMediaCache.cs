using System.IO;
using StarBridge.Core.ShipMedia;

namespace StarBridge.Desktop;

internal static class ShipMediaCache
{
    internal static string GetPath(string mediaId)
    {
        if (!Guid.TryParseExact(mediaId?.Trim(), "N", out _))
        {
            return "";
        }

        var directory = Path.Combine(DesktopAppConfig.ConfigDirectory, "Images", "ShipMedia");
        return Path.Combine(directory, $"{mediaId.Trim().ToLowerInvariant()}.image");
    }

    internal static string? Resolve(string? mediaId)
    {
        if (string.IsNullOrWhiteSpace(mediaId))
        {
            return null;
        }

        var path = GetPath(mediaId);
        return path.Length > 0 && File.Exists(path) && new FileInfo(path).Length is > 0 and <= ShipMediaPolicy.MaximumImageBytes
            ? path
            : null;
    }

    internal static async Task<string> StoreAsync(string mediaId, byte[] bytes)
    {
        if (bytes.Length is <= 0 or > ShipMediaPolicy.MaximumImageBytes)
        {
            throw new InvalidDataException("图片大小不符合要求。");
        }

        var path = GetPath(mediaId);
        if (path.Length == 0)
        {
            throw new InvalidDataException("图片标识无效。");
        }

        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        var temporaryPath = path + ".tmp";
        await File.WriteAllBytesAsync(temporaryPath, bytes);
        File.Move(temporaryPath, path, overwrite: true);
        return path;
    }

    internal static void Remove(string? mediaId)
    {
        var path = string.IsNullOrWhiteSpace(mediaId) ? "" : GetPath(mediaId);
        if (path.Length == 0 || !File.Exists(path))
        {
            return;
        }

        try
        {
            File.Delete(path);
        }
        catch
        {
            // Cache cleanup is best-effort. The immutable media ID prevents stale replacement.
        }
    }
}
