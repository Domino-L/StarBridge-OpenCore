using StarBridge.Core.Overlay;
namespace StarBridge.Core.Tests;
internal static class OverlayAppearanceOptionsTests
{
    internal static void RunAll()
    {
        OverlayArchivedAppearanceMigrationTests.RunAll();
        var empty = OverlayAppearanceOptions.Parse(OverlayAppearanceOptions.Empty.Json);
        if (empty != OverlayAppearanceOptions.Empty || empty.Profile("unknown") is not null)
            throw new InvalidOperationException("Empty appearance envelope must not invent defaults");
        var input = """{"schemaVersion":1,"profiles":{"example":{"version":7,"values":{"color":2,"visible":true,"slots":[1,2],"label":"local"}}}}""";
        var options = OverlayAppearanceOptions.Parse(input);
        if (options.Profile("example")!.Value.GetProperty("version").GetInt32() != 7 || OverlayAppearanceOptions.Parse(options.Json) != options)
            throw new InvalidOperationException("Unknown private schemas are preserved structurally, not executed");
        var csv = OverlayDisplaySettings.Default.Serialize();
        var installedIdentity = OverlayDisplaySettings.Default with { Skin = OverlaySkin.HajiCitizen, RequestedSkin = OverlaySkin.HajiCitizen };
        var reopenedIdentity = OverlayDisplaySettings.Parse(installedIdentity.Serialize());
        if (reopenedIdentity.Skin != OverlaySkin.HajiCitizen || reopenedIdentity.EffectiveRequestedSkin != OverlaySkin.HajiCitizen ||
            (int)OverlaySkin.Default != 0 || (int)OverlaySkin.NightShadow != 1 || (int)OverlaySkin.Verdict != 3)
            throw new InvalidOperationException("Optional identity must round-trip without reassigning existing skin IDs");
        if ((OverlayDisplaySettings.Default with { AppearanceOptions = options }).Serialize() != csv ||
            OverlayDisplaySettings.Parse(csv).AppearanceOptions != OverlayAppearanceOptions.Empty)
            throw new InvalidOperationException("Options must not change legacy CSV semantics");
        foreach (var invalid in new[] {
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"key":1,"key":2}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"constructor":1}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"n":1e999}}}}""",
            """{"schemaVersion":1,"profiles":{"example":{"version":1,"values":{"a":[[[[[[[[1]]]]]]]]}}}}""",
            "{\"schemaVersion\":1,\"profiles\":{\"example\":{\"version\":1,\"values\":{\"a\":[" + string.Join(',', Enumerable.Repeat("0",1100)) + "]}}}}",
            new string('x',OverlayAppearanceOptions.MaximumBytes+1) })
        {
            try { OverlayAppearanceOptions.Parse(invalid); throw new InvalidOperationException("Unbounded or ambiguous appearance options accepted"); }
            catch (FormatException) { }
        }
    }
}
