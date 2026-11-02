using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Settings;

internal static class FirstUseCompletionRuntimeTests
{
    internal static async Task Run()
    {
        await LocalFinish();
        await ChangedSettingsAndIdentity();
        await CloseDuringActualRead();
        await ProductProtocol();
        Console.WriteLine("PASS completion owner: actual local installation, device review, explicit statistics choice, changed identity/settings and physical close");
    }

    private static async Task LocalFinish()
    {
        await using var f = await Fixture.Create();
        Check((await f.Completion.ReadAsync()).State == "needsIdentity", "A saved profile without a listening choice cannot finish");
        await Expect(() => f.Completion.FinishAsync(Op()));
        f.Listening();
        Check((await f.Completion.ReadAsync()).State == "needsSettings", "Defaults and page navigation cannot acknowledge device choices");
        await f.Review();
        Check((await f.Completion.ReadAsync()).State == "needsStatistics", "Identity and device review cannot grant recording consent");
        f.Consent(GameplayRecordingConsent.Declined);
        var ready = await f.Completion.ReadAsync();
        Check(ready.State == "ready" && ready.Mode == "local", "An explicit recording decline completes the choice without recording");
        var before = f.Data.Files();
        var receipt = await f.Completion.FinishAsync(ready.CompletionKey!);
        Check(receipt is { State: "completed", Mode: "local", CompletedMode: "local" }, "Actual owner commits local completion");
        var after = f.Data.Files();
        Check(before.All(pair => after[pair.Key] == pair.Value) && after.Keys.Except(before.Keys).All(p => p.Contains("first-use-completion-v1")),
            "Completion writes only its historical receipt and does not change identity or domain choices");
        Check(f.Network.Calls == 0 && f.Data.Native.Commands == 0 && f.Data.Startup.Writes == 0 && f.Data.Sink.Calls == 0,
            "Finishing local setup contacts no account, registers no startup, invokes no native command and sends no notice");
        Check(new FirstUseCompletionStore(f.Data.Device).Read()?.Mode == "local", "Completion survives actual store reopen");
        await Expect(() => f.Completion.FinishAsync(ready.CompletionKey!));
    }

    private static async Task ChangedSettingsAndIdentity()
    {
        await using var f = await Fixture.Create(); f.Listening(); await f.Review(); f.Consent(GameplayRecordingConsent.Allowed);
        var ready = await f.Completion.ReadAsync();
        f.Data.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 2, StartupChoiceMade = true,
            CloseBehaviorChoiceMade = true, KeepRunningInBackground = false });
        await Expect(() => f.Completion.FinishAsync(ready.CompletionKey!));
        Check(new FirstUseCompletionStore(f.Data.Device).Read() is null, "Changed device choices cannot use an old completion key");
        await f.Review(saveChoices: false);
        ready = await f.Completion.ReadAsync();
        var state = f.Data.Store.Read();
        f.Data.Store.SelectSource(state.Revision, Op(), Path.Combine(f.Data.Root, "install", "PTU", "Game.log"), "PTU", () => true);
        await Expect(() => f.Completion.FinishAsync(ready.CompletionKey!));
        Check(new FirstUseCompletionStore(f.Data.Device).Read() is null && f.Data.Store.Read().Profiles.Count == 1,
            "Changing source cannot finish the old profile, delete it or merge identities");
    }

    private static async Task CloseDuringActualRead()
    {
        await using var f = await Fixture.Create(); f.Listening(); await f.Review(); f.Consent(GameplayRecordingConsent.Declined);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var release = new ManualResetEventSlim();
        var entered = new TaskCompletionSource(TaskCreationOptions.RunContinuationsAsynchronously);
        f.Data.AppStore.OnLoad = _ => { entered.TrySetResult(); release.Wait(); };
        var pending = Task.Run(() => f.Completion.ReadAsync());
        await entered.Task.WaitAsync(TimeSpan.FromSeconds(5));
        var close = native.DisposeAsync().AsTask();
        Check(!close.IsCompleted, "Control retirement waits for the real held device read");
        release.Set();
        try { await pending; } catch (OperationCanceledException) { }
        await close.WaitAsync(TimeSpan.FromSeconds(5));
        f.Data.AppStore.OnLoad = null;
        Check((await f.Completion.ReadAsync()).State == "unavailable" && new FirstUseCompletionStore(f.Data.Device).Read() is null,
            "Closing the actual owner discards late readiness and creates no completion record");
    }

    private static string Op() => Guid.NewGuid().ToString("N");
    private static async Task ProductProtocol()
    {
        await using var f = await Fixture.Create(); f.Listening(); await f.Review(); f.Consent(GameplayRecordingConsent.Declined);
        var selected = f.Data.Store.Read().Sources.Single();
        Directory.CreateDirectory(Path.GetDirectoryName(selected.LogPath)!);
        File.WriteAllText(selected.LogPath, "");
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var guide = new FirstUseBridgeDispatcher(f.Data.Device, f.Runtime, native,
            new FirstUseStartupReader(f.Data.Device, () => new("fresh", "0.7.2")), new NoPicker(),
            _ => throw new Exception("Local guide attempted online configuration"), () => "en");
        var generation = f.Runtime.FirstUseMode!.ControlGeneration;
        StarBridge.NativeBridge.BridgeEnvelope Request(string name, object body) =>
            StarBridge.NativeBridge.BridgeEnvelope.Request(name, Op(), generation, body);
        var read = await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && read.Response.AccountContext is null && read.Events.Count == 0, "Real guide reads without account context or synthetic events");
        var body = read.Response.Payload;
        Check(body.GetProperty("facts").GetProperty("localSettingsReady").GetBoolean() && body.GetProperty("completed").ValueKind == System.Text.Json.JsonValueKind.Null,
            "Real device readiness is distinct from completion");
        var checkpoint = new { step = "summary", mode = "local", sourceKey = body.GetProperty("facts").GetProperty("sourceKey").GetString(),
            evidenceKey = body.GetProperty("facts").GetProperty("evidenceKey").GetString() };
        var saved = await guide.DispatchAsync(Request("onboarding.saveProgress", new { schemaVersion = 1,
            expectedStateKey = body.GetProperty("stateKey").GetString(), checkpoint }));
        Check(saved.Response.Status == "ok" && new FirstUseCompletionStore(f.Data.Device).Read() is null,
            "Persisting the summary page cannot mark actual setup complete");
        var finished = await guide.DispatchAsync(Request("onboarding.finish", new { schemaVersion = 1,
            expectedStateKey = saved.Response.Payload.GetProperty("stateKey").GetString(), checkpoint }));
        Check(finished.Response.Status == "ok" && finished.Response.Payload.GetProperty("completed").GetProperty("step").GetString() == "summary" &&
            finished.Response.Payload.GetProperty("completed").GetProperty("evidenceKey").GetString() == checkpoint.evidenceKey,
            "Actual finish returns a durable receipt under the original stable confirmed source");
        Check(new FirstUseCompletionStore(f.Data.Device).Read()?.Mode == "local" && f.Network.Calls == 0, "Product finish persists without online traffic");
        var invalid = await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1, completed = true }));
        Check(invalid.Response.Status == "error", "Renderer cannot insert completion claims into the product read");
        Console.WriteLine("PASS actual first-use product read, progress, finish and bounded metadata");
    }
    private sealed class NoPicker : IFirstUseLogPicker
    { public Task<string?> PickAsync(string locale, CancellationToken token) => throw new Exception("Unexpected picker in completion test"); }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Expect(Func<Task> action)
    { try { await action(); } catch (LocalFirstUseException e) when (e.Code == "firstUse.context_changed") { return; } throw new InvalidOperationException("Expected stale completion rejection"); }

    private sealed class Fixture : IAsyncDisposable
    {
        internal readonly LocalDeviceSetupReaderTests.Fixture Data = new();
        internal readonly NoNetwork Network = new();
        internal AccountBridgeRuntime Runtime = null!;
        internal FirstUseCompletionRuntime Completion => Runtime.FirstUseCompletion!;
        internal static async Task<Fixture> Create()
        {
            var f = new Fixture();
            try
            {
                var origin = new Uri("https://synthetic-scm.example.invalid/");
                var options = new ScmOAuthOptions("fixture", origin, origin, origin, "synthetic-client", "synthetic-resource", "profile.read", "/callback");
                var oauth = new OAuthPkceClient(new ScmHttpClient(f.Network), new EmptyVault(), options);
                var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(Path.Combine(f.Data.Device, "cache")), "fixture", () => null, initialGeneration: 1);
                await host.GetCurrentAsync(default);
                f.Runtime = new(host, gameLog: new GameLogSettingsStore(f.Data.Device));
                await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Data.Device, _ => Task.FromResult(f.Runtime), localGameProbe: () => new("notRunning"));
                Check((await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Runtime.Generation)).State == "local", "Real account retirement establishes local mode");
                f.Data.Generation = f.Runtime.FirstUseMode.ControlGeneration;
                f.Runtime.ConfigureFirstUseDeviceSetup(f.Data.Application, f.Data.Overlay, f.Data.Notifications, f.Data.Reminder);
                return f;
            }
            catch { await f.DisposeAsync(); throw; }
        }
        internal void Listening()
        {
            var state = Data.Store.Read();
            Data.Store.SetListening(state.Revision, Op(), state.SelectedSourceKey!, true, () => true);
        }
        internal async Task Review(bool saveChoices = true)
        {
            if (saveChoices) Data.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 1, StartupChoiceMade = true, CloseBehaviorChoiceMade = true });
            var review = Runtime.FirstUseDeviceReview!;
            var observed = await review.ReadAsync();
            Check((await review.ConfirmAsync(observed.ReviewKey!, ["application", "overlay", "notifications", "playReminder"])).State == "reviewed", "Real device choices are explicitly reviewed");
        }
        internal void Consent(GameplayRecordingConsent choice)
        {
            var profile = Data.Store.Read().ActiveProfileId!;
            var store = new LocalGameplayTimeStore(Data.Device);
            using var lease = store.Open(profile, () => true);
            var old = store.Read(profile);
            lease.Save(old, old with { Consent = choice }, () => true);
        }
        public async ValueTask DisposeAsync()
        {
            if (Runtime is not null) { await Runtime.RetireFirstUseControlsAsync(); await Runtime.RetireFirstUseLocalSourcesAsync(); Runtime.Dispose(); }
            Data.Dispose(); Network.Dispose();
        }
    }
    private sealed class EmptyVault : ITokenVault
    {
        public string? LoadActiveAccountKey() => null;
        public string? LoadRefreshToken(string key) => null;
        public void SaveRefreshToken(string key, string token) => throw new Exception("Unexpected credential write");
        public void DeleteRefreshToken(string key) => throw new Exception("Unexpected credential deletion");
    }
    private sealed class NoNetwork : HttpMessageHandler
    {
        internal int Calls;
        protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken token)
        { Calls++; throw new Exception("Local completion must not contact an account service"); }
    }
}
