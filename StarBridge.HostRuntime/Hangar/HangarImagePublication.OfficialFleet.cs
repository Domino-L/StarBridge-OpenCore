using System.Security.Cryptography;
using StarBridge.Core.ShipMedia;

namespace StarBridge.HostRuntime.Hangar;

internal sealed record OfficialHangarImageReceipt(ShipMediaSummaryContract Media, string ContentHash, string ImageVersion);
internal sealed record OfficialHangarImageGrant(string InstanceRef, string ShipCode, string MediaId, string ContentHash,
    double CropFocusX, double CropFocusY, double CropZoom, string ImageVersion);

internal static partial class HangarImagePublication
{
    // Reuse the same saved image reader; the official audience is an explicit
    // selected-instance set. Never call the community all-inventory media lane.
    internal static async Task<OfficialHangarImageGrant[]> PrepareSelectedAsync(LocalHangarSnapshot snapshot,
        IReadOnlyCollection<string> selected, string owner, Func<string, string?> readImage,
        Func<ShipMediaUploadRequestContract, CancellationToken, Task<OfficialHangarImageReceipt>> upload,
        Action prepared, Action current, CancellationToken token)
    {
        var ships = CommunityHangarPublication.Build(snapshot);
        if (selected.Count > 10000 || selected.Distinct(StringComparer.Ordinal).Count() != selected.Count ||
            selected.Except(ships.Select(ship => ship.Id), StringComparer.Ordinal).Any()) throw InvalidImage();
        var requests = new List<(ShipMediaUploadRequestContract Image, string Hash, int Length)>();
        foreach (var ship in ships.Where(ship => selected.Contains(ship.Id, StringComparer.Ordinal)))
        {
            current(); token.ThrowIfCancellationRequested();
            var data = readImage(ship.Id); if (data is null) continue;
            const string prefix = "data:image/png;base64,";
            if (!data.StartsWith(prefix, StringComparison.Ordinal) || data.Length > 700000 || requests.Count >= ShipMediaPolicy.MaximumUploadsPerHour) throw InvalidImage();
            byte[] bytes; try { bytes = Convert.FromBase64String(data[prefix.Length..]); } catch (FormatException) { throw InvalidImage(); }
            if (bytes.Length is < 1 or > ShipMediaPolicy.MaximumImageBytes) throw InvalidImage();
            requests.Add((new(ship.Id, ship.Code, ship.DisplayName, data[prefix.Length..], Guid.NewGuid().ToString("N")),
                Convert.ToHexString(SHA256.HashData(bytes)).ToLowerInvariant(), bytes.Length));
        }
        current(); token.ThrowIfCancellationRequested(); prepared();
        var grants = new List<OfficialHangarImageGrant>(); var mediaIds = new HashSet<string>(StringComparer.Ordinal);
        foreach (var (image, hash, length) in requests)
        {
            current(); token.ThrowIfCancellationRequested();
            var receipt = await upload(image, token);
            current(); token.ThrowIfCancellationRequested();
            var media = receipt.Media;
            if (media is null || media.OwnerAccountId != owner || media.OwnerDisplayName != "" ||
                media.ShipInstanceId != image.ShipInstanceId || media.ShipCode != image.ShipCode || media.ShipDisplayName != image.ShipDisplayName ||
                media.MediaId is not { Length: 32 } || media.MediaId.Any(c => c is not (>= '0' and <= '9' or >= 'a' and <= 'f')) || !mediaIds.Add(media.MediaId) ||
                media.ContentType != "image/png" || media.SizeBytes != length || media.Width is < 1 or > 4096 || media.Height is < 1 or > 4096 ||
                (long)media.Width * media.Height > ShipMediaPolicy.MaximumPixels ||
                media.CropFocusX != image.CropFocusX || media.CropFocusY != image.CropFocusY || media.CropZoom != image.CropZoom ||
                receipt.ContentHash != hash || receipt.ImageVersion != ShipImageVersion.Compute(media.MediaId, hash, media.CropFocusX, media.CropFocusY, media.CropZoom)) throw InvalidImage();
            grants.Add(new(media.ShipInstanceId, media.ShipCode, media.MediaId, hash, media.CropFocusX, media.CropFocusY, media.CropZoom, receipt.ImageVersion));
        }
        current(); token.ThrowIfCancellationRequested(); return grants.ToArray();
    }

    private static LocalHangarStoreException InvalidImage() => new("hangar.image_not_allowed", "Invalid official image preparation or receipt.");
}
