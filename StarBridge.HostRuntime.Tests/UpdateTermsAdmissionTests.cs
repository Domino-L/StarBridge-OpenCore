using StarBridge.HostRuntime.Lifecycle;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Updates;
using StarBridge.NativeBridge;

internal static class UpdateTermsAdmissionTests
{
    internal static async Task Run()
    {
        var root = Path.Combine(Path.GetTempPath(), "update-terms-" + Guid.NewGuid().ToString("N"));
        Directory.CreateDirectory(root);
        try
        {
            var terms = new TestBuildNoticeStore(root);
            var ordinary = new DeviceNetworkAdmission(() => false);
            var source = new Source();
            var downloads = 0;
            var installation = new FlutterUpdateInstallation((_, _) => {
                downloads++; return Task.FromResult("synthetic-update");
            }, (_, _) => Task.CompletedTask);
            using var bridge = new FlutterUpdateBridgeDispatcher(source, () => "0.7.2", () => 1,
                installation: installation, network: ordinary, terms: terms);
            BridgeEnvelope Request(string name, object payload) => BridgeEnvelope.Request(name,
                Guid.NewGuid().ToString("N"), 1, payload);
            var check = Request(FlutterUpdateBridgeDispatcher.RequestName, new { schemaVersion = 1 });
            var prepare = Request(FlutterUpdateBridgeDispatcher.PrepareRequestName, new { schemaVersion = 1, version = "0.7.3" });
            Require((await bridge.DispatchAsync(check)).Response.Status == "error" &&
                (await bridge.DispatchAsync(prepare)).Response.Status == "error" && source.Calls == 0 && downloads == 0,
                "Missing terms cannot check or download");
            File.WriteAllText(Path.Combine(root, TestBuildNoticeStore.FileName),
                "{\"SchemaVersion\":1,\"TermsVersion\":\"old\"}");
            Require((await bridge.DispatchAsync(check)).Response.Status == "error", "Old terms do not admit manual updates");
            File.WriteAllText(Path.Combine(root, TestBuildNoticeStore.LegacyFileName),
                "{\"SchemaVersion\":1,\"TermsVersion\":\"" + TestBuildNoticeStore.TermsVersion + "\"}");
            Require((await bridge.DispatchAsync(check)).Response.Status == "error",
                "The 0.7.2.1 file is not read for the current terms");
            terms.Acknowledge(TestBuildNoticeStore.TermsVersion, "Synthetic terms fixture", () => true);
            Require((await bridge.DispatchAsync(check)).Response.Status == "ok" &&
                (await bridge.DispatchAsync(prepare)).Response.Status == "ok" && source.Calls == 1 && downloads == 1,
                "Current terms admit manual checks and downloads without any onboarding or account state");
            Require(ordinary.Enter() is null, "Ordinary device network remains closed in local mode");
            var automatic = Request(FlutterUpdateBridgeDispatcher.RequestName, new { schemaVersion = 1, automatic = true });
            Require((await bridge.DispatchAsync(automatic)).Response.Status == "error" && source.Calls == 1,
                "Background checks retain device-mode admission even after terms are accepted");
            source.Hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
            var pending = bridge.DispatchAsync(check).AsTask();
            await source.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            File.Delete(Path.Combine(root, TestBuildNoticeStore.FileName));
            source.Hold.TrySetResult();
            Require((await pending).Response.Status == "cancelled", "Invalid terms invalidate an in-flight update lease");
            terms.Acknowledge(TestBuildNoticeStore.TermsVersion, "Synthetic terms fixture", () => true);
            source.Hold = new(TaskCreationOptions.RunContinuationsAsynchronously);
            source.Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
            pending = bridge.DispatchAsync(check).AsTask();
            await source.Entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
            bridge.Dispose();
            Require((await pending).Response.Status == "cancelled", "Exit retires and cancels the dedicated update epoch");
            Console.WriteLine("PASS manual update terms: missing/old/current receipt, local mode, download, invalid lease and retirement");
        }
        finally { Directory.Delete(root, true); }
    }
    private static void Require(bool value, string message) { if (!value) throw new Exception(message); }
    private sealed class Source : IApplicationUpdateSource
    {
        internal int Calls;
        internal TaskCompletionSource? Hold;
        internal TaskCompletionSource Entered = new(TaskCreationOptions.RunContinuationsAsynchronously);
        public async Task<ApplicationUpdateCheck> CheckForUpdateAsync(CancellationToken token = default)
        {
            Calls++;
            if (Hold is { } hold) { Entered.TrySetResult(); await hold.Task.WaitAsync(token); }
            return new("up-to-date");
        }
        public void Dispose() { }
    }
}
