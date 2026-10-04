using System.Text.Json;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class MenuRecoveryTests
{
    internal static async Task Verify()
    {
        var root = Path.Combine(Path.GetTempPath(), "StarBridge-menu-recovery-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        void Require(bool value, string label) { if (!value) throw new Exception(label); }
        try
        {
            var first = new MenuSessionRecoveryStore(root);
            var a = first.Begin();
            Require(!a.PreviousInterrupted && a == first.Begin(), "first process begins once without reporting itself as a crash");
            var second = new MenuSessionRecoveryStore(root);
            var b = second.Begin();
            Require(b.PreviousInterrupted && a.Token != b.Token, "restart without explicit exit detects interruption");
            try { first.Finish(a.Token); throw new Exception("old owner closed new marker"); }
            catch (ApplicationPreferencesException) { }
            second.Finish(b.Token);
            try { first.Begin(); throw new Exception("old owner replaced clean marker"); }
            catch (ApplicationPreferencesException) { }
            var third = new MenuSessionRecoveryStore(root);
            var c = third.Begin();
            Require(!c.PreviousInterrupted, "explicit normal exit clears interruption");
            third.Finish(c.Token);
            Require(third.Begin() == c && new MenuSessionRecoveryStore(root).Begin().PreviousInterrupted,
                "opening again after an exit attempt re-arms marker");
            foreach (var corrupt in new[] { "{", "{\"schemaVersion\":\"one\",\"token\":\"bad\",\"clean\":true}", new string('x', 513) })
            {
                File.WriteAllText(Path.Combine(root, "menu-session.v1.json"), corrupt);
                Require(new MenuSessionRecoveryStore(root).Begin().PreviousInterrupted, "corrupt marker is not a normal exit");
            }
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 5))
            {
                var begin = await dispatcher.DispatchAsync(BridgeEnvelope.Request("applicationPreferences.menu.begin", "start", 5, new { schemaVersion = 1 }));
                Require(begin.Response.Status == "ok", "current process can begin");
                var token = begin.Response.Payload.GetProperty("token").GetString();
                var raw = File.ReadAllText(Path.Combine(root, "menu-session.v1.json"));
                foreach (var request in new[] {
                    BridgeEnvelope.Request("applicationPreferences.menu.finish", "stale", 4, new { schemaVersion = 1, token }),
                    BridgeEnvelope.Request("applicationPreferences.menu.finish", "wrong", 5, new { schemaVersion = 1, token = new string('0', 32) }),
                    BridgeEnvelope.Request("applicationPreferences.menu.begin", "account", 5, new { schemaVersion = 1 }, new("test", "synthetic", "menu-account")),
                    BridgeEnvelope.Request("applicationPreferences.menu.begin", "extra", 5, new { schemaVersion = 1, account = "forbidden" }) })
                {
                    Require((await dispatcher.DispatchAsync(request)).Response.Status != "ok", "invalid session intent denied");
                    Require(raw == File.ReadAllText(Path.Combine(root, "menu-session.v1.json")), "denied intent preserves marker");
                }
            }
            // Host disposal/pipe loss is also the Flutter crash cleanup path.
            Require(new MenuSessionRecoveryStore(root).Begin().PreviousInterrupted, "Host disposal must never mark client clean");
            using var document = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "menu-session.v1.json")));
            Require(document.RootElement.EnumerateObject().Select(p => p.Name).Order().SequenceEqual(new[] { "clean", "schemaVersion", "token" }),
                "marker stores only bounded UI session identity, not account/tool data");
            Console.WriteLine("PASS menu interruption, explicit exit, ownership, re-arm, corruption and bridge generation");
        }
        finally { Directory.Delete(root, true); }
    }
}
