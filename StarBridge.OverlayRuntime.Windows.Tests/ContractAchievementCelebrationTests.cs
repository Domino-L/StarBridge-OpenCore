using System.Windows;
using System.Windows.Media;
using System.Windows.Media.Imaging;
using StarBridge.Core.Achievements;
using StarBridge.HostRuntime.Achievements;
using StarBridge.OverlayRuntime.Windows;

internal static class ContractAchievementCelebrationTests
{
    internal static void Run()
    {
        Exception? failure = null; var rendered = 0;
        var thread = new Thread(() => {
            try
            {
                var names = new Dictionary<string, string[]> {
                    ["contract-first"] = ["开张大吉", "開張大吉", "Open for Business"],
                    ["contract-tsg-lead"] = ["打击群·领队", "打擊群·領隊", "TSG · Leader"],
                    ["contract-tsg-complete"] = ["打击群·凯旋", "打擊群·凱旋", "TSG · Triumph"],
                    ["contract-tsg-swift"] = ["打击群·闪击", "打擊群·閃擊", "TSG · Blitz"],
                    ["contract-tsg-deathless"] = ["打击群·不灭", "打擊群·不滅", "TSG · Undying"] };
                Require(names.Keys.SequenceEqual(ContractAchievementPolicy.AwardIds), "five visible IDs");
                var locales = new[] { "zh-CN", "zh-TW", "en-US" };
                foreach (var (id, text) in names)
                foreach (var light in new[] { false, true })
                for (var i = 0; i < locales.Length; i++)
                {
                    var facts = new ContractAchievementRecord(new string('W', 160), DateTimeOffset.Parse("2026-11-04T12:00:00Z"),
                        DateTimeOffset.Parse("2026-11-04T13:00:00Z"), DateTimeOffset.Parse("2026-11-04T13:21:00Z"), 38, true, 0);
                    var lines = facts.Lines(id)!;
                    var card = new AchievementCelebrationCard(locales[i], light, false, id, record: lines);
                    Require(new AchievementCelebrationCard(locales[i], light, false, id).Memory == "", "no local record hides the line");
                    Require(System.Windows.Automation.AutomationProperties.GetName(card).EndsWith(text[i]) && card.Memory == lines.For(locales[i]),
                        "localized name and local record: " + id);
                    Require(card.HasArtwork == new AchievementCelebrationCard(locales[i], light, false).HasArtwork, "first-entry artwork fallback");
                    var locked = Draw(card, 450); var earned = Draw(card, 1400);
                    Require(!locked.SequenceEqual(earned), "offscreen reveal changes pixels");
                    var layout = card.MeasureText(1.25);
                    Require(layout.Top >= 5 && layout.Bottom <= AchievementCelebrationCard.CardHeight - 5 &&
                        layout.MemoryHeight > 0, "the glass fits the record");
                    rendered++;
                }
                foreach (var id in names.Keys)
                    Require(new AchievementCelebration(id, DateTimeOffset.UtcNow, 1, () => true).CanPresent, "visible celebration admitted");
                Require(!new AchievementCelebration("contract-future", DateTimeOffset.UtcNow, 1, () => true).CanPresent,
                    "unknown awards never present");
            }
            catch (Exception e) { failure = e; }
        });
        thread.SetApartmentState(ApartmentState.STA); thread.Start(); thread.Join();
        if (failure is not null) throw failure;
        Console.WriteLine($"SUMMARY CONTRACT OVERLAY passed={rendered} failed=0 (offscreen only, no HWND)");
    }
    private static byte[] Draw(AchievementCelebrationCard card, double ms)
    {
        card.Advance(ms, 0); var width = (int)card.Width; var height = (int)card.Height;
        card.Measure(new Size(width, height)); card.Arrange(new Rect(0, 0, width, height)); card.UpdateLayout();
        var bitmap = new RenderTargetBitmap(width, height, 96, 96, PixelFormats.Pbgra32); bitmap.Render(card);
        var pixels = new byte[width * height * 4]; bitmap.CopyPixels(pixels, width * 4, 0); return pixels;
    }
    private static void Require(bool condition, string message) { if (!condition) throw new Exception(message); }
}
