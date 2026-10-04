using StarBridge.Core.Overlay;

namespace StarBridge.Core.Tests;

internal static class OverlayLayoutInputAuditTests
{
    internal static void RunAll()
    {
        var failures = new List<string>();
        foreach (var test in new Action[] { LayoutValues, SettingsValues, FractionalCrosshairValues, EnumSettingsValues, CollisionBounds })
        {
            try { test(); }
            catch (Exception error) { failures.Add(test.Method.Name + ": " + error.Message); }
        }
        Check(failures.Count == 0, string.Join(Environment.NewLine, failures));
    }

    private static void LayoutValues()
    {
        foreach (var raw in new[] { "NaN", "Infinity", "-Infinity", "1e9999" })
        foreach (var index in new[] { 1, 2, 3, 4 })
        {
            var parts = new[] { "Members", "0.1", "0.2", "0.3", "0.4" };
            parts[index] = raw;
            Check(!InformationOverlayLayoutItem.ParseMany(string.Join(',', parts)).Any(), "non-finite geometry is rejected: " + raw);
        }
        Check(!InformationOverlayLayoutItem.ParseMany(" ,0,0,0.2,0.2").Any(), "empty module key is skipped without an exception");
        var sane = InformationOverlayLayoutItem.ParseMany("Members,0.1,0.2,0.3,0.4,999,999,0,NaN,Infinity,-Infinity").Single();
        Check(Enum.IsDefined(sane.HorizontalAnchor) && Enum.IsDefined(sane.VerticalAnchor), "undefined anchors recover from finite geometry");
        Check(double.IsFinite(sane.TextOpacity) && double.IsFinite(sane.BackgroundOpacity) && double.IsFinite(sane.DecorationOpacity), "invalid optional opacity recovers independently");
        var rect = InformationOverlayLayoutGeometry.ResolveItemRect(sane, 1920, 1080);
        Check(double.IsFinite(rect.Left) && double.IsFinite(rect.Top), "recovered item reaches finite rendering geometry");
    }

    private static void SettingsValues()
    {
        foreach (var raw in new[] { "NaN", "Infinity", "-Infinity", "1e9999" })
        foreach (var index in new[] { 5, 16, 17, 18, 26, 27, 33, 40, 41, 42, 55, 60, 67, 69, 70, 73 })
        {
            var parts = OverlayDisplaySettings.Default.Serialize().Split(',');
            parts[index] = raw;
            var settings = OverlayDisplaySettings.Parse(string.Join(',', parts));
            Check(typeof(OverlayDisplaySettings).GetProperties().Where(p => p.PropertyType == typeof(double))
                .All(p => double.IsFinite((double)p.GetValue(settings)!)), "all legacy display numbers remain finite: " + index + "/" + raw);
        }
        Check(double.IsFinite(OverlayDisplaySettings.NormalizeMemberNameColumnRatio(double.NaN)), "direct member column normalization is finite");
        foreach (var raw in new[] { "NaN", "Infinity", "-Infinity", "1e9999" })
        {
            var overrides = OverlayEventNotificationDurationOverrides.Parse(string.Join(';', Enumerable.Repeat(raw, 11)));
            Check(typeof(OverlayEventNotificationDurationOverrides).GetProperties().Where(p => p.PropertyType == typeof(double))
                .All(p => double.IsFinite((double)p.GetValue(overrides)!)), "every duration override is finite");
        }
    }

    private static void FractionalCrosshairValues()
    {
        foreach (var opacity in new[] { 0.2, 0.37, 0.6, 1.0 })
        foreach (var outline in new[] { 0.0, 0.13, 0.4, 0.8 })
        {
            var settings = OverlayDisplaySettings.Default with { CrosshairOpacity = opacity, CrosshairOutlineOpacity = outline };
            var restored = OverlayDisplaySettings.Parse(settings.Serialize());
            Check(Math.Abs(restored.CrosshairOpacity - opacity) < 0.00001 &&
                Math.Abs(restored.CrosshairOutlineOpacity - outline) < 0.00001,
                "crosshair opacity and outline retain fractional values through legacy persistence");
        }
    }

    private static void CollisionBounds()
    {
        foreach (var surface in new[] { (640d, 360d), (1280d, 720d), (1920d, 1080d) })
        {
            var layout = InformationOverlayLayoutItem.ParseMany("Squads,0.05,0.7,0.2,0.05;Members,0.05,0.77,0.2,0.05;Chat,0.05,0.84,0.2,0.05");
            Check(InformationOverlayLayoutGeometry.ResolveItems(layout, surface.Item1, surface.Item2).Values
                .All(r => r.Bottom <= surface.Item2 + 0.01 && r.Top >= 0), "minimum-height collision correction must not push modules outside the screen");
        }
        var random = new Random(930);
        var keys = new[] { "Notice", "Squads", "Members", "Chat" };
        for (var iteration = 0; iteration < 1000; iteration++)
        {
            var width = random.Next(320, 7681);
            var height = random.Next(240, 4321);
            var layout = keys.Select(key => new InformationOverlayLayoutItem(key, random.NextDouble(), random.NextDouble(), random.NextDouble(), random.NextDouble())).ToArray();
            var original = InformationOverlayLayoutItem.SerializeMany(layout);
            Check(InformationOverlayLayoutGeometry.ResolveItems(layout, width, height).Values.All(r =>
                double.IsFinite(r.Left) && double.IsFinite(r.Top) && double.IsFinite(r.Width) && double.IsFinite(r.Height) &&
                r.Left >= 0 && r.Top >= 0 && r.Right <= width + 0.01 && r.Bottom <= height + 0.01), "seeded layouts stay finite and within each viewport");
            Check(InformationOverlayLayoutItem.SerializeMany(layout) == original, "responsive correction preserves persisted layout");
        }
    }

    private static void EnumSettingsValues()
    {
        foreach (var index in new[] { 1, 10, 13, 20, 25, 29, 31, 32, 37, 43, 44, 50, 52, 53, 61, 62, 64, 68, 72 })
        {
            var parts = OverlayDisplaySettings.Default.Serialize().Split(',');
            parts[index] = "999";
            var parsed = OverlayDisplaySettings.Parse(string.Join(',', parts));
            Check(typeof(OverlayDisplaySettings).GetProperties().Where(p => p.PropertyType.IsEnum && !p.PropertyType.IsDefined(typeof(FlagsAttribute), false))
                .All(p => Enum.IsDefined(p.PropertyType, p.GetValue(parsed)!)), "undefined legacy display enums recover: " + index);
        }
    }
    private static void Check(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
}
