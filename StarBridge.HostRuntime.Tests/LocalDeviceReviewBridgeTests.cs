using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class LocalDeviceReviewBridgeTests
{
    private static readonly string[] Sections = ["application", "overlay", "notifications", "playReminder"];
    private static BridgeEnvelope Request(LocalDeviceSetupReaderTests.Fixture f, string name, object? payload = null) =>
        BridgeEnvelope.Request(name, Guid.NewGuid().ToString("N"), f.Generation, payload ?? new { schemaVersion = 1 });
    private static void Chosen(LocalDeviceSetupReaderTests.Fixture f) => f.AppStore.Actual.Save(
        ApplicationPreferencesSnapshot.Default with { Revision = 1, StartupChoiceMade = true, CloseBehaviorChoiceMade = true });
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Case(string name, Func<Task> action) { await action(); Console.WriteLine("PASS device review bridge: " + name); }
    internal static async Task Run()
    {
        await Case("actual projections are read-only and omit identity, paths and readiness", Projection);
        await Case("explicit four-section confirmation crosses the actual storage Interface once", Confirmation);
        await Case("strict requests and exact account exemptions cannot broaden authority", Invalid);
        await Case("ordinary settings and generations revoke old confirmation", Stale);
        await Case("failed and disposed owners preserve originals and expose no private detail", Failure);
        await Case("composite routes only two exact review commands to the borrowed owner", Composition);
    }
    private static LocalDeviceReviewBridgeDispatcher Dispatcher(LocalDeviceSetupReaderTests.Fixture f) =>
        new(new(f.Reader, new(f.Device)), () => f.Generation);
    private static async Task Projection()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); using var d = Dispatcher(f); var files = f.Files();
        var read = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response;
        Require(read.Status == "ok" && read.AccountContext is null && read.Payload.GetProperty("state").GetString() == "choicesRequired", "explicit choices, not accepted defaults");
        var raw = read.Payload.GetRawText();
        Require(!raw.Contains(f.Root) && !raw.Contains("Pilot-Example") &&
            new[] { "profileId", "sourceKey", "localSettingsReady", "revision", "hostGeneration" }
                .All(field => !raw.Contains(field, StringComparison.OrdinalIgnoreCase)), "allowlisted presentation only");
        f.Unchanged(files); Require(f.Startup.Writes + f.Native.Commands + f.AccountReads + f.ProcessReads + f.Sink.Calls == 0, "no side effects");
    }
    private static async Task Confirmation()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); using var d = Dispatcher(f); var files = f.Files();
        var key = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response.Payload.GetProperty("reviewKey").GetString();
        var command = Request(f, LocalDeviceReviewBridgeDispatcher.ConfirmRequest, new { schemaVersion = 1, reviewKey = key, reviewedSections = Sections });
        var reply = (await d.DispatchAsync(command)).Response;
        Require(reply.Status == "ok" && reply.Payload.GetProperty("state").GetString() == "reviewed", "actual review committed");
        Require((await d.DispatchAsync(command)).Response.Error?.Code == "firstUse.context_changed", "consumed observation cannot replay");
        Require(new LocalDeviceReviewStore(f.Device).Read().Revision == 1 && files.All(p => f.Files()[p.Key] == p.Value), "domain settings unchanged");
    }
    private static async Task Invalid()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); using var d = Dispatcher(f); var files = f.Files();
        foreach (var json in new[] { "{}", "[]", "{\"schemaVersion\":1,\"schemaVersion\":1}", "{\"schemaVersion\":true}",
            "{\"schemaVersion\":1,\"path\":\"private\"}" })
        {
            using var document = JsonDocument.Parse(json);
            var reply = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest, document.RootElement))).Response;
            Require(reply.Status == "error" && reply.Error?.Code == "firstUse.invalid_request", "strict fields");
        }
        var key = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response.Payload.GetProperty("reviewKey").GetString();
        foreach (var sections in new[] { Array.Empty<string>(), new[] { "application", "overlay", "notifications", "notifications" }, new[] { "application", "overlay", "notifications", "other" } })
            Require((await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ConfirmRequest,
                new { schemaVersion = 1, reviewKey = key, reviewedSections = sections }))).Response.Status == "error", "all four explicit");
        var contextual = Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest) with { AccountContext = new("fixture", "fixture", "fixture") };
        Require((await d.DispatchAsync(contextual)).Response.Status == "error", "renderer account cannot become review authority");
        foreach (var name in new[] { LocalDeviceReviewBridgeDispatcher.ReadRequest, LocalDeviceReviewBridgeDispatcher.ConfirmRequest })
            Require(!BridgeRequestPolicy.RequiresAccountContext(name), "device-only exact exemption");
        Require(BridgeRequestPolicy.RequiresAccountContext("onboarding.deviceReview.delete") &&
            BridgeRequestPolicy.RequiresAccountContext("friends.read"), "no prefix or business exemption");
        f.Unchanged(files);
    }
    private static async Task Stale()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); using var d = Dispatcher(f);
        var key = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response.Payload.GetProperty("reviewKey").GetString();
        var command = Request(f, LocalDeviceReviewBridgeDispatcher.ConfirmRequest, new { schemaVersion = 1, reviewKey = key, reviewedSections = Sections });
        f.Generation++;
        Require((await d.DispatchAsync(command)).Response.Error?.Code == "firstUse.context_changed", "Host epoch guard");
        command = command with { SessionGeneration = f.Generation };
        Require((await d.DispatchAsync(command)).Response.Error?.Code == "firstUse.context_changed", "old ticket not valid in new epoch");
        Chosen(f); var read = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response;
        key = read.Payload.GetProperty("reviewKey").GetString();
        f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 2, StartupChoiceMade = true,
            CloseBehaviorChoiceMade = true, KeepRunningInBackground = false });
        Require((await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ConfirmRequest,
            new { schemaVersion = 1, reviewKey = key, reviewedSections = Sections }))).Response.Error?.Code == "firstUse.context_changed", "actual settings recheck");
    }
    private static async Task Failure()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var d = Dispatcher(f);
        var directory = Path.Combine(f.Device, "first-use-device-review-v1"); Directory.CreateDirectory(directory);
        var path = Path.Combine(directory, "state.bin"); File.WriteAllText(path, "damaged synthetic record");
        var files = f.Files(); var reply = (await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response;
        Require(reply.Error?.Code == "firstUse.device_review_read_failed" && !reply.Error.Message.Contains(f.Root), "safe storage failure");
        d.Dispose(); Require((await d.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response.Status == "error", "closed owner");
        f.Unchanged(files);
    }
    private static async Task Composition()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var fallback = new NeverDispatch();
        using var composite = new CompositeBridgeDispatcher(fallback, fallback, f.Application, firstUseDeviceReview: Dispatcher(f));
        var read = (await composite.DispatchAsync(Request(f, LocalDeviceReviewBridgeDispatcher.ReadRequest))).Response;
        Require(read.Status == "ok" && fallback.Calls == 0, "real exact routing");
        Require((await composite.DispatchAsync(Request(f, "onboarding.deviceReview.delete"))).Response.Status == "error" &&
            fallback.Calls == 0 && !AccountBridgeRuntime.AdvertisedCapabilities.Contains("onboarding.firstUse.v1"), "no completion or prefix authority");
    }
    private sealed class NeverDispatch : IBridgeRequestDispatcher
    {
        internal int Calls;
        public event Action<BridgeEnvelope>? EventReady { add { } remove { } }
        public ValueTask<BridgeDispatchBatch> DispatchAsync(BridgeEnvelope request, CancellationToken token = default)
        { Calls++; throw new InvalidOperationException("Unexpected fallback"); }
        public void Dispose() { }
    }
}
