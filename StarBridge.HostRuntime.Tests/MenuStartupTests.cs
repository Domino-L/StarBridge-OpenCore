using System.Text.Json;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class MenuStartupTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-menu-startup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        var path = Path.Combine(root, "menu-preferences.v1.json");
        var a = new string('a', 32);
        var b = new string('b', 32);
        void Require(bool value, string label) { if (!value) throw new Exception(label); }
        JsonElement Arm(JsonElement original, bool value) {
            var data = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(original.GetRawText())!;
            data["safeModeNextLaunch"] = JsonSerializer.SerializeToElement(value);
            data["restoreDesktop"] = JsonSerializer.SerializeToElement(true);
            return JsonSerializer.SerializeToElement(data);
        }
        try
        {
            var store = new MenuPreferencesStore(root);
            Require(!store.BeginStartup(a) && !File.Exists(path), "normal startup does not create or rewrite a document");
            var current = store.Read();
            var layout = JsonSerializer.SerializeToElement(new { version = 1,
                panels = new[] { new { id = "browser", bounds = new[] { 20d, 40, 500, 350 } } }, open = new[] { "friends", "browser" } });
            store.Save(current.Revision, layout, Arm(current.Settings, true));
            var raw = File.ReadAllText(path);
            Require(!store.BeginStartup(a) && raw == File.ReadAllText(path), "arming during this session waits for the next app start");
            try { store.BeginStartup(b); throw new Exception("substitute startup owner accepted"); }
            catch (ApplicationPreferencesException) { }
            var next = new MenuPreferencesStore(root);
            next.SaveHotkey(1, new("Ctrl+Alt+F8", false, false));
            var before = next.Read();
            File.SetAttributes(path, FileAttributes.ReadOnly);
            try { next.BeginStartup(b); throw new Exception("failed durable consume reported success"); }
            catch (Exception error) when (error is IOException or UnauthorizedAccessException) { }
            Require(File.ReadAllText(path) == JsonSerializer.Serialize(before, BridgeProtocol.JsonOptions), "failed consume keeps armed flag and layout");
            File.SetAttributes(path, FileAttributes.Normal);
            Require(next.BeginStartup(b), "retry activates only after durable consumption");
            var consumed = next.Read();
            Require(consumed.Revision == 3 && !consumed.Settings.GetProperty("safeModeNextLaunch").GetBoolean() &&
                consumed.Layout.GetRawText() == before.Layout.GetRawText() && consumed.Hotkey == before.Hotkey,
                "one-shot consume increments CAS revision and keeps layout, order and shortcut");
            Require(new MenuPreferencesStore(root).BeginStartup(b), "reply loss and Host replacement recover the durable receipt");
            var after = new MenuPreferencesStore(root);
            Require(!after.BeginStartup(a), "new app process does not reuse previous safe session");
            after.Save(consumed.Revision, consumed.Layout, Arm(consumed.Settings, true));
            Require(!after.BeginStartup(a) && after.Read().Settings.GetProperty("safeModeNextLaunch").GetBoolean(), "arming again does not change running-session result");
            Require(new MenuPreferencesStore(root).BeginStartup(b) && new MenuPreferencesStore(root).Read().Settings.GetProperty("safeModeNextLaunch").GetBoolean(), "old receipt does not consume newly armed flag");
            foreach (var bad in new[] { "null", "1", "\"true\"" }) {
                var value = after.Read();
                using var document = JsonDocument.Parse(value.Settings.GetRawText().Replace("\"safeModeNextLaunch\":true", "\"safeModeNextLaunch\":" + bad));
                try { after.Save(value.Revision, value.Layout, document.RootElement); throw new Exception("invalid startup flag accepted"); }
                catch (ArgumentException) { }
            }
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 5);
            foreach (var request in new[] {
                BridgeEnvelope.Request("applicationPreferences.menu.startup", "stale", 4, new { schemaVersion = 1, token = a }),
                BridgeEnvelope.Request("applicationPreferences.menu.startup", "extra", 5, new { schemaVersion = 1, token = a, account = "forbidden" }),
                BridgeEnvelope.Request("applicationPreferences.menu.startup", "invalid", 5, new { schemaVersion = 1, token = "bad" }),
                BridgeEnvelope.Request("applicationPreferences.menu.startup", "account", 5, new { schemaVersion = 1, token = a }, new("test", "synthetic", "synthetic-account")) }) {
                var original = File.ReadAllText(path);
                Require((await dispatcher.DispatchAsync(request)).Response.Status != "ok" && original == File.ReadAllText(path), "invalid startup intent cannot consume settings");
            }
            var reply = await dispatcher.DispatchAsync(BridgeEnvelope.Request("applicationPreferences.menu.startup", "valid", 5, new { schemaVersion = 1, token = new string('c', 32) }));
            Require(reply.Response.Status == "ok" && reply.Response.Payload.GetProperty("safe").GetBoolean() && reply.Response.AccountContext is null, "real dispatcher consumes only bounded local startup intent");
            using var saved = JsonDocument.Parse(File.ReadAllText(path));
            Require(saved.RootElement.GetProperty("startup").EnumerateObject().Select(p => p.Name).Order().SequenceEqual(new[] { "safe", "token" }), "receipt contains no account, source, URL, draft or image");
            Require(!BridgeRequestPolicy.RequiresAccountContext("applicationPreferences.menu.startup"), "startup does not require account credentials");
            var validFile = File.ReadAllText(path);
            foreach (var invalidReceipt in new[] {
                "{\"token\":\"bad\",\"safe\":true}",
                "{\"token\":\"" + a + "\",\"safe\":true,\"account\":\"forbidden\"}",
                "{\"token\":\"" + a + "\",\"safe\":1}" }) {
                var content = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(validFile)!;
                using var invalid = JsonDocument.Parse(invalidReceipt);
                content["startup"] = invalid.RootElement.Clone();
                var corrupted = JsonSerializer.Serialize(content);
                File.WriteAllText(path, corrupted);
                var rejected = new MenuPreferencesStore(root).Read();
                // JsonElement equality is document identity, not JSON content.
                Require(rejected.Revision == 0 && rejected.Startup is null &&
                    rejected.Layout.GetRawText() == MenuPreferencesStore.Default.Layout.GetRawText() &&
                    rejected.Settings.GetRawText() == MenuPreferencesStore.Default.Settings.GetRawText() && File.ReadAllText(path) == corrupted,
                    "data-bearing or malformed receipt is refused without rewriting file");
            }
            Console.WriteLine("PASS menu one-shot startup, durable reply recovery, ownership, save failure, strict intent and preserved layout");
        }
        finally
        {
            if (File.Exists(path)) File.SetAttributes(path, FileAttributes.Normal);
            Directory.Delete(root, true);
        }
    }
}
