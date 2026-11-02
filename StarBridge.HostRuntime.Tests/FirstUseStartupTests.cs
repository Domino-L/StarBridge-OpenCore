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
