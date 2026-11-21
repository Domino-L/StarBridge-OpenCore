using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Presence;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static partial class FirstUseBusinessOwnerTests
{
    internal static async Task RunProductOnlineProtocol()
    {
        await RunReturningUsageMode();
        await Case("product online guide carries explicit identity review through one installation and completion", () => ProductOnlineProtocol(false));
        await Case("completed local setup switches online without replacing its historical receipt", () => ProductOnlineProtocol(false, true));
        await Case("product guide supplements retained online setup without browser login or lost credentials", () => ProductOnlineProtocol(true));
    }

    private static async Task ProductOnlineProtocol(bool resume, bool completed = false)
    {
        using var f = new Fixture();
        f.Original.Clock.AllowTimers = true;
        await f.Original.Prepare();
        var root = f.Original.Local.Root;
        var account = f.Original.Local.Runtime;
        var local = new LocalFirstUseStore(root);
        var source = local.Read().Sources.Single();
        var completedPath = Path.Combine(root, "first-use-completion-v1", "state.bin");
        byte[]? completedBytes = null;
        string? replacementLog = null;
        if (completed)
        {
            new FirstUseCompletionStore(root).Save(null, Id(), "local", local.Read().ActiveProfileId,
                source.SourceKey, () => true);
            completedBytes = File.ReadAllBytes(completedPath);
            replacementLog = Path.Combine(root, "switch", "LIVE", "Game.log");
            Directory.CreateDirectory(Path.GetDirectoryName(replacementLog)!);
            File.WriteAllText(replacementLog,
                $"<{DateTimeOffset.UtcNow.AddMinutes(-1):yyyy-MM-dd'T'HH:mm:ss.fff'Z'}> nickname=\"Pilot-Example\" playerGEID=100\n");
        }
        Directory.CreateDirectory(Path.GetDirectoryName(source.LogPath)!);
        File.WriteAllText(source.LogPath, "");
        var appStore = new ApplicationPreferencesStore(root);
        using var application = new ApplicationPreferencesBridgeDispatcher(appStore,
            new LocalDeviceSetupReaderTests.Startup(), () => f.Original.Mode.ControlGeneration);
        using var overlay = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), new OverlayWorkspaceStore(root),
            () => f.Original.Mode.ControlGeneration, () => throw new Exception("Device read consulted account"),
            new LocalDeviceSetupReaderTests.Native());
        using var notices = new NotificationSettingsBridgeDispatcher(root, () => f.Original.Mode.ControlGeneration);
        using var reminder = new ContinuousPlayReminderRuntime(root,
            () => throw new Exception("Device read sampled game"), new LocalDeviceSetupReaderTests.ReminderSink());
        account.ConfigureFirstUseDeviceSetup(application, overlay, notices, reminder);
        await using var native = new NativeAccountRuntimeBinding(account);
        var installations = 0;
        using var guide = new FirstUseBridgeDispatcher(root, account, native,
            new FirstUseStartupReader(root, () => new("fresh", "0.7.2")), new ProductNoPicker(replacementLog),
            owner => { Check(ReferenceEquals(owner, f.Original.Candidate), "Only the original online graph is installed"); installations++; }, () => "en");
        JsonElement latest = default;
        async Task<JsonElement> Call(string name, string step = "mode", string? action = null)
        {
            var facts = latest.ValueKind == JsonValueKind.Undefined ? default : latest.GetProperty("facts");
            var checkpoint = new { step, mode = "online", sourceKey = facts.ValueKind == JsonValueKind.Undefined ? null : facts.GetProperty("sourceKey").GetString(),
                evidenceKey = facts.ValueKind == JsonValueKind.Undefined ? null : facts.GetProperty("evidenceKey").GetString() };
            object body = name == "onboarding.read" ? new { schemaVersion = 1 } : action is null
                ? new { schemaVersion = 1, expectedStateKey = latest.GetProperty("stateKey").GetString(), checkpoint }
                : new { schemaVersion = 1, expectedStateKey = latest.GetProperty("stateKey").GetString(), checkpoint, action };
            var request = BridgeEnvelope.Request(name, Id(), f.Original.Mode.ControlGeneration, body);
            var response = await guide.DispatchAsync(request);
            Check(response.Response.Status == "ok", $"Product {action ?? name}: {response.Response.Error?.Code}");
            Check(response.Response.AccountContext is null && response.Events.Count == 0 &&
                response.Response.SessionGeneration == request.SessionGeneration, "Original correlation is not account authority");
            return latest = response.Response.Payload;
        }
        await Call("onboarding.read");
        await Call("onboarding.execute", action: "applyMode");
        Check(f.Original.BrowserOpens == 0 && f.Original.Clock.Timers == 0, "Choosing online neither authenticates nor starts business");
        await Call("onboarding.execute", action: "login");
        Check(latest.GetProperty("facts").GetProperty("signedIn").GetBoolean() && f.Original.Clock.Timers == 0,
            "Explicit product login does not install business");
        if (completed)
        {
            await Call("onboarding.saveProgress", "log");
            await Call("onboarding.execute", "log", "selectLog");
            Check(local.Read().Progress is null && latest.GetProperty("facts").GetProperty("onlineSetupPending").GetBoolean() &&
                latest.GetProperty("restored").GetProperty("step").GetString() == "log",
                "Clearing stale source UI progress does not lose the pending mode/log step");
        }
        await Call("onboarding.execute", "identity", "refresh");
        await Call("onboarding.execute", "identity", "confirmHandle");
        if (completed)
            Check(latest.GetProperty("restored").GetProperty("step").GetString() == "mode" &&
                latest.GetProperty("completed").ValueKind == JsonValueKind.Object,
                "Confirmed replacement log resumes at name review without replacing historical completion");
        Check(!latest.GetProperty("facts").GetProperty("onlineIdentityMatched").GetBoolean(),
            "Local Handle confirmation alone is not SCM identity confirmation");
        using var onlineReview = new FirstUseOnlineReviewBridgeDispatcher(f.Original.Mode, () => f.Original.Mode.ControlGeneration);
        async Task ConfirmOnline()
        {
            var checkedIdentity = await onlineReview.DispatchAsync(BridgeEnvelope.Request("onboarding.onlineReview.v2.review", Id(),
                f.Original.Mode.ControlGeneration, new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision }));
            Check(checkedIdentity.Response.Status == "ok", "Original online review must succeed");
            var confirmedIdentity = await onlineReview.DispatchAsync(BridgeEnvelope.Request("onboarding.onlineReview.v2.confirm", Id(),
                f.Original.Mode.ControlGeneration, new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision,
                    confirmationKey = checkedIdentity.Response.Payload.GetProperty("identity").GetProperty("confirmationKey").GetString() }));
            Check(confirmedIdentity.Response.Status == "ok" && confirmedIdentity.Response.Payload.GetProperty("identity").GetProperty("state").GetString() == "confirmedForHandoff",
                "Explicit original online review confirms authoritative SCM identity separately");
        }
        await ConfirmOnline();
        await Call("onboarding.read");
        Check(latest.GetProperty("facts").GetProperty("onlineIdentityMatched").GetBoolean(),
            "The product guide observes original SCM confirmation, not a renderer claim");
        appStore.Save(ApplicationPreferencesSnapshot.Default with { Revision = 1, StartupChoiceMade = true, CloseBehaviorChoiceMade = true });
        var review = await account.FirstUseDeviceReview!.ReadAsync();
        Check((await account.FirstUseDeviceReview.ConfirmAsync(review.ReviewKey!, ["application", "overlay", "notifications", "playReminder"])).State == "reviewed",
            "Original device editors explicitly review choices");
        var statistics = new LocalGameplayTimeStore(root);
        var profile = local.Read().ActiveProfileId!;
        using (var lease = statistics.Open(profile, () => true))
        { var before = statistics.Read(profile); lease.Save(before, before with { Consent = GameplayRecordingConsent.Declined }, () => true); }
        await Call("onboarding.read");
        await Call("onboarding.execute", "local", "reviewLocalSettings");
        await Call("onboarding.execute", "online", "reviewOnlineChoices");
        Check(installations == 1 && f.Original.Mode.HasInstalledOnlineForCompletion && f.Original.Clock.Timers == 7,
            "The product route installs exactly one physically live graph");
        await Call("onboarding.saveProgress", "summary");
        Check(completed || new FirstUseCompletionStore(root).Read() is null, "Summary persistence is not completion");
        await Call("onboarding.finish", "summary");
        Check(new FirstUseCompletionStore(root).Read()?.Mode == (completed ? "local" : "online") &&
            latest.GetProperty("completed").GetProperty("mode").GetString() == (completed ? "local" : "online"), "Actual product receipt survives reopen");
        if (completed)
            Check(File.ReadAllBytes(completedPath).SequenceEqual(completedBytes!), "Switching online never rewrites historical completion bytes");
        if (!resume) return;
        var browser = f.Original.BrowserOpens;
        var tokens = f.Original.Transport.TokenRequests;
        await Call("onboarding.execute", action: "applyMode");
        Check(f.Original.Mode.HasInstalledOnlineAccount && f.Original.Transport.TokenRequests == tokens && installations == 1,
            "Re-entering an online guide keeps its installed original account without a second login or installation");
        Check((await f.Original.Mode.ApplyOfflineAsync(f.Original.Mode.Current.Revision, Id(), native.Generation)).State == "offline",
            "Only explicit offline selection suspends the online account");
        await Call("onboarding.read");
        await Call("onboarding.execute", action: "applyMode");
        Check(f.Original.Mode.RetainsOnlineReviewSession && f.Original.Transport.Revokes == 0,
            "Re-entering setup suspends original online business and retains login");
        await Call("onboarding.execute", action: "login");
        Check(f.Original.BrowserOpens == browser && f.Original.Transport.TokenRequests == tokens + 1,
            "Explicit resume refreshes the original retained credential, with no new browser");
        await ConfirmOnline();
        await Call("onboarding.read");
        await Call("onboarding.execute", "online", "reviewOnlineChoices");
        await Call("onboarding.saveProgress", "summary");
        await Call("onboarding.finish", "summary");
        Check(installations == 2 && f.Original.Mode.HasInstalledOnlineForCompletion && f.Original.Transport.Revokes == 0 &&
            f.Original.Vault.LoadActiveAccountKey() is not null, "Retained guide finishes on the second unique Native graph without sign-out");
    }

    internal static async Task RunReturningUsageMode()
    {
        foreach (var kind in new[] { "legacy", "device", "resume", "update", "completed", "fresh", "unknown" })
        {
            var root = Path.Combine(Path.GetTempPath(), "starbridge-first-use-account-stop", Id());
            Directory.CreateDirectory(root);
            if (kind == "legacy") File.WriteAllText(Path.Combine(root, "desktop.config"), "synthetic old use");
            if (kind is "device" or "resume")
            {
                new ApplicationPreferencesStore(root).Save(ApplicationPreferencesSnapshot.Default with { Revision = 1 });
                Directory.CreateDirectory(Path.Combine(root, "gameplay-time-local-v1"));
            }
            var local = new LocalFirstUseStore(root);
            if (kind == "resume") local.SaveProgress(0, Id(), new("log", "local", null, null, null), () => true);
            if (kind == "completed") new FirstUseCompletionStore(root).Save(null, Id(), "local", Id(), "synthetic-source-0001", () => true);
            var receipt = new FirstUseCompletionStore(root).Read();
            var startup = new FirstUseStartupReader(root, () => kind == "unknown" ? null : new(kind == "update" ? "update" : "fresh", "0.7.2"));
            var expected = kind is "resume" or "fresh" ? "firstUse" : kind == "unknown" ? "unknown" : "returning";
            var reason = kind switch { "resume" => "resume", "fresh" => "freshInstallation", "unknown" => "installationUnknown",
                "update" => "updateInstallation", "completed" => "completedSetup", _ => "previousUse" };
            Check(startup.Read() == new FirstUseStartupObservation(expected, reason, kind == "resume"), "Startup fixture " + kind + ": " + startup.Read());
            using var f = new Fixture(new FirstUseOnlineReturnTests.Fixture(0, sharedRoot: root, initializeLocalState: false));
            // Ordinary owners write after the one startup observation.
            await f.Original.Prepare();
            f.Original.Clock.AllowTimers = true;
            var account = f.Original.Local.Runtime;
            var appStore = new ApplicationPreferencesStore(root);
            using var application = new ApplicationPreferencesBridgeDispatcher(appStore, new LocalDeviceSetupReaderTests.Startup(), () => f.Original.Mode.ControlGeneration);
            using var overlay = new OverlayBridgeDispatcher(new OverlaySettingsStore(root), new OverlayWorkspaceStore(root),
                () => f.Original.Mode.ControlGeneration, () => throw new Exception("Unexpected account read"), new LocalDeviceSetupReaderTests.Native());
            using var notices = new NotificationSettingsBridgeDispatcher(root, () => f.Original.Mode.ControlGeneration);
            using var reminder = new ContinuousPlayReminderRuntime(root, () => throw new Exception("Unexpected game sample"), new LocalDeviceSetupReaderTests.ReminderSink());
            account.ConfigureFirstUseDeviceSetup(application, overlay, notices, reminder);
            await using var native = new NativeAccountRuntimeBinding(account);
            var logPath = Path.Combine(root, "install", "LIVE", "Game.log");
            var installations = 0;
            Action<AccountBridgeRuntime> configure = owner => { Check(ReferenceEquals(owner, f.Original.Candidate), "Original graph only"); installations++; };
            using var guide = new FirstUseBridgeDispatcher(root, account, native, startup, new ProductNoPicker(logPath), configure, () => "en");
            using var review = new FirstUseOnlineReviewBridgeDispatcher(f.Original.Mode, () => f.Original.Mode.ControlGeneration);
            using var install = new FirstUseOnlineInstallationBridgeDispatcher(f.Original.Mode, native, configure);
            BridgeEnvelope Request(string name, object body) => BridgeEnvelope.Request(name, Id(), f.Original.Mode.ControlGeneration, body);
            async Task<JsonElement> Read()
            {
                var reply = (await guide.DispatchAsync(Request("onboarding.read", new { schemaVersion = 1 }))).Response;
                Check(reply.Status == "ok" && reply.Payload.GetProperty("facts").GetProperty("eligibility").GetString() == expected, "Stable projected classification " + kind);
                return reply.Payload;
            }
            async Task<BridgeEnvelope> Action(string action, string step = "mode")
            {
                var read = await Read(); var facts = read.GetProperty("facts");
                return (await guide.DispatchAsync(Request("onboarding.execute", new { schemaVersion = 1,
                    expectedStateKey = read.GetProperty("stateKey").GetString(), action,
                    checkpoint = new Dictionary<string, object?> { ["step"] = step, ["mode"] = "online", ["sourceKey"] = facts.GetProperty("sourceKey").GetString(), ["evidenceKey"] = facts.GetProperty("evidenceKey").GetString() } }))).Response;
            }
            Task<BridgeDispatchBatch> Review(string action, string? key = null) => review.DispatchAsync(Request("onboarding.onlineReview.v2." + action,
                key is null ? (object)new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision }
                : new { schemaVersion = 2, revision = f.Original.Mode.Current.Revision, confirmationKey = key })).AsTask();
            Task<BridgeDispatchBatch> Install() => install.DispatchAsync(Request(FirstUseOnlineInstallationBridgeDispatcher.InstallRequest,
                new { schemaVersion = 1, revision = f.Original.Mode.Current.Revision })).AsTask();
            await Read();
            File.WriteAllText(Path.Combine(root, "application-behavior.json"), "synthetic later device write");
            Check(startup.Read().Eligibility == expected && startup.Read().Reason == reason, "Later device writes cannot reclassify startup");
            if (expected != "returning")
            {
                Check((await Action("applyMode")).Error?.Code == "firstUse.evidence_required", "Unfinished and unknown users cannot skip log identity");
                Console.WriteLine("PASS R4 projection: " + kind + " -> " + expected + "/" + reason);
                continue;
            }
            Check((await Review("begin")).Response.Status == "ok", "Returning user can begin through onlineReview without completion");
            Check((await Review("cancel")).Response.Status == "ok", "Returning user can cancel pending mode");
            var applied = await Action("applyMode");
            Check(applied.Status == "ok", "Returning user can begin through product mode action: " + applied.Error?.Code);
            Check((await Install()).Response.Status != "ok" && installations == 0, "No install before authentication and identity");
            Check((await Action("login")).Status == "ok", "Explicit login uses original offline fixture transport");
            var identity = (await Review("review")).Response.Payload.GetProperty("identity");
            Check(identity.GetProperty("state").GetString() == "needsLocalIdentity" && identity.GetProperty("confirmationKey").ValueKind == JsonValueKind.Null,
                "Returning classification cannot grant missing local identity");
            Check((await Install()).Response.Status != "ok" && installations == 0, "Login alone cannot install");
            Directory.CreateDirectory(Path.GetDirectoryName(logPath)!);
            File.WriteAllText(logPath, $"<{DateTimeOffset.UtcNow.AddMinutes(-1):yyyy-MM-dd'T'HH:mm:ss.fff'Z'}> nickname=\"Pilot-Example\" playerGEID=100\n");
            Check((await Action("selectLog", "log")).Status == "ok", "Explicit log selection");
            Check((await Action("refresh", "identity")).Status == "ok", "Actual local evidence refresh");
            Check((await Action("confirmHandle", "identity")).Status == "ok", "Explicit local identity confirmation");
            Check((await Install()).Response.Status != "ok" && installations == 0, "Local identity alone cannot install");
            identity = (await Review("review")).Response.Payload.GetProperty("identity");
            Check((await Review("confirm", identity.GetProperty("confirmationKey").GetString())).Response.Status == "ok", "Explicit authoritative online confirmation");
            Check((await Install()).Response.Status == "ok" && installations == 1 && f.Original.Mode.HasInstalledOnlineForCompletion,
                "Original installation route works without an invented completion");
            using var mode = native.CreateModeDispatcher()!;
            Check((await mode.DispatchAsync(Request(FirstUseModeBridgeDispatcher.OfflineRequest,
                new { schemaVersion = 1, revision = f.Original.Mode.Current.Revision }))).Response.Status == "ok" && f.Original.Mode.LocalMode().Active,
                "Original mode route returns online user to local mode");
            await Read();
            Check(new FirstUseCompletionStore(root).Read() == receipt, "Usage mode does not create or replace completion");
            Console.WriteLine("PASS R4 projection and actual mode/onlineReview/onlineInstallation round trip: " + kind + " -> " + expected + "/" + reason);
        }
    }
    private sealed class ProductNoPicker(string? path = null) : IFirstUseLogPicker
    { public Task<string?> PickAsync(string locale, CancellationToken token) => path is null
        ? throw new Exception("Unexpected picker") : Task.FromResult<string?>(path); }
}

