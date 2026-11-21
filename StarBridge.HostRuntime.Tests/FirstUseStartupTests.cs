using System.Security.AccessControl;
using System.Security.Principal;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.NativeBridge;

internal static class FirstUseStartupTests
{
    internal static async Task Run()
    {
        FirstUseInstalledSourceTests.Run();
        var root = Path.Combine(Path.GetTempPath(), "starbridge-startup-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            string Area(string name) => Path.Combine(root, name);
            FirstUseStartupReader Reader(string name, string? kind) => new(Area(name), () => kind is null ? null : new(kind, "0.7.2"));
            Check(Reader("missing", null).Read() == new FirstUseStartupObservation("unknown", "installationUnknown", false), "Missing new marker is not a new user");
            Check(!Directory.Exists(Area("missing")), "Startup read creates no product data");
            Check(Reader("fresh", "fresh").Read().Eligibility == "firstUse", "Verified fresh install can start setup");
            Check(Reader("update", "update").Read().Eligibility == "returning", "Update without local data must not force setup");
            Check(Reader("unknown", "untrusted").Read().Eligibility == "unknown", "Unknown source is not fresh");
            // Existing official users who never saved preferences: account log /
            // play-time stores and the event journal still prove previous use.
            foreach (var directory in new[] { "game-log-local-v1", "gameplay-time-local-v1" })
            {
                var area = Area("dir-" + directory);
                Directory.CreateDirectory(Path.Combine(area, directory));
                Check(Reader("dir-" + directory, "fresh").Read() == new FirstUseStartupObservation("returning", "previousUse", false),
                    "Previous account data survives a fresh-looking reinstall");
                Check(Reader("dir-" + directory, null).Read().Eligibility == "returning", "Data outranks a missing install stamp");
            }
            var wrongType = Area("wrong-type");
            Directory.CreateDirectory(Path.Combine(wrongType, "local-event-log.json"));
            Check(Reader("wrong-type", "fresh").Read().Eligibility == "unknown", "Unexpected marker shape is unknown, not new");
            foreach (var file in new[] { "desktop.config", "onboarding.complete", "onboarding-introduction.read", "application-preferences.v1.json", "application-behavior.json", "local-event-log.json" })
            {
                var name = Path.GetFileNameWithoutExtension(file);
                Directory.CreateDirectory(Area(name));
                var path = Path.Combine(Area(name), file);
                File.WriteAllText(path, "synthetic previous use; deliberately not parsed");
                var before = File.ReadAllBytes(path);
                Check(Reader(name, "fresh").Read().Eligibility == "returning", "Existing use survives reinstall and new Flutter marker");
                Check(before.SequenceEqual(File.ReadAllBytes(path)), "Existing history is not rewritten");
            }
            var pending = new LocalFirstUseStore(Area("pending"));
            pending.SaveProgress(0, Guid.NewGuid().ToString("N"), new("mode", "local", null, null, null), () => true);
            var pendingReader = Reader("pending", "update");
            Check(pendingReader.Read() == new FirstUseStartupObservation("firstUse", "resume", true), "Confirmed partial setup survives an update");
            File.WriteAllText(Path.Combine(Area("pending"), "application-preferences.v1.json"), "synthetic new settings");
            Check(Reader("pending", "update").Read().Reason == "resume", "Setup's saved settings do not erase resumable progress");
            // Restart regression: a returning user who switches in Usage mode or
            // picks a log in settings saves progress, and must stay returning.
            var marker = (string name) => File.Exists(Path.Combine(Area(name), FirstUseStartupReader.MarkerDirectory, FirstUseStartupReader.ReturningMarker));
            var started = (string name) => File.Exists(Path.Combine(Area(name), FirstUseStartupReader.MarkerDirectory, FirstUseStartupReader.StartedMarker));
            Check(marker("update") && !started("update"), "Returning is recorded even when the data root did not exist yet");
            Directory.CreateDirectory(Area("fresh"));
            Check(Reader("fresh", "fresh").Read().Eligibility == "firstUse" && !marker("fresh"), "A new user gets no returning marker");
            foreach (var (name, kind, reason) in new[] { ("switch-device", "fresh", "previousUse"), ("switch-update", "update", "updateInstallation") })
            {
                Directory.CreateDirectory(Area(name));
                if (name == "switch-device") File.WriteAllText(Path.Combine(Area(name), "application-preferences.v1.json"), "synthetic previous use");
                Check(Reader(name, kind).Read() == new FirstUseStartupObservation("returning", reason, false) && marker(name), "Returning start is remembered: " + name);
                var store = new LocalFirstUseStore(Area(name));
                store.SaveProgress(0, Guid.NewGuid().ToString("N"), new("mode", "online", null, null, null), () => true);
                store.SaveProgress(1, Guid.NewGuid().ToString("N"), new("mode", "local", null, null, null), () => true);
                Check(Reader(name, kind).Read() == new FirstUseStartupObservation("returning", "previousUse", false),
                    "Usage-mode progress does not turn a returning user into first use after restart: " + name);
                Check(Reader(name, null).Read().Eligibility == "returning", "The marker outranks a missing install stamp: " + name);
            }
            // An updated install whose store was written only outside the guide
            // (no guide progress) is previous use; a fresh install still resumes.
            foreach (var (name, kind, eligibility) in new[] { ("settings-update", "update", "returning"), ("settings-fresh", "fresh", "firstUse") })
            {
                new LocalFirstUseStore(Area(name)).ClearDeferredStatistics(0, Guid.NewGuid().ToString("N"), () => true);
                Check(Reader(name, kind).Read().Eligibility == eligibility, "Store without guide progress: " + name);
            }
            // A new user whose guide page was cleared by choosing another log stays
            // a new user after an update; the start marker outranks the update rule.
            {
                Check(Reader("started-update", "fresh").Read().Eligibility == "firstUse" && started("started-update") && !marker("started-update"),
                    "A new user's start is remembered");
                var store = new LocalFirstUseStore(Area("started-update"));
                store.SaveProgress(0, Guid.NewGuid().ToString("N"), new("log", "local", null, null, null), () => true);
                store.SelectSource(1, Guid.NewGuid().ToString("N"), Path.Combine(Area("started-update"), "game", "LIVE", "Game.log"), "LIVE", () => true);
                Check(store.Read() is { Progress: null, Revision: > 0 }, "Choosing a new log clears the guide page");
                Check(Reader("started-update", "update").Read() == new FirstUseStartupObservation("firstUse", "resume", true) && !marker("started-update"),
                    "An update cannot turn a new user with a cleared page into a returning user");
            }
            // A new user who quits before the first guide save stays new: after an
            // update, after ordinary device use, and after a rollback to a build that
            // never reads the marker followed by an upgrade.
            {
                var zero = Area("started-zero");
                Directory.CreateDirectory(zero);
                Check(Reader("started-zero", "fresh").Read() == new FirstUseStartupObservation("firstUse", "freshInstallation", false) &&
                    started("started-zero"), "A new user's start is remembered before anything is saved");
                Check(new LocalFirstUseStore(zero).Read().Revision == 0, "Quit before the first save");
                Check(Reader("started-zero", "update").Read() == new FirstUseStartupObservation("firstUse", "freshInstallation", false) &&
                    !marker("started-zero"), "An update cannot record a zero-progress new user as returning");
                var old = new StarBridge.HostRuntime.Onboarding.Rollback0721.FirstUseStartupReader(zero,
                    () => new StarBridge.HostRuntime.Onboarding.Rollback0721.FirstUseInstallSource("update", "0.7.2")).Read();
                Check(old.Eligibility is "firstUse" or "returning", "The older build still starts on this root: " + old);
                File.WriteAllText(Path.Combine(zero, "application-preferences.v1.json"), "synthetic settings written by the older build");
                Check(started("started-zero"), "A rollback leaves the start marker in place");
                Check(Reader("started-zero", "update").Read() == new FirstUseStartupObservation("firstUse", "freshInstallation", false) &&
                    !marker("started-zero"), "Rollback, device use and an upgrade keep a zero-progress new user in setup");
                var store = new LocalFirstUseStore(zero);
                store.SaveProgress(0, Guid.NewGuid().ToString("N"), new("log", "local", null, null, null), () => true);
                Check(Reader("started-zero", "update").Read() == new FirstUseStartupObservation("firstUse", "resume", true),
                    "Once saved, the same user resumes");
                new FirstUseCompletionStore(zero).Save(null, Guid.NewGuid().ToString("N"), "local", Guid.NewGuid().ToString("N"),
                    "synthetic-source-0001", () => true);
                Check(Reader("started-zero", "update").Read() == new FirstUseStartupObservation("returning", "completedSetup", false),
                    "Completing setup ends first use despite the start marker");
            }
            // The marker cannot be written: the failure is reported, nothing may be
            // saved, the next start answers the same, and the next save records it.
            {
                var blocked = Area("blocked");
                var folder = Path.Combine(blocked, FirstUseStartupReader.MarkerDirectory);
                Directory.CreateDirectory(folder);
                File.WriteAllText(Path.Combine(blocked, "application-preferences.v1.json"), "synthetic previous use");
                var info = new DirectoryInfo(folder);
                var security = info.GetAccessControl();
                var denied = new DirectorySecurity();
                denied.SetSecurityDescriptorBinaryForm(security.GetSecurityDescriptorBinaryForm(), AccessControlSections.Access);
                FirstUseStartupReader blockedReader;
                using (var identity = WindowsIdentity.GetCurrent())
                {
                    var rule = new FileSystemAccessRule(identity.User!, FileSystemRights.CreateFiles, AccessControlType.Deny);
                    denied.AddAccessRule(rule);
                    info.SetAccessControl(denied);
                    try
                    {
                        blockedReader = Reader("blocked", "fresh");
                        Check(blockedReader.Read() == new FirstUseStartupObservation("returning", "previousUse", false) && !marker("blocked") &&
                            !blockedReader.EnsureRecorded(), "A marker that cannot be written is reported, not assumed");
                        Check(Reader("blocked", "fresh").Read().Eligibility == "returning", "Nothing saved, so the next start answers the same");
                    }
                    finally
                    {
                        // Writing back the unmodified original object changes nothing;
                        // remove the deny rule explicitly.
                        denied.RemoveAccessRuleSpecific(rule);
                        info.SetAccessControl(denied);
                    }
                }
                Check(blockedReader.EnsureRecorded() && marker("blocked"), "The next save records the marker first");
                var store = new LocalFirstUseStore(blocked);
                store.SaveProgress(0, Guid.NewGuid().ToString("N"), new("mode", "online", null, null, null), () => true);
                Check(Reader("blocked", "fresh").Read() == new FirstUseStartupObservation("returning", "previousUse", false),
                    "After the recovered marker, Usage-mode progress stays returning");
            }
            Directory.CreateDirectory(Path.Combine(Area("corrupt"), "local-first-use-v1"));
            var corrupt = Path.Combine(Area("corrupt"), "local-first-use-v1", "state.bin");
            File.WriteAllBytes(corrupt, [1, 2, 3]);
            Check(Reader("corrupt", "fresh").Read().Eligibility == "unknown" && File.ReadAllBytes(corrupt).SequenceEqual(new byte[] { 1, 2, 3 }), "Damaged progress remains unknown and intact");

            long generation = 4;
            using var route = new FirstUseStartupBridgeDispatcher(Reader("fresh", "fresh"), () => generation);
            var request = BridgeEnvelope.Request(FirstUseStartupBridgeDispatcher.ReadRequest, Guid.NewGuid().ToString("N"), generation, new { schemaVersion = 1 });
            using var other = new RejectDispatcher();
            using var composite = new CompositeBridgeDispatcher(other, other, other, firstUseStartup: route);
            var batch = await composite.DispatchAsync(request);
            Check(batch.Response.Status == "ok" && batch.Response.AccountContext is null && batch.Events.Count == 0 &&
                batch.Response.Payload.EnumerateObject().Count() == 4 && batch.Response.Payload.GetProperty("eligibility").GetString() == "firstUse" && other.Calls == 0,
                "Actual composed startup route is finite, accountless and read-only");
            foreach (var invalid in new[] {
                request with { AccountContext = new("fixture", "scm", "synthetic-owner") },
                request with { Payload = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, completed = true }) },
                request with { Payload = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = "1" }) }
            }) Check((await route.DispatchAsync(invalid)).Response.Status == "error", "Renderer cannot supply use or completion claims");
            generation++;
            Check((await route.DispatchAsync(request)).Response.Status == "error", "Stale startup generation is rejected");
            Check(!BridgeRequestPolicy.RequiresAccountContext(FirstUseStartupBridgeDispatcher.ReadRequest) &&
                BridgeRequestPolicy.RequiresAccountContext("onboarding.startup.finish"), "Only exact read route is accountless");
            Console.WriteLine("PASS startup eligibility: fresh/update/unknown, previous use, resumed progress, damaged records and actual composed strict route");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private sealed class RejectDispatcher : IBridgeRequestDispatcher
    {
        internal int Calls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        { Calls++; throw new InvalidOperationException("Startup read reached another owner"); }
        public void Dispose() { }
    }
}
