using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using System.Text.Json;

internal static class ApplicationInteractionPreferencesTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), $"starbridge-interaction-preferences-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        try
        {
            var baseline = ApplicationPreferencesSnapshot.Default with
            {
                LocaleOverride = "zh-TW", AppearanceMode = "light", MotionPreference = "reduce",
                KeepRunningInBackground = false, StartMinimized = true, AppearancePreviewGuideSeen = true
            };
            var store = new ApplicationPreferencesStore(root);
            store.Save(baseline);
            // Real v1 file without the new property must retain every old value.
            var path = Path.Combine(root, "application-preferences.v1.json");
            var legacy = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path))!;
            legacy.Remove("interactionStyle");
            File.WriteAllText(path, JsonSerializer.Serialize(legacy));
            Equal(baseline, new ApplicationPreferencesStore(root).Load().Snapshot, "old v1 defaults only new style");

            long revision = 0;
            foreach (var style in new[] { "standard", "rail", "scan", "glow" })
            {
                using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3))
                {
                    var saved = await dispatcher.DispatchAsync(Update(revision, new { interactionStyle = style }));
                    Equal("ok", saved.Response.Status, $"save {style}");
                    Equal(++revision, saved.Response.Payload.GetProperty("revision").GetInt64(), "one revision per write");
                }
                var expected = baseline with { InteractionStyle = style, Revision = revision, InteractionStyleChoiceMade = true };
                Equal(expected, new ApplicationPreferencesStore(root).Load().Snapshot, $"real file reopen {style}");
                using var reopened = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
                var read = await reopened.DispatchAsync(BridgeEnvelope.Request(
                    ApplicationPreferencesRequestNames.Get, "reopen", 3, new { schemaVersion = 1 }));
                Equal(style, read.Response.Payload.GetProperty("preferences").GetProperty("interactionStyle").GetString(), "bridge read after reopen");
                Console.WriteLine($"PASS interaction style {style} real file persistence, reopen and existing fields");
            }

            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3))
            {
                foreach (var invalid in new object?[] { "unknown", "SCAN", "", null, 42, true })
                {
                    var before = File.ReadAllText(path);
                    var rejected = await dispatcher.DispatchAsync(Update(revision, new { interactionStyle = invalid }));
                    Equal("error", rejected.Response.Status, "invalid style rejected");
                    Equal(before, File.ReadAllText(path), "invalid patch never changes file");
                }
                var stale = await dispatcher.DispatchAsync(Update(revision - 1, new { interactionStyle = "rail" }));
                Equal(ApplicationPreferencesStableErrors.RevisionConflict, stale.Response.Error!.Code, "stale style rejected");
                Equal("glow", store.Load().Snapshot.InteractionStyle, "stale request retains committed style");
            }
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(new RejectingStore(), () => 3))
            {
                var failed = await dispatcher.DispatchAsync(Update(0, new { interactionStyle = "rail" }));
                Equal(ApplicationPreferencesStableErrors.SaveFailed, failed.Response.Error!.Code, "save failure typed");
                var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                    ApplicationPreferencesRequestNames.Get, "after-failure", 3, new { schemaVersion = 1 }));
                Equal(0L, read.Response.Payload.GetProperty("revision").GetInt64(), "failure does not advance revision");
                Equal("scan", read.Response.Payload.GetProperty("preferences").GetProperty("interactionStyle").GetString(), "failure retains confirmed style");
            }
            Console.WriteLine("PASS interaction style invalid patches, stale revision and failed save retain confirmed state");
            await ScanDefaultMigration(root);
        }
        finally
        {
            // Only this test's literal GUID-prefixed child of the temp directory.
            var resolved = Path.GetFullPath(root);
            if (Path.GetDirectoryName(resolved) == Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) &&
                Path.GetFileName(resolved).StartsWith("starbridge-interaction-preferences-", StringComparison.Ordinal))
                Directory.Delete(resolved, recursive: true);
        }
    }

    // 0.7.3 one-time move to the "scan" default (user: "把所有人的交互都换成扫描").
    private static async Task ScanDefaultMigration(string parent)
    {
        var baseline = ApplicationPreferencesSnapshot.Default with
        {
            Revision = 5, LocaleOverride = "zh-CN", StartupChoiceMade = true,
            CloseBehaviorChoiceMade = true, BackgroundHintShown = true
        };

        // A 0.7.2 file: every save wrote the whole snapshot, so "standard" is
        // there although the user never picked it, and neither new flag exists.
        foreach (var (stored, expected) in new[] { ("standard", "scan"), ("rail", "rail"), ("glow", "glow"), ("scan", "scan") })
        {
            var root = Child(parent, $"old-{stored}");
            var path = WriteOld072File(root, baseline with { InteractionStyle = stored });
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3))
            {
                Equal(expected, await ReadStyle(dispatcher, "upgrade"), $"0.7.2 {stored} after upgrade");
            }
            var file = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path))!;
            Equal(expected, file["interactionStyle"].GetString(), $"0.7.2 {stored} written back");
            Equal(true, file["interactionStyleScanMigrated"].GetBoolean(), $"0.7.2 {stored} migration marked done");
            Equal(5L, file["revision"].GetInt64(), $"0.7.2 {stored} migration keeps revision");
            var reloaded = new ApplicationPreferencesStore(root).Load();
            Equal(false, reloaded.MigrationPending, $"0.7.2 {stored} nothing left to migrate");
            Equal(baseline with { InteractionStyle = expected, InteractionStyleScanMigrated = true }, reloaded.Snapshot,
                $"0.7.2 {stored} keeps every other field");
        }
        Console.WriteLine("PASS interaction scan migration: 0.7.2 standard becomes scan, rail/glow/scan kept, other fields kept");

        // After the migration the user picks "standard" in settings: it stays, forever.
        {
            var root = Child(parent, "choose-standard");
            WriteOld072File(root, baseline with { InteractionStyle = "standard" });
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3))
            {
                Equal("scan", await ReadStyle(dispatcher, "first"), "migrated before the choice");
                var saved = await dispatcher.DispatchAsync(Update(5, new { interactionStyle = "standard" }));
                Equal("ok", saved.Response.Status, "user picks standard");
            }
            for (var restart = 0; restart < 2; restart++)
            {
                using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
                Equal("standard", await ReadStyle(dispatcher, $"restart-{restart}"), $"user standard kept after restart {restart}");
            }
            var snapshot = new ApplicationPreferencesStore(root).Load().Snapshot;
            Equal(true, snapshot.InteractionStyleChoiceMade, "settings pick is recorded");
        }
        Console.WriteLine("PASS interaction scan migration: user's later standard pick survives restarts");

        // A choice made before the flag existed cannot be told apart; a choice
        // recorded by this build (flag set, migration not yet run) is kept.
        {
            var root = Child(parent, "chosen-not-migrated");
            new ApplicationPreferencesStore(root).Save(baseline with
            {
                InteractionStyle = "standard", InteractionStyleChoiceMade = true, InteractionStyleScanMigrated = false
            });
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            Equal("standard", await ReadStyle(dispatcher, "chosen"), "recorded choice is never migrated");
        }

        // Only once: a migrated file that later holds "standard" without the
        // choice flag (for example written back by an older build) is left alone.
        {
            var root = Child(parent, "only-once");
            new ApplicationPreferencesStore(root).Save(baseline with
            {
                InteractionStyle = "standard", InteractionStyleScanMigrated = true
            });
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            Equal("standard", await ReadStyle(dispatcher, "once"), "migration runs only once");
        }
        Console.WriteLine("PASS interaction scan migration: recorded choice kept; migration happens only once");

        // New install: no settings file at all reads scan.
        {
            var root = Child(parent, "fresh");
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                ApplicationPreferencesRequestNames.Get, "fresh", 3, new { schemaVersion = 1 }));
            Equal("defaulted", read.Response.Payload.GetProperty("storageState").GetString(), "fresh install defaulted");
            Equal("scan", read.Response.Payload.GetProperty("preferences").GetProperty("interactionStyle").GetString(), "fresh install scan");
            Equal(false, File.Exists(Path.Combine(root, "application-preferences.v1.json")), "read alone writes no file");
        }

        // A file older than the interaction setting (no interactionStyle key) reads scan.
        {
            var root = Child(parent, "pre-style");
            var path = WriteOld072File(root, baseline);
            var file = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path))!;
            file.Remove("interactionStyle");
            File.WriteAllText(path, JsonSerializer.Serialize(file));
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            Equal("scan", await ReadStyle(dispatcher, "pre-style"), "file without the style key reads scan");
        }
        Console.WriteLine("PASS interaction scan migration: fresh install and pre-style files read scan");

        // Write-back failure: the file is not touched, the migrated value is
        // still used, and the next successful save carries it with the flag.
        {
            var root = Child(parent, "write-fails");
            var path = WriteOld072File(root, baseline with { InteractionStyle = "standard" });
            var before = File.ReadAllText(path);
            var store = new FlakyStore(new ApplicationPreferencesStore(root)) { FailSaves = true };
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(store, () => 3);
            Equal("scan", await ReadStyle(dispatcher, "fail"), "failed write-back still uses scan");
            Equal(before, File.ReadAllText(path), "failed write-back leaves the file as it was");
            store.FailSaves = false;
            var saved = await dispatcher.DispatchAsync(Update(5, new { holidayAppearance = false }));
            Equal("ok", saved.Response.Status, "later unrelated save");
            // Read the raw file: Load() would migrate again in memory and hide a
            // write that never happened (review CX-ISCAN-DEFAULT-073-REVIEW P2).
            var raw = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path))!;
            Equal("scan", raw["interactionStyle"].GetString(), "later save writes scan to disk");
            Equal(true, raw["interactionStyleScanMigrated"].GetBoolean(), "later save writes the done flag to disk");
            Equal(false, raw["interactionStyleChoiceMade"].GetBoolean(), "unrelated save is not a style choice");
            Equal(false, new ApplicationPreferencesStore(root).Load().MigrationPending, "nothing left to migrate after the save");
        }
        Console.WriteLine("PASS interaction scan migration: failed write-back keeps the file intact and retries on the next save");
    }

    private static string Child(string parent, string name)
    {
        var root = Path.Combine(parent, name);
        Directory.CreateDirectory(root);
        return root;
    }

    private static string WriteOld072File(string root, ApplicationPreferencesSnapshot snapshot)
    {
        new ApplicationPreferencesStore(root).Save(snapshot);
        var path = Path.Combine(root, "application-preferences.v1.json");
        var file = JsonSerializer.Deserialize<Dictionary<string, JsonElement>>(File.ReadAllText(path))!;
        if (!file.Remove("interactionStyleChoiceMade") || !file.Remove("interactionStyleScanMigrated"))
            throw new InvalidOperationException("expected the new flags in the saved file");
        File.WriteAllText(path, JsonSerializer.Serialize(file));
        return path;
    }

    private static async Task<string?> ReadStyle(ApplicationPreferencesBridgeDispatcher dispatcher, string id)
    {
        var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
            ApplicationPreferencesRequestNames.Get, id, 3, new { schemaVersion = 1 }));
        Equal("ok", read.Response.Status, $"read {id}");
        return read.Response.Payload.GetProperty("preferences").GetProperty("interactionStyle").GetString();
    }

    private sealed class FlakyStore(IApplicationPreferencesStore inner) : IApplicationPreferencesStore
    {
        public bool FailSaves { get; set; }
        public ApplicationPreferencesReadResult Load() => inner.Load();
        public void Save(ApplicationPreferencesSnapshot snapshot)
        {
            if (FailSaves)
                throw new ApplicationPreferencesException(
                    ApplicationPreferencesStableErrors.SaveFailed, "Synthetic migration write-back failure", retryable: true);
            inner.Save(snapshot);
        }
    }

    private static BridgeEnvelope Update(long revision, object patch) => BridgeEnvelope.Request(
        ApplicationPreferencesRequestNames.Update, "interaction-save", 3,
        new { schemaVersion = 1, expectedRevision = revision, patch });

    private static void Equal<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
            throw new InvalidOperationException($"{label}: expected '{expected}', got '{actual}'");
    }

    private sealed class RejectingStore : IApplicationPreferencesStore
    {
        public ApplicationPreferencesReadResult Load() => ApplicationPreferencesReadResult.Defaulted;
        public void Save(ApplicationPreferencesSnapshot snapshot) => throw new ApplicationPreferencesException(
            ApplicationPreferencesStableErrors.SaveFailed, "Synthetic interaction preference save failure", retryable: true);
    }
}
