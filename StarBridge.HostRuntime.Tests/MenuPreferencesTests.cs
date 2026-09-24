using System.Text.Json;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class MenuPreferencesTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-menu-test-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var store = new MenuPreferencesStore(root);
            var initial = store.Read();
            var layout = JsonSerializer.SerializeToElement(new { version = 1, panels = new[] { new { id = "browser", bounds = new[] { 50d, 70, 800, 500 } } }, open = Array.Empty<string>() });
            var saved = store.Save(0, layout, initial.Settings);
            Require(saved.Revision == 1 && new MenuPreferencesStore(root).Read().Layout.GetProperty("panels").GetArrayLength() == 1, "persists geometry");
            try { store.Save(0, layout, initial.Settings); throw new Exception("stale revision accepted"); }
            catch (ApplicationPreferencesException) { }
            foreach (var bad in new[] {
                "{\"version\":1,\"panels\":[],\"open\":[\"friends\"]}",
                "{\"version\":1,\"panels\":[{\"id\":\"p1\",\"bounds\":[1,2,3,4]}],\"open\":[]}",
                "{\"version\":1,\"panels\":[{\"id\":\"browser\",\"bounds\":[1,2,-3,4]}],\"open\":[]}",
                "{\"version\":1,\"panels\":[],\"open\":[],\"account\":\"forbidden\"}"
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(1, document.RootElement, initial.Settings); throw new Exception("invalid document accepted"); }
                catch (ArgumentException) { }
            }
            Require(store.Read().Revision == 1, "invalid writes preserve file");
            var remembered = JsonSerializer.SerializeToElement(new { showClock = true, showContext = true, dimming = .5, restoreDesktop = true, snapWindows = false });
            var desktop = JsonSerializer.SerializeToElement(new { version = 1, panels = new[] { new { id = "browser", bounds = new[] { -500d, 1500, 800, 500 } } }, open = new[] { "friends", "browser", "settings" } });
            store.Save(1, desktop, remembered);
            var restarted = new MenuPreferencesStore(root).Read();
            Require(restarted.Revision == 2 && restarted.Layout.GetProperty("open")[1].GetString() == "browser" && restarted.Layout.GetProperty("panels")[0].GetProperty("bounds")[0].GetDouble() == -500, "restart preserves desktop z order and offscreen geometry");
            foreach (var bad in new[] {
                "{\"version\":1,\"panels\":[],\"open\":[\"friends\",\"friends\"]}",
                "{\"version\":1,\"panels\":[],\"open\":[\"p1\"]}",
                "{\"version\":1,\"panels\":[],\"open\":[123]}"
            })
            {
                using var document = JsonDocument.Parse(bad);
                try { store.Save(2, document.RootElement, remembered); throw new Exception("invalid desktop accepted"); }
                catch (ArgumentException) { }
            }
            var legacy = JsonSerializer.SerializeToElement(new { showClock = false, showContext = true, dimming = .5 });
            store.Save(2, layout, legacy);
            Require(new MenuPreferencesStore(root).Read().Revision == 3, "legacy settings remain readable");
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 5);
            var request = BridgeEnvelope.Request("applicationPreferences.menu.get", "menu", 5, new { schemaVersion = 1 });
            var read = await dispatcher.DispatchAsync(request);
            Require(read.Response.Status == "ok", "dispatcher reads local preferences");
            var stale = await dispatcher.DispatchAsync(BridgeEnvelope.Request("applicationPreferences.menu.get", "old", 4, new { schemaVersion = 1 }));
            Require(stale.Response.Status != "ok", "stale generation denied");
            Console.WriteLine("PASS menu local geometry, revision conflict, allowlist, atomic preservation and generation checks");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Require(bool value, string label) { if (!value) throw new Exception(label); }
}
