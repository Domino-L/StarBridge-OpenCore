namespace StarBridge.Desktop;

using System.Text;
using StarBridge.HostRuntime.Overlay;

public sealed partial class NativeInformationOverlayRuntime
{
    // The rally as it holds the top notice slot: title, one line of text, the hotkeys.
    internal static OverlayRallySlot RallySlotFor(InformationOverlayReminder reminder, string language)
    {
        var rally = reminder.Rally!;
        var zh = language.StartsWith("zh", StringComparison.OrdinalIgnoreCase);
        var traditional = language.Equals("zh-TW", StringComparison.OrdinalIgnoreCase) ||
            language.Equals("zh-Hant", StringComparison.OrdinalIgnoreCase);
        var title = traditional ? "艦隊召集" : zh ? "舰队召集" : "Fleet rally";
        var hint = traditional ? "Ctrl+Alt+Y 馬上到 · Ctrl+Alt+N 來不了" : zh ? "Ctrl+Alt+Y 马上到 · Ctrl+Alt+N 来不了"
            : "Ctrl+Alt+Y on my way · Ctrl+Alt+N can't make it";
        var body = rally.Sample
            ? traditional ? "（範例）這是一則範例召集" : zh ? "（示例）这是一条示例召集" : "(sample) This is a sample rally"
            : reminder.Preview == "hiddenDetails" || string.IsNullOrWhiteSpace(rally.Text)
                ? traditional ? "有新的召集，可在客戶端回應" : zh ? "有新的召集，可在客户端回应" : "New rally. Respond in the client."
                : zh ? $"「{TruncateRallyText(rally.Text)}」" : $"“{TruncateRallyText(rally.Text)}”";
        return new(reminder.Id, title, body, hint, zh ? "召集中" : "Rally on", rally.ExpiresAt, zh, traditional);
    }

    private static string TruncateRallyText(string text)
    {
        // Enumerating Unicode scalars preserves supplementary CJK and surrogate pairs.
        static int Width(Rune rune) => rune.Value is
            >= 0x1100 and <= 0x115f or >= 0x2329 and <= 0x232a or
            >= 0x2e80 and <= 0xa4cf or >= 0xac00 and <= 0xd7a3 or
            >= 0xf900 and <= 0xfaff or >= 0xfe10 and <= 0xfe19 or
            >= 0xfe30 and <= 0xfe6f or >= 0xff01 and <= 0xff60 or
            >= 0xffe0 and <= 0xffe6 or >= 0x20000 and <= 0x3ffff ? 2 : 1;
        var width = 0;
        foreach (var rune in text.EnumerateRunes()) width += Width(rune);
        if (width <= 32) return text;
        var result = new StringBuilder();
        width = 0;
        foreach (var rune in text.EnumerateRunes())
        {
            width += Width(rune);
            if (width > 31) break;
            result.Append(rune.ToString());
        }
        return result.Append('…').ToString();
    }
}
