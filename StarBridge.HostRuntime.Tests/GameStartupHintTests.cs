using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Notifications;
using StarBridge.NativeBridge;

internal static class GameStartupHintTests
{
    internal static async Task Run()
    {
        var checks = 0;
        void Check(bool value, string reason) { checks++; if (!value) throw new Exception(reason); }
        var now = DateTimeOffset.UtcNow;
        var session = new GameStartupSession("notRunning");
        var reads = 0;
        var ready = false;
        var binding = "Alt+M";
        var sink = new Sink();
        using var hint = new GameStartupHintRuntime(() => { reads++; return session; },
            () => ready ? new(binding, () => ready) : null, sink, () => ("zh-CN", "dark", true), () => now);
        await hint.TickAsync(); Check(sink.Calls == 0, "No hint outside the game");
        session = new("unknown"); await hint.TickAsync(); Check(sink.Calls == 0, "Unknown process state cannot become a launch");
        session = new("running", 42); await hint.TickAsync(); Check(sink.Calls == 0, "Never advertise an unregistered shortcut");
        ready = true; sink.Allowed = false; await hint.TickAsync(); Check(sink.Calls == 1, "A denied background attempt is not delivered");
        sink.Allowed = true; binding = "Ctrl+Shift+M"; await hint.TickAsync();
        Check(sink.Notice?.GameStartupHint is { Binding: "Ctrl+Shift+M", ProcessId: 42 }, "Use current saved/registered shortcut and actual session PID");
        var shown = sink.Calls;
        await hint.TickAsync(); Check(sink.Calls == shown, "One hint per game launch, not every foreground change");
        var old = sink.Notice!; ready = false; Check(!old.IsCurrent(), "Owner revocation immediately retires visible content"); ready = true;
        session = new("unknown"); await hint.TickAsync(); session = new("running", 42); await hint.TickAsync();
        Check(sink.Calls == shown, "Transient unknown state does not repeat the same launch hint");
        session = new("notRunning"); await hint.TickAsync(); session = new("running", 42); await hint.TickAsync();
        Check(sink.Calls == shown + 1, "Observed game exit permits a new launch including reused PID");
        session = new("running", 43, now); ready = false; await hint.TickAsync(); now = now.AddMinutes(6); ready = true; await hint.TickAsync();
        Check(sink.Calls == shown + 1, "Do not replay an old startup hint after a long unavailable registration");
        var before = reads; ready = false; await hint.TickAsync(); await hint.TickAsync();
        Check(reads == before, "Without a usable shortcut the process list is not read"); ready = true;
        session = new("running", 45, now.AddMinutes(-1)); await hint.TickAsync();
        Check(sink.Notice?.GameStartupHint is { ProcessId: 45 } && sink.Calls == shown + 2, "A launch one minute ago still gets its hint");
        session = new("running", 45); await hint.TickAsync();
        Check(sink.Calls == shown + 2, "An unknown start time does not split one launch into two");
        session = new("running", 45, now); await hint.TickAsync();
        Check(sink.Calls == shown + 3, "A reused PID with a new start time is a new launch even without an observed exit");
        session = new("running", 46, now.AddMinutes(-6)); ready = false; await hint.TickAsync(); ready = true; await hint.TickAsync();
        Check(sink.Calls == shown + 3, "A launch older than five minutes, first seen once the shortcut works, is not advertised");
        session = new("running", 47, now.AddMinutes(1)); await hint.TickAsync();
        Check(sink.Calls == shown + 4, "A start time ahead of this clock is timed from now");
        session = new("running", 60); await hint.TickAsync(); var count = sink.Calls;
        session = new("running", 60, now.AddMinutes(-1)); await hint.TickAsync();
        Check(sink.Calls == count, "A start time read late does not repeat the hint");
        session = new("running", 60, now); await hint.TickAsync();
        Check(sink.Calls == count + 1, "Once learned, the start time tells a reused PID apart");
        sink.Allowed = false; session = new("running", 61); await hint.TickAsync(); count = sink.Calls;
        sink.Allowed = true; session = new("running", 61, now.AddMinutes(-10)); await hint.TickAsync();
        Check(sink.Calls == count, "A launch found to be ten minutes old is no longer advertised");
        session = new("running", 44, now); await hint.TickAsync(); old = sink.Notice!; hint.Dispose(); Check(!old.IsCurrent(), "Disposal revokes pending and visible grants");

        (string? OwnerKey, long Generation) scope = ("fixture", 2);
        var native = new Runtime();
        using var bridge = new MenuHotkeyBridgeDispatcher(native, () => scope,
            (generation, body) => BridgeEnvelope.Event("menuHotkey.intent", generation, 1, body), 99, menuWindowShown: _ => true);
        Check(bridge.ReadGameStartupHint() is null, "No grant before primary attachment");
        BridgeEnvelope Request(long client, string key, bool enabled = true) => BridgeEnvelope.Request("menuHotkey.attach", Guid.NewGuid().ToString("N"), 2,
            new { schemaVersion = 1, client, binding = key, enabled, closeWithHotkey = true });
        native.State = "failed"; await bridge.DispatchAsync(Request(1, "Alt+M")); Check(bridge.ReadGameStartupHint() is null, "Failed raw input registration cannot claim ready");
        native.State = "registered"; await bridge.DispatchAsync(Request(2, "F9"));
        var grant = bridge.ReadGameStartupHint()!; Check(grant.Binding == "F9" && grant.IsCurrent(), "Grant reads actual registered custom chord");
        await bridge.DispatchAsync(BridgeEnvelope.Request("menuHotkey.window", Guid.NewGuid().ToString("N"), 2,
            new { schemaVersion = 1, client = 2, request = 1, phase = "visible", window = 77 }));
        Check(!grant.IsCurrent() && bridge.ReadGameStartupHint() is null, "Opening menu hides or suppresses its usage hint");
        await bridge.DispatchAsync(Request(3, "F10", false)); Check(bridge.ReadGameStartupHint() is null, "Disabled menu shortcut never gets a startup hint");
        await bridge.DispatchAsync(Request(4, "F10")); grant = bridge.ReadGameStartupHint()!; scope = (null, 3);
        Check(!grant.IsCurrent() && bridge.ReadGameStartupHint() is null, "Generation/logout immediately revokes shortcuts advertised on screen");
        Console.WriteLine($"PASS game startup hint: {checks} assertions; real shortcut, launch dedupe, foreground deferral, revocation and expiry");
    }
    private sealed class Sink : IDesktopNotificationSink
    {
        internal int Calls; internal bool Allowed = true; internal DesktopNotification? Notice;
        public ValueTask<bool> TryPresentAsync(DesktopNotification notification, CancellationToken token) { Calls++; Notice = notification; return ValueTask.FromResult(Allowed); }
        public void Clear() { }
        public void Dispose() { }
    }
    private sealed class Runtime : IMenuHotkeyRuntime
    {
        internal string State = "registered";
        public ValueTask<string> ConfigureMenuHotkeyAsync(MenuHotkeyRegistration? registration, CancellationToken token = default) => ValueTask.FromResult(State);
        public ValueTask UpdateMenuWindowAsync(MenuHotkeyRegistration registration, long request, string phase, long window, CancellationToken token = default) => ValueTask.CompletedTask;
    }
}
