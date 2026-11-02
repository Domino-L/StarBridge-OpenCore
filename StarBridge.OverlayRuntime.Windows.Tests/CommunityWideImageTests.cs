using System.IO;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.OverlayRuntime.Windows;

internal static class CommunityWideImageTests
{
    internal static void Run()
    {
        var random = new Random(17);
        BitmapSource Image(int width, int height)
        {
            var bytes = new byte[width * height * 4];
            random.NextBytes(bytes);
            for (var i = 3; i < bytes.Length; i += 4) bytes[i] = 255;
            var image = BitmapSource.Create(width, height, 96, 96, PixelFormats.Bgra32, null, bytes, width * 4);
            image.Freeze();
            return image;
        }
        void Check(bool value, string message) { if (!value) throw new Exception(message); }
        var large = Image(3840, 2160);
        foreach (var (kind, height) in new[] { ("banner", 480), ("background", 1080) })
        {
            foreach (var (source, expectedWidth) in new[] { (large, 1920), (Image(640, 360), 640) })
            {
                var data = WindowsCommunityWideImage.Crop(source, kind, 0, 0, 1);
                Check(data.StartsWith("data:image/jpeg;base64,"), "JPEG prefix");
                var bytes = Convert.FromBase64String(data[23..]);
                Check(bytes.Length <= 2 * 1024 * 1024, "JPEG byte budget");
                using var stream = new MemoryStream(bytes);
                var decoder = new JpegBitmapDecoder(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad);
                var frame = decoder.Frames.Single();
                Check(frame.PixelWidth == expectedWidth && frame.PixelHeight == expectedWidth * height / 1920, "exact ratio and no upscale");
            }
        }
        var preview = WindowsCommunityWideImage.Preview(large);
        Check(preview.Length <= 700000 && preview.StartsWith("data:image/png;base64,"), "PNG preview cap");
        using (var stream = new MemoryStream(Convert.FromBase64String(preview[22..])))
        {
            var frame = new PngBitmapDecoder(stream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
            Check(frame.PixelWidth * 9 == frame.PixelHeight * 16, "preview preserves source aspect");
        }
        foreach (var (kind, x, y, width) in new[] {
            ("banner", .9, 0.0, .2), ("background", 0.0, .01, 1.0),
            ("banner", 0.0, 0.0, .199), ("invalid", 0.0, 0.0, 1.0),
            ("banner", double.NaN, 0.0, 1.0), ("banner", 0.0, double.PositiveInfinity, 1.0),
            ("banner", -.01, 0.0, 1.0) })
        {
            try { WindowsCommunityWideImage.Crop(large, kind, x, y, width); throw new Exception("Invalid rectangle accepted"); }
            catch (InvalidDataException) { }
        }
        // Valid crop at the exact right edge and small odd dimensions.
        var edge = WindowsCommunityWideImage.Crop(large, "background", .8, .8, .2);
        Check(edge.Length > 23, "exact edge crop accepted");
        var odd = WindowsCommunityWideImage.Crop(Image(641, 361), "background", 0, 0, 1);
        using var oddStream = new MemoryStream(Convert.FromBase64String(odd[23..]));
        var oddFrame = new JpegBitmapDecoder(oddStream, BitmapCreateOptions.None, BitmapCacheOption.OnLoad).Frames[0];
        Check(oddFrame.PixelWidth == 640 && oddFrame.PixelHeight == 360, "round down preserves exact ratio");
        Console.WriteLine("PASS wide encoder: JPEG budget, 4:1/16:9, 1920 cap, no upscale, previews, bounds");
    }
}
