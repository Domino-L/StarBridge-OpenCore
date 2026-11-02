using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace StarBridge.OverlayRuntime.Windows;

/// <summary>Local pixel-only export. Coordinates are fractions of the original image axes.</summary>
public static class WindowsCommunityWideImage
{
    public const int MaximumBytes = 2 * 1024 * 1024;

    public static string Preview(BitmapSource image)
    {
        for (var dimension = 1024; dimension >= 64; dimension /= 2)
        {
            var scale = Math.Min(1, (double)dimension / Math.Max(image.PixelWidth, image.PixelHeight));
            var resized = Resize(image, Math.Max(1, (int)(image.PixelWidth * scale)), Math.Max(1, (int)(image.PixelHeight * scale)));
            using var stream = new MemoryStream();
            var encoder = new PngBitmapEncoder();
            encoder.Frames.Add(BitmapFrame.Create(resized));
            encoder.Save(stream);
            var data = "data:image/png;base64," + Convert.ToBase64String(stream.ToArray());
            if (data.Length <= 700000) return data;
        }
        throw new InvalidDataException();
    }

    public static string Crop(BitmapSource image, string kind, double x, double y, double width)
    {
        var (ratioWidth, ratioHeight) = kind switch
        {
            "banner" => (4, 1), "background" => (16, 9), _ => throw new InvalidDataException()
        };
        if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(width) ||
            x is < 0 or > 1 || y is < 0 or > 1 || width is < .2 or > 1)
            throw new InvalidDataException();
        var cropWidth = image.PixelWidth * width;
        var cropHeight = cropWidth * ratioHeight / ratioWidth;
        // Validate the requested rectangle before rounding to integral pixels; never clamp an invalid request.
        if (x + width > 1 + 1e-12 || y * image.PixelHeight + cropHeight > image.PixelHeight + 1e-9)
            throw new InvalidDataException();
        var units = (int)Math.Floor(Math.Min(cropWidth / ratioWidth, cropHeight / ratioHeight));
        if (units < 1) throw new InvalidDataException();
        var left = (int)Math.Floor(x * image.PixelWidth);
        var top = (int)Math.Floor(y * image.PixelHeight);
        var cropped = new CroppedBitmap(image, new Int32Rect(left, top, units * ratioWidth, units * ratioHeight));
        var outputUnits = Math.Min(units, 1920 / ratioWidth);
        var resized = Resize(cropped, outputUnits * ratioWidth, outputUnits * ratioHeight);
        // White backing removes alpha without leaking hidden RGB values or source metadata into JPEG.
        for (var quality = 88; quality >= 40; quality -= 8)
        {
            using var stream = new MemoryStream();
            var encoder = new JpegBitmapEncoder { QualityLevel = quality };
            encoder.Frames.Add(BitmapFrame.Create(resized));
            encoder.Save(stream);
            if (stream.Length <= MaximumBytes)
                return "data:image/jpeg;base64," + Convert.ToBase64String(stream.ToArray());
        }
        throw new InvalidDataException();
    }

    private static BitmapSource Resize(BitmapSource image, int width, int height)
    {
        var visual = new DrawingVisual();
        RenderOptions.SetBitmapScalingMode(visual, BitmapScalingMode.HighQuality);
        using (var drawing = visual.RenderOpen())
        {
            drawing.DrawRectangle(System.Windows.Media.Brushes.White, null, new Rect(0, 0, width, height));
            drawing.DrawImage(image, new Rect(0, 0, width, height));
        }
        var output = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32);
        output.Render(visual);
        output.Freeze();
        return output;
    }
}
