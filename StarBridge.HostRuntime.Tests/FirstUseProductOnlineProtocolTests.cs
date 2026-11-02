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
        await Case("product online guide carries explicit identity review through one installation and completion", () => ProductOnlineProtocol(false));
        await Case("product guide supplements retained online setup without browser login or lost credentials", () => ProductOnlineProtocol(true));
    }

    private static async Task ProductOnlineProtocol(bool resume)
    {
        using var f = new Fixture();
        f.Original.Clock.AllowTimers = true;
        await f.Original.Prepare();
        var root = f.Original.Local.Root;
        var account = f.Original.Local.Runtime;
        var local = new LocalFirstUseStore(root);
        var source = local.Read().Sources.Single();
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
            new FirstUseStartupReader(root, () => new("fresh", "0.7.2")), new ProductNoPicker(),
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
        await Call("onboarding.execute", "identity", "refresh");
        await Call("onboarding.execute", "identity", "confirmHandle");
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
        Check(new FirstUseCompletionStore(root).Read() is null, "Summary persistence is not completion");
        await Call("onboarding.finish", "summary");
        Check(new FirstUseCompletionStore(root).Read()?.Mode == "online" &&
            latest.GetProperty("completed").GetProperty("mode").GetString() == "online", "Actual online product receipt survives reopen");
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

    private sealed class ProductNoPicker : IFirstUseLogPicker
    { public Task<string?> PickAsync(string locale, CancellationToken token) => throw new Exception("Unexpected picker"); }
}

