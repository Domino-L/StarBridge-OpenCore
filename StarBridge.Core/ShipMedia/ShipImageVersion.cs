using System.Security.Cryptography;
using System.Text.Json;

namespace StarBridge.Core.ShipMedia;

public static class ShipImageVersion
{
    public static string Compute(string mediaId, string contentHash, double cropFocusX, double cropFocusY, double cropZoom) =>
        Convert.ToHexString(SHA256.HashData(JsonSerializer.SerializeToUtf8Bytes(new
        {
            MediaId = mediaId,
            Sha256 = contentHash,
            CropFocusX = cropFocusX,
            CropFocusY = cropFocusY,
            CropZoom = cropZoom
        }))).ToLowerInvariant();
}
