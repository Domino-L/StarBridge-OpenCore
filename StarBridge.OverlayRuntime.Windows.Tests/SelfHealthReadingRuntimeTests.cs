using System.IO;
using System.Diagnostics;
using StarBridge.Desktop.Tests;
using StarBridge.HostRuntime.HealthReading;
using StarBridge.OverlayRuntime.Windows.HealthReading;

// "读取自己的血量" composition: with the switch off (the default) nothing is captured and the
// runtime stops promptly. Live capture of a running game is not exercised in automated tests.
internal static class SelfHealthReadingRuntimeTests
{
    internal static void Run()
    {
        var polled = 0;
        var runtime = new SelfHealthReadingRuntime(() => { Interlocked.Increment(ref polled); return false; });
        var waited = Stopwatch.StartNew();
        while (Volatile.Read(ref polled) < 2 && waited.Elapsed < TimeSpan.FromSeconds(5)) Thread.Sleep(50);
        if (Volatile.Read(ref polled) < 2) throw new InvalidOperationException("the switch is polled");
        if (runtime.Hub.Current != SelfHealthReading.None) throw new InvalidOperationException("switch off: no reading");
        var stop = Stopwatch.StartNew();
        runtime.Dispose();
        if (stop.Elapsed > TimeSpan.FromSeconds(2)) throw new InvalidOperationException($"dispose took {stop.Elapsed}");
        Console.WriteLine("PASS own health runtime stays idle with the switch off and stops promptly");
        SharedMembersNeverCarryHealth();
        OnlyThePinnedModelLoads();
        BackgroundReadingRules();
    }

    // "游戏在后台时也读取" (default off): an unreadable setting counts as off; the last image stands in only briefly,
    // so a window that stopped drawing hides the ring after the reader's 2 seconds; a missing game window is looked for
    // at most every 2 seconds.
    static void BackgroundReadingRules()
    {
        if (HudWindowCaptureFactory.Allowed(() => throw new InvalidOperationException("broken setting")))
            throw new InvalidOperationException("a failing background setting must count as off");
        if (!HudWindowCaptureFactory.Allowed(() => true) || HudWindowCaptureFactory.Allowed(() => false))
            throw new InvalidOperationException("the background setting is followed");
        if (!HudWindowCapture.MayReuse(1000, 1000 + HudWindowCapture.ReuseForMilliseconds) ||
            HudWindowCapture.MayReuse(1000, 1001 + HudWindowCapture.ReuseForMilliseconds))
            throw new InvalidOperationException("the last image is reused for at most ReuseForMilliseconds");
        if (HudWindowCapture.ReuseForMilliseconds > 500) throw new InvalidOperationException("reuse must stay short");
        if (!HudGameWindow.SearchDue(-HudGameWindow.SearchEveryMilliseconds, 0) ||
            HudGameWindow.SearchDue(5000, 5000 + HudGameWindow.SearchEveryMilliseconds - 1) ||
            !HudGameWindow.SearchDue(5000, 5000 + HudGameWindow.SearchEveryMilliseconds))
            throw new InvalidOperationException("the game window is looked for at most every SearchEveryMilliseconds");
        Console.WriteLine("PASS own health background reading: setting failures read as off, short reuse, throttled search");
    }

    // A model file whose hash is not the pinned one (damaged, swapped, older) is never loaded.
    static void OnlyThePinnedModelLoads()
    {
        var dir = Path.Combine(Path.GetTempPath(), "sb-own-health-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(dir);
        try
        {
            var path = Path.Combine(dir, "model.bin");
            File.WriteAllBytes(path, new byte[] { 1, 2, 3 });
            if (SelfHealthReadingRuntime.LoadPinnedModel(path, SelfHealthReadingRuntime.ModelSha256) != null)
                throw new InvalidOperationException("a file with another hash was loaded");
            if (SelfHealthReadingRuntime.LoadPinnedModel(Path.Combine(dir, "missing.bin"), SelfHealthReadingRuntime.ModelSha256) != null)
                throw new InvalidOperationException("a missing file was loaded");
            if (SelfHealthReadingRuntime.ModelSha256.Length != 64) throw new InvalidOperationException("pin is a sha256");
            // Where the private model is staged (.private-ops, git-ignored), the pinned hash must match it.
            const string model = "hud-health-v1.bin";
            var staged = Path.Combine(OverlayVisorTests.FindRepositoryRoot(), ".private-ops", "hud-health", model);
            if (File.Exists(staged))
            {
                if (SelfHealthReadingRuntime.LoadPinnedModel(staged, SelfHealthReadingRuntime.ModelSha256) == null)
                    throw new InvalidOperationException("the staged private model does not match the pinned hash");
            }
            else
                Console.WriteLine($"SKIP own health staged model hash: open-core restricted model {model} absent");
            Console.WriteLine("PASS own health loads only the pinned model file");
        }
        finally { try { Directory.Delete(dir, true); } catch (IOException) { } }
    }

    // The visor shows health on the own row only: nothing named Shared* in the overlay may carry it.
    static void SharedMembersNeverCarryHealth()
    {
        const System.Reflection.BindingFlags all = System.Reflection.BindingFlags.Public | System.Reflection.BindingFlags.NonPublic |
            System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.Static | System.Reflection.BindingFlags.DeclaredOnly;
        Type[] types;
        try { types = typeof(SelfHealthReadingRuntime).Assembly.GetTypes(); }
        catch (System.Reflection.ReflectionTypeLoadException e) { types = e.Types.Where(t => t != null).ToArray()!; }
        var offenders = types.SelectMany(t => t.GetMembers(all).Select(m => (t, m)))
            .Where(x => x.m.Name.StartsWith("Shared", StringComparison.Ordinal) &&
                (x.m.Name.Contains("Health", StringComparison.OrdinalIgnoreCase) || x.m.Name.Contains("Vitals", StringComparison.OrdinalIgnoreCase)))
            .Select(x => $"{x.t.FullName}.{x.m.Name}").ToArray();
        if (offenders.Length > 0) throw new InvalidOperationException("shared overlay members carry health: " + string.Join(", ", offenders));
        Console.WriteLine("PASS own health never appears in shared overlay members");
    }
}
