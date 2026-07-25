namespace StarBridge.Desktop;

using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;

public static class FleetProfilePayloadBuilder
{
    public static string BuildTagSummary(
        IEnumerable<string> selectedIds,
        Func<string, string?> resolveName,
        int maxTags)
    {
        var names = selectedIds
            .Where(id => !string.IsNullOrWhiteSpace(id))
            .Select(id => resolveName(id.Trim()))
            .Where(name => !string.IsNullOrWhiteSpace(name))
            .Select(name => name!.Trim())
            .Distinct(StringComparer.OrdinalIgnoreCase)
            .Take(Math.Max(0, maxTags))
            .ToArray();

        return names.Length == 0 ? "未指定" : string.Join(" / ", names);
    }

    public static byte[] EncodeSquarePngForSync(
        BitmapSource source,
        int maxBytes,
        int maxDimension)
    {
        ArgumentNullException.ThrowIfNull(source);
        if (maxBytes <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxBytes));
        }

        if (maxDimension <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxDimension));
        }

        var targetDimension = Math.Min(maxDimension, Math.Max(source.PixelWidth, source.PixelHeight));
        while (targetDimension >= 64)
        {
            var prepared = ResizeToFit(source, targetDimension);
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(prepared));
            using var stream = new MemoryStream();
            encoder.Save(stream);
            if (stream.Length <= maxBytes)
            {
                return stream.ToArray();
            }

            targetDimension = (int)Math.Floor(targetDimension * 0.82);
        }

        throw new InvalidOperationException("图片内容过于复杂，无法压缩到同步大小限制内。");
    }

    private static BitmapSource ResizeToFit(BitmapSource source, int maxDimension)
    {
        var scale = Math.Min(
            1d,
            Math.Min(
                maxDimension / (double)Math.Max(1, source.PixelWidth),
                maxDimension / (double)Math.Max(1, source.PixelHeight)));
        if (scale >= 0.9999d)
        {
            return source;
        }

        var resized = new TransformedBitmap(source, new ScaleTransform(scale, scale));
        resized.Freeze();
        return resized;
    }
}
