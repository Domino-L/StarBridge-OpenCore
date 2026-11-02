using System.Reflection;
using StarBridge.Core.Overlay;

namespace StarBridge.Desktop.Tests;

/// <summary>
/// Field report 2026-10-18: right after opening, every module read "unavailable"
/// for a while. Sources whose authorization lapsed while the overlay was closed are
/// being re-read; until a module has shown data since opening it reads "Syncing <source>…".
/// A lapse after it has shown data stays a real "unavailable".
/// </summary>
internal static class OverlayModuleSyncTests
{
    private static readonly OverlayModuleEmptyState Unavailable = new("You are not in a room");

    internal static void RunAll()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        var flags = BindingFlags.NonPublic | BindingFlags.Instance;
        var start = typeof(NativeInformationOverlayRuntime).GetMethod("StartModuleSync", flags)!;
        var apply = typeof(NativeInformationOverlayRuntime).GetMethod("ApplyModuleSync", flags)!;
        OverlayModulePresentation Apply(OverlayModulePresentation modules, DateTimeOffset at) =>
            (OverlayModulePresentation)apply.Invoke(runtime, [modules, "en", at])!;

        var opened = DateTimeOffset.UtcNow;
        start.Invoke(runtime, [(DateTimeOffset?)opened]);
        var first = Apply(Modules(available: false), opened.AddSeconds(1));
        Check(first.Members.EmptyMessage == new OverlayModuleEmptyState("Syncing Room fixture…", OverlayModuleEmptyKind.Syncing) &&
            first.Chat.EmptyMessage?.Headline == "Syncing Room fixture…",
            "modules without data since opening read as syncing their own named source, not unavailable");
        Check(first.NextValidationAt == opened + NativeInformationOverlayRuntime.ModuleSyncWindow,
            "the end of the sync window schedules a re-check");

        var shown = Apply(Modules(available: true), opened.AddSeconds(2));
        Check(shown.Members.EmptyMessage is null, "available modules carry no message");
        var lapsed = Apply(Modules(available: false), opened.AddSeconds(3));
        Check(lapsed.Members.EmptyMessage == Unavailable,
            "a module that already showed data reports a later lapse as unavailable");

        start.Invoke(runtime, [(DateTimeOffset?)opened]);
        var late = Apply(Modules(available: false), opened + NativeInformationOverlayRuntime.ModuleSyncWindow + TimeSpan.FromSeconds(1));
        Check(late.Members.EmptyMessage == Unavailable && late.NextValidationAt is null,
            "after the sync window an unread source reports its real state");

        start.Invoke(runtime, [(DateTimeOffset?)null]);
        Check(Apply(Modules(available: false), opened).Members.EmptyMessage == Unavailable,
            "with no window open there is no syncing state");
        Console.WriteLine("PASS overlay modules read as syncing only until they first show data after opening");
        StandbyDemandNeedsGameShownAndClosed();
    }

    // Background renewal needs all of: game running, HUD shown this run, HUD not
    // shown now, and a module-source display intent.
    private static void StandbyDemandNeedsGameShownAndClosed()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        var type = typeof(NativeInformationOverlayRuntime);
        var flags = BindingFlags.NonPublic | BindingFlags.Instance;
        void Set(string field, object? value) => type.GetField(field, flags)!.SetValue(runtime, value);
        Check(!runtime.HasStandbyDemand, "a fresh runtime does not renew anything");
        Set("_standbyGameRunning", true);
        Set("_moduleDemand", new StarBridge.HostRuntime.Overlay.InformationOverlayModuleDemand(
            OverlayPresetSources.Default, [OverlaySourceModule.Members]));
        Check(!runtime.HasStandbyDemand, "a HUD never shown this run is not in use");
        Set("_shownThisRun", true);
        Check(runtime.HasStandbyDemand && !runtime.HasDisplayDemand, "closed HUD with the game running renews in the background");
        Set("_standbyGameRunning", false);
        Check(!runtime.HasStandbyDemand, "renewal stops when the game is not running");
        Set("_standbyGameRunning", true);
        Set("_moduleDemand", null);
        Check(!runtime.HasStandbyDemand, "without module-source intent there is nothing to renew");
        Console.WriteLine("PASS overlay background renewal only while the game runs and the used HUD is closed");
    }

    private static OverlayModulePresentation Modules(bool available)
    {
        var scene = new OverlayModuleScene(
            new OverlaySceneSnapshot([], available, OverlaySceneContext.Local(OverlayScenePreference.Auto)),
            new OverlayCommandState(null, null, null, null, null, null), [], "Room fixture", available, available ? "room" : null)
        { EmptyMessage = available ? null : Unavailable };
        return new OverlayModulePresentation(scene, scene, scene, scene, scene, "fixture");
    }

    private static void Check(bool result, string message) { if (!result) throw new Exception(message); }
}
