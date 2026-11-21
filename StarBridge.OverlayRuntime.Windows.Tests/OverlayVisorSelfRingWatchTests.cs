using System.Reflection;
using System.Text.Json;
using Vortice.Direct2D1;
using Vortice.Direct3D;
using Vortice.Direct3D11;
using Vortice.DirectWrite;
using Vortice.DXGI;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// 11-15 (user: "满血，只有圆环在闪"): the visor counts, without names or values, how often the player's own health ring
/// goes away, why, and how often it comes back within a second; one summary line a minute, only when the ring was drawn
/// or went away.
/// </summary>
internal static class OverlayVisorSelfRingWatchTests
{
    private static int _failures;

    private static void Check(bool value, string name, object? evidence = null)
    {
        if (!value) _failures++;
        Console.WriteLine(JsonSerializer.Serialize(new { Kind = "CHECK", Name = name, Status = value ? "PASS" : "FAIL", Evidence = evidence }));
    }

    private static OverlayVisorMember Self(OverlayVisorVitals vitals = OverlayVisorVitals.Alive) =>
        new("Aster", "", "", "", OverlayVisorMemberState.InGame, false, false, vitals, vitals == OverlayVisorVitals.Alive ? 1 : 0);

    private static OverlayVisorMember Other(string name) => new(name, "", "", "", OverlayVisorMemberState.InGame, false, false);

    internal static void Run()
    {
        _failures = 0;
        var alive = OverlayVisorVitals.Alive;
        Check(OverlayVisorSelfRingWatch.SelfRing(true, [Self(), Other("Vega")], 1, alive) == (true, null), "own row with a reading: drawn");
        Check(OverlayVisorSelfRingWatch.SelfRing(true, [Self(OverlayVisorVitals.Unknown)], 1, OverlayVisorVitals.Unknown) == (false, "reading"),
            "no reading: not drawn, reason reading");
        Check(OverlayVisorSelfRingWatch.SelfRing(false, [Self()], 1, alive) == (false, "panel"), "members group hidden: reason panel");
        Check(OverlayVisorSelfRingWatch.SelfRing(true, [Other("Vega")], 0, alive) == (false, "noSelfRow"), "no own row: reason noSelfRow");
        Check(OverlayVisorSelfRingWatch.SelfRing(true, [Other("Aster"), Self()], 1, alive) == (false, "nameShared"),
            "another row with the same name first: its empty ring is drawn, reason nameShared");
        Check(OverlayVisorSelfRingWatch.SelfRing(true, [Self(), Other("Aster")], 1, alive) == (true, null),
            "own row first among the same name: drawn");

        var lines = new List<string>();
        var watch = new OverlayVisorSelfRingWatch(lines.Add);
        IReadOnlyList<OverlayVisorMember> shown = [Self(), Other("Vega")];
        IReadOnlyList<OverlayVisorMember> gone = [Self(OverlayVisorVitals.Unknown), Other("Vega")];
        double t = 10;
        watch.Observe(t, true, shown, 1, alive);
        // twice a second: gone for a frame by the reading, back 0.1 s later
        for (var i = 0; i < 4; i++)
        {
            watch.Observe(t += 0.4, true, gone, 1, OverlayVisorVitals.Unknown);
            watch.Observe(t += 0.1, true, shown, 1, alive);
        }
        // once because the own row went missing, back after 2 s (not within a second)
        watch.Observe(t += 0.5, true, [Other("Vega")], 0, alive);
        watch.Observe(t += 2, true, shown, 1, alive);
        // once by a shared name
        watch.Observe(t += 0.5, true, [Other("Aster"), Self()], 1, alive);
        watch.Observe(t += 0.2, true, shown, 2, alive);
        // the renderer's loss flashes so far: 0 at the start, 3 more now
        watch.Observe(t += 0.2, true, shown, 1, alive, new(Flashes: 3, IntroFrames: 4, LiveClears: 1, TopmostChecks: 6, TopmostRaised: 1));
        // a frame whose scene has the ring but whose picture did not compose it
        watch.Observe(t += 0.1, true, shown, 1, alive, new(Flashes: 3, IntroFrames: 4, LiveClears: 1, TopmostChecks: 6, TopmostRaised: 1, RingMissing: true));
        Check(lines.Count == 0, "nothing written before the minute is up", lines);
        watch.Observe(t = 71, true, shown, 1, alive, new(Flashes: 5, IntroFrames: 4, LiveClears: 1, TopmostChecks: 7, TopmostRaised: 1));
        var summary = lines.SingleOrDefault() ?? "";
        Check(summary.StartsWith("visor-self-ring summary ", StringComparison.Ordinal), "summary line", summary);
        var fields = Fields(summary);
        // hides at 10.4, 10.9, 11.4, 11.9 (reading), 12.4 (no own row), 14.9 (shared name): gaps 500 x4, 2500
        foreach (var (key, want) in new[] { ("hidden", "6"), ("backIn1s", "5"), ("hiddenBy.reading", "4"), ("hiddenBy.panel", "0"),
            ("hiddenBy.noSelfRow", "1"), ("hiddenBy.nameShared", "1"), ("gap.under600", "4"), ("gap.600to900", "0"), ("gap.over900", "1"),
            ("flashes", "3"), ("introFrames", "4"), ("liveClears", "1"), ("topmostChecks", "6"), ("topmostRaised", "1"),
            ("notComposed", "1"), ("manySelfRows", "1") })
            Check(fields.GetValueOrDefault(key) == want, $"summary {key}={want}", summary);
        Check(!summary.Contains("Aster", StringComparison.Ordinal) && !summary.Contains("Vega", StringComparison.Ordinal), "no names in the line", summary);
        // only these fields, all whole counts: nothing else (no name, no health value) can slip into the line
        var allowed = new HashSet<string>(StringComparer.Ordinal) { "frames", "drawnFrames", "notComposed", "hidden", "backIn1s", "hiddenBy.reading",
            "hiddenBy.panel", "hiddenBy.noSelfRow", "hiddenBy.nameShared", "gap.under600", "gap.600to900", "gap.over900", "flashes", "introFrames",
            "liveClears", "topmostChecks", "topmostRaised", "refresh.timer", "refresh.push", "refresh.modules", "refresh.menu", "refresh.forced",
            "refresh.sync", "manySelfRows" };
        var words = summary.Split(' ', StringSplitOptions.RemoveEmptyEntries);
        Check(words.Length == allowed.Count + 2 && words.Skip(2).All(w => w.Split('=', 2) is [var k, var v] && allowed.Contains(k) && v.All(char.IsAsciiDigit)),
            "summary: exactly the allowed count fields", summary);

        // a minute in which the ring was never drawn and never went away writes nothing
        var quiet = new List<string>();
        var idle = new OverlayVisorSelfRingWatch(quiet.Add);
        idle.Observe(0, true, gone, 1, OverlayVisorVitals.Unknown);
        idle.Observe(30, true, gone, 1, OverlayVisorVitals.Unknown);
        idle.Observe(61, true, gone, 1, OverlayVisorVitals.Unknown);
        Check(quiet.Count == 0, "no reading the whole minute: no line", quiet);

        // flashes are counted from the renderer's running total: the next minute starts with the 2 seen at 71, and a new
        // renderer (total back to 0) does not count negative
        watch.Observe(80, true, shown, 1, alive, new(Flashes: 0, Refresh: new(Timer: 10, Push: 2)));
        var r90 = new OverlayVisorRefreshTotals(Timer: 90, Push: 3, Modules: 1, Menu: 1, Forced: 1, Sync: 2);
        watch.Observe(90, true, shown, 1, alive, new(Flashes: 1, Refresh: r90));
        // the ring going away 0.8 s after the previous time: the 600-900 bucket (the 750 ms scene rebuild)
        watch.Observe(100, true, gone, 1, OverlayVisorVitals.Unknown, new(Flashes: 1, Refresh: r90));
        watch.Observe(100.05, true, shown, 1, alive, new(Flashes: 1, Refresh: r90));
        watch.Observe(100.8, true, gone, 1, OverlayVisorVitals.Unknown, new(Flashes: 1, Refresh: r90));
        watch.Observe(100.85, true, shown, 1, alive, new(Flashes: 1, Refresh: r90));
        lines.Clear();
        watch.Observe(132, true, shown, 1, alive, new(Flashes: 1, Refresh: r90));
        var second = Fields(lines.SingleOrDefault() ?? "");
        Check(second.GetValueOrDefault("flashes") == "3", "second minute: 2 at its start plus 1 after a new renderer", second);
        Check(second.GetValueOrDefault("gap.600to900") == "1" && second.GetValueOrDefault("gap.over900") == "1" && second.GetValueOrDefault("hidden") == "2",
            "second minute gaps: one long (after 14.9), one 0.8 s", second);
        // refresh totals: 0 until 71, 10/2 at 80, 90/3/1/1/1 at 90 (the first minute saw none)
        foreach (var (key, want) in new[] { ("refresh.timer", "90"), ("refresh.push", "3"), ("refresh.modules", "1"), ("refresh.menu", "1"), ("refresh.forced", "1"), ("refresh.sync", "2") })
            Check(second.GetValueOrDefault(key) == want, $"second minute {key}={want}", second);
        Check(fields.GetValueOrDefault("refresh.timer") == "0", "first minute: no refreshes", summary);
        // the process-wide counters count by source and only go up
        var before = OverlayVisorRefreshCounts.Read();
        OverlayVisorRefreshCounts.Timer(); OverlayVisorRefreshCounts.Push();
        var after = OverlayVisorRefreshCounts.Read();
        Check(after.Timer == before.Timer + 1 && after.Push == before.Push + 1 && after.Menu == before.Menu, "refresh counters count by source", new { before, after });

        RendererCountsLossFlashes();

        if (_failures != 0) throw new InvalidOperationException($"Visor self-ring watch failures: {_failures}");
    }

    private static Dictionary<string, string> Fields(string line) => line.Split(' ', StringSplitOptions.RemoveEmptyEntries)
        .Select(part => part.Split('=', 2)).Where(kv => kv.Length == 2).GroupBy(kv => kv[0]).ToDictionary(g => g.Key, g => g.Last()[1]);

    // A reading wobbling 100 -> 99 -> 100 -> 99 flashes the ring on each step down; going up never flashes.
    private static void RendererCountsLossFlashes()
    {
        using var d3d = D3D11.D3D11CreateDevice(DriverType.Warp, DeviceCreationFlags.BgraSupport, [Vortice.Direct3D.FeatureLevel.Level_11_0]);
        using var dxgi = d3d.QueryInterface<IDXGIDevice>();
        using var factory = D2D1.D2D1CreateFactory<ID2D1Factory1>();
        using var device = factory.CreateDevice(dxgi);
        using var dc = device.CreateDeviceContext(DeviceContextOptions.None);
        using var dw = DWrite.DWriteCreateFactory<IDWriteFactory5>();
        using var renderer = new OverlayVisorRenderer(dc, dw);
        var step = typeof(OverlayVisorRenderer).GetMethod("StepRing", BindingFlags.Instance | BindingFlags.NonPublic)!;
        var member = Self();
        void At(float health, double t) => step.Invoke(renderer, ["Aster", member with { Health = health }, t]);
        At(1, 0);
        At(0.99f, 0.125); At(1, 0.25); At(0.99f, 0.375); At(1, 0.5);
        Check(renderer.RingFlashes == 2, "100/99 wobble: one loss flash per step down", renderer.RingFlashes);
        At(1, 0.625);
        Check(renderer.RingFlashes == 2, "no change: no flash", renderer.RingFlashes);
    }
}
