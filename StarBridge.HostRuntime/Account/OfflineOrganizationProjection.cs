using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.NativeBridge;

namespace StarBridge.HostRuntime.Account;

internal static class OfflineOrganizationProjection
{
    internal static object Read(OfflineOrganizationDirectory directory, JsonElement body, bool media)
    {
        var offset = body.TryGetProperty("offset", out var rawOffset) ? rawOffset.GetInt32() : 0;
        var expected = body.TryGetProperty("directoryVersion", out var rawVersion) ? rawVersion.GetString() : null;
        if (expected is not null && expected != directory.Version) throw Failure("directory_changed");
        if (offset < 0) throw Failure("invalid_request");
        if (!media)
        {
            if (offset > directory.Items.Count || offset > 0 && expected is null) throw Failure("invalid_request");
            var rows = directory.Items.Skip(offset).Take(20).ToArray();
            return new { schemaVersion = 1, source = "cached", directory.CachedAtUtc, directory.Complete,
                directoryVersion = directory.Version,
                items = rows.Select(row => new { row.Id, row.Name, logoAvailable = row.LogoImageData is not null,
                    logoVersion = row.LogoImageData is null ? null : ImageVersion(row.LogoImageData), row.LogoCachedAtUtc }).ToArray(),
                nextOffset = offset + rows.Length < directory.Items.Count ? (int?)(offset + rows.Length) : null };
        }
        var id = body.GetProperty("id").GetString();
        if (id is not { Length: 64 } || id.Any(ch => ch is not (>= '0' and <= '9' or >= 'a' and <= 'f')))
            throw Failure("invalid_request");
        var image = directory.Items.FirstOrDefault(row => row.Id == id)?.LogoImageData ?? throw Failure("unavailable");
        var bytes = ImageBytes(image);
        var version = Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant();
        var previous = body.TryGetProperty("version", out var rawPrevious) ? rawPrevious.GetString() : null;
        if (offset > 0 && previous is null) throw Failure("invalid_request");
        if (previous is not null && previous != version) throw Failure("media_changed");
        if (offset >= bytes.Length) throw Failure("invalid_request");
        var count = Math.Min(192 * 1024, bytes.Length - offset);
        return new { schemaVersion = 1, kind = "logo", memberRef = (string?)null, version,
            mimeType = image.StartsWith("data:image/png;", StringComparison.Ordinal) ? "image/png" : "image/jpeg",
            totalBytes = bytes.Length, offset, next = offset + count < bytes.Length ? (int?)(offset + count) : null,
            data = Convert.ToBase64String(bytes, offset, count) };
    }
    private static string ImageVersion(string image) => Convert.ToHexString(SHA256.HashData(ImageBytes(image))).ToLowerInvariant();
    private static byte[] ImageBytes(string image) => Convert.FromBase64String(image[(image.IndexOf(',') + 1)..]);
    private static AccountBridgeHostException Failure(string suffix) => new("offlineAccount." + suffix);
}
