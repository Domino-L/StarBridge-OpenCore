using StarBridge.Core.Presence;

namespace StarBridge.Desktop.Tests;

internal static class ShipDisplayNameBoundaryTests
{
    internal static void RunAll()
    {
        Check("英仙座", "RSI_Perseus", "known runtime ID keeps its existing Chinese translation");
        Check("英仙座", "Perseus", "known English name keeps its existing Chinese translation");
        Check("渡鸦EX", "渡鸦EX", "already translated mixed-model label remains stable");
        Check(PlayerSessionStatePresentation.WaitingForRecognition,
            PlayerSessionStatePresentation.WaitingForRecognition, "session-state text is not a ship code");
        Check("等待识别", null, "missing data uses the caller fallback", "等待识别");
        Check("等待识别", "   ", "blank data uses the caller fallback", "等待识别");
        Check("等待识别", "Unknown", "generic unknown input uses the caller fallback", "等待识别");
        Check("等待识别", "None", "generic none input uses the caller fallback", "等待识别");

        foreach (var text in new[] { "Uncatalogued Fixture Ship", "MISC Future Explorer", "Prototype Mark-II" })
            Check(text, text, "readable untranslated names must remain readable");
        Check(new string('X', 256), new string('X', 256), "bounded untranslated text survives");
        Check("未知舰船", new string('X', 257), "overlong input is rejected");
        Check("未知舰船", "Readable\0Ship", "control characters are rejected");

        foreach (var code in new[] { "MISC_Future_Test", "AEGS_Uncatalogued_Fixture_98765", "ZX99_Prototype-MarkII_004", "AEGS_98765" })
        {
            Check("未知舰船", code, "unknown internal IDs cannot become visible ship names");
            Check("未知舰船", code, "recognized-data fallback is distinct from missing-data text", "等待识别");
            var eventText = OverlayEventShipPresentation.FormatShipChange("Fixture", code, zh: true);
            if (eventText != "Fixture 切换飞船：未知舰船" || eventText.Contains(code, StringComparison.Ordinal))
                throw new InvalidOperationException("The actual Chinese ship-event formatter leaked an internal ID.");
        }
        if (OverlayEventShipPresentation.FormatShipChange("Fixture", "Uncatalogued Fixture Ship", zh: true)
            != "Fixture 切换飞船：Uncatalogued Fixture Ship")
            throw new InvalidOperationException("The actual event formatter erased an untranslated readable name.");
        Console.WriteLine("PASS Chinese ship presentation separates known names, readable untranslated labels and unknown runtime IDs");
    }

    private static void Check(string expected, string? input, string because, string fallback = "未知舰船")
    {
        var actual = ShipDisplayNamePresentation.ResolveChinese(input, fallback);
        if (actual != expected) throw new InvalidOperationException($"{because}: expected {expected}, got {actual}");
    }
}
