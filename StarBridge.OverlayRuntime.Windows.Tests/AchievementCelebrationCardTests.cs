using StarBridge.OverlayRuntime.Windows;
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
                VerifyGlass();
                // Real renderer and bundled art, without opening a window or
                // emitting sound/awards/network requests on the maintainer device.
                var scm = new AchievementCelebrationCard("zh-CN", false, false, "scm-1", 0, "星际圣诞", "Assets/Achievements/scm-holiday-christmas-512.webp");
                Require(scm.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(scm).EndsWith("星际圣诞"), "SCM holiday uses its exact display name and bundled WebP pair");
                Require(!Draw(scm, 450).SequenceEqual(Draw(scm, 1400)), "SCM artwork uses the existing full reveal");
                // Build 105: daily and limited-event art ships as bundled 512 WebP pairs.
                foreach (var art in new[] { "daily-account-rookie", "daily-account-regular", "daily-account-veteran", "daily-guide-beginner",
                    "daily-guide-adept", "daily-guide-master", "daily-trade-beginner", "daily-trade-adept", "daily-trade-master",
                    "daily-bounty-beginner", "daily-bounty-leader", "event-spring-elite", "event-checkin-streak", "event-spring-participant" })
                {
                    var card = new AchievementCelebrationCard("zh-CN", false, false, "scm-3", 0, "中登", $"Assets/Achievements/scm-{art}-512.webp");
                    Require(card.HasArtwork, $"SCM {art} earned and locked WebP resolve in the Windows plug-in");
                }
                foreach (var rejected in new[] { "Assets/Achievements/scm-other-account-regular-512.webp", "Assets/Achievements/scm-daily-x/../scm-daily-account-regular-512.webp",
                    "Assets/Achievements/scm-daily-account-regular.svg", "Assets\\Achievements\\scm-daily-account-regular-512.webp" })
                    Require(!new AchievementCelebrationCard("zh-CN", false, false, "scm-3", 0, "中登", rejected).HasArtwork, $"Rejected local art path {rejected}");
                // Build 105: past three single cards, one summary card names the rest.
                foreach (var (locale, text, memory) in new[] { ("zh-CN", "另有 4 个 SCM 成就已解锁", "到成就中心查看"),
                    ("zh-TW", "另有 4 個 SCM 成就已解鎖", "到成就中心查看"), ("en-US", "4 more SCM achievements unlocked", "See them in the achievement centre") })
                {
                    var summary = new AchievementCelebrationCard(locale, false, false, "scm-summary", 0, null, null, null, 4);
                    Require(!summary.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(summary).EndsWith(text) && summary.Memory == memory,
                        $"SCM summary card names how many more ({locale})");
                    Require(!Draw(summary, 450).SequenceEqual(Draw(summary, 1400)), "Summary card uses the existing reveal");
                }
                var untrusted = new AchievementCelebrationCard("en-US", false, true, "scm-2", 0, "Synthetic SCM", "https://blocked.invalid/image.webp");
                Require(!untrusted.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(untrusted).EndsWith("Synthetic SCM"), "No remote image loads; optional artwork preserves server display name");
                foreach (var light in new[] { false, true })
                foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
                {
                    var card = new AchievementCelebrationCard(locale, light, false);
                    Require(card.HasArtwork, "Both formal artwork resources resolve in the Windows plug-in");

                    var preload = Draw(card, 0);
                    var sealedCard = Draw(card, 450);
                    var earnedCard = Draw(card, 1400);
                    Require(!preload.SequenceEqual(sealedCard) && !sealedCard.SequenceEqual(earnedCard),
                        "The hidden start, sweep and fully engraved glass render distinctly");
                    Require(card.LifetimeMilliseconds == 5560, "Entry 760ms, readable hold 4500ms, exit 300ms");
                    var reduced = new AchievementCelebrationCard(locale, light, true);
                    Require(Draw(reduced, 0).SequenceEqual(Draw(reduced, 3000)) && reduced.LifetimeMilliseconds == 4500,
                        "Reduced motion immediately shows the final readable card for 4500ms");
                    foreach (var id in StarBridge.Core.Achievements.HangarAchievementPolicy.Ids)
                    {
                        var series = new AchievementCelebrationCard(locale, light, false, id, 4);
                        Require(series.HasArtwork && System.Windows.Automation.AutomationProperties.GetName(series).EndsWith(" · IV", StringComparison.Ordinal),
                            "Every series resolves its own locked/earned images and exposes the Roman rank only in the name");
                        Require(!Draw(series, 450).SequenceEqual(Draw(series, 1400)),
                            "Each series uses the accepted locked-to-earned reveal");
                        var staticSeries = new AchievementCelebrationCard(locale, light, true, id, 4);
                        Require(Draw(staticSeries, 0).SequenceEqual(Draw(staticSeries, 3000)),
                            "Series achievements respect reduced motion");
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

    private static void VerifyGlass()
    {
        var ordinary = new AchievementCelebrationCard("zh-CN", false, false);
        var rare = new AchievementCelebrationCard("zh-CN", false, false, rarityTier: "rare", rarityBasisPoints: 420);
        var ultra = new AchievementCelebrationCard("zh-CN", false, false, rarityTier: "veryRare", rarityBasisPoints: 4);
        Require(ordinary.RarityLine == "" && ordinary.EntryMilliseconds == 760 && ordinary.LifetimeMilliseconds == 5560,
            "Missing rarity uses ordinary timing with no rarity row");
        Require(rare.RarityLine == "稀有 · 4.2% 的玩家获得" && rare.EntryMilliseconds == 820 && rare.LifetimeMilliseconds == 5620,
            "Rare supports the localized ratio and its own full timeline");
        Require(ultra.RarityLine == "极稀有 · 少于 0.1% 的玩家获得" && ultra.EntryMilliseconds == 1100 && ultra.LifetimeMilliseconds == 5900,
            "Ultra rare supports the below-threshold ratio and its own full timeline");

        AchievementCelebrationCard Scm(string locale, string? tier) =>
            new(locale, false, false, "scm-1", displayName: "Synthetic SCM", rarityTier: tier);
        var common = Scm("en-US", "COMMON");
        var unknown = Scm("en-US", null);
        Require(common.RarityLine == "" && unknown.RarityLine == "" &&
            common.LifetimeMilliseconds == unknown.LifetimeMilliseconds &&
            Draw(common, 1400).SequenceEqual(Draw(unknown, 1400)), "Missing and COMMON rarity render identical ordinary cards");
        Require(Scm("zh-TW", "EPIC").RarityLine == "史詩" &&
            Scm("zh-CN", "LEGENDARY").RarityLine == "传说" &&
            Scm("en-US", "RARE").RarityLine == "Rare", "SCM tiers use achievement centre labels without a ratio");
        Require(new AchievementCelebrationCard("zh-TW", false, false, rarityBasisPoints: 1).RarityLine == "少於 0.1% 的玩家獲得" &&
            new AchievementCelebrationCard("en-US", false, false, rarityTier: "veryRare", rarityBasisPoints: 8).RarityLine ==
                "Ultra rare · Earned by fewer than 0.1% of players", "App rarity uses the client percentage labels");

        var normalPixels = Draw(ordinary, 1400);
        var rarePixels = Draw(rare, 1400);
        var ultraPixels = Draw(ultra, 1400);
        var width = (int)ordinary.Width;
        var height = (int)ordinary.Height;
        int Pixel(byte[] pixels, int x, int y) => BitConverter.ToInt32(pixels, (y * width + x) * 4);
        var seam = new[] { normalPixels, rarePixels, ultraPixels }.Select(p => Pixel(p, width - 1, 65)).ToArray();
        var edge = new[] { normalPixels, rarePixels, ultraPixels }.Select(p => Pixel(p, 90, 24)).ToArray();
        Require(seam.Distinct().Count() == 3 && edge.Distinct().Count() == 3,
            "Each rarity has visibly distinct seam and edge pixels");
        byte Alpha(int x, int y) => normalPixels[(y * width + x) * 4 + 3];
        Require(Alpha(25, 26) < 64 && Alpha(25, height - 3) < 64 &&
            Alpha(44, 29) > 190 && Alpha(44, height - 6) > 190 &&
            Alpha(width - 6, 25) > 190 && Alpha(width - 6, height - 2) > 190,
            "Both left corners are clipped symmetrically while the right corners stay square");
        var reduced = new AchievementCelebrationCard("zh-CN", false, true, rarityTier: "rare", rarityBasisPoints: 420);
        Require(Draw(reduced, 0).SequenceEqual(rarePixels), "Reduced motion's first frame is identical to the settled rare card");
        Require(Draw(reduced, reduced.LifetimeMilliseconds).All(channel => channel == 0), "Reduced motion disappears immediately after the hold");
        rare.Advance(2000, 9);
        Require(rare.IsArrangeValid && Draw(rare, 2000).SequenceEqual(rarePixels),
            "Dwell holds a single drawing even when more notices arrive");
        Require(Draw(rare, rare.LifetimeMilliseconds).All(channel => channel == 0), "Exit ends with a fully hidden card");

        var summary = new AchievementCelebrationCard("en-US", false, false, "scm-summary", summaryCount: 8, rarityTier: "EPIC");
        var staticSummary = new AchievementCelebrationCard("en-US", false, true, "scm-summary", summaryCount: 8);
        Require(summary.RarityLine == "" && summary.SummaryCountAt(420) == 1 && summary.SummaryCountAt(590) is > 1 and < 8 &&
            summary.SummaryCountAt(760) == 8 && staticSummary.SummaryCountAt(0) == 8, "Summary counts up only during animated entry");
        var summaryPixels = Draw(summary, 1000);
        var missingPixels = Draw(unknown, 1000);
        var art = Enumerable.Range(45, 62).SelectMany(y => Enumerable.Range(52, 58).Select(x => (X: x, Y: y))).ToArray();
        Require(art.All(p => Pixel(summaryPixels, p.X, p.Y) == Pixel(missingPixels, p.X, p.Y)) &&
            art.Select(p => Pixel(summaryPixels, p.X, p.Y)).Distinct().Count() > 64,
            "Summary uses the detailed brand mark in the same artwork well as a missing picture");

        foreach (var locale in new[] { "zh-CN", "zh-TW", "en-US" })
        {
            var english = locale == "en-US";
            var poem = new AchievementCelebrationCard(locale, false, false, "hangar-home", 5,
                rarityTier: "veryRare", rarityBasisPoints: 300).MeasureText(1.25);
            var longName = new AchievementCelebrationCard(locale, true, false, "scm-1",
                displayName: "A particularly long achievement name that must fit", rarityTier: "LEGENDARY").MeasureText(1.25);
            var contract = new AchievementCelebrationCard(locale, false, false, "contract-first",
                record: new("第一行\n第二行", "第一行\n第二行", "First line\nSecond line"),
                rarityTier: "rare", rarityBasisPoints: 320).MeasureText(1.25);
            Require(poem.Top >= 5 && poem.Bottom <= 103 && (!english || poem.MemoryHeight > 22) &&
                longName.NameSize < 17 && longName.Top >= 5 && longName.Bottom <= 103 &&
                contract.MemoryHeight > 22 && contract.Top >= 5 && contract.Bottom <= 103, $"No text overflow in {locale}");
        }
        Console.WriteLine("PASS G1 glass: geometry, palettes, missing rarity, reduced motion, still dwell, summary and text");
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
}
