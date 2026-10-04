using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;

namespace StarBridge.Desktop.Tests;

internal static class OverlaySharedHotkeyTests
{
    internal static void RunAll()
    {
        MenuPolicyUsesTheSharedWpfRules();
        SynchronizationDoesNotRestartTheListener();
        MenuRegistrationSharesTheExistingListener();
        Console.WriteLine("PASS shared menu hotkey policy and stable native listener configuration");
    }

    private static void MenuRegistrationSharesTheExistingListener()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        var current = true;
        var intents = new List<MenuHotkeyIntent>();
        var registration = new MenuHotkeyRegistration("Alt+M", true, true,
            Environment.ProcessId, () => current, intents.Add);
        string Configure(MenuHotkeyRegistration? value) => runtime.ConfigureMenuHotkeyAsync(value).AsTask().GetAwaiter().GetResult();
        Equal("registered", Configure(registration), "menu works without information workspace");
        var revision = runtime.HotkeyConfigurationRevision;
        Equal("registered", Configure(registration), "idempotent registration");
        Equal(revision, runtime.HotkeyConfigurationRevision, "same menu does not restart listener");
        var workspace = new InformationOverlayRuntimeWorkspace(1, InformationOverlayDefaults.DefaultSettings with
        {
            AutoOpenOverlayOnGameStart = false, AutoOpenOverlayOnGameForeground = false,
            AutoCloseOverlayOnGameBackground = false
        }, InformationOverlayDefaults.CreateLayout(null), "Alt+M", true, GameLogSessionSnapshot.Empty, "en");
        runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace).AsTask().GetAwaiter().GetResult();
        Equal("conflictWithInformation", Configure(registration), "information route wins chord conflict");
        runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace with { HotkeyEnabled = false }).AsTask().GetAwaiter().GetResult();
        Equal("registered", Configure(registration), "menu independent of information master switch");
        runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, workspace with { SourcePresetsEnabled = true }).AsTask().GetAwaiter().GetResult();
        Equal("registered", Configure(registration), "damaged information source cannot disable menu");
        current = false;
        Equal("disabled", Configure(registration), "revoked session cannot register");
        Equal("disabled", Configure(null), "detach");
        Equal(0, intents.Count, "configuration never itself opens menu");
    }

    private static void MenuPolicyUsesTheSharedWpfRules()
    {
        foreach (var (text, state) in new[]
        {
            ("Alt+M", OverlayHotkeyBindingState.Ready),
            ("F8", OverlayHotkeyBindingState.Ready),
            ("M", OverlayHotkeyBindingState.ModifierRequired),
            ("Alt+Tab", OverlayHotkeyBindingState.Reserved),
            ("Alt+F4", OverlayHotkeyBindingState.Reserved),
            ("Escape", OverlayHotkeyBindingState.Reserved),
            ("Ctrl+Alt+Delete", OverlayHotkeyBindingState.Reserved),
            ("not-a-key", OverlayHotkeyBindingState.Invalid),
            ("control + shift + f10", OverlayHotkeyBindingState.ConflictWithInformation)
        })
        {
            var plan = OverlayHotkeyBindingPolicy.Build("Ctrl+Shift+F10", true, text, true);
            Equal(state, plan.MenuState, text);
            var routes = plan.CreateGameCompatibleRoutes(11, 22);
            Equal(state == OverlayHotkeyBindingState.Ready ? 2 : 1, routes.Count, "route count");
            Equal(11, routes[0].CommandId, "menu validation cannot remove information route");
        }
        var menuOnly = OverlayHotkeyBindingPolicy.Build("Alt+M", false, "Alt+M", true);
        Equal(OverlayHotkeyBindingState.Ready, menuOnly.MenuState, "disabled information cannot conflict");
        Equal(22, menuOnly.CreateGameCompatibleRoutes(11, 22).Single().CommandId, "independent enablement");
        var invalidInformation = OverlayHotkeyBindingPolicy.Build("invalid", true, "Alt+M", true);
        Equal(22, invalidInformation.CreateGameCompatibleRoutes(11, 22).Single().CommandId, "invalid information cannot disable menu");
        var disabledMenu = OverlayHotkeyBindingPolicy.Build("F10", true, "Alt+M", false);
        Equal("Alt+M", disabledMenu.MenuHotkey?.StorageText, "retain configured chord for disabled settings display");
        Equal(1, disabledMenu.CreateGameCompatibleRoutes(11, 22).Count, "disabled menu emits no route");
        Equal(OverlayHotkeyBindingPolicy.Build("Ctrl+Shift+F10", true, "Alt+M", true),
            OverlayHotkeyBindingPolicy.Build("shift + control + F10", true, "alt + m", true),
            "semantically identical plans");

        var router = new GameCompatibleHotkeyTriggerRouter(
            OverlayHotkeyBindingPolicy.Build("F10", true, "Alt+M", true).CreateGameCompatibleRoutes(11, 22));
        var input = new GameCompatibleHotkeyInput(0x4d, GameCompatibleHotkeyModifiers.Alt, true, false);
        Equal(true, router.TryResolve(input, out var command), "menu input");
        Equal(22, command, "menu command");
        Equal(false, router.TryResolve(input, out _), "held key does not repeat");
        Equal(false, router.TryResolve(input with { IsKeyDown = false }, out _), "release");
        Equal(false, router.TryResolve(input with { IsInjected = true }, out _), "injected input rejected");
        Equal(true, router.TryResolve(new(0x79, 0, true, false), out command), "information route remains usable");
        Equal(11, command, "information command");
    }

    private static void SynchronizationDoesNotRestartTheListener()
    {
        using var runtime = new NativeInformationOverlayRuntime();
        var workspace = new InformationOverlayRuntimeWorkspace(1,
            InformationOverlayDefaults.DefaultSettings with
            {
                AutoOpenOverlayOnGameStart = false,
                AutoOpenOverlayOnGameForeground = false,
                AutoCloseOverlayOnGameBackground = false
            }, InformationOverlayDefaults.CreateLayout(null),
            "Ctrl+Alt+Shift+F11", true, GameLogSessionSnapshot.Empty, "en");
        InformationOverlayRuntimeSnapshot Sync(InformationOverlayRuntimeWorkspace value) =>
            runtime.ExecuteAsync(InformationOverlayRuntimeCommand.Sync, value).AsTask().GetAwaiter().GetResult();
        var initial = Sync(workspace);
        if (initial.HotkeyState is not ("registered" or "gameCompatibleOnly"))
            throw new InvalidOperationException("Raw-input listener unavailable: " + initial.HotkeyState);
        var revision = runtime.HotkeyConfigurationRevision;
        for (var index = 0; index < 12; index++)
        {
            Sync(workspace with { Revision = index + 2, HotkeyBinding = "shift + alt + control + f11" });
            Equal(revision, runtime.HotkeyConfigurationRevision, "source sync must retain listener and key-down state");
        }
        Sync(workspace with { HotkeyBinding = "Ctrl+Alt+Shift+F12" });
        Equal(++revision, runtime.HotkeyConfigurationRevision, "new chord reconfigures once");
        Equal("disabled", Sync(workspace with { HotkeyEnabled = false }).HotkeyState, "disable");
        Equal(++revision, runtime.HotkeyConfigurationRevision, "disable releases route");
        Sync(workspace with { HotkeyEnabled = false, HotkeyBinding = "F10" });
        Equal(revision, runtime.HotkeyConfigurationRevision, "disabled chord edit cannot register");
        Equal("invalid", Sync(workspace with { HotkeyBinding = "invalid" }).HotkeyState, "invalid state");
        Equal(++revision, runtime.HotkeyConfigurationRevision, "invalid transition");
        Sync(workspace with { HotkeyBinding = "also-invalid" });
        Equal(revision, runtime.HotkeyConfigurationRevision, "invalid refresh cannot restart listener");
        Sync(workspace);
        Equal(++revision, runtime.HotkeyConfigurationRevision, "re-enable");
        Sync(workspace with { SourcePresetsEnabled = true });
        Equal(++revision, runtime.HotkeyConfigurationRevision, "invalid preset disables information hotkey");
        // Retry must consult the effective plan, not the still-enabled setting.
        Thread.Sleep(TimeSpan.FromSeconds(6));
        Equal("disabled", runtime.ReadStatusAsync().AsTask().GetAwaiter().GetResult().HotkeyState,
            "invalid source cannot revive shortcut through background retry");
    }

    private static void Equal<T>(T expected, T actual, string context)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{context}: expected {expected}, got {actual}");
    }
}
