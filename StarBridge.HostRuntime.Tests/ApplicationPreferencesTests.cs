using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;
using System.Text.Json;

internal static class ApplicationPreferencesTests
{
    internal static async Task LivePresentationLanguage()
    {
        var root = CreateRoot();
        try
        {
            var store = new ApplicationPreferencesStore(root);
            store.Save(ApplicationPreferencesSnapshot.Default with { LocaleOverride = "zh-TW" });
            using var preferences = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            AssertEqual("zh-TW", preferences.CurrentLocaleOverride,
                "native startup reads saved override before Flutter requests");
            var read = await preferences.DispatchAsync(Request("initial", 3));
            var revision = read.Response.Payload.GetProperty("revision").GetInt64();
            foreach (var language in new string?[] { "en-US", "zh-CN", null })
            {
                var saved = await preferences.DispatchAsync(Request("save-language", 3,
                    ApplicationPreferencesRequestNames.Update,
                    // Flutter sends explicit JSON null when restoring follow-system.
                    JsonSerializer.SerializeToElement(new { schemaVersion = 1, expectedRevision = revision, patch = new { localeOverride = language } })));
                AssertEqual("ok", saved.Response.Status, "language save succeeds");
                AssertEqual(language, preferences.CurrentLocaleOverride, "native presentation follows only committed language");
                revision = saved.Response.Payload.GetProperty("revision").GetInt64();
            }
            using var failing = new ApplicationPreferencesBridgeDispatcher(new FailingSaveStore(), () => 3);
            await failing.DispatchAsync(Request("failed-language", 3, ApplicationPreferencesRequestNames.Update,
                new { schemaVersion = 1, expectedRevision = 0, patch = new { localeOverride = "zh-TW" } }));
            AssertEqual<string?>(null, failing.CurrentLocaleOverride, "failed save does not leak draft language");
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task DefaultsAndPersistence()
    {
        var root = CreateRoot();
        try
        {
            var remembered = ApplicationPreferencesSnapshot.Default with
            {
                LaunchAtStartup = false,
                StartMinimized = true,
                StartupChoiceMade = true
            };
            var destinationStore = new ApplicationPreferencesStore(Path.Combine(root, "remembered"));
            destinationStore.Save(remembered);
            AssertEqual(true, destinationStore.Load().Snapshot.StartMinimized,
                "disabled startup preserves saved destination after reopening");
            using (var dispatcher = new ApplicationPreferencesBridgeDispatcher(
                       root,
                       () => 4))
            {
                var defaults = await dispatcher.DispatchAsync(Request("get-defaults", 4));
                AssertEqual(BridgeResponseStatuses.Ok, defaults.Response.Status, "default status");
                AssertEqual("defaulted", defaults.Response.Payload.GetProperty("storageState").GetString(), "default storage state");
                AssertEqual(0L, defaults.Response.Payload.GetProperty("revision").GetInt64(), "default revision");
                var defaultPreferences = defaults.Response.Payload.GetProperty("preferences");
                AssertEqual(JsonValueKind.Null, defaultPreferences.GetProperty("localeOverride").ValueKind, "default locale override");
                AssertEqual("dark", defaultPreferences.GetProperty("appearanceMode").GetString(), "default appearance");
                AssertEqual("followSystem", defaultPreferences.GetProperty("motionPreference").GetString(), "default motion");
                var defaultBehavior = defaultPreferences.GetProperty("applicationBehavior");
                AssertEqual(false, defaultBehavior.GetProperty("launchAtStartup").GetBoolean(), "default startup");
                AssertEqual(true, defaultBehavior.GetProperty("keepRunningInBackground").GetBoolean(), "default background");
                AssertEqual(false, defaultBehavior.GetProperty("startupChoiceMade").GetBoolean(), "default startup choice");

                var update = await dispatcher.DispatchAsync(
                    Request(
                        "update",
                        4,
                        ApplicationPreferencesRequestNames.Update,
                        new
                        {
                            schemaVersion = 1,
                            expectedRevision = 0,
                            patch = new
                            {
                                localeOverride = "zh-TW",
                                appearanceMode = "light",
                                motionPreference = "reduce",
                                applicationBehavior = new
                                {
                                    launchAtStartup = true,
                                    keepRunningInBackground = true,
                                    startMinimized = true,
                                    startupChoiceMade = true,
                                    closeBehaviorChoiceMade = true,
                                    backgroundHintShown = false
                                }
                            }
                        }));
                AssertEqual(BridgeResponseStatuses.Ok, update.Response.Status, "update status");
                AssertEqual(1L, update.Response.Payload.GetProperty("revision").GetInt64(), "updated revision");
                AssertEqual(
                    "zh-TW",
                    update.Response.Payload.GetProperty("preferences").GetProperty("localeOverride").GetString(),
                    "updated locale");
            }

            using var restored = new ApplicationPreferencesBridgeDispatcher(root, () => 4);
            var response = await restored.DispatchAsync(Request("get-restored", 4));
            AssertEqual("ready", response.Response.Payload.GetProperty("storageState").GetString(), "restored storage state");
            AssertEqual(1L, response.Response.Payload.GetProperty("revision").GetInt64(), "restored revision");
            var restoredPreferences = response.Response.Payload.GetProperty("preferences");
            AssertEqual("zh-TW", restoredPreferences.GetProperty("localeOverride").GetString(), "restored locale");
            AssertEqual("light", restoredPreferences.GetProperty("appearanceMode").GetString(), "restored appearance");
            AssertEqual("reduce", restoredPreferences.GetProperty("motionPreference").GetString(), "restored motion");
            var restoredBehavior = restoredPreferences.GetProperty("applicationBehavior");
            AssertEqual(true, restoredBehavior.GetProperty("launchAtStartup").GetBoolean(), "restored startup");
            AssertEqual(true, restoredBehavior.GetProperty("startMinimized").GetBoolean(), "restored background startup");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task InvalidUpdateFailsClosed()
    {
        var root = CreateRoot();
        try
        {
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 2);
            var update = await dispatcher.DispatchAsync(
                Request(
                    "invalid-update",
                    2,
                    ApplicationPreferencesRequestNames.Update,
                    new
                    {
                        schemaVersion = 1,
                        expectedRevision = 0,
                        patch = new { localeOverride = "unsupported" }
                    }));
            AssertEqual(BridgeResponseStatuses.Error, update.Response.Status, "invalid update status");
            AssertEqual(
                ApplicationPreferencesStableErrors.InvalidValue,
                update.Response.Error?.Code,
                "invalid update code");

            var current = await dispatcher.DispatchAsync(Request("after-invalid", 2));
            AssertEqual(
                JsonValueKind.Null,
                current.Response.Payload.GetProperty("preferences").GetProperty("localeOverride").ValueKind,
                "invalid update did not mutate");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task LegacyApplicationBehaviorIsProjectedWithoutWpf()
    {
        var root = CreateRoot();
        try
        {
            File.WriteAllText(
                Path.Combine(root, "application-behavior.json"),
                """
                {
                  "LaunchAtStartup": true,
                  "KeepRunningInBackground": true,
                  "StartMinimized": true,
                  "BackgroundHintShown": true,
                  "CloseBehaviorChoiceMade": true
                }
                """);

            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(
                root,
                () => 6);
            var response = await dispatcher.DispatchAsync(Request("legacy-behavior", 6));

            AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "legacy behavior status");
            AssertEqual("ready", response.Response.Payload.GetProperty("storageState").GetString(), "legacy behavior storage state");
            var behavior = response.Response.Payload
                .GetProperty("preferences")
                .GetProperty("applicationBehavior");
            AssertEqual(true, behavior.GetProperty("launchAtStartup").GetBoolean(), "legacy startup");
            AssertEqual(true, behavior.GetProperty("keepRunningInBackground").GetBoolean(), "legacy background");
            AssertEqual(true, behavior.GetProperty("startMinimized").GetBoolean(), "legacy minimized startup");
            AssertEqual(true, behavior.GetProperty("startupChoiceMade").GetBoolean(), "legacy startup choice");
            AssertEqual(true, behavior.GetProperty("backgroundHintShown").GetBoolean(), "legacy hint state");
            AssertEqual(true, behavior.GetProperty("closeBehaviorChoiceMade").GetBoolean(), "legacy close choice");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task OlderV1PreferencesRemainReadable()
    {
        var root = CreateRoot();
        try
        {
            File.WriteAllText(
                Path.Combine(root, "application-preferences.v1.json"),
                """
                {
                  "schemaVersion": 1,
                  "revision": 3,
                  "localeOverride": "zh-CN",
                  "appearanceMode": "dark",
                  "motionPreference": "followSystem",
                  "launchAtStartup": false,
                  "keepRunningInBackground": false,
                  "startMinimized": false,
                  "closeBehaviorChoiceMade": true,
                  "backgroundHintShown": false
                }
                """);

            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 7);
            var response = await dispatcher.DispatchAsync(Request("older-v1", 7));

            AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "older v1 status");
            AssertEqual("ready", response.Response.Payload.GetProperty("storageState").GetString(), "older v1 state");
            var behavior = response.Response.Payload
                .GetProperty("preferences")
                .GetProperty("applicationBehavior");
            AssertEqual(false, behavior.GetProperty("startupChoiceMade").GetBoolean(), "older v1 startup choice");
            AssertEqual(false, behavior.GetProperty("keepRunningInBackground").GetBoolean(), "older v1 background");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task CorruptFileRecoversToDefaults()
    {
        var root = CreateRoot();
        try
        {
            File.WriteAllText(Path.Combine(root, "application-preferences.v1.json"), "not-json");
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 0);
            var response = await dispatcher.DispatchAsync(Request("corrupt", 0));
            AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "corrupt recovery status");
            AssertEqual(
                "recoveredDefaults",
                response.Response.Payload.GetProperty("storageState").GetString(),
                "corrupt recovery state");
            AssertEqual(
                JsonValueKind.Null,
                response.Response.Payload.GetProperty("preferences").GetProperty("localeOverride").ValueKind,
                "corrupt recovery locale");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task RevisionConflictFailsClosed()
    {
        var root = CreateRoot();
        try
        {
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 3);
            var first = await dispatcher.DispatchAsync(
                Request(
                    "first-update",
                    3,
                    ApplicationPreferencesRequestNames.Update,
                    new
                    {
                        schemaVersion = 1,
                        expectedRevision = 0,
                        patch = new { appearanceMode = "light" }
                    }));
            AssertEqual(BridgeResponseStatuses.Ok, first.Response.Status, "first update status");

            var stale = await dispatcher.DispatchAsync(
                Request(
                    "stale-update",
                    3,
                    ApplicationPreferencesRequestNames.Update,
                    new
                    {
                        schemaVersion = 1,
                        expectedRevision = 0,
                        patch = new { motionPreference = "reduce" }
                    }));
            AssertEqual(BridgeResponseStatuses.Error, stale.Response.Status, "stale update status");
            AssertEqual(
                ApplicationPreferencesStableErrors.RevisionConflict,
                stale.Response.Error?.Code,
                "stale update code");

            var current = await dispatcher.DispatchAsync(Request("after-conflict", 3));
            var preferences = current.Response.Payload.GetProperty("preferences");
            AssertEqual("light", preferences.GetProperty("appearanceMode").GetString(), "conflict kept appearance");
            AssertEqual("followSystem", preferences.GetProperty("motionPreference").GetString(), "conflict kept motion");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task ReadFailureIsExplicitAndRetryable()
    {
        using var dispatcher = new ApplicationPreferencesBridgeDispatcher(
            new FailingReadStore(),
            () => 1);
        var response = await dispatcher.DispatchAsync(Request("read-failed", 1));
        AssertEqual(BridgeResponseStatuses.Error, response.Response.Status, "read failure status");
        AssertEqual(
            ApplicationPreferencesStableErrors.ReadFailed,
            response.Response.Error?.Code,
            "read failure code");
        AssertEqual(true, response.Response.Error?.Retryable, "read failure retryable");
    }

    internal static async Task AccountContextIsRejected()
    {
        var root = CreateRoot();
        try
        {
            using var dispatcher = new ApplicationPreferencesBridgeDispatcher(root, () => 5);
            var request = BridgeEnvelope.Request(
                ApplicationPreferencesRequestNames.Get,
                "unexpected-account-context",
                5,
                new { schemaVersion = 1 },
                new BridgeAccountContext("test", "scm", "subject"));
            var response = await dispatcher.DispatchAsync(request);
            AssertEqual(BridgeResponseStatuses.Error, response.Response.Status, "account context status");
            AssertEqual(
                BridgeErrorCodes.InvalidEnvelope,
                response.Response.Error?.Code,
                "account context code");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static async Task StartupRegistrationRollsBackWhenSaveFails()
    {
        var registration = new RecordingStartupRegistration();
        using var dispatcher = new ApplicationPreferencesBridgeDispatcher(
            new FailingSaveStore(),
            registration,
            () => 8);
        var update = await dispatcher.DispatchAsync(
            Request(
                "startup-save-failed",
                8,
                ApplicationPreferencesRequestNames.Update,
                new
                {
                    schemaVersion = 1,
                    expectedRevision = 0,
                    patch = new
                    {
                        applicationBehavior = new
                        {
                            launchAtStartup = true,
                            keepRunningInBackground = true,
                            startMinimized = true,
                            startupChoiceMade = true,
                            closeBehaviorChoiceMade = true,
                            backgroundHintShown = false
                        }
                    }
                }));

        AssertEqual(BridgeResponseStatuses.Error, update.Response.Status, "startup save failure status");
        AssertEqual(ApplicationPreferencesStableErrors.SaveFailed, update.Response.Error?.Code, "startup save failure code");
        AssertEqual("True,False", string.Join(',', registration.Writes), "startup registration rollback");
        AssertEqual(false, registration.Enabled, "startup registration final state");
    }

    internal static async Task StartupRegistrationWaitsForTheFirstChoice()
    {
        var registration = new RecordingStartupRegistration();
        using var dispatcher = new ApplicationPreferencesBridgeDispatcher(
            new DefaultPreferencesStore(),
            registration,
            () => 9);

        var response = await dispatcher.DispatchAsync(Request("startup-unconfirmed", 9));

        AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "unconfirmed startup status");
        AssertEqual(0, registration.Writes.Count, "unconfirmed startup registry writes");
    }

    internal static async Task DecliningStartupIsAppliedOnlyOnContinue()
    {
        var registration = new RecordingStartupRegistration();
        using var dispatcher = new ApplicationPreferencesBridgeDispatcher(
            new DefaultPreferencesStore(),
            registration,
            () => 10);

        var response = await dispatcher.DispatchAsync(
            Request(
                "startup-declined",
                10,
                ApplicationPreferencesRequestNames.Update,
                new
                {
                    schemaVersion = 1,
                    expectedRevision = 0,
                    patch = new
                    {
                        applicationBehavior = new
                        {
                            launchAtStartup = false,
                            keepRunningInBackground = true,
                            startMinimized = false,
                            startupChoiceMade = true,
                            closeBehaviorChoiceMade = false,
                            backgroundHintShown = false
                        }
                    }
                }));

        AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "declined startup status");
        AssertEqual("False", string.Join(',', registration.Writes), "declined startup registry write");
    }

    internal static void StartupCommandTargetsTheFlutterExecutable()
    {
        var executable = Path.Combine("C:\\Program Files", "StarBridge", "starbridge_flutter.exe");
        AssertEqual(
            $"\"{Path.GetFullPath(executable)}\" --startup",
            WindowsApplicationStartupRegistration.BuildCommand(executable),
            "Flutter startup command");
    }

    private static BridgeEnvelope Request(
        string correlationId,
        long generation,
        string name = ApplicationPreferencesRequestNames.Get,
        object? payload = null) =>
        BridgeEnvelope.Request(
            name,
            correlationId,
            generation,
            payload ?? new { schemaVersion = 1 });

    private static string CreateRoot()
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"starbridge-preferences-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }

    private static void AssertEqual<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{label}: expected '{expected}', actual '{actual}'.");
        }
    }

    private sealed class FailingReadStore : IApplicationPreferencesStore
    {
        public ApplicationPreferencesReadResult Load() =>
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.ReadFailed,
                "Synthetic read failure.",
                retryable: true);

        public void Save(ApplicationPreferencesSnapshot snapshot) =>
            throw new InvalidOperationException("Save should not be called.");
    }

    private sealed class FailingSaveStore : IApplicationPreferencesStore
    {
        public ApplicationPreferencesReadResult Load() =>
            ApplicationPreferencesReadResult.Defaulted;

        public void Save(ApplicationPreferencesSnapshot snapshot) =>
            throw new ApplicationPreferencesException(
                ApplicationPreferencesStableErrors.SaveFailed,
                "Synthetic save failure.",
                retryable: true);
    }

    private sealed class DefaultPreferencesStore : IApplicationPreferencesStore
    {
        public ApplicationPreferencesReadResult Load() =>
            ApplicationPreferencesReadResult.Defaulted;

        public void Save(ApplicationPreferencesSnapshot snapshot)
        {
        }
    }

    private sealed class RecordingStartupRegistration : IApplicationStartupRegistration
    {
        internal List<bool> Writes { get; } = [];
        internal bool Enabled { get; private set; }

        public bool TrySetEnabled(bool enabled, out string? error)
        {
            Enabled = enabled;
            Writes.Add(enabled);
            error = null;
            return true;
        }
    }
}
