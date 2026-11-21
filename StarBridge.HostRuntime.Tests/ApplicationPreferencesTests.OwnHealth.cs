using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using System.Text.Json;

// "读取自己的血量": a separate switch, default off (11-09 user decision).
internal static partial class ApplicationPreferencesTests
{
    internal static async Task ReadOwnHealthIsOffByDefaultAndPersists()
    {
        var root = CreateRoot();
        try
        {
            AssertEqual(false, ApplicationPreferencesSnapshot.Default.ReadOwnHealth, "default snapshot is off");
            using (var fresh = new ApplicationPreferencesBridgeDispatcher(root, () => 1))
            {
                AssertEqual(false, fresh.CurrentReadOwnHealth, "getter is off before any request");
                var read = await fresh.DispatchAsync(Request("own-health-default", 1));
                AssertEqual(false, read.Response.Payload.GetProperty("preferences").GetProperty("readOwnHealth").GetBoolean(),
                    "default response is off");
            }
            var store = new ApplicationPreferencesStore(root);
            var expected = ApplicationPreferencesSnapshot.Default with { Revision = 3, LocaleOverride = "en-US", HolidayAppearance = false };
            store.Save(expected);
            foreach (var enabled in new[] { true, false })
            {
                using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 2))
                {
                    var saved = await dispatcher.DispatchAsync(Request("own-health-save", 2,
                        ApplicationPreferencesRequestNames.Update,
                        new { schemaVersion = 1, expectedRevision = expected.Revision, patch = new { readOwnHealth = enabled } }));
                    AssertEqual(BridgeResponseStatuses.Ok, saved.Response.Status, "own-health patch saved");
                    AssertEqual(enabled, dispatcher.CurrentReadOwnHealth, "getter follows the committed value");
                }
                expected = expected with { Revision = expected.Revision + 1, ReadOwnHealth = enabled };
                AssertEqual(expected, store.Load().Snapshot, "own-health patch preserves every other preference");
                using var stored = JsonDocument.Parse(File.ReadAllText(Path.Combine(root, "application-preferences.v1.json")));
                AssertEqual(enabled, stored.RootElement.GetProperty("readOwnHealth").GetBoolean(), "own-health persisted in JSON");
                using var reopened = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
                AssertEqual(enabled, reopened.CurrentReadOwnHealth, "own-health survives restart before the first request");
            }
            // A file written by an older client has no readOwnHealth: it reads as off.
            var path = Path.Combine(root, "application-preferences.v1.json");
            var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            json.Remove("readOwnHealth");
            File.WriteAllText(path, json.ToJsonString());
            AssertEqual(false, store.Load().Snapshot.ReadOwnHealth, "older file without the field reads as off");
            using (var older = new ApplicationPreferencesBridgeDispatcher(root, () => 5))
                AssertEqual(false, older.CurrentReadOwnHealth, "older file: getter is off");
            Console.WriteLine("PASS read own health is off by default and persists");
        }
        finally { Directory.Delete(root, true); }
    }

    // "游戏在后台时也读取": a sub-switch, default off (11-13 user: "默认关"), saved on its own.
    internal static async Task ReadOwnHealthInBackgroundIsOffByDefaultAndPersists()
    {
        var root = CreateRoot();
        try
        {
            AssertEqual(false, ApplicationPreferencesSnapshot.Default.ReadOwnHealthInBackground, "default snapshot: background off");
            using (var fresh = new ApplicationPreferencesBridgeDispatcher(root, () => 1))
            {
                AssertEqual(false, fresh.CurrentReadOwnHealthInBackground, "getter is off before any request");
                var read = await fresh.DispatchAsync(Request("own-health-background-default", 1));
                AssertEqual(false, read.Response.Payload.GetProperty("preferences").GetProperty("readOwnHealthInBackground").GetBoolean(),
                    "default response: background off");
            }
            var store = new ApplicationPreferencesStore(root);
            var expected = ApplicationPreferencesSnapshot.Default with { Revision = 2, ReadOwnHealth = true };
            store.Save(expected);
            foreach (var enabled in new[] { true, false })
            {
                using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 2))
                {
                    var saved = await dispatcher.DispatchAsync(Request("own-health-background-save", 2,
                        ApplicationPreferencesRequestNames.Update,
                        new { schemaVersion = 1, expectedRevision = expected.Revision, patch = new { readOwnHealthInBackground = enabled } }));
                    AssertEqual(BridgeResponseStatuses.Ok, saved.Response.Status, "background patch saved");
                    AssertEqual(enabled, dispatcher.CurrentReadOwnHealthInBackground, "getter follows the committed value");
                    AssertEqual(true, dispatcher.CurrentReadOwnHealth, "the main switch is untouched");
                }
                expected = expected with { Revision = expected.Revision + 1, ReadOwnHealthInBackground = enabled };
                AssertEqual(expected, store.Load().Snapshot, "background patch preserves every other preference");
                using var reopened = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
                AssertEqual(enabled, reopened.CurrentReadOwnHealthInBackground, "background survives restart before the first request");
            }
            // A file written by b93 or older has no readOwnHealthInBackground: it reads as off.
            store.Save(expected with { ReadOwnHealthInBackground = true });
            var path = Path.Combine(root, "application-preferences.v1.json");
            var json = System.Text.Json.Nodes.JsonNode.Parse(File.ReadAllText(path))!.AsObject();
            json.Remove("readOwnHealthInBackground");
            File.WriteAllText(path, json.ToJsonString());
            AssertEqual(false, store.Load().Snapshot.ReadOwnHealthInBackground, "older file without the field reads as off");
            AssertEqual(true, store.Load().Snapshot.ReadOwnHealth, "older file keeps the main switch");
            // Invalid values and unknown neighbours are rejected and change nothing.
            var before = File.ReadAllText(path);
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 4))
            {
                var revision = store.Load().Snapshot.Revision;
                foreach (var patchJson in new[]
                {
                    """{"readOwnHealthInBackground":"true"}""", """{"readOwnHealthInBackground":null}""",
                    """{"readOwnHealthInBackground":1}""", """{"readOwnHealthInBackground":true,"readOwnHealthAlways":true}"""
                })
                {
                    using var patch = JsonDocument.Parse(patchJson);
                    var rejected = await dispatcher.DispatchAsync(Request("own-health-background-invalid", 4,
                        ApplicationPreferencesRequestNames.Update,
                        new { schemaVersion = 1, expectedRevision = revision, patch = patch.RootElement }));
                    AssertEqual(BridgeResponseStatuses.Error, rejected.Response.Status, "invalid background patch rejected");
                    AssertEqual(before, File.ReadAllText(path), "invalid background patch leaves file unchanged");
                    AssertEqual(false, dispatcher.CurrentReadOwnHealthInBackground, "invalid patch leaves background off");
                }
            }
            Console.WriteLine("PASS read own health in background is off by default, persists and rejects invalid values");
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task ReadOwnHealthRejectsInvalidPatches()
    {
        var root = CreateRoot();
        try
        {
            var store = new ApplicationPreferencesStore(root);
            store.Save(ApplicationPreferencesSnapshot.Default);
            var path = Path.Combine(root, "application-preferences.v1.json");
            var originalJson = File.ReadAllText(path);
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            foreach (var patchJson in new[]
            {
                """{"readOwnHealth":"true"}""", """{"readOwnHealth":null}""", """{"readOwnHealth":1}""",
                """{"readOwnHealth":{}}""", """{"readOwnHealth":true,"readOtherHealth":true}"""
            })
            {
                using var patch = JsonDocument.Parse(patchJson);
                var rejected = await dispatcher.DispatchAsync(Request("own-health-invalid", 3,
                    ApplicationPreferencesRequestNames.Update,
                    new { schemaVersion = 1, expectedRevision = 0, patch = patch.RootElement }));
                AssertEqual(BridgeResponseStatuses.Error, rejected.Response.Status, "invalid own-health patch rejected");
                AssertEqual(originalJson, File.ReadAllText(path), "invalid patch leaves file unchanged");
                AssertEqual(false, dispatcher.CurrentReadOwnHealth, "invalid patch leaves the switch off");
            }
            Console.WriteLine("PASS read own health rejects invalid values and unknown fields");
        }
        finally { Directory.Delete(root, true); }
    }
}
