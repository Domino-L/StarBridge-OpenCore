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
                var expected = baseline with { InteractionStyle = style, Revision = revision };
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
                var failed = await dispatcher.DispatchAsync(Update(0, new { interactionStyle = "scan" }));
                Equal(ApplicationPreferencesStableErrors.SaveFailed, failed.Response.Error!.Code, "save failure typed");
                var read = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
                    ApplicationPreferencesRequestNames.Get, "after-failure", 3, new { schemaVersion = 1 }));
                Equal(0L, read.Response.Payload.GetProperty("revision").GetInt64(), "failure does not advance revision");
                Equal("standard", read.Response.Payload.GetProperty("preferences").GetProperty("interactionStyle").GetString(), "failure retains confirmed style");
            }
            Console.WriteLine("PASS interaction style invalid patches, stale revision and failed save retain confirmed state");
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
