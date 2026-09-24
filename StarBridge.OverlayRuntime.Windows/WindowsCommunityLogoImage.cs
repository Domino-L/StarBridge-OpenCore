using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

namespace StarBridge.OverlayRuntime.Windows;

/// <summary>Bounded image decoding and the existing WPF PNG export policy, without a window.</summary>
public static class WindowsCommunityLogoImage
{
    public static BitmapSource Load(Stream input)
    {
        if (input.Length <= 0 || input.Length > 32 * 1024 * 1024) throw new InvalidDataException();
        var decoder = BitmapDecoder.Create(input, BitmapCreateOptions.PreservePixelFormat, BitmapCacheOption.OnDemand);
        if (decoder is not (PngBitmapDecoder or JpegBitmapDecoder or BmpBitmapDecoder) || decoder.Frames.Count != 1)
            throw new InvalidDataException();
        var frame = decoder.Frames[0];
        if (frame.PixelWidth <= 0 || frame.PixelHeight <= 0 || (long)frame.PixelWidth * frame.PixelHeight > 16 * 1024 * 1024)
            throw new InvalidDataException();
        var original = new FormatConvertedBitmap(frame, PixelFormats.Bgra32, null, 0);
        var stride = checked(original.PixelWidth * 4);
        var pixels = new byte[checked(stride * original.PixelHeight)];
        original.CopyPixels(pixels, stride, 0);
        // Detach pixels and discard metadata before closing the selected user file.
        var retained = BitmapSource.Create(original.PixelWidth, original.PixelHeight, 96, 96, PixelFormats.Bgra32, null, pixels, stride);
        retained.Freeze();
        return retained;
    }

    public static string Preview(BitmapSource image) => Png(StarBridge.Desktop.FleetProfilePayloadBuilder.EncodeSquarePngForSync(image, 512 * 1024, 1024));

    public static string Crop(BitmapSource image, double x, double y, double size, int maximumBytes = 512 * 1024, int dimension = 512)
    {
        if (!double.IsFinite(x) || !double.IsFinite(y) || !double.IsFinite(size) ||
            x < 0 || y < 0 || size is < .2 or > 1) throw new InvalidDataException();
        var side = Math.Max(1, (int)Math.Round(Math.Min(image.PixelWidth, image.PixelHeight) * size));
        if (x * image.PixelWidth + side > image.PixelWidth + 1 || y * image.PixelHeight + side > image.PixelHeight + 1)
            throw new InvalidDataException();
        var left = Math.Clamp((int)Math.Round(x * image.PixelWidth), 0, image.PixelWidth - side);
        var top = Math.Clamp((int)Math.Round(y * image.PixelHeight), 0, image.PixelHeight - side);
        var cropped = new CroppedBitmap(image, new Int32Rect(left, top, side, side));
        cropped.Freeze();
        return Png(StarBridge.Desktop.FleetProfilePayloadBuilder.EncodeSquarePngForSync(cropped, maximumBytes, dimension));
    }
    private static string Png(byte[] bytes) => "data:image/png;base64," + Convert.ToBase64String(bytes);
}
