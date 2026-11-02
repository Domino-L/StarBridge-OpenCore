using System.Buffers.Binary;
using System.IO.Compression;

internal static class CommunityImageFixtures
{
    // Generated solid-colour images, without external assets or an image library.
    internal static byte[] Png(int width = 2, int height = 2)
    {
        using var result = new MemoryStream();
        result.Write(new byte[] { 137, 80, 78, 71, 13, 10, 26, 10 });
        var header = new byte[13];
        BinaryPrimitives.WriteUInt32BigEndian(header, (uint)width);
        BinaryPrimitives.WriteUInt32BigEndian(header.AsSpan(4), (uint)height);
        header[8] = 8; // 8-bit grayscale
        Chunk(result, "IHDR"u8, header);
        using var pixels = new MemoryStream();
        using (var zlib = new ZLibStream(pixels, CompressionLevel.SmallestSize, leaveOpen: true))
        {
            var row = new byte[width + 1]; // filter byte followed by black pixels
            for (var y = 0; y < height; y++) zlib.Write(row);
        }
        Chunk(result, "IDAT"u8, pixels.ToArray());
        Chunk(result, "IEND"u8, []);
        return result.ToArray();
    }

    private static void Chunk(Stream stream, ReadOnlySpan<byte> type, ReadOnlySpan<byte> content)
    {
        Span<byte> number = stackalloc byte[4];
        BinaryPrimitives.WriteUInt32BigEndian(number, (uint)content.Length);
        stream.Write(number);
        stream.Write(type);
        stream.Write(content);
        uint crc = 0xFFFFFFFF;
        foreach (var value in type.ToArray().Concat(content.ToArray()))
        {
            crc ^= value;
            for (var bit = 0; bit < 8; bit++) crc = (crc >> 1) ^ (0xEDB88320u & (uint)-(int)(crc & 1));
        }
        BinaryPrimitives.WriteUInt32BigEndian(number, ~crc);
        stream.Write(number);
    }

    // Minimal 2x2 grayscale JPEG: unit quantization, DC=0, AC end-of-block.
    internal static byte[] Jpeg()
    {
        using var result = new MemoryStream();
        result.Write(new byte[] { 0xFF, 0xD8 });
        Segment(result, 0xDB, new byte[] { 0 }.Concat(Enumerable.Repeat((byte)1, 64)).ToArray());
        Segment(result, 0xC0, new byte[] { 8, 0, 2, 0, 2, 1, 1, 0x11, 0 });
        var table = new byte[18];
        table[1] = 1;
        Segment(result, 0xC4, table);
        table[0] = 0x10;
        Segment(result, 0xC4, table);
        Segment(result, 0xDA, new byte[] { 1, 1, 0, 0, 63, 0 });
        result.Write(new byte[] { 0x3F, 0xFF, 0xD9 });
        return result.ToArray();
    }

    private static void Segment(Stream stream, byte marker, byte[] content)
    {
        stream.Write(new byte[] { 0xFF, marker, (byte)((content.Length + 2) >> 8), (byte)(content.Length + 2) });
        stream.Write(content);
    }

    internal static byte[] JpegHeader(int width = 2, int height = 2, byte marker = 0xC0) =>
        [0xFF, 0xD8, 0xFF, marker, 0, 11, 8, (byte)(height >> 8), (byte)height,
            (byte)(width >> 8), (byte)width, 1, 1, 0x11, 0,
            0xFF, 0xDA, 0, 8, 1, 1, 0, 0, 63, 0];

    internal static byte[] PngHeader(byte depth, byte color, byte compression = 0, byte filter = 0, byte interlace = 0)
    {
        using var result = new MemoryStream();
        result.Write(Png()[..8]);
        var header = Png()[16..29];
        header[8] = depth; header[9] = color; header[10] = compression;
        header[11] = filter; header[12] = interlace;
        Chunk(result, "IHDR"u8, header);
        return result.ToArray();
    }
    internal static string Data(byte[] bytes, string mime = "png") => "data:image/" + mime + ";base64," + Convert.ToBase64String(bytes);
    internal static string Boundary(int extra = 0)
    {
        var bytes = new byte[2 * 1024 * 1024 + extra];
        Png().CopyTo(bytes, 0);
        return Data(bytes);
    }
    internal static IEnumerable<string> Invalid()
    {
        yield return Boundary(1);
        yield return Data(Png(), "jpeg");
        yield return Data(Jpeg(), "png");
        yield return Data(Png(4097, 1));
        yield return Data(Png(1, 4097));
        yield return Data(Png()[..24]);
        yield return "data:image/png;base64,AQ==";
        yield return "data:image/gif;base64,R0lGODlh";
        yield return "data:image/png;base64,%%%";
        yield return "";
        foreach (var invalid in InvalidHeaders()) yield return invalid.Image;
    }

    internal static IEnumerable<(string Name, string Image)> InvalidHeaders()
    {
        var png = Png();
        for (var length = 0; length < 33; length++)
            yield return ($"PNG truncated at {length}", Data(png[..length]));
        foreach (var offset in new[] { 0, 8, 11, 12, 16, 29, 32 })
        {
            var corrupt = (byte[])png.Clone();
            corrupt[offset] ^= 1;
            yield return ($"PNG corrupt signature/length/type/IHDR CRC at {offset}", Data(corrupt));
        }
        yield return ("PNG zero width", Data(Png(0, 1)));
        yield return ("PNG zero height", Data(Png(1, 0)));
        foreach (var header in new[] { PngHeader(4, 2), PngHeader(16, 3), PngHeader(1, 4),
            PngHeader(4, 6), PngHeader(8, 1), PngHeader(8, 5), PngHeader(0, 0),
            PngHeader(8, 0, compression: 1), PngHeader(8, 0, filter: 1), PngHeader(8, 0, interlace: 2) })
            yield return ("PNG illegal IHDR with correct CRC", Data(header));
        var frame = JpegHeader()[2..15];
        foreach (var marker in new byte[] { 0xC0, 0xC1, 0xC2, 0xC3, 0xC5, 0xC9, 0xCF })
        {
            var second = (byte[])frame.Clone(); second[1] = marker;
            yield return ("JPEG duplicate/conflicting/unsupported SOF after first", Data(
                JpegHeader()[..15].Concat(second).Concat(JpegHeader()[15..]).ToArray(), "jpeg"));
            yield return ("JPEG unsupported SOF before supported SOF", Data(
                new byte[] { 0xFF, 0xD8 }.Concat(second).Concat(JpegHeader()[2..]).ToArray(), "jpeg"));
        }
        yield return ("JPEG SOF without SOS", Data(JpegHeader()[..15], "jpeg"));
        yield return ("JPEG no SOF", Data([0xFF, 0xD8, 0xFF, 0xD9], "jpeg"));
        yield return ("JPEG APP segment past EOF", Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 16, 1], "jpeg"));
        yield return ("JPEG length below two", Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 1], "jpeg"));
        yield return ("JPEG incomplete length", Data([0xFF, 0xD8, 0xFF, 0xE0, 0], "jpeg"));
        yield return ("JPEG truncated SOF", Data(JpegHeader()[..^1], "jpeg"));
        yield return ("JPEG unsupported SOF", Data(JpegHeader(marker: 0xC3), "jpeg"));
        yield return ("JPEG zero width", Data(JpegHeader(0, 1), "jpeg"));
        yield return ("JPEG zero height", Data(JpegHeader(1, 0), "jpeg"));
        yield return ("JPEG wide", Data(JpegHeader(4097, 1), "jpeg"));
        yield return ("JPEG tall", Data(JpegHeader(1, 4097), "jpeg"));
        yield return ("JPEG scan before SOF", Data(new byte[] { 0xFF, 0xD8, 0xFF, 0xDA }.Concat(JpegHeader()[2..]).ToArray(), "jpeg"));
        var tooMany = new byte[] { 0xFF, 0xD8 }.Concat(Enumerable.Range(0, 4096).SelectMany(_ => new byte[] { 0xFF, 1 }));
        yield return ("JPEG marker budget", Data(tooMany.Concat(JpegHeader()[2..]).ToArray(), "jpeg"));
        yield return ("JPEG fill without marker", Data([0xFF, 0xD8, 0xFF, 0xFF], "jpeg"));
        foreach (var (mime, bytes) in new[] { ("bmp", new byte[] { 66, 77, 0, 0 }),
            ("gif", "GIF89a"u8.ToArray()), ("webp", "RIFF0000WEBP"u8.ToArray()) })
        {
            yield return ($"{mime} upload", Data(bytes, mime));
            yield return ($"{mime} disguised as PNG", Data(bytes));
            yield return ($"{mime} disguised as JPEG", Data(bytes, "jpeg"));
        }
    }
}
