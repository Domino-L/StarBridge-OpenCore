using StarBridge.OverlayRuntime.Windows;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;

internal static class AchievementCelebrationCardTests
{
    internal static void Run()
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                // Real renderer and bundled art, without opening a window or
                // emitting sound/awards/network requests on the maintainer device.
                var scm = new AchievementCelebrationCard("zh-CN", false, false, "scm-1", 0, "星际圣诞", "Assets/Achievements/scm-holiday-christmas-512.webp");
                Require(scm.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(scm).EndsWith("星际圣诞"), "SCM holiday uses its exact display name and bundled WebP pair");
                Require(!Draw(scm, 650).SequenceEqual(Draw(scm, 1400)), "SCM artwork uses the existing full reveal");
                var untrusted = new AchievementCelebrationCard("en-US", false, true, "scm-2", 0, "Synthetic SCM", "https://blocked.invalid/image.webp");
                Require(!untrusted.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(untrusted).EndsWith("Synthetic SCM"), "No remote image loads; optional artwork preserves server display name");
                foreach (var light in new[] { false, true })
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                {
                    var card = new AchievementCelebrationCard(locale, light, false);
                    Require(card.HasArtwork, "Both formal artwork resources resolve in the Windows plug-in");
                    VerifyArtworkSampling(card);
                    var preload = Draw(card, 0);
                    var sealedCard = Draw(card, 650);
                    var earnedCard = Draw(card, 1400);
                    Require(!preload.SequenceEqual(sealedCard) && !sealedCard.SequenceEqual(earnedCard),
                        "Accepted preload/release and seal reveal have separate real render stages");
                    Require(card.LifetimeMilliseconds == 5980, "Entry 1800ms, readable hold 4s, subtler exit 180ms");
                    var reduced = new AchievementCelebrationCard(locale, light, true);
                    Require(Draw(reduced, 0).SequenceEqual(Draw(reduced, 3000)) && reduced.LifetimeMilliseconds == 4000,
                        "Reduced motion immediately shows the final readable card for four seconds");
                    foreach (var id in StarBridge.Core.Achievements.HangarAchievementPolicy.Ids)
                    {
                        var series = new AchievementCelebrationCard(locale, light, false, id, 4);
                        Require(series.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(series).EndsWith(" · IV", StringComparison.Ordinal),
                            "Every series resolves its own locked/earned images and exposes the Roman rank only in the name");
                        Require(!Draw(series, 650).SequenceEqual(Draw(series, 1400)),
                            "Each series uses the accepted locked-to-earned reveal");
                        var staticSeries = new AchievementCelebrationCard(locale, light, true, id, 4);
                        Require(Draw(staticSeries, 0).SequenceEqual(Draw(staticSeries, 3000)),
                            "Series achievements respect reduced motion");
                    }
                    if (Environment.GetEnvironmentVariable("STARBRIDGE_ACHIEVEMENT_RENDER_OUTPUT") is { Length: > 0 } output)
                    {
                        Directory.CreateDirectory(output);
                        foreach (var time in new[] { 300, 650, 900, 1400 })
                        {
                            var bitmap = Render(card, time);
                            var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                            using var file = File.Create(Path.Combine(output, $"achievement-{locale}-{(light ? "light" : "dark")}-{time}.png"));
                            encoder.Save(file);
                        }
                    }
                }
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw new InvalidOperationException("Achievement native renderer regression failed", failure);
        Console.WriteLine("PASS achievement native renderer: real artwork, three languages, two themes, reveal, hold and reduced motion");
    }
    private static RenderTargetBitmap Render(AchievementCelebrationCard card, double elapsed)
    {
        card.Advance(elapsed, 2);
        card.Measure(new(card.Width, card.Height)); card.Arrange(new Rect(0, 0, card.Width, card.Height)); card.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)card.Width, (int)card.Height, 96, 96, PixelFormats.Pbgra32);
        bitmap.Render(card); return bitmap;
    }
    private static byte[] Draw(AchievementCelebrationCard card, double elapsed)
    {
        var bitmap = Render(card, elapsed); var bytes = new byte[bitmap.PixelWidth * bitmap.PixelHeight * 4];
        bitmap.CopyPixels(bytes, bitmap.PixelWidth * 4, 0); return bytes;
    }
    private static void VerifyArtworkSampling(AchievementCelebrationCard card)
    {
        var artwork = (BitmapSource)typeof(AchievementCelebrationCard).GetField("_earned",
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic)!.GetValue(card)!;
        Require(artwork.PixelWidth >= 272 && artwork.PixelHeight >= 272, "Bundled art has enough native pixels for a 68 DIP icon at 400% scaling");
        foreach (var dpi in new[] { 96, 120, 144, 192, 288 })
        {
            card.Advance(1400, 0); card.Measure(new(card.Width, card.Height));
            card.Arrange(new Rect(0, 0, card.Width, card.Height)); card.UpdateLayout();
            var width = (int)Math.Ceiling(card.Width * dpi / 96d); var height = (int)Math.Ceiling(card.Height * dpi / 96d);
            var actual = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32); actual.Render(card);
            // Use a FrameworkElement just like the production drawing owner.
            // A DrawingVisual does not propagate the attached scaling setting
            // to this renderer, which would compare against Linear again.
            var reference = new ReferenceArtwork(artwork) { Width = card.Width, Height = card.Height };
            reference.Measure(new(card.Width, card.Height)); reference.Arrange(new Rect(0, 0, card.Width, card.Height));
            var expected = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32); expected.Render(reference);
            var a = new byte[width * height * 4]; var e = new byte[a.Length];
            actual.CopyPixels(a, width * 4, 0); expected.CopyPixels(e, width * 4, 0);
            // Ignore the fractional clip edge. The visible interior must use the
            // original pixels with high quality resampling, including fractional DPI.
            var differences = 0;
            for (var y = (int)Math.Ceiling(20 * dpi / 96d); y < (int)Math.Floor(84 * dpi / 96d); y++)
            for (var x = (int)Math.Ceiling(24 * dpi / 96d); x < (int)Math.Floor(88 * dpi / 96d); x++)
            for (var channel = 0; channel < 3; channel++)
            { var index = (y * width + x) * 4 + channel; if (Math.Abs(a[index] - e[index]) > 1) differences++; }
            Require(differences == 0, $"Achievement icon must use native high quality sampling at {dpi} DPI; {differences} channels differ");
            // Negative control follows the original window's default Linear
            // setting. It must differ, or this test cannot catch lost detail.
            RenderOptions.SetBitmapScalingMode(card, BitmapScalingMode.Unspecified);
            var legacy = new RenderTargetBitmap(width, height, dpi, dpi, PixelFormats.Pbgra32); legacy.Render(card);
            var legacyBytes = new byte[a.Length]; legacy.CopyPixels(legacyBytes, width * 4, 0);
            Require(!legacyBytes.SequenceEqual(a), "Quality comparison must distinguish original Linear sampling from the candidate");
            RenderOptions.SetBitmapScalingMode(card, BitmapScalingMode.HighQuality);
            if (Environment.GetEnvironmentVariable("STARBRIDGE_ACHIEVEMENT_RENDER_OUTPUT") is { Length: > 0 } output)
            {
                Directory.CreateDirectory(output);
                var clientCapture = Path.Combine(output, $"flutter-first-entry-{dpi}.png");
                if (dpi != 120 && File.Exists(clientCapture))
                {
                    var clientImage = new BitmapImage(new Uri(clientCapture));
                    var clientPixels = new FormatConvertedBitmap(clientImage, PixelFormats.Pbgra32, null, 0);
                    var clientBytes = new byte[clientImage.PixelWidth * clientImage.PixelHeight * 4];
                    clientPixels.CopyPixels(clientBytes, clientImage.PixelWidth * 4, 0);
                    double Difference(byte[] native)
                    {
                        var sum = 0d; var count = 0;
                        var left = (int)Math.Round(22 * dpi / 96d); var top = (int)Math.Round(18 * dpi / 96d);
                        var margin = (int)Math.Ceiling(8 * dpi / 96d);
                        for (var y = margin; y < clientImage.PixelHeight - margin; y++)
                        for (var x = margin; x < clientImage.PixelWidth - margin; x++)
                        for (var channel = 0; channel < 3; channel++)
                        { sum += Math.Abs(native[((top + y) * width + left + x) * 4 + channel] - clientBytes[(y * clientImage.PixelWidth + x) * 4 + channel]); count++; }
                        return sum / count;
                    }
                    var candidateError = Difference(a); var originalError = Difference(legacyBytes);
                    Console.WriteLine($"Artwork/client comparison at {dpi} DPI: Linear {originalError:F3}, candidate {candidateError:F3} mean channel error");
                    Require(candidateError < originalError, "Native candidate must match the same-size Flutter client more closely than the original rendering");
                }
                foreach (var (label, bitmap) in new[] { ("linear", legacy), ("high-quality", actual) })
                {
                    var encoder = new PngBitmapEncoder(); encoder.Frames.Add(BitmapFrame.Create(bitmap));
                    using var file = File.Create(Path.Combine(output, $"sampling-{dpi}-{label}.png")); encoder.Save(file);
                    var crop = new CroppedBitmap(bitmap, new Int32Rect((int)Math.Round(26 * dpi / 96d),
                        (int)Math.Round(38 * dpi / 96d), (int)Math.Round(68 * dpi / 96d), (int)Math.Round(68 * dpi / 96d)));
                    var iconEncoder = new PngBitmapEncoder(); iconEncoder.Frames.Add(BitmapFrame.Create(crop));
                    using var iconFile = File.Create(Path.Combine(output, $"icon-{dpi}-{label}.png")); iconEncoder.Save(iconFile);
                }
            }
        }
    }
    private sealed class ReferenceArtwork(BitmapSource artwork) : FrameworkElement
    {
        protected override void OnRender(DrawingContext drawing)
        {
            RenderOptions.SetBitmapScalingMode(this, BitmapScalingMode.HighQuality);
            drawing.DrawImage(artwork, new Rect(22, 18, 68, 68));
        }
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
