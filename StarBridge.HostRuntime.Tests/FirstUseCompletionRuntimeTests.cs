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
        await BootstrapAtLog();
        await LocalFinish();
        await NoLogFinish();
        await ChangedSettingsAndIdentity();
        await CloseDuringActualRead();
        await ProductProtocol();
        Console.WriteLine("PASS completion owner: actual local installation, device review, explicit statistics choice, changed identity/settings and physical close");
    }

    private static async Task BootstrapAtLog()
    {
        await using var f = await Fixture.Create(startLocal: false);
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        using var guide = new FirstUseBridgeDispatcher(f.Data.Device, f.Runtime, native,
            new FirstUseStartupReader(f.Data.Device, () => new("fresh", "0.7.3")), new NoPicker(),
            _ => throw new Exception("Bootstrap must not configure an online account"), () => "en");
        var read = await guide.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("onboarding.read", Op(),
            f.Runtime.FirstUseMode!.ControlGeneration, new { schemaVersion = 1 }));
        Check(read.Response.Status == "ok" && f.Network.Calls == 0, "Opening the new guide does not restore an online account");
        var facts = read.Response.Payload.GetProperty("facts");
        var reply = await guide.DispatchAsync(StarBridge.NativeBridge.BridgeEnvelope.Request("onboarding.execute", Op(),
            f.Runtime.FirstUseMode.ControlGeneration, new { schemaVersion = 1,
                expectedStateKey = read.Response.Payload.GetProperty("stateKey").GetString(),
                checkpoint = new { step = "log", mode = "local", sourceKey = facts.GetProperty("sourceKey").GetString(),
                    evidenceKey = facts.GetProperty("evidenceKey").GetString() }, action = "applyMode" }));
        Check(reply.Response.Status == "ok" && f.Runtime.FirstUseMode.LocalMode().Active && f.Network.Calls == 0 &&
            reply.Response.Payload.GetProperty("facts").GetProperty("publicationSuspended").GetBoolean(),
            "Log-first bootstrap requires the original local retirement receipt and makes zero HTTP requests");
        Check(f.Data.Store.Read().Progress is { Step: "log", Mode: "local" } &&
            new FirstUseCompletionStore(f.Data.Device).Read() is null, "Bootstrap writes compatible unfinished progress only");
        Console.WriteLine("PASS log-first bootstrap retires the fresh account before log selection without network or completion");
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

    private static async Task NoLogFinish()
    {
        await using var f = await Fixture.Create();
        var state = f.Data.Store.Read();
        f.Data.Store.DeferLog(state.Revision, Op(), () => true);
        await f.Review();
        Check((await f.Completion.ReadAsync()).State == "needsStatistics", "No-log setup still requires an explicit recording choice");
        var readScopeCurrent = true;
        var revokedChoice = f.Runtime.FirstUseStatistics!.ReadConsent(() => readScopeCurrent);
        readScopeCurrent = false;
        await Expect(() => { f.Runtime.FirstUseStatistics.ConfirmConsent(revokedChoice.ChoiceKey!, true, () => true); return Task.CompletedTask; });
        Check(f.Data.Store.Read().DeferredStatisticsAllowed is null, "A retired read scope cannot save device consent through a newer request");
        var choice = f.Runtime.FirstUseStatistics!.ReadConsent(() => true);
        Check(choice.State == "choiceRequired" && !choice.Recording, "No profile is fabricated for a device choice");
        var declined = f.Runtime.FirstUseStatistics.ConfirmConsent(choice.ChoiceKey!, false, () => true);
        Check(declined is { State: "saved", Consent: "declined", Recording: false }, "No-log setup accepts an explicit decline too");
        choice = f.Runtime.FirstUseStatistics.ReadConsent(() => true);
        var saved = f.Runtime.FirstUseStatistics.ConfirmConsent(choice.ChoiceKey!, true, () => true);
        Check(saved is { State: "saved", Consent: "allowed", Recording: false }, "Allowing statistics without identity cannot start recording");
        var ready = await f.Completion.ReadAsync();
        Check(ready.State == "ready", "Reviewed local no-log setup can finish");
        await using var native = new NativeAccountRuntimeBinding(f.Runtime);
        var path = Path.Combine(f.Data.Root, "later", "LIVE", "Game.log");
        using var guide = new FirstUseBridgeDispatcher(f.Data.Device, f.Runtime, native,
            new FirstUseStartupReader(f.Data.Device, () => new("fresh", "0.7.3")), new PathPicker(path),
            _ => throw new Exception("Unexpected online configuration"), () => "en");
        StarBridge.NativeBridge.BridgeEnvelope Request(string name, object body) =>
            StarBridge.NativeBridge.BridgeEnvelope.Request(name, Op(), f.Runtime.FirstUseMode!.ControlGeneration, body);
        async Task<StarBridge.NativeBridge.BridgeEnvelope> Action(string request, string step, string mode, string? action = null)
        {
            var read = (await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response;
            var facts = read.Payload.GetProperty("facts");
            var checkpoint = new Dictionary<string, object?> { ["step"] = step, ["mode"] = mode,
                ["sourceKey"] = facts.GetProperty("sourceKey").GetString(), ["evidenceKey"] = facts.GetProperty("evidenceKey").GetString() };
            object body = action is null ? new { schemaVersion = 1, expectedStateKey = read.Payload.GetProperty("stateKey").GetString(), checkpoint }
                : new { schemaVersion = 1, expectedStateKey = read.Payload.GetProperty("stateKey").GetString(), checkpoint, action };
            return (await guide.DispatchAsync(Request(request, body))).Response;
        }
        StarBridge.NativeBridge.BridgeEnvelope RetryRequest(StarBridge.NativeBridge.BridgeEnvelope read) =>
            Request("onboarding.execute", new { schemaVersion = 1, expectedStateKey = read.Payload.GetProperty("stateKey").GetString(),
                checkpoint = new { step = "identity", mode = "local",
                    sourceKey = read.Payload.GetProperty("facts").GetProperty("sourceKey").GetString(),
                    evidenceKey = read.Payload.GetProperty("facts").GetProperty("evidenceKey").GetString() }, action = "finishLogSetup" });
        var rejected = await Action("onboarding.execute", "mode", "online", "applyMode");
        Check(rejected.Status == "error" && rejected.Error?.Code == "firstUse.evidence_required" &&
            f.Runtime.FirstUseMode!.Current.State == "local" && f.Network.Calls == 0,
            "Before completion, Host refuses online selection without log identity and performs no network request");
        var finished = await Action("onboarding.finish", "summary", "local");
        Check(finished.Status == "ok" && finished.Payload.GetProperty("completed").ValueKind == System.Text.Json.JsonValueKind.Object,
            "Product protocol returns the no-log completion receipt: " + finished.Status + "/" + finished.Error?.Code);
        var receipt = new FirstUseCompletionStore(f.Data.Device).Read();
        Check(receipt is { Mode: "local", LogDeferred: true, ProfileId: null, SourceKey: null }, "No-log receipt has an explicit marker and no invented identity");
        Check(new FirstUseStartupReader(f.Data.Device, () => new("fresh", "0.7.3")).Read().Reason == "completedSetup", "Restart does not reopen completed no-log setup");
        Check(f.Runtime.FirstUseStatistics.Current.Recording == false && f.Runtime.FirstUseGame!.Current.State != "ready" &&
            f.Data.Store.Read().ActiveProfileId is null, "Completion grants neither recording nor local game/achievement evidence");
        Check(f.Runtime.FirstUseOverlaySource!.Capture()?.Read().State != "ready", "No-log completion does not authorize overlay game data");
        f.Runtime.FirstUseMode!.RequestOnline(f.Runtime.FirstUseMode.Current.Revision, Op());
        Check((await f.Completion.ReadAsync()).State != "ready", "Pending online mode cannot finish without identity");
        await Expect(() => f.Completion.FinishAsync(Op()));
        Check((await Action("onboarding.finish", "summary", "online")).Status == "error" &&
            (await Action("onboarding.execute", "log", "online", "skipLog")).Status == "error",
            "Host rejects both online no-log finish and online skip requests");
        await f.Runtime.FirstUseMode.CancelOnlineAsync(f.Runtime.FirstUseMode.Current.Revision, Op());
        Directory.CreateDirectory(Path.GetDirectoryName(path)!);
        File.WriteAllText(path, $"<{DateTimeOffset.UtcNow.AddMinutes(-1):yyyy-MM-dd'T'HH:mm:ss.fff'Z'}> nickname=\"Pilot-Example\" playerGEID=100\n");
        var selectedLog = await Action("onboarding.execute", "log", "local", "selectLog");
        Check(selectedLog.Status == "ok", "Completed no-log setup can select a log from settings: " + selectedLog.Error?.Code);
        var refreshed = await Action("onboarding.execute", "identity", "local", "refresh");
        Check(refreshed.Payload.GetProperty("facts").GetProperty("handle").GetString() == "Pilot-Example", "Settings reuses actual local identity discovery");
        var statisticsDirectory = Path.Combine(f.Data.Device, "local-gameplay-time-v1");
        Directory.CreateDirectory(statisticsDirectory);
        var profileId = f.Data.Store.Read().Profiles.Single().Id;
        using (var blocked = new FileStream(Path.Combine(statisticsDirectory, profileId + ".bin.lock"),
            FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
        {
            Check((await Action("onboarding.execute", "identity", "local", "confirmHandle")).Status == "error",
                "A locked statistics writer fails after identity confirmation");
            var pending = (await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response;
            Check(pending.Payload.GetProperty("facts").TryGetProperty("logSetupPending", out var unfinished) && unfinished.GetBoolean(),
                "A reread must expose unfinished log setup after statistics migration fails");
            Check(f.Data.Store.Read().DeferredStatisticsAllowed == true && f.Data.Store.Read().Sources.Single(s => s.SourceKey == f.Data.Store.Read().SelectedSourceKey).ListeningEnabled != true,
                "Failure retains the explicit choice and does not start listening");
        }
        var observedPending = (await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response;
        var oldModeRequest = RetryRequest(observedPending);
        f.Runtime.FirstUseMode.RequestOnline(f.Runtime.FirstUseMode.Current.Revision, Op());
        Check((await guide.DispatchAsync(oldModeRequest)).Response.Status == "error" && f.Data.Store.Read().DeferredStatisticsAllowed == true,
            "A mode change rejects the issued retry without consuming statistics consent");
        Check((await Action("onboarding.execute", "identity", "local", "finishLogSetup")).Status == "error",
            "A newly read retry also rejects the wrong checkpoint mode during online setup");
        await f.Runtime.FirstUseMode.CancelOnlineAsync(f.Runtime.FirstUseMode.Current.Revision, Op());
        var roundtripRequest = RetryRequest((await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response);
        f.Runtime.FirstUseMode.RequestOnline(f.Runtime.FirstUseMode.Current.Revision, Op());
        await f.Runtime.FirstUseMode.CancelOnlineAsync(f.Runtime.FirstUseMode.Current.Revision, Op());
        Check((await guide.DispatchAsync(roundtripRequest)).Response.Status == "error",
            "Changing mode away and back rejects the old mode revision even when projected facts look unchanged");
        using var coldGuide = new FirstUseBridgeDispatcher(f.Data.Device, f.Runtime, native,
            new FirstUseStartupReader(f.Data.Device, () => new("fresh", "0.7.3")), new PathPicker(path),
            _ => throw new Exception("Unexpected online configuration"), () => "en");
        var coldRead = (await coldGuide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response;
        Check(coldRead.Payload.GetProperty("facts").GetProperty("logSetupPending").GetBoolean(), "A new dispatcher restores durable pending setup");
        Check((await coldGuide.DispatchAsync(RetryRequest(coldRead))).Response.Status == "ok" &&
            !f.Data.Store.Read().LogDeferred && f.Data.Store.Read().ActiveProfileId is not null,
            "Only explicit evidence confirmation establishes identity after no-log completion");
        Check(new LocalGameplayTimeStore(f.Data.Device).Read(f.Data.Store.Read().ActiveProfileId!).Consent == GameplayRecordingConsent.Allowed &&
            f.Data.Store.Read().DeferredStatisticsAllowed is null, "Settings Handle confirmation transfers the saved explicit allow through the original profile writer");
        var identityBytes = File.ReadAllBytes(Path.Combine(f.Data.Device, "local-first-use-v1", "state.bin"));
        var statisticsBytes = File.ReadAllBytes(Path.Combine(statisticsDirectory, profileId + ".bin"));
        var retried = await Action("onboarding.execute", "identity", "local", "finishLogSetup");
        Check(retried.Status == "ok" && !retried.Payload.GetProperty("facts").GetProperty("logSetupPending").GetBoolean() &&
            identityBytes.SequenceEqual(File.ReadAllBytes(Path.Combine(f.Data.Device, "local-first-use-v1", "state.bin"))) &&
            statisticsBytes.SequenceEqual(File.ReadAllBytes(Path.Combine(statisticsDirectory, profileId + ".bin"))),
            "Successful setup retries are read-only and do not write consent or listening twice");
        var cancelledRequest = RetryRequest((await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response);
        var cancelled = false;
        try { await guide.DispatchAsync(cancelledRequest, new CancellationToken(true)); }
        catch (OperationCanceledException) { cancelled = true; }
        Check(cancelled &&
            statisticsBytes.SequenceEqual(File.ReadAllBytes(Path.Combine(statisticsDirectory, profileId + ".bin"))),
            "A cancelled retry cannot write or resume setup");
        var revisionRequest = RetryRequest((await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response);
        var revised = f.Data.Store.Read();
        f.Data.Store.SaveProgress(revised.Revision, Op(), new("identity", "local", revised.SelectedSourceKey, null, null), () => true);
        Check((await guide.DispatchAsync(revisionRequest)).Response.Status == "error",
            "A changed local revision rejects even a matching identity and source");
        var oldIdentityRequest = RetryRequest((await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response);
        var currentIdentity = f.Data.Store.Read();
        f.Data.Store.InvalidateSourceIdentity(currentIdentity.Revision, Op(), currentIdentity.SelectedSourceKey!, () => true);
        Check((await guide.DispatchAsync(oldIdentityRequest)).Response.Status == "error" &&
            (await Action("onboarding.execute", "identity", "local", "finishLogSetup")).Status == "error",
            "Both old and freshly read retries reject an identity that is no longer confirmed");
        await guide.RetireAsync();
        Check((await guide.DispatchAsync(oldIdentityRequest)).Response.Status == "error", "A retired request owner cannot retry setup");
        Check(f.Network.Calls == 0, "No-log setup makes no account network requests");
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
        await entered.Task.WaitAsync(FirstUseTestWait.Bound);
        var close = native.DisposeAsync().AsTask();
        Check(!close.IsCompleted, "Control retirement waits for the real held device read");
        release.Set();
        try { await pending; } catch (OperationCanceledException) { }
        await close.WaitAsync(FirstUseTestWait.Bound);
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
    private sealed class PathPicker(string path) : IFirstUseLogPicker
    { public Task<string?> PickAsync(string locale, CancellationToken token) => Task.FromResult<string?>(path); }
    private static void Check(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }
    private static async Task Expect(Func<Task> action)
    { try { await action(); } catch (LocalFirstUseException e) when (e.Code == "firstUse.context_changed") { return; } throw new InvalidOperationException("Expected stale completion rejection"); }

    private sealed class Fixture : IAsyncDisposable
    {
        internal readonly LocalDeviceSetupReaderTests.Fixture Data = new();
        internal readonly NoNetwork Network = new();
        internal AccountBridgeRuntime Runtime = null!;
        internal FirstUseCompletionRuntime Completion => Runtime.FirstUseCompletion!;
        internal static async Task<Fixture> Create(bool startLocal = true)
        {
            var f = new Fixture();
            try
            {
                var origin = new Uri("https://synthetic-scm.example.invalid/");
                var options = new ScmOAuthOptions("fixture", origin, origin, origin, "synthetic-client", "synthetic-resource", "profile.read", "/callback");
                var oauth = new OAuthPkceClient(new ScmHttpClient(f.Network), new EmptyVault(), options);
                var host = new ScmAccountBridgeHost(oauth, new ScmProfileCacheStore(Path.Combine(f.Data.Device, "cache")), "fixture", () => null, initialGeneration: 1);
                if (startLocal) await host.GetCurrentAsync(default);
                f.Runtime = new(host, gameLog: new GameLogSettingsStore(f.Data.Device));
                await AccountBridgeRuntime.CreateWithFirstUseModeAsync(f.Data.Device, _ => Task.FromResult(f.Runtime), localGameProbe: () => new("notRunning"));
                if (startLocal) Check((await f.Runtime.FirstUseMode!.ApplyLocalAsync(0, Op(), f.Runtime.Generation)).State == "local", "Real account retirement establishes local mode");
                f.Data.Generation = f.Runtime.FirstUseMode!.ControlGeneration;
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
