using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Presence;
using StarBridge.NativeBridge;

// The 0.7.2 release installs no keyboard hook (user decision 2026-10-31). A file
// left by an earlier build stays on disk untouched and cannot turn anything on.
internal static class SafeHotkeyPreferencesTests
{
    private const string OldFile = "desktop.safe-hotkeys.json";

    internal static void Run()
    {
        // Release runs have no debug root; the store only needs a private scratch folder.
        var root = Environment.GetEnvironmentVariable("STARBRIDGE_DEBUG_DATA_ROOT") ?? Path.GetTempPath();
        var directory = Path.Combine(root, "safe-hotkeys-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(directory);
        var store = new OverlayWorkspaceStore(directory);
        var before = store.Load();
        foreach (var old in new[] { "{\"safeHotkeys\":true}", "{\"safeHotkeys\":false}", "{\"safeHotkeys\":\"false\"}", "not json" })
        {
            var path = Path.Combine(directory, OldFile);
            File.WriteAllText(path, old);
            var current = store.Load();
            Check(current.Revision == before.Revision, "old file does not change the workspace: " + old);
            before = store.Apply(new(current.Revision, OverlayWorkspaceMutationKind.SaveActive,
                Settings: current.Settings, Layout: current.Layout, RenderMode: current.RenderMode, Hotkey: current.Hotkey));
            Check(File.ReadAllText(path) == old, "saving never rewrites the old file: " + old);
        }
        RegisterChoice(Path.Combine(root, "register-" + Guid.NewGuid().ToString("N")));
        Wire(Path.Combine(root, "safe-wire-" + Guid.NewGuid().ToString("N"))).GetAwaiter().GetResult();
    }

    // UseRegisteredHotkey is an explicit choice: an upgrade, an old file or a damaged file leaves it off.
    private static void RegisterChoice(string directory)
    {
        Directory.CreateDirectory(directory);
        var file = Path.Combine(directory, "desktop.registered-hotkey.json");
        File.WriteAllText(Path.Combine(directory, OldFile), "{\"safeHotkeys\":true}");
        var store = new OverlayWorkspaceStore(directory);
        var current = store.Load();
        Check(current.Hotkey.UseRegisteredHotkey == false, "an upgrade starts with UseRegisteredHotkey off");
        foreach (var bad in new[] { "not json", "{}", "[]", "{\"registerHotKey\":\"true\"}", "{\"registerHotKey\":1}" })
        {
            File.WriteAllText(file, bad);
            Check(store.Load().Hotkey.UseRegisteredHotkey == false, "anything but true stays off: " + bad);
        }
        File.Delete(file);
        current = store.Load();
        current = store.Apply(new(current.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: current.Settings,
            Layout: current.Layout, RenderMode: current.RenderMode, Hotkey: current.Hotkey with { UseRegisteredHotkey = true }));
        Check(new OverlayWorkspaceStore(directory).Load().Hotkey.UseRegisteredHotkey == true, "the explicit choice persists");
        current = store.Apply(new(current.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: current.Settings,
            Layout: current.Layout, RenderMode: current.RenderMode, Hotkey: current.Hotkey with { UseRegisteredHotkey = null }));
        Check(current.Hotkey.UseRegisteredHotkey == true, "a save without the field keeps the choice");
        current = store.Apply(new(current.Revision, OverlayWorkspaceMutationKind.SaveActive, Settings: current.Settings,
            Layout: current.Layout, RenderMode: current.RenderMode, Hotkey: current.Hotkey with { UseRegisteredHotkey = false }));
        Check(new OverlayWorkspaceStore(directory).Load().Hotkey.UseRegisteredHotkey == false, "it can be turned off again");
    }

    private static async Task Wire(string directory)
    {
        Directory.CreateDirectory(directory);
        File.WriteAllText(Path.Combine(directory, OldFile), "{\"safeHotkeys\":true}");
        var runtime = new Runtime();
        using var bridge = new OverlayBridgeDispatcher(directory, () => 1,
            () => GameLogSessionSnapshot.Empty, runtime);
        async Task<BridgeEnvelope> Send(string name, object payload) =>
            (await bridge.DispatchAsync(BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), 1, payload))).Response;
        var read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
        Check(!read.Payload.GetProperty("hotkey").TryGetProperty("safeHotkeys", out _), "workspace reports no safe hotkey choice");
        Check(!read.Payload.GetProperty("hotkey").GetProperty("registerHotKey").GetBoolean(), "workspace reports UseRegisteredHotkey off by default");
        object Save(object hotkey) => new
        {
            schemaVersion = 1, action = "saveActive", expectedRevision = read.Payload.GetProperty("revision").GetInt64(),
            settings = read.Payload.GetProperty("settings"), layout = read.Payload.GetProperty("layout"),
            renderMode = "DirectComposition", hotkey
        };
        foreach (var value in new[] { true, false })
        {
            var rejected = await Send("overlay.updateWorkspace", Save(new { binding = "Alt+O", enabled = true, safeHotkeys = value }));
            Check(rejected.Status != "ok" && runtime.Workspace is null, "settings cannot send the field: " + value);
        }
        var saved = await Send("overlay.updateWorkspace", Save(new { binding = "Alt+O", enabled = true }));
        Check(saved.Status == "ok" && runtime.Workspace?.UseRegisteredHotkey == false, "a normal hotkey save still works and stays on Raw Input");
        read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
        saved = await Send("overlay.updateWorkspace", Save(new { binding = "Alt+O", enabled = true, registerHotKey = true }));
        Check(saved.Status == "ok" && runtime.Workspace?.UseRegisteredHotkey == true, "the choice reaches the runtime immediately");
        read = await Send("overlay.getWorkspace", new { schemaVersion = 1 });
        Check(read.Payload.GetProperty("hotkey").GetProperty("registerHotKey").GetBoolean(), "the workspace reports the saved choice");
        var invalid = await Send("overlay.updateWorkspace", Save(new { binding = "Alt+O", enabled = true, registerHotKey = "yes" }));
        Check(invalid.Status != "ok", "a non-boolean choice is rejected");
        var status = await Send("overlay.runtime.getState", new { schemaVersion = 1 });
        Check(status.Payload.GetProperty("hotkeyRegistrationFailures").GetString() == "Ctrl+Alt+Y", "the runtime reports which shortcuts could not register");
        foreach (var field in new[] { "safeHotkeys", "hotkeyMode", "hotkeyFallbackReason", "hotkeyHealth", "hotkeyMessage" })
            Check(!status.Payload.TryGetProperty(field, out _), "runtime reports no " + field);
        Check(!OverlayBridgeDispatcher.AdvertisedCapabilities.Contains("hotkeys.safe") &&
            OverlayBridgeDispatcher.AdvertisedCapabilities.Contains("hotkeys.temporary"), "only the temporary route capability remains");
    }

    private sealed class Runtime : IInformationOverlayRuntime, ISafeHotkeyRuntime
    {
        internal InformationOverlayRuntimeWorkspace? Workspace;
        public string? HotkeyRegistrationFailures => "Ctrl+Alt+Y";
        public event Action<int, long>? HostHotkeyTriggered { add { } remove { } }
        public ValueTask ConfigureHostHotkeyAsync(int commandId, string? binding, long lease, CancellationToken cancellationToken = default)
            => ValueTask.CompletedTask;
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
        {
            Workspace = workspace;
            return ValueTask.FromResult(InformationOverlayRuntimeSnapshot.Unavailable);
        }
        public ValueTask ConfigureTemporaryHotkeyAsync(int commandId, string? binding, CancellationToken cancellationToken = default)
            => ValueTask.CompletedTask;
        public void Dispose() { }
    }

    private static void Check(bool condition, string label)
    {
        if (!condition) throw new Exception("FAIL " + label);
        Console.WriteLine("PASS " + label);
    }
}
