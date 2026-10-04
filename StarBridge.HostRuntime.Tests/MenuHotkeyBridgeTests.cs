using StarBridge.HostRuntime.Overlay;
using StarBridge.NativeBridge;
using StarBridge.HostRuntime.Settings;

internal static class MenuHotkeyBridgeTests
{
    internal static async Task Run()
    {
        (string? OwnerKey, long Generation) scope = ("synthetic", 2);
        var runtime = new Runtime();
        Require(!BridgeRequestPolicy.RequiresAccountContext("menuHotkey.attach"), "shared protocol policy");
        long sequence = 80;
        using var dispatcher = new MenuHotkeyBridgeDispatcher(runtime, () => scope,
            (generation, payload) => BridgeEnvelope.Event("menuHotkey.intent", generation, ++sequence, payload), 42);
        var events = new List<BridgeEnvelope>();
        dispatcher.EventReady += events.Add;
        BridgeEnvelope Request(string name, object body, long generation = 2) =>
            BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), generation, body);
        object Attach(long client) => new { schemaVersion = 1, client, binding = "Alt+M", enabled = true, closeWithHotkey = true };
        async Task<string?> Send(string name, object body, long generation = 2) =>
            (await dispatcher.DispatchAsync(Request(name, body, generation))).Response.Status;
        Require(await Send("menuHotkey.attach", Attach(1)) == "ok", "attach");
        var old = runtime.Registration!;
        Require(old.ClientProcessId == 42 && old.IsCurrent(), "scope and parent PID are Host-owned");
        old.Trigger(new("open", 0, 44, 66));
        Require(events.Count == 1 && events[0].Sequence == 81, "shared event factory");
        Require(await Send("menuHotkey.window", new { schemaVersion = 1, client = 1, request = 5, phase = "opening", window = 0 }) == "ok", "window routing");
        Require(runtime.WindowUpdates == 1, "one update");
        Require(!dispatcher.IsMenuVisible, "opening is not visible");
        async Task Window(long request, string phase, long window = 44) =>
            Require(await Send("menuHotkey.window", new { schemaVersion = 1, client = 1, request, phase, window }) == "ok", "presentation observation");
        await Window(5, "visible", 0);
        Require(!dispatcher.IsMenuVisible, "zero window is not visible");
        await Window(5, "visible");
        Require(dispatcher.IsMenuVisible, "current visible menu observed");
        await Window(4, "closed");
        Require(dispatcher.IsMenuVisible, "late old close cannot hide current menu");
        await Window(5, "closed");
        await Window(5, "visible");
        Require(!dispatcher.IsMenuVisible, "closed opening cannot resurrect");
        await Window(6, "visible");
        Require(dispatcher.IsMenuVisible, "new opening can become visible");
        Require(await Send("menuHotkey.attach", Attach(3)) == "ok", "replace primary");
        Require(!dispatcher.IsMenuVisible, "new primary does not inherit visibility");
        Require(!old.IsCurrent(), "old primary synchronously revoked");
        old.Trigger(new("open", 0, 44, 66));
        Require(events.Count == 1, "late old callback rejected");
        Require(await Send("menuHotkey.detach", new { schemaVersion = 1, client = 1 }) == "error", "old detach rejected");
        Require(runtime.Registration!.IsCurrent(), "new owner survives old detach");
        Require(await Send("menuHotkey.attach", Attach(2)) == "error", "late attach rejected");
        Require(await Send("menuHotkey.window", new { schemaVersion = 1, client = 3, request = 6, phase = "visible", window = 44, token = "synthetic" }) == "error", "arbitrary data rejected");
        var active = runtime.Registration!;
        scope = (null, 3);
        Require(!dispatcher.IsMenuVisible, "logout never retains menu visibility");
        Require(!active.IsCurrent(), "logout revokes before asynchronous cleanup");
        active.Trigger(new("close", 5, 0, 0));
        Require(events.Count == 1, "no event after logout");
        dispatcher.Invalidate();
        Require(await Send("menuHotkey.attach", Attach(4), 3) == "error", "unsigned owner cannot attach");
        scope = ("second-synthetic", 4);
        Require(await Send("menuHotkey.attach", Attach(4), 2) == "error", "old generation rejected");
        Require(await Send("menuHotkey.attach", Attach(4), 4) == "ok", "new account");
        active.Trigger(new("open", 0, 44, 66));
        Require(events.Count == 1, "old account callback cannot reopen");
        Require(await Send("menuHotkey.detach", new { schemaVersion = 1, client = 4 }, 4) == "ok", "detach");
        Require(runtime.Registration is null, "native listener revoked");
        Require(await Send("menuHotkey.attach", Attach(4), 4) == "error", "detached client cannot resurrect");
        runtime.FailConfiguration = true;
        Require(await Send("menuHotkey.attach", Attach(5), 4) == "error", "failed native attach is reported");
        Require(runtime.LastRegistration?.IsCurrent() == false, "failed attach leaves no authority");
        runtime.FailConfiguration = false;
        using var cancelled = new CancellationTokenSource();
        cancelled.Cancel();
        Require((await dispatcher.DispatchAsync(Request("menuHotkey.attach", Attach(6), 4), cancelled.Token)).Response.Status == "cancelled",
            "cancelled request cannot attach");
        Require(await Send("menuHotkey.attach", Attach(6), 4) == "ok", "retry after failure");
        var final = runtime.Registration!;
        dispatcher.Dispose();
        Require(!final.IsCurrent(), "dispose revokes callbacks synchronously");
        await SettingsTransactions();
        Console.WriteLine("PASS menu hotkey Host scope, generation, event sequence, replacement and revocation");
    }
    private static async Task SettingsTransactions()
    {
        var store = new Preferences();
        var runtime = new Runtime();
        using var dispatcher = new MenuHotkeyBridgeDispatcher(runtime, () => ("fixture", 1),
            (g, p) => BridgeEnvelope.Event("menuHotkey.intent", g, 1, p), 42, store);
        async Task<BridgeEnvelope> Send(string name, object payload) => (await dispatcher.DispatchAsync(
            BridgeEnvelope.Request(name, Guid.NewGuid().ToString(), 1, payload))).Response;
        object Edit(long revision, string binding, bool enabled = true) =>
            new { schemaVersion = 1, client = 1, expectedRevision = revision, binding, enabled, closeWithHotkey = false };
        Require((await Send("menuHotkey.attach", new { schemaVersion = 1, client = 1, binding = "Alt+M", enabled = true, closeWithHotkey = true })).Status == "ok", "persistent attach");
        Require(runtime.Registration!.Binding == "F9", "startup consumes saved settings, not renderer defaults");
        var previous = runtime.Registration;
        Require((await Send("menuHotkey.settings.update", Edit(4, "F10"))).Status == "ok", "valid edit saved");
        Require(store.Value.Options.Binding == "F10" && store.Value.Revision == 5, "commit advances one revision");
        Require(runtime.Registration!.SharesSessionWith(previous) && runtime.Registration.IsCurrent(), "edit retains menu ownership");
        previous = runtime.Registration;
        Require((await Send("menuHotkey.settings.update", Edit(4, "F11"))).Error?.Code == "menuPreferences.revision_conflict", "stale CAS rejected");
        Require(ReferenceEquals(previous, runtime.Registration), "stale CAS never touches runtime");
        runtime.RejectedBinding = "F12";
        Require((await Send("menuHotkey.settings.update", Edit(5, "F12"))).Error?.Code == "menuHotkey.conflictWithInformation", "native policy reports conflict");
        Require(ReferenceEquals(previous, runtime.Registration) && store.Value.Revision == 5, "conflict restores working key without write");
        store.FailSave = true;
        Require((await Send("menuHotkey.settings.update", Edit(5, "F11"))).Status == "error", "disk failure reported");
        Require(ReferenceEquals(previous, runtime.Registration) && store.Value.Revision == 5, "disk failure rolls back runtime");
        store.FailSave = false;
        Require((await Send("menuHotkey.settings.update", Edit(5, "F11", false))).Status == "ok", "disable persists");
        var read = await Send("menuHotkey.settings.get", new { schemaVersion = 1, client = 1 });
        Require(read.Payload.GetProperty("state").GetString() == "disabled" && read.Payload.GetProperty("revision").GetInt64() == 6, "read returns committed settings and actual state");
        Require((await Send("menuHotkey.settings.get", new { schemaVersion = 1, client = 1, token = "not-allowed" })).Status == "error", "get rejects extra fields");
        Require(!BridgeRequestPolicy.RequiresAccountContext("menuHotkey.settings.update"), "settings use Host-owned current scope");
    }
    private sealed class Preferences : IMenuHotkeyPreferences
    {
        internal MenuHotkeyPreferences Value = new(4, new("F9"));
        internal bool FailSave;
        public MenuHotkeyPreferences ReadHotkey() => Value;
        public MenuHotkeyPreferences SaveHotkey(long expectedRevision, MenuHotkeyOptions options)
        {
            if (FailSave) throw new IOException("synthetic disk failure");
            if (expectedRevision != Value.Revision) throw new InvalidOperationException("stale");
            return Value = new(Value.Revision + 1, options);
        }
    }
    private static void Require(bool condition, string name) { if (!condition) throw new Exception(name); }
    private sealed class Runtime : IMenuHotkeyRuntime
    {
        public MenuHotkeyRegistration? Registration;
        public MenuHotkeyRegistration? LastRegistration;
        public bool FailConfiguration;
        public string? RejectedBinding;
        public int WindowUpdates;
        public ValueTask<string> ConfigureMenuHotkeyAsync(MenuHotkeyRegistration? registration, CancellationToken cancellationToken = default)
        {
            Registration = registration;
            if (registration != null)
            {
                LastRegistration = registration;
                if (FailConfiguration) throw new InvalidOperationException("synthetic native failure");
            }
            return ValueTask.FromResult(registration?.Binding == RejectedBinding && RejectedBinding is not null
                ? "conflictWithInformation" : registration?.Enabled == false ? "disabled" : "registered");
        }
        public ValueTask UpdateMenuWindowAsync(MenuHotkeyRegistration registration, long request, string phase, long window, CancellationToken cancellationToken = default)
        { WindowUpdates++; return ValueTask.CompletedTask; }
    }
}
