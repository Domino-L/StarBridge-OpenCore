using System.Windows;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

// The loading line reads once on open and then relies on these pushes instead
// of polling. Real production STA/HWND lifecycle, offscreen, synthetic data only.
internal static class OverlayRuntimeStateEventTests
{
    internal static async Task Run()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        var pushed = new List<InformationOverlayRuntimeSnapshot>();
        var threads = new HashSet<int>();
        runtime.StateChanged += snapshot =>
        {
            lock (pushed) { pushed.Add(snapshot); threads.Add(Environment.CurrentManagedThreadId); }
        };
        runtime.StateChanged += _ => throw new InvalidOperationException("a failing subscriber");
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                EnableStartupTransition = false, AutoFocusGameWindowOnOpen = false,
                AutoOpenOverlayOnGameStart = false, AutoOpenOverlayOnGameForeground = false,
                AutoCloseOverlayOnGameBackground = false
            }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "en");
        Task<InformationOverlayRuntimeSnapshot> Run(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace? with = null) => runtime.ExecuteAsync(command, with ?? workspace).AsTask();
        List<InformationOverlayRuntimeSnapshot> Pushed() { lock (pushed) return [.. pushed]; }

        var synced = await Run(InformationOverlayRuntimeCommand.Sync);
        Check(Pushed() is [var first] && first == synced, "the first sync pushes the state it returns");
        await Run(InformationOverlayRuntimeCommand.Sync);
        await Task.Delay(1600); // Two follow-game ticks with nothing changed.
        Check(Pushed().Count == 1, "an unchanged state is not pushed again, by commands or ticks");

        var opened = await Run(InformationOverlayRuntimeCommand.Open);
        Check(opened is { WindowState: "open", IsVisible: true }, "offscreen HUD opens");
        Check(Pushed()[^1] == opened && Pushed().Count == 2, "open pushes once, before its response returns");

        var revised = await Run(InformationOverlayRuntimeCommand.Sync, workspace with { Revision = 2 });
        Check(Pushed()[^1] == revised && revised.AppliedRevision == 2, "a newly applied revision is pushed");

        var closed = await Run(InformationOverlayRuntimeCommand.Close, workspace with { Revision = 2 });
        Check(closed is { WindowState: "closed", IsVisible: false } && Pushed()[^1] == closed, "close pushes the closed state");
        var all = Pushed();
        Check(all.Zip(all.Skip(1)).All(pair => pair.First != pair.Second), "no two consecutive pushes are equal");
        lock (pushed) Check(threads.Count == 1 && !threads.Contains(Environment.CurrentManagedThreadId),
            "pushes are raised on the runtime's control thread");
        Console.WriteLine("PASS native overlay runtime pushes each distinct state once, on its control thread");
    }

    private static void Check(bool condition, string message) { if (!condition) throw new Exception(message); }
}
