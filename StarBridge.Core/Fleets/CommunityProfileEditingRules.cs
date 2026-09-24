using System.Text;

namespace StarBridge.Core.Fleets;

/// <summary>New explicit profile edits only. Legacy read limits remain unchanged.</summary>
public static class CommunityProfileEditingRules
{
    public static int TextUnits(string value) => value.EnumerateRunes().Sum(rune => rune.Value <= 0x7f ? 1 : 2);
    public static bool TextFits(string field, string value) => field switch
    {
        "name" => value.Trim().EnumerateRunes().Count() is >= 1 and <= 32 && !value.Any(char.IsControl),
        "logoText" => TextUnits(value) <= 16,
        "description" or "recruitingNote" => TextUnits(value) <= 400,
        "websiteUrl" => value.EnumerateRunes().Count() <= 256,
        _ => true
    };

    public static bool TagsFit(string value)
    {
        var tokens = value.Split(['/', '·', '、', ',', '，', ';', '；', '|'], StringSplitOptions.TrimEntries | StringSplitOptions.RemoveEmptyEntries)
            .Distinct(StringComparer.OrdinalIgnoreCase).ToArray();
        var core = 0; var style = 0; var other = 0;
        foreach (var token in tokens)
        {
            var tag = LegacyFleetTagCatalog.Tags.FirstOrDefault(tag =>
                token.Equals(tag.Id, StringComparison.OrdinalIgnoreCase) || token.Equals(tag.Name, StringComparison.OrdinalIgnoreCase));
            if (tag is null) return false;
            switch (tag.CategoryId) { case "core": core++; break; case "style": case "scale": style++; break; default: other++; break; }
        }
        return core is >= 1 and <= 3 && other + Math.Max(0, style - 2) <= 5;
    }

    public static bool RecruitmentFits(bool recruiting, bool listed, string? joining) =>
        !recruiting || (listed && joining is "Open" or "Approval");

    public static bool ActivityWindowFits(string start, string end, bool nextDay) =>
        LegacyFleetCreationRules.IsTime24(start) && LegacyFleetCreationRules.IsTime24(end) &&
        nextDay == (string.CompareOrdinal(end, start) <= 0);
}
