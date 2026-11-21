using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.OverlayRuntime.Windows;

internal static class AchievementCelebrationOffscreenProbe
{
    private const double Scale = 1.25, Dpi = 96 * Scale;

    internal static void Run(string output)
    {
        Exception? failure = null;
        var thread = new Thread(() =>
        {
            try
            {
                Directory.CreateDirectory(output);
                Capture(output);
                MeasureAnimation();
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA);
        thread.Start();
        thread.Join();
        if (failure is not null) throw new InvalidOperationException("G1 offscreen capture failed", failure);
    }

    private static AchievementCelebrationCard Own(string id, string? tier = null, int? ratio = null, bool light = false, bool reduced = false) =>
        new("zh-CN", light, reduced, id, rarityTier: tier, rarityBasisPoints: ratio);

    private static AchievementCelebrationCard Scm(string name, string? art, string? tier) =>
        new("zh-CN", false, false, "scm-1", displayName: name,
            localImagePath: art is null ? null : $"Assets/Achievements/scm-{art}-512.webp", rarityTier: tier);

    private static void Capture(string output)
    {
        void Save(string label, AchievementCelebrationCard card, double time, bool artwork = true)
        {
            if (card.HasArtwork != artwork) throw new InvalidOperationException("Unexpected artwork state: " + label);
            card.PrepareGlass(Scale);
            var bitmap = Render(card, time);
            var png = new PngBitmapEncoder();
            png.Frames.Add(BitmapFrame.Create(bitmap));
            using var file = File.Create(Path.Combine(output, label + ".png"));
            png.Save(file);
        }

        Save("01-dark-ordinary", Own("first-entry"), 1400);
        Save("02-dark-rare", Own("journey-lorville", "rare", 420), 1400);
        Save("03-dark-ultra-rare", Own("journey-orison", "veryRare", 4), 1400);
        Save("04-dark-scm-holiday-common", Scm("星际圣诞", "holiday-christmas", "COMMON"), 1400);
        Save("05-dark-scm-holiday-epic", Scm("粽情端午", "holiday-dragon-boat", "EPIC"), 1400);
        Save("06-dark-scm-daily", Scm("中登", "daily-account-regular", "RARE"), 1400);
        Save("07-dark-no-artwork", Scm("星海探索", null, "COMMON"), 1400, artwork: false);
        Save("08-dark-summary", new("zh-CN", false, false, "scm-summary", summaryCount: 8), 1400, artwork: false);
        Save("09-light-rare", Own("journey-lorville", "rare", 420, light: true), 1400);
        Save("10-reduced-first-frame", Own("journey-lorville", "rare", 420, reduced: true), 0);
        var animation = Own("journey-orison", "veryRare", 4);
        Save("11-entry-sliding-100ms", animation, 100);
        Save("12-entry-half-sweep-440ms", animation, 440);
        Save("13-entry-settled-1100ms", animation, 1100);
        Console.WriteLine("PASS G1 offscreen capture: 13 PNGs");
    }

    private static void MeasureAnimation()
    {
        var frameMs = new List<double>();
        var buildMs = new List<double>();
        for (var run = 0; run < 7; run++)
        {
            var card = Own("journey-orison", "veryRare", 4);
            var started = Stopwatch.GetTimestamp();
            card.PrepareGlass(Scale);
            if (run > 0) buildMs.Add(Stopwatch.GetElapsedTime(started).TotalMilliseconds);
            var row = new byte[(int)(card.Width * Scale) * 4];
            void Measure(double time)
            {
                var start = Stopwatch.GetTimestamp();
                var bitmap = Render(card, time);
                bitmap.CopyPixels(new Int32Rect(0, bitmap.PixelHeight - 1, bitmap.PixelWidth, 1), row, row.Length, 0);
                if (run > 0) frameMs.Add(Stopwatch.GetElapsedTime(start).TotalMilliseconds);
            }
            const double frame = 1000d / 60;
            for (var elapsed = 0d; elapsed < card.EntryMilliseconds; elapsed += frame) Measure(elapsed);
            Measure(card.EntryMilliseconds);
            var exitStart = card.EntryMilliseconds + AchievementCelebrationCard.HoldMilliseconds;
            for (var elapsed = frame; elapsed < AchievementCelebrationCard.ExitMilliseconds; elapsed += frame)
                Measure(exitStart + elapsed);
            Measure(card.LifetimeMilliseconds);
        }
        Print("frame", frameMs);
        Print("cache", buildMs);
    }

    private static void Print(string label, List<double> samples)
    {
        samples.Sort();
        var mid = (samples[(samples.Count - 1) / 2] + samples[samples.Count / 2]) / 2;
        var p95 = samples[(int)Math.Ceiling(samples.Count * .95) - 1];
        Console.WriteLine(string.Create(CultureInfo.InvariantCulture,
            $"G1 timing {label} (ms): n={samples.Count} mean={samples.Average():F3} median={mid:F3} p95={p95:F3} max={samples[^1]:F3}"));
    }

    private static RenderTargetBitmap Render(AchievementCelebrationCard card, double elapsed)
    {
        card.Advance(elapsed, 0);
        card.Measure(new(card.Width, card.Height));
        card.Arrange(new(0, 0, card.Width, card.Height));
        card.UpdateLayout();
        var bitmap = new RenderTargetBitmap((int)(card.Width * Scale), (int)(card.Height * Scale), Dpi, Dpi, PixelFormats.Pbgra32);
        bitmap.Render(card);
        return bitmap;
    }
}
