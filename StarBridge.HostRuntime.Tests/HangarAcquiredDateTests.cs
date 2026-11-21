using System.Globalization;
using System.Text.Json;
using StarBridge.HostRuntime.Hangar;

/// <summary>
/// User 11-12: "个人机库的加入时间应该展示官网机库的入库时间 而非导入客户端的时间". The saved ship already keeps
/// the RSI pledge date text; the client gets it as a plain date and never falls back to the import time.
/// </summary>
internal static class HangarAcquiredDateTests
{
    public static Task Run()
    {
        var now = new DateTimeOffset(2026, 11, 12, 8, 0, 0, TimeSpan.Zero);
        var cases = new (string? Text, string? Expected)[]
        {
            ("Sep 01, 2026", "2026-09-01"),
            ("Sep 1, 2026", "2026-09-01"),
            ("September 1, 2026", "2026-09-01"),
            ("Created: Sep 01, 2026", "2026-09-01"),
            ("  Dec 31,   2015 ", "2015-12-31"),
            ("1 Sep 2026", "2026-09-01"),
            ("2026-09-01", "2026-09-01"),
            ("2026年9月1日", "2026-09-01"),
            ("2026 年 09 月 01 日", "2026-09-01"),
            ("创建：2020年2月29日", "2020-02-29"),
            ("：2020年2月29日", "2020-02-29"), // saved by readers that left the full-width colon
            (": Sep 01, 2026", "2026-09-01"),
            ("Jan 01, 2011", "2011-01-01"), ("Dec 31, 2010", null),
            ("2026年11月14日", null), // today + 2 days
            ("Sep 01, 2026x", null), ("xSep 01, 2026", null), ("Sep 01 2026", null),
            ("2026年11月13日", "2026-11-13"), // one day ahead tolerates the page's own time zone
            (null, null), ("", null), ("   ", null), ("soon", null),
            ("2026年13月1日", null), ("2021年2月29日", null), ("Feb 30, 2026", null),
            ("Sep 01, 2026 10:00", null), ("09/01/2026", null), ("0000年1月1日", null),
            ("Jan 01, 2005", null), ("2026年11月20日", null), (new string('x', 200), null),
        };
        var original = CultureInfo.CurrentCulture;
        try
        {
            foreach (var culture in new[] { "en-US", "de-DE", "zh-CN", "ar-SA" })
            {
                CultureInfo.CurrentCulture = CultureInfo.GetCultureInfo(culture);
                foreach (var (text, expected) in cases)
                {
                    var actual = HangarAcquiredDate.Format(text, now);
                    if (actual != expected)
                        throw new Exception($"Pledge date '{text}' under {culture}: expected {expected ?? "null"}, got {actual ?? "null"}");
                }
            }
        }
        finally { CultureInfo.CurrentCulture = original; }

        // The saved row carries the official date beside the unchanged import time.
        var imported = new DateTimeOffset(2026, 11, 1, 3, 4, 5, TimeSpan.Zero);
        var dated = new LocalHangarShip("acquired-fixture", "pledge-fixture", "Carrack", "Anvil", "Sep 01, 2024", imported);
        using (var row = JsonDocument.Parse(JsonSerializer.Serialize(HangarShipNames.PresentSaved(dated))))
        {
            if (row.RootElement.GetProperty("acquiredOn").GetString() != "2024-09-01" ||
                row.RootElement.GetProperty("addedAt").GetDateTimeOffset() != imported)
                throw new Exception("Saved ship must present the official pledge date and keep the import time separate");
        }
        foreach (var text in new string?[] { null, "unknown" })
        {
            using var row = JsonDocument.Parse(JsonSerializer.Serialize(HangarShipNames.PresentSaved(dated with { AcquiredText = text })));
            if (row.RootElement.GetProperty("acquiredOn").ValueKind != JsonValueKind.Null)
                throw new Exception("A ship without a readable official date must present it as unknown, never the import time");
        }

        // The account copy keeps the date text, so a restored hangar shows the same official date.
        var snapshot = new LocalHangarSnapshot(3, imported, "op", [dated]);
        var bytes = HangarArchive.Serialize(HangarArchive.FromSnapshot(snapshot));
        using (var archive = JsonDocument.Parse(bytes))
        {
            var restored = HangarArchive.ToLocal(HangarArchive.Parse(archive.RootElement).Ships[0]);
            if (restored.AcquiredText != "Sep 01, 2024" || HangarAcquiredDate.Format(restored.AcquiredText, now) != "2024-09-01")
                throw new Exception("Account hangar copy must keep the official pledge date");
        }
        Console.WriteLine("PASS Personal hangar shows the official pledge date (zh/en, culture-independent, unknown stays unknown)");
        return Task.CompletedTask;
    }
}
