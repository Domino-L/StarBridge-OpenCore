using System.Windows;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

// Real production STA/HWND lifecycle, offscreen, synthetic data only.
internal static class MenuHudLifecycleTests
{
    internal static async Task Run()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        var created = 0;
        runtime.BeforeWindowCreation = _ => created++;
        var current = true;
        var registration = new MenuHotkeyRegistration("Alt+M", false, true,
            Environment.ProcessId, () => current, _ => { });
        await runtime.ConfigureMenuHotkeyAsync(registration);
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                EnableStartupTransition = false, AutoFocusGameWindowOnOpen = false,
                AutoOpenOverlayOnGameStart = false, AutoOpenOverlayOnGameForeground = false,
                AutoCloseOverlayOnGameBackground = false
            }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "en");
        Task<InformationOverlayRuntimeSnapshot> Run(InformationOverlayRuntimeCommand command) =>
            runtime.ExecuteAsync(command, workspace).AsTask();
        Task Phase(long request, string phase) =>
            runtime.UpdateMenuWindowAsync(registration, request, phase, 0).AsTask();
        await Run(InformationOverlayRuntimeCommand.Sync);
        await Phase(1, "opening");
        await Phase(1, "closed");
        Check(created == 0 && !runtime.HasDisplayDemand, "menu alone cannot turn on disabled HUD");

        await Run(InformationOverlayRuntimeCommand.Open);
        Check(created == 1 && runtime.IsVisible, "initial real offscreen window");
        await Phase(2, "opening");
        Check(runtime.IsVisible && runtime.HasDisplayDemand, "menu opening keeps enabled HUD visible beneath menu");
        Check((await runtime.ReadStatusAsync()).WindowState == "open", "menu does not suppress HUD diagnostics");
        using var menuWindow = new MenuZOrderFixture();
        await runtime.UpdateMenuWindowAsync(registration, 2, "visible", menuWindow.Handle.ToInt64());
        await menuWindow.AssertAbove(runtime.TestWindowHandle);
        menuWindow.TryPromote(runtime.TestWindowHandle);
        await menuWindow.AssertAbove(runtime.TestWindowHandle);
        registration = registration with { Binding = "F8", CloseWithHotkey = false };
        await runtime.ConfigureMenuHotkeyAsync(registration);
        Check(runtime.IsVisible && runtime.HasDisplayDemand, "editing shortcut retains current menu and visible HUD");
        for (var i = 0; i < 3; i++)
            Check((await Run(InformationOverlayRuntimeCommand.Sync)).WindowState == "open",
                "ordinary sync preserves visible HUD");
        await Phase(1, "closed");
        Check(runtime.IsVisible, "stale close preserves HUD");
        await menuWindow.AssertAbove(runtime.TestWindowHandle);
        await Phase(2, "closed");
        Check(runtime.IsVisible && created == 1, "restore same HWND without startup replay");

        await Phase(3, "opening");
        await Run(InformationOverlayRuntimeCommand.Close);
        await Phase(3, "closed");
        Check(!runtime.IsVisible && !runtime.HasDisplayDemand, "explicit off wins over remembered state");
        await Phase(4, "opening");
        workspace = workspace with { Settings = workspace.Settings with { EnableStartupTransition = true } };
        var deferred = await Run(InformationOverlayRuntimeCommand.Open);
        Check(deferred.WindowState == "open" && deferred.IsVisible && created == 2,
            "explicit on inside menu creates visible HUD");
        Check(!runtime.TestStartupTransitionEnabled && workspace.Settings.EnableStartupTransition,
            "menu open suppresses only this opening's startup cover, not saved preference");
        await Phase(4, "closed");
        Check(runtime.IsVisible && created == 2, "deferred on opens when menu closes");

        await Phase(5, "opening");
        await Phase(6, "opening");
        await Phase(5, "closed");
        Check(runtime.IsVisible, "superseded close cannot change HUD visibility");
        await Phase(6, "closed");
        Check(runtime.IsVisible && created == 2, "replacement menu retains original restore intent");

        await Phase(7, "opening");
        current = false;
        runtime.RequestContentRefresh();
        var revoked = await Run(InformationOverlayRuntimeCommand.Sync);
        Check(revoked.WindowState == "closed" && !runtime.HasDisplayDemand, "revocation clears hidden HUD, not restores it");
        await Phase(7, "closed");
        Check(!runtime.IsVisible, "late revoked close has no authority");
        current = true;
        await runtime.ConfigureMenuHotkeyAsync(registration with { IsCurrent = () => true });
        await Run(InformationOverlayRuntimeCommand.Open);
        var replacement = registration with { IsCurrent = () => true };
        await runtime.ConfigureMenuHotkeyAsync(replacement);
        await runtime.UpdateMenuWindowAsync(replacement, 8, "opening", 0);
        await runtime.ConfigureMenuHotkeyAsync(null);
        Check(!runtime.IsVisible && !runtime.HasDisplayDemand, "detach destroys hidden session content");
        await runtime.UpdateMenuWindowAsync(replacement, 8, "closed", 0);
        Check(!runtime.IsVisible, "detached request cannot restore");
        await ColdOpenCannotEscapeMenu();
        Console.WriteLine("PASS real menu/HUD visibility, HWND stacking, explicit intent and stale/revoked session guards");
    }

    private static async Task ColdOpenCannotEscapeMenu()
    {
        var started = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        var ready = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        InformationOverlayCommunityContent? content = null;
        using var runtime = new NativeInformationOverlayRuntime(
            communityProvider: () => Volatile.Read(ref content), sceneModeProvider: () => "community",
            prepareCommunity: async _ => { started.TrySetResult(); await ready.Task; });
        runtime.TestSurfaceBounds = new Rect(-30000, -30000, 800, 600);
        var created = 0;
        runtime.BeforeWindowCreation = _ => created++;
        var menu = new MenuHotkeyRegistration("Alt+M", false, true, Environment.ProcessId, () => true, _ => { });
        await runtime.ConfigureMenuHotkeyAsync(menu);
        var workspace = new InformationOverlayRuntimeWorkspace(1, InformationOverlayDefaults.DefaultSettings with
        {
            EnableStartupTransition = false, AutoFocusGameWindowOnOpen = false,
            AutoOpenOverlayOnGameStart = false, AutoOpenOverlayOnGameForeground = false,
            AutoCloseOverlayOnGameBackground = false
        }, [], "Alt+O", false, GameLogSessionSnapshot.Empty, "en");
        Check((await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Open, workspace)).WindowState == "opening", "cold preparation pending");
        await started.Task.WaitAsync(TimeSpan.FromSeconds(2));
        await runtime.UpdateMenuWindowAsync(menu, 1, "opening", 0);
        Volatile.Write(ref content, new InformationOverlayCommunityContent("fixture", "Fixture", []));
        ready.SetResult();
        await Task.Delay(100); // Allow authorized cold preparation to finish.
        Check((await runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace)).WindowState == "open" && created == 1,
            "authorized cold open is not canceled by opening menu");
        await runtime.UpdateMenuWindowAsync(menu, 1, "closed", 0);
        Check(runtime.IsVisible && created == 1, "close resolves pending open using current authorized content");
    }

    private static void Check(bool value, string message)
    {
        if (!value) throw new InvalidOperationException(message);
    }
}
