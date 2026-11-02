using System.Buffers.Binary;

namespace StarBridge.Communities;

/// <summary>Validation for new banner/background uploads; historical reads keep their existing formats.</summary>
internal static class CommunityImageUpload
{
    internal const int MaximumBytes = 2 * 1024 * 1024;
    internal const int MaximumTextLength = (MaximumBytes + 2) / 3 * 4 + 32;
    private const int MaximumDimension = 4096;
    private const long MaximumPixels = 16_777_216;
    private const int MaximumJpegMarkers = 4096;

    internal static string? Normalize(string? source)
    {
        if (string.IsNullOrEmpty(source) || source.Length > MaximumTextLength) return null;
        var comma = source.IndexOf(',');
        var header = comma < 0 ? "" : source[..comma];
        if (header is not ("data:image/png;base64" or "data:image/jpeg;base64")) return null;
        byte[] bytes;
        try { bytes = Convert.FromBase64String(source[(comma + 1)..]); }
        catch (FormatException) { return null; }
        if (bytes.Length is 0 or > MaximumBytes) return null;
        if (!(header == "data:image/png;base64" ? HasPngHeader(bytes) : HasJpegHeader(bytes))) return null;
        return header + "," + Convert.ToBase64String(bytes);
    }

    // Header validation only: compressed pixels, later chunks/scans and animation
    // are not decoded or inspected. Historical reads must not use this upload gate.
    private static bool HasPngHeader(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 33 || !bytes[..8].SequenceEqual(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 })) return false;
        if (BinaryPrimitives.ReadUInt32BigEndian(bytes[8..]) != 13 ||
            !bytes.Slice(12, 4).SequenceEqual("IHDR"u8)) return false;
        var validDepth = bytes[25] switch
        {
            0 => bytes[24] is 1 or 2 or 4 or 8 or 16,
            2 or 4 or 6 => bytes[24] is 8 or 16,
            3 => bytes[24] is 1 or 2 or 4 or 8,
            _ => false
        };
        if (!validDepth || bytes[26] != 0 || bytes[27] != 0 || bytes[28] > 1) return false;
        var crc = uint.MaxValue;
        foreach (var value in bytes.Slice(12, 17))
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++)
                crc = (crc >> 1) ^ ((crc & 1) == 0 ? 0 : 0xEDB88320u);
        }
        return ~crc == BinaryPrimitives.ReadUInt32BigEndian(bytes[29..]) &&
            HasValidDimensions(BinaryPrimitives.ReadUInt32BigEndian(bytes[16..]),
                BinaryPrimitives.ReadUInt32BigEndian(bytes[20..]));
    }

    private static bool HasJpegHeader(ReadOnlySpan<byte> bytes)
    {
        if (bytes.Length < 2 || bytes[0] != 0xFF || bytes[1] != 0xD8) return false;
        var offset = 2;
        var foundFrame = false;
        for (var count = 0; count < MaximumJpegMarkers && offset < bytes.Length; count++)
        {
            if (bytes[offset++] != 0xFF) return false;
            // Marker fill bytes consume input; even a file of FF bytes is bounded by MaximumBytes.
            while (offset < bytes.Length && bytes[offset] == 0xFF) offset++;
            if (offset == bytes.Length) return false;
            var marker = bytes[offset++];
            // No byte stuffing, second SOI, end-of-image or scan data before a supported SOF.
            if (marker is 0x00 or 0xD8 or 0xD9) return false;
            if (marker is 0x01 or >= 0xD0 and <= 0xD7) continue; // standalone markers
            if (bytes.Length - offset < 2) return false;
            var length = BinaryPrimitives.ReadUInt16BigEndian(bytes[offset..]);
            if (length < 2 || length > bytes.Length - offset) return false;
            if (marker == 0xDA)
                return foundFrame && length >= 6 && bytes[offset + 2] > 0 && length == 6 + 2 * bytes[offset + 2];
            // C4 (DHT), C8 (JPG), CC (DAC) are not SOF markers.
            if (marker is >= 0xC0 and <= 0xCF && marker is not (0xC4 or 0xC8 or 0xCC))
            {
                if (foundFrame || marker is not (0xC0 or 0xC1 or 0xC2) || length < 8) return false;
                var components = bytes[offset + 7];
                if (components == 0 || length != 8 + 3 * components) return false;
                if (!HasValidDimensions(BinaryPrimitives.ReadUInt16BigEndian(bytes[(offset + 5)..]),
                    BinaryPrimitives.ReadUInt16BigEndian(bytes[(offset + 3)..]))) return false;
                foundFrame = true;
            }
            offset += length;
        }
        return false;
    }

    private static bool HasValidDimensions(uint width, uint height) =>
        width is > 0 and <= MaximumDimension && height is > 0 and <= MaximumDimension &&
        (long)width * height <= MaximumPixels;
}
