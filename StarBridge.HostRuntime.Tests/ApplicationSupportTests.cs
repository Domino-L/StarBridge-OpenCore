using StarBridge.HostRuntime.Support;
using StarBridge.NativeBridge;

internal static class ApplicationSupportTests
{
    internal static async Task ReusedExplorerWindowReportsOpenSuccess()
    {
        var root = CreateRoot();
        try
        {
            var calls = 0;
            var inspector = new WindowsApplicationSupportInspector(root, null, shellStart: start =>
            {
                calls++;
                AssertEqual(root, start.FileName, "owned directory only");
                AssertEqual(true, start.UseShellExecute, "Windows shell opens directory");
                return null; // Shell accepted the request using an existing Explorer process.
            });
            using var dispatcher = new ApplicationSupportBridgeDispatcher(inspector, inspector);
            var response = await dispatcher.DispatchAsync(Request(ApplicationSupportRequestNames.OpenDataDirectory,
                "existing-explorer", 0, new { schemaVersion = 1 }));
            AssertEqual(1, calls, "one shell request, no replay");
            AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "opened folder must not report failure");
            AssertEqual(true, response.Response.Payload.GetProperty("opened").GetBoolean(), "opened receipt");
            var failing = new WindowsApplicationSupportInspector(root, null, shellStart: _ =>
                throw new System.ComponentModel.Win32Exception("fixture failure"));
            using var rejected = new ApplicationSupportBridgeDispatcher(failing, failing);
            var failure = await rejected.DispatchAsync(Request(ApplicationSupportRequestNames.OpenDataDirectory,
                "shell-rejected", 0, new { schemaVersion = 1 }));
            AssertEqual(ApplicationSupportStableErrors.OpenFailed, failure.Response.Error?.Code, "actual shell failure remains visible");
        }
        finally { Directory.Delete(root, true); }
    }

    internal static async Task ConnectionProbeIsBoundedAndDoesNotAuthenticate()
    {
        foreach (var status in new[] { "healthy", "degraded", "unhealthy" })
        {
            var handler = new HealthFixture(status);
            var check = await DiagnosticConnectionProbe.CheckAsync(new Uri("https://fixture.invalid/"), default, handler);
            AssertEqual(status == "healthy" ? ApplicationSupportStates.Healthy : ApplicationSupportStates.ActionRequired, check.State, "health status");
            AssertEqual(1, handler.Calls, "one request, no retry");
        }
        var oversized = await DiagnosticConnectionProbe.CheckAsync(new Uri("https://fixture.invalid/"), default, new HealthFixture(new string('x', 5000)));
        AssertEqual(ApplicationSupportStates.Unavailable, oversized.State, "bounded response");
    }

    private sealed class HealthFixture(string status) : System.Net.Http.HttpMessageHandler
    {
        internal int Calls;
        protected override Task<System.Net.Http.HttpResponseMessage> SendAsync(System.Net.Http.HttpRequestMessage request, CancellationToken cancellationToken)
        {
            Calls++;
            AssertEqual("/health", request.RequestUri!.AbsolutePath, "fixed health route");
            AssertEqual(true, request.Headers.Authorization == null, "no authentication");
            return Task.FromResult(new System.Net.Http.HttpResponseMessage(System.Net.HttpStatusCode.OK)
            { Content = new System.Net.Http.StringContent("{\"status\":\"" + status + "\"}") });
        }
    }
    internal static void CacheCleanupPreservesUserAndUnknownFiles()
    {
        var root = CreateRoot();
        try
        {
            var images = Directory.CreateDirectory(Path.Combine(root, "Images")).FullName;
            var ship = Directory.CreateDirectory(Path.Combine(images, "ShipMedia")).FullName;
            File.WriteAllText(Path.Combine(images, "fleet-test-logo.png"), "fixture");
            File.WriteAllText(Path.Combine(ship, Guid.NewGuid().ToString("N") + ".image"), "fixture");
            File.WriteAllText(Path.Combine(images, "avatar.png"), "keep");
            File.WriteAllText(Path.Combine(images, "unknown.png"), "keep");
            File.WriteAllText(Path.Combine(root, "settings.json"), "keep");
            AssertEqual(2, ImageCacheMaintenance.Clear(root), "known cache count");
            AssertEqual(true, File.Exists(Path.Combine(images, "avatar.png")), "avatar retained");
            AssertEqual(true, File.Exists(Path.Combine(images, "unknown.png")), "unknown retained");
            AssertEqual(true, File.Exists(Path.Combine(root, "settings.json")), "settings retained");
            AssertEqual(0, ImageCacheMaintenance.Clear(root), "empty is harmless");
        }
        finally { Directory.Delete(root, true); }
    }
    internal static async Task DataLocationIsExplicitAndDoesNotCreateOrEnumerateData()
    {
        var root = CreateRoot();
        var missing = Path.Combine(root, "not-created");
        try
        {
            AssertFalse(BridgeRequestPolicy.RequiresAccountContext(
                ApplicationSupportRequestNames.GetDataLocation), "location works signed out");
            using var dispatcher = new ApplicationSupportBridgeDispatcher(missing, null);
            var response = await dispatcher.DispatchAsync(Request(
                ApplicationSupportRequestNames.GetDataLocation, "location", 0, new { schemaVersion = 1 }));
            AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "location status");
            AssertEqual(missing, response.Response.Payload.GetProperty("path").GetString(), "owned path");
            AssertEqual(false, response.Response.Payload.GetProperty("exists").GetBoolean(), "missing folder");
            AssertFalse(Directory.Exists(missing), "read must not create data directory");
            var safe = await dispatcher.DispatchAsync(Request("safe-after-location", 0));
            AssertFalse(safe.Response.Payload.GetRawText().Contains(missing), "safe summary must not contain location");
            var injected = await dispatcher.DispatchAsync(Request(
                ApplicationSupportRequestNames.GetDataLocation, "injection", 0,
                new { schemaVersion = 1, path = root }));
            AssertEqual(BridgeErrorCodes.InvalidEnvelope, injected.Response.Error?.Code, "reject supplied path");
            var stale = await dispatcher.DispatchAsync(Request(
                ApplicationSupportRequestNames.GetDataLocation, "stale-location", 1, new { schemaVersion = 1 }));
            AssertEqual(BridgeErrorCodes.StaleGeneration, stale.Response.Error?.Code, "location stale");
        }
        finally { Directory.Delete(root, recursive: true); }
    }

    internal static async Task DispatcherProjectsStructuredSafeSnapshot()
    {
        using var dispatcher = new ApplicationSupportBridgeDispatcher(
            new FixedInspector(
                new ApplicationSupportSnapshot(
                    new(ApplicationSupportStates.Healthy, "writable"),
                    new(ApplicationSupportStates.ActionRequired, "notConfigured"),
                    new(
                        ApplicationSupportStates.Healthy,
                        "notEnabled",
                        Registered: false,
                        TargetExists: null,
                        TargetsCurrentExecutable: null),
                    new(
                        ApplicationSupportStates.ActionRequired,
                        "duplicateInstallations",
                        "ambiguous",
                        CurrentInstallations: 1,
                        OtherInstallations: 2,
                        OrphanedRegistrations: 0,
                        ScanWarnings: 0))),
            () => 7);

        var response = await dispatcher.DispatchAsync(Request("support-read", 7));
        AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "response status");
        AssertEqual(true, response.Response.Payload.GetProperty("hasIssues").GetBoolean(), "issues");
        AssertEqual(false, response.Response.Payload.GetProperty("hasUnavailableChecks").GetBoolean(), "unavailable");
        var checks = response.Response.Payload.GetProperty("checks");
        AssertEqual("writable", checks.GetProperty("dataDirectory").GetProperty("detail").GetString(), "data directory");
        AssertEqual("notConfigured", checks.GetProperty("gameLog").GetProperty("detail").GetString(), "game log");
        AssertEqual(2, checks.GetProperty("installation").GetProperty("otherInstallations").GetInt32(), "other installs");
        var wire = response.Response.Payload.GetRawText();
        AssertFalse(wire.Contains("token", StringComparison.OrdinalIgnoreCase), "payload contains no token field");
        AssertFalse(wire.Contains("path", StringComparison.OrdinalIgnoreCase), "payload contains no path field");
        using var composite = new StarBridge.HostRuntime.CompositeBridgeDispatcher(
            new ApplicationSupportBridgeDispatcher(new ThrowingInspector()),
            new ApplicationSupportBridgeDispatcher(new ThrowingInspector()),
            new ApplicationSupportBridgeDispatcher(new ThrowingInspector()), support: dispatcher);
        var routed = await composite.DispatchAsync(Request("support-composite", 7));
        AssertEqual(BridgeResponseStatuses.Ok, routed.Response.Status, "real composite routes support requests");
    }

    internal static void WindowsInspectorChecksFilesWithoutReturningPaths()
    {
        var root = CreateRoot();
        var gameLog = Path.Combine(root, "Game.log");
        File.WriteAllText(gameLog, "session");
        try
        {
            var inspector = new WindowsApplicationSupportInspector(
                root,
                Path.Combine(root, "starbridge_flutter.exe"),
                () => gameLog);
            var snapshot = inspector.Inspect();

            AssertEqual(ApplicationSupportStates.Healthy, snapshot.DataDirectory.State, "data state");
            AssertEqual("writable", snapshot.DataDirectory.Detail, "data detail");
            AssertEqual(ApplicationSupportStates.Healthy, snapshot.GameLog.State, "log state");
            AssertEqual("readable", snapshot.GameLog.Detail, "log detail");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static void WindowsInspectorDistinguishesMissingLogSelection()
    {
        var root = CreateRoot();
        try
        {
            var notConfigured = new WindowsApplicationSupportInspector(
                root,
                Path.Combine(root, "starbridge_flutter.exe"));
            AssertEqual(
                "notConfigured",
                notConfigured.Inspect().GameLog.Detail,
                "unconfigured log");

            var missing = new WindowsApplicationSupportInspector(
                root,
                Path.Combine(root, "starbridge_flutter.exe"),
                () => Path.Combine(root, "missing", "Game.log"));
            AssertEqual("fileMissing", missing.Inspect().GameLog.Detail, "missing log");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static void WindowsInspectorOpensOnlyItsOwnedDataRoot()
    {
        var root = CreateRoot();
        string? opened = null;
        try
        {
            var inspector = new WindowsApplicationSupportInspector(
                root,
                Path.Combine(root, "starbridge_flutter.exe"),
                openDirectory: path => opened = path);

            inspector.OpenDataDirectory();

            AssertEqual(
                Path.TrimEndingDirectorySeparator(Path.GetFullPath(root)),
                opened,
                "opened data root");
        }
        finally
        {
            Directory.Delete(root, recursive: true);
        }
    }

    internal static void InstallationClassificationPreservesPortableMode()
    {
        var portable = WindowsApplicationSupportInspector.ClassifyInstallations([], 0);
        AssertEqual(ApplicationSupportStates.Healthy, portable.State, "portable state");
        AssertEqual("portable", portable.Mode, "portable mode");

        var installed = WindowsApplicationSupportInspector.ClassifyInstallations(
            [new InstallationEntry(ValidUninstaller: true, IsCurrent: true)],
            0);
        AssertEqual(ApplicationSupportStates.Healthy, installed.State, "installed state");
        AssertEqual("installed", installed.Mode, "installed mode");

        var duplicate = WindowsApplicationSupportInspector.ClassifyInstallations(
            [
                new InstallationEntry(ValidUninstaller: true, IsCurrent: true),
                new InstallationEntry(ValidUninstaller: true, IsCurrent: false)
            ],
            0);
        AssertEqual(ApplicationSupportStates.ActionRequired, duplicate.State, "duplicate state");
        AssertEqual("duplicateInstallations", duplicate.Detail, "duplicate detail");

        var orphaned = WindowsApplicationSupportInspector.ClassifyInstallations(
            [new InstallationEntry(ValidUninstaller: false, IsCurrent: false)],
            0);
        AssertEqual(ApplicationSupportStates.ActionRequired, orphaned.State, "orphan state");
        AssertEqual("staleRegistrations", orphaned.Detail, "orphan detail");

        var partial = WindowsApplicationSupportInspector.ClassifyInstallations([], 1);
        AssertEqual(ApplicationSupportStates.Unavailable, partial.State, "partial state");
        AssertEqual("scanPartial", partial.Detail, "partial detail");
    }

    internal static void StartupCommandParserAcceptsFlutterExecutable()
    {
        var executable = Path.GetFullPath(
            Path.Combine(Path.GetTempPath(), "Star Bridge", "starbridge_flutter.exe"));
        AssertEqual(
            true,
            WindowsApplicationSupportInspector.TryParseCommand(
                $"\"{executable}\" --startup",
                out var parsed),
            "quoted startup command");
        AssertEqual(executable, parsed, "quoted executable");
        AssertEqual(
            true,
            WindowsApplicationSupportInspector.TryParseCommand(
                $"{executable} --startup",
                out parsed),
            "unquoted startup command");
        AssertEqual(executable, parsed, "unquoted executable");
    }

    internal static async Task DispatcherFailsClosed()
    {
        using var dispatcher = new ApplicationSupportBridgeDispatcher(
            new ThrowingInspector(),
            () => 3);
        var failed = await dispatcher.DispatchAsync(Request("support-failed", 3));
        AssertEqual(BridgeResponseStatuses.Error, failed.Response.Status, "failure status");
        AssertEqual(
            ApplicationSupportStableErrors.InspectionFailed,
            failed.Response.Error?.Code,
            "failure code");
        AssertEqual(true, failed.Response.Error?.Retryable, "failure retryable");

        var stale = await dispatcher.DispatchAsync(Request("support-stale", 2));
        AssertEqual(BridgeResponseStatuses.Error, stale.Response.Status, "stale status");
        AssertEqual(BridgeErrorCodes.StaleGeneration, stale.Response.Error?.Code, "stale code");
    }

    internal static async Task DispatcherOpensOwnedDirectoryWithoutAcceptingAPath()
    {
        AssertFalse(
            BridgeRequestPolicy.RequiresAccountContext(
                ApplicationSupportRequestNames.OpenDataDirectory),
            "open data directory is account agnostic");
        var actions = new RecordingActions();
        using var dispatcher = new ApplicationSupportBridgeDispatcher(
            new FixedInspector(HealthySnapshot()),
            actions,
            () => 7);

        var opened = await dispatcher.DispatchAsync(
            Request(
                ApplicationSupportRequestNames.OpenDataDirectory,
                "support-open",
                7,
                new { schemaVersion = 1 }));
        AssertEqual(BridgeResponseStatuses.Ok, opened.Response.Status, "open status");
        AssertEqual(true, opened.Response.Payload.GetProperty("opened").GetBoolean(), "opened");
        AssertEqual(1, actions.OpenCount, "open count");

        var injectedPath = await dispatcher.DispatchAsync(
            Request(
                ApplicationSupportRequestNames.OpenDataDirectory,
                "support-path-injection",
                7,
                new { schemaVersion = 1, path = @"C:\\Users\\someone-else" }));
        AssertEqual(BridgeResponseStatuses.Error, injectedPath.Response.Status, "path injection status");
        AssertEqual(
            BridgeErrorCodes.InvalidEnvelope,
            injectedPath.Response.Error?.Code,
            "path injection error");
        AssertEqual(1, actions.OpenCount, "path injection did not open");
    }

    private static BridgeEnvelope Request(string id, long generation) =>
        Request(
            ApplicationSupportRequestNames.Inspect,
            id,
            generation,
            new { schemaVersion = 1 });

    private static BridgeEnvelope Request(
        string name,
        string id,
        long generation,
        object payload) =>
        BridgeEnvelope.Request(name, id, generation, payload);

    private static ApplicationSupportSnapshot HealthySnapshot() => new(
        new(ApplicationSupportStates.Healthy, "writable"),
        new(ApplicationSupportStates.Healthy, "readable"),
        new(
            ApplicationSupportStates.Healthy,
            "notEnabled",
            Registered: false,
            TargetExists: null,
            TargetsCurrentExecutable: null),
        new(
            ApplicationSupportStates.Healthy,
            "portable",
            "portable",
            CurrentInstallations: 0,
            OtherInstallations: 0,
            OrphanedRegistrations: 0,
            ScanWarnings: 0));

    private static string CreateRoot()
    {
        var root = Path.Combine(
            Path.GetTempPath(),
            $"starbridge-support-{Guid.NewGuid():N}");
        Directory.CreateDirectory(root);
        return root;
    }

    private static void AssertFalse(bool value, string label)
    {
        if (value)
        {
            throw new InvalidOperationException(label);
        }
    }

    private static void AssertEqual<T>(T expected, T actual, string label)
    {
        if (!EqualityComparer<T>.Default.Equals(expected, actual))
        {
            throw new InvalidOperationException(
                $"{label}: expected '{expected}', actual '{actual}'.");
        }
    }

    private sealed class FixedInspector(ApplicationSupportSnapshot snapshot)
        : IApplicationSupportInspector
    {
        public ApplicationSupportSnapshot Inspect() => snapshot;
    }

    private sealed class ThrowingInspector : IApplicationSupportInspector
    {
        public ApplicationSupportSnapshot Inspect() =>
            throw new IOException("Synthetic path and account details must not cross the Bridge.");
    }

    private sealed class RecordingActions : IApplicationSupportActions
    {
        internal int OpenCount { get; private set; }

        public void OpenDataDirectory() => OpenCount++;
    }
}
