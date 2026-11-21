using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Achievements;
using StarBridge.OverlayRuntime.Windows;

internal static class JourneyAchievementCelebrationTests
{
    internal static void Run()
    {
        Exception? failure = null;
        var thread = new Thread(() => {
            try
            {
                var names = new Dictionary<string, string[]> {
                    ["journey-lorville"] = ["罗威尔黄昏", "羅威爾黃昏", "Lorville Dusk"],
                    ["journey-area18"] = ["霓虹十八区", "霓虹十八區", "Neon Area18"],
                    ["journey-orison"] = ["云上奥里森", "雲上奧里森", "Orison Above the Clouds"],
                    ["journey-new-babbage"] = ["雪落新巴贝奇", "雪落新巴貝奇", "Snowfall over New Babbage"],
                    ["journey-stanton"] = ["巡礼斯坦顿", "巡禮斯坦頓", "Stanton Pilgrimage"],
                    ["journey-levski"] = ["岩中列夫斯基", "岩中列夫斯基", "Levski in the Rock"],
                    ["journey-pyro-majors"] = ["初探派罗", "初探派羅", "First Steps in Pyro"],
                    ["journey-pyro-all"] = ["火海行者", "火海行者", "Walker of the Fire Sea"],
                    ["journey-grimhex"] = ["法外六角湾", "法外六角灣", "Lawless Grim HEX"]
                };
                Require(names.Keys.SequenceEqual(JourneyAchievementPolicy.AwardIds), "visible catalog order");
                var locales = new[] { "zh-CN", "zh-TW", "en-US" };
                foreach (var (id, labels) in names)
                foreach (var light in new[] { false, true })
                for (var locale = 0; locale < locales.Length; locale++)
                {
                    var card = new AchievementCelebrationCard(locales[locale], light, false, id);
                    Require(card.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(card).EndsWith(labels[locale]),
                        "exact localized name and bundled PNG pair: " + id);
                    Require(!Draw(card, 450).SequenceEqual(Draw(card, 1400)), "locked to earned reveal: " + id);
                    RequireFits(card, id + " " + locales[locale]);
                    Require(new AchievementCelebrationCard(locales[locale], light, false, id).Memory.Length > 0, "journey cards carry their existing line: " + id);
                    if (id == JourneyAchievementPolicy.GrimhexId)
                        Require(card.Memory == new[] { "环中暗礁，自成一港", "環中暗礁，自成一港", "A hidden reef in the ring, a harbour of its own" }[locale], "exact Grim HEX memory");
                }
                // 11-05 paired art (seven), 11-07 Grim HEX and Open for Business: each carries its own earned and locked PNGs.
                foreach (var id in new[] { "journey-levski", "journey-pyro-majors", "journey-pyro-all", "journey-grimhex",
                    "contract-tsg-lead", "contract-tsg-complete", "contract-tsg-swift", "contract-tsg-deathless", "contract-first" })
                {
                    foreach (var state in new[] { "earned", "locked" })
                    {
                        BitmapImage? own = null;
                        try { own = new BitmapImage(new Uri($"pack://application:,,,/StarBridge.OverlayRuntime.Windows;component/Assets/Achievements/{id}-{state}.png")); }
                        catch (System.IO.IOException) { }
                        Require(own is { PixelWidth: 512, PixelHeight: 512 }, $"own {state} artwork bundled: " + id);
                    }
                    Require(new AchievementCelebrationCard("zh-CN", false, false, id).HasArtwork, "paired artwork: " + id);
                }
                foreach (var locale in locales)
                {
                    foreach (var id in HangarAchievementPolicy.Ids)
                        RequireFits(new AchievementCelebrationCard(locale, false, false, id, 4), id + " " + locale);
                    RequireFits(new AchievementCelebrationCard(locale, false, false), "first entry " + locale);
                    var scm = new AchievementCelebrationCard(locale, false, false, "scm-1", 0, "星际圣诞", "Assets/Achievements/scm-holiday-christmas-512.webp");
                    Require(scm.Memory.Length == 0, "SCM cards have no memory line");
                    RequireFits(scm, "scm " + locale);
                }
            }
            catch (Exception error) { failure = error; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;

        var started = new List<string>(); var surfaces = new List<Surface>(); var allowed = true;
        using var playback = new AchievementCelebrationPlayback(n => {
            started.Add(n.AchievementId); var surface = new Surface(); surfaces.Add(surface); return surface;
        }, () => allowed, check => check(), () => { });
        foreach (var id in JourneyAchievementPolicy.AwardIds)
            playback.Submit(new(id, DateTimeOffset.UtcNow, 1, () => true, Receipt: "synthetic-" + id));
        playback.Advance(250); playback.Advance(500);
        allowed = false; playback.Advance(50); playback.Advance(100000);
        Require(started.Count == 1 && surfaces[0].Elapsed == 500, "blocked desktop pauses current city without skipping");
        allowed = true; playback.Advance(250);
        for (var i = 0; i < 120; i++) playback.Advance(500);
        Require(started.SequenceEqual(JourneyAchievementPolicy.AwardIds) && surfaces.All(s => s.Disposed),
            "nine journey cards use existing complete FIFO playback");
        Console.WriteLine("PASS CITYHOST artwork/playback: 1 group, 0 failed (54 offscreen cards, nine-card FIFO)");
    }
    private sealed class Surface : IAchievementCelebrationSurface
    {
        public double EntryMilliseconds => 760;
        public double LifetimeMilliseconds => 5980;
        public bool IsVisible { get; private set; }
        internal double Elapsed;
        internal bool Disposed;
        public void Show() => IsVisible = true;
        public void Hide() => IsVisible = false;
        public void Advance(double elapsed, int remaining) => Elapsed = elapsed;
        public void UpdatePosition() { }
        public void Dispose() { Disposed = true; IsVisible = false; }
    }
    private static byte[] Draw(AchievementCelebrationCard card, double elapsed)
    {
        card.Advance(elapsed, 0);
        var width = (int)card.Width; var height = (int)card.Height;
        card.Measure(new Size(width, height)); card.Arrange(new Rect(0, 0, width, height)); card.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(card);
        var pixels = new byte[width * height * 4]; bitmap.CopyPixels(pixels, width * 4, 0); return pixels;
    }
    // Long names and wrapped lines must end inside the card, clear of its edges.
    private static void RequireFits(AchievementCelebrationCard card, string label)
    {
        var layout = card.MeasureText(1.25);
        Require(layout.Top >= 5 && layout.Bottom <= AchievementCelebrationCard.CardHeight - 5,
            "engraving fits between the glass edges: " + label);
    }
    private static void Require(bool value, string reason) { if (!value) throw new Exception(reason); }
}
