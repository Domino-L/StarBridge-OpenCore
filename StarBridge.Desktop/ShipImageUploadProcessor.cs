using SkiaSharp;
using StarBridge.Core.ShipMedia;
using System.IO;

namespace StarBridge.Desktop;

internal sealed record PreparedShipImageUpload(
    byte[] EncodedBytes,
    int SourceWidth,
    int SourceHeight,
    int OutputWidth,
    int OutputHeight,
    string SourceFormat,
    string OutputFormat);

internal static class ShipImageUploadProcessor
{
    private const int MaximumSourceBytes = 64 * 1024 * 1024;
    private const long MaximumSourcePixels = 80_000_000;
    private static readonly int[] JpegQualityLevels = [90, 84, 78, 72, 66, 60, 54];
    private static readonly double[] DimensionSteps = [1d, 0.88d, 0.76d, 0.64d, 0.52d];
    private static readonly SKColor JpegBackground = new(5, 18, 27);

    public static PreparedShipImageUpload Prepare(
        string path,
        int quarterTurns,
        int maxWidth,
        int maxHeight)
    {
        var file = new FileInfo(path);
        if (!file.Exists)
        {
            throw new InvalidDataException("找不到这张图片，请重新选择。");
        }

        if (file.Length <= 0 || file.Length > MaximumSourceBytes)
        {
            throw new InvalidDataException("图片文件过大或内容为空，请选择小于 64 MB 的图片。");
        }

        return Prepare(File.ReadAllBytes(path), file.Name, quarterTurns, maxWidth, maxHeight);
    }

    public static PreparedShipImageUpload Prepare(
        byte[] sourceBytes,
        string fileName,
        int quarterTurns,
        int maxWidth,
        int maxHeight)
    {
        ArgumentNullException.ThrowIfNull(sourceBytes);
        if (sourceBytes.Length <= 0 || sourceBytes.Length > MaximumSourceBytes)
        {
            throw new InvalidDataException("图片文件过大或内容为空，请选择小于 64 MB 的图片。");
        }

        if (maxWidth <= 0 || maxHeight <= 0)
        {
            throw new ArgumentOutOfRangeException(nameof(maxWidth));
        }

        using var data = SKData.CreateCopy(sourceBytes);
        using var codec = SKCodec.Create(data);
        if (codec is null || codec.Info.Width <= 0 || codec.Info.Height <= 0)
        {
            throw new InvalidDataException("暂时无法读取这张图片。请尝试导出为 PNG、JPG 或 WebP 后重新选择。");
        }

        var sourceWidth = codec.Info.Width;
        var sourceHeight = codec.Info.Height;
        if ((long)sourceWidth * sourceHeight > MaximumSourcePixels)
        {
            throw new InvalidDataException("图片尺寸过大，请先缩小到 8000 万像素以内再上传。");
        }

        using var source = SKBitmap.Decode(data);
        if (source is null)
        {
            throw new InvalidDataException("图片内容无法完整读取。请尝试导出为 PNG、JPG 或 WebP 后重新选择。");
        }

        var normalizedTurns = ((quarterTurns % 4) + 4) % 4;
        using var oriented = CreateOrientedBitmap(source, normalizedTurns);
        var fit = CalculateFit(oriented.Width, oriented.Height, maxWidth, maxHeight);
        var sourceFormat = ResolveSourceFormat(fileName);

        foreach (var step in DimensionSteps)
        {
            var width = Math.Max(1, (int)Math.Round(fit.Width * step));
            var height = Math.Max(1, (int)Math.Round(fit.Height * step));
            using var resized = ResizeBitmap(oriented, width, height, transparent: true);

            if (step == 1d)
            {
                var pngBytes = Encode(resized, SKEncodedImageFormat.Png, 100);
                if (pngBytes.Length <= ShipMediaPolicy.MaximumImageBytes)
                {
                    return new PreparedShipImageUpload(
                        pngBytes,
                        sourceWidth,
                        sourceHeight,
                        width,
                        height,
                        sourceFormat,
                        "PNG");
                }
            }

            using var opaque = CompositeForJpeg(resized);
            foreach (var quality in JpegQualityLevels)
            {
                var jpegBytes = Encode(opaque, SKEncodedImageFormat.Jpeg, quality);
                if (jpegBytes.Length <= ShipMediaPolicy.MaximumImageBytes)
                {
                    return new PreparedShipImageUpload(
                        jpegBytes,
                        sourceWidth,
                        sourceHeight,
                        width,
                        height,
                        sourceFormat,
                        "JPG");
                }
            }
        }

        throw new InvalidDataException("图片内容过于复杂，自动优化后仍无法上传。请先缩小图片后重试。");
    }

    private static SKBitmap CreateOrientedBitmap(SKBitmap source, int quarterTurns)
    {
        var swapSides = quarterTurns is 1 or 3;
        var output = new SKBitmap(
            swapSides ? source.Height : source.Width,
            swapSides ? source.Width : source.Height,
            SKColorType.Rgba8888,
            SKAlphaType.Premul);
        using var canvas = new SKCanvas(output);
        canvas.Clear(SKColors.Transparent);
        switch (quarterTurns)
        {
            case 1:
                canvas.Translate(output.Width, 0);
                canvas.RotateDegrees(90);
                break;
            case 2:
                canvas.Translate(output.Width, output.Height);
                canvas.RotateDegrees(180);
                break;
            case 3:
                canvas.Translate(0, output.Height);
                canvas.RotateDegrees(270);
                break;
        }

        canvas.DrawBitmap(source, 0, 0);
        canvas.Flush();
        return output;
    }

    private static SKBitmap ResizeBitmap(SKBitmap source, int width, int height, bool transparent)
    {
        var output = new SKBitmap(width, height, SKColorType.Rgba8888, SKAlphaType.Premul);
        using var canvas = new SKCanvas(output);
        canvas.Clear(transparent ? SKColors.Transparent : JpegBackground);
        using var paint = new SKPaint { IsAntialias = true };
        canvas.DrawBitmap(source, new SKRect(0, 0, width, height), paint);
        canvas.Flush();
        return output;
    }

    private static SKBitmap CompositeForJpeg(SKBitmap source) =>
        ResizeBitmap(source, source.Width, source.Height, transparent: false);

    private static byte[] Encode(SKBitmap bitmap, SKEncodedImageFormat format, int quality)
    {
        using var image = SKImage.FromBitmap(bitmap);
        using var encoded = image.Encode(format, quality) ??
                            throw new InvalidDataException("图片暂时无法完成处理，请重新选择。");
        return encoded.ToArray();
    }

    private static (int Width, int Height) CalculateFit(int width, int height, int maxWidth, int maxHeight)
    {
        var scale = Math.Min(1d, Math.Min((double)maxWidth / width, (double)maxHeight / height));
        return (
            Math.Max(1, (int)Math.Round(width * scale)),
            Math.Max(1, (int)Math.Round(height * scale)));
    }

    private static string ResolveSourceFormat(string fileName)
    {
        var extension = Path.GetExtension(fileName).TrimStart('.').ToUpperInvariant();
        return string.IsNullOrWhiteSpace(extension) ? "图片" : extension;
    }
}
