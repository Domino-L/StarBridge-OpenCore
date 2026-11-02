using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Reminders;

internal static class LocalDeviceSetupReviewTests
{
    private static readonly string[] Sections = ["application", "overlay", "notifications", "playReminder"];
    private static string Op() => Guid.NewGuid().ToString("N");
    private static string FilePath(LocalDeviceSetupReaderTests.Fixture f) => Path.Combine(f.Device, "first-use-device-review-v1", "state.bin");
    private static LocalDeviceSetupReviewRuntime Runtime(LocalDeviceSetupReaderTests.Fixture f) => new(f.Reader, new(f.Device));
    private static void Chosen(LocalDeviceSetupReaderTests.Fixture f) => f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with
        { Revision = 1, StartupChoiceMade = true, CloseBehaviorChoiceMade = true });
    private static void Require(bool value, string message) { if (!value) throw new InvalidOperationException(message); }
    private static async Task Expect(string code, Func<Task> action)
    { try { await action(); } catch (LocalFirstUseException error) when (error.Code == code) { return; } throw new InvalidOperationException("Expected " + code); }
    private static async Task Case(string name, Func<Task> action)
    { await action(); Console.WriteLine("PASS first-use device review: " + name); }
    internal static async Task Run()
    {
        await Case("unreviewed defaults and incomplete ordinary choices never become confirmed", Defaults);
        await Case("explicit review preserves domain choices and grants no account or Native side effects", ExplicitReview);
        await Case("reopen retains shared review without copying profile statistics or consent", Reopen);
        await Case("language, appearance and unchanged owner revisions do not erase semantic review", PresentationChanges);
        await Case("ordinary settings changes revoke the old observation and require fresh review", ChangedChoices);
        await Case("source, identity and Host changes reject stale confirmation", ChangedScope);
        await Case("every section must be explicit and opaque observations cannot be invented or replayed", InvalidAndReplay);
        await Case("damaged review remains intact and repair alone does not grant confirmation", Damage);
        await Case("busy writers, cancellation, CAS and final guards cannot acknowledge review", Guards);
        await Case("retirement waits for actual settings reads and rejects late confirmation", Retirement);
        await Case("product composition borrows the actual owners without advertising completion", Composition);
        await Case("strict protected review documents preserve invalid original evidence", StrictDocuments);
    }
    private static async Task Defaults()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); var r = Runtime(f); var files = f.Files();
        Require((await r.ReadAsync()) is { State: "choicesRequired", ReviewKey: null }, "defaults need explicit ordinary application choices");
        await Expect("firstUse.context_changed", () => r.ConfirmAsync(Op(), Sections));
        f.Unchanged(files); Require(!File.Exists(FilePath(f)), "inspection cannot mark reviewed");
        Chosen(f);
        Require((await r.ReadAsync()) is { State: "reviewRequired", ReviewKey: not null }, "saved choices alone do not prove review");
        Require(!File.Exists(FilePath(f)), "reading saved choices does not write a review");
        await r.RetireAsync();
    }
    private static async Task ExplicitReview()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        var files = f.Files(); var first = await r.ReadAsync();
        Require((await r.ConfirmAsync(first.ReviewKey!, Sections)).State == "reviewed", "explicit current confirmation saved");
        var after = f.Files();
        Require(files.All(p => after[p.Key] == p.Value) && after.Keys.Except(files.Keys).All(p => p.StartsWith("device" + Path.DirectorySeparatorChar + "first-use-device-review-v1")),
            "review cannot mutate domain choices, local profiles or statistics");
        Require(f.Startup.Writes == 0 && f.Native.Commands == 0 && f.Sink.Calls == 0 && f.ProcessReads == 0 && f.AccountReads == 0,
            "review does not register startup, open Native, notify, sample or contact an account");
        var doc = new LocalDeviceReviewStore(f.Device).Read();
        Require(doc.Revision == 1 && doc.Fingerprint!.Length == 64 && !JsonSerializer.Serialize(doc).Contains("Pilot-Example"),
            "only reviewed choices fingerprint is stored, not an identity or authorization");
        await r.RetireAsync();
    }
    private static async Task Reopen()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        await r.ConfirmAsync((await r.ReadAsync()).ReviewKey!, Sections); await r.RetireAsync();
        f.Generation++;
        var reopened = Runtime(f); var files = f.Files();
        Require((await reopened.ReadAsync()).State == "reviewed", "process-local Host generation is not persisted as a device setting");
        f.Unchanged(files); Require(!Directory.Exists(Path.Combine(f.Device, "local-gameplay-time-v1")), "device review grants no per-profile statistics choice");
        await reopened.RetireAsync();
    }
    private static async Task ChangedChoices()
    {
        foreach (var area in Sections)
        {
            using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
            var confirmed = await r.ConfirmAsync((await r.ReadAsync()).ReviewKey!, Sections);
            var saved = File.ReadAllBytes(FilePath(f));
            switch (area)
            {
                case "application": f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 2,
                    StartupChoiceMade = true, CloseBehaviorChoiceMade = true, KeepRunningInBackground = false }); break;
                case "overlay": var hud = f.Workspace.Inspect(); f.Workspace.Apply(new(hud.Revision,
                    StarBridge.HostRuntime.Overlay.OverlayWorkspaceMutationKind.SaveActive,
                    Settings: hud.Settings with { Opacity = .51 }, Layout: hud.Layout, RenderMode: hud.RenderMode, Hotkey: hud.Hotkey)); break;
                case "notifications": File.WriteAllText(Path.Combine(f.Device, "notification-settings.v1.json"), JsonSerializer.Serialize(
                    new StarBridge.HostRuntime.Notifications.LocalNotificationSettings(Revision: 1, InAppEnabled: false), StarBridge.NativeBridge.BridgeProtocol.JsonOptions)); break;
                case "playReminder": new ContinuousPlayStore(f.Device).SaveSettings(new(false, 90, 60, 1)); break;
            }
            await Expect("firstUse.context_changed", () => r.ConfirmAsync(confirmed.ReviewKey!, Sections));
            Require((await r.ReadAsync()).State == "reviewRequired" && File.ReadAllBytes(FilePath(f)).SequenceEqual(saved), "changed " + area + " cannot inherit review");
            await r.RetireAsync();
        }
    }
    private static async Task PresentationChanges()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        var issued = await r.ConfirmAsync((await r.ReadAsync()).ReviewKey!, Sections);
        var stored = File.ReadAllBytes(FilePath(f));
        f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 2, StartupChoiceMade = true,
            CloseBehaviorChoiceMade = true, LocaleOverride = "en-US", AppearanceMode = "light", MotionPreference = "reduce" });
        new ContinuousPlayStore(f.Device).SaveSettings(new(Revision: 1));
        await Expect("firstUse.context_changed", () => r.ConfirmAsync(issued.ReviewKey!, Sections));
        Require((await r.ReadAsync()).State == "reviewed" && File.ReadAllBytes(FilePath(f)).SequenceEqual(stored),
            "reread retains shared reviewed semantics without automatically writing or borrowing an old live token");
        await r.RetireAsync();
    }
    private static async Task ChangedScope()
    {
        foreach (var area in new[] { "host", "source", "identity" })
        {
            using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
            var issued = await r.ReadAsync(); var state = f.Store.Read();
            if (area == "host") f.Generation++;
            else if (area == "source") f.Store.SelectSource(state.Revision, Op(), Path.Combine(f.Root, "install", "PTU", "Game.log"), "PTU", () => true);
            else f.Store.ForgetProfile(state.Revision, Op(), state.ActiveProfileId!, () => true);
            await Expect("firstUse.context_changed", () => r.ConfirmAsync(issued.ReviewKey!, Sections));
            Require(!File.Exists(FilePath(f)), "stale " + area + " does not persist acknowledgement");
            await r.RetireAsync();
        }
    }
    private static async Task InvalidAndReplay()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f); var first = await r.ReadAsync();
        foreach (var list in new[] { Array.Empty<string>(), new[] { "application", "overlay", "notifications" },
            new[] { "application", "overlay", "notifications", "notifications" }, new[] { "application", "overlay", "notifications", "unknown" } })
            await Expect("firstUse.invalid_request", () => r.ConfirmAsync(first.ReviewKey!, list));
        await Expect("firstUse.invalid_request", () => r.ConfirmAsync("not-an-observation", Sections));
        await Expect("firstUse.context_changed", () => r.ConfirmAsync(Op(), Sections));
        await r.ConfirmAsync(first.ReviewKey!, Sections);
        await Expect("firstUse.context_changed", () => r.ConfirmAsync(first.ReviewKey!, Sections));
        Require(new LocalDeviceReviewStore(f.Device).Read().Revision == 1, "replay has no second commit");
        await r.RetireAsync();
    }
    private static async Task Damage()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        await r.ConfirmAsync((await r.ReadAsync()).ReviewKey!, Sections);
        var damaged = Encoding.UTF8.GetBytes("damaged"); File.WriteAllBytes(FilePath(f), damaged);
        await Expect("firstUse.device_review_read_failed", () => r.ReadAsync());
        Require(File.ReadAllBytes(FilePath(f)).SequenceEqual(damaged), "invalid original preserved");
        File.Delete(FilePath(f)); // Explicit fixture repair of its exact synthetic record, not product behavior.
        Require((await r.ReadAsync()).State == "reviewRequired", "repair does not automatically restore review");
        await r.RetireAsync();
    }
    private static async Task Guards()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f); var issued = await r.ReadAsync();
        Directory.CreateDirectory(Path.GetDirectoryName(FilePath(f))!);
        using (var lease = new FileStream(FilePath(f) + ".lock", FileMode.OpenOrCreate, FileAccess.ReadWrite, FileShare.None))
            await Expect("firstUse.device_review_write_failed", () => r.ConfirmAsync(issued.ReviewKey!, Sections));
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        try { await r.ConfirmAsync(issued.ReviewKey!, Sections, cancelled.Token); throw new InvalidOperationException("Expected cancellation"); }
        catch (OperationCanceledException) { }
        Require(!File.Exists(FilePath(f)), "failed or cancelled review cannot acknowledge");
        var store = new LocalDeviceReviewStore(f.Device); var calls = 0;
        await Expect("firstUse.context_changed", () => Task.Run(() => store.Save(LocalDeviceReview.Empty, Op(), new string('A', 64), () => ++calls < 2)));
        Require(!File.Exists(FilePath(f)), "final guard loss leaves no review document");
        store.Save(LocalDeviceReview.Empty, Op(), new string('B', 64), () => true);
        await Expect("firstUse.revision_conflict", () => r.ConfirmAsync(issued.ReviewKey!, Sections));
        Require(store.Read().Fingerprint == new string('B', 64), "concurrent review preserved");
        await r.RetireAsync();
    }
    private static async Task Retirement()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        using var entered = new ManualResetEventSlim(); using var release = new ManualResetEventSlim();
        f.AppStore.OnLoad = _ => { entered.Set(); release.Wait(); };
        var read = Task.Run(() => r.ReadAsync()); Require(entered.Wait(TimeSpan.FromSeconds(5)), "actual settings owner admitted");
        var retired = r.RetireAsync(); Require(!retired.IsCompleted, "cancellation is not actual owner exit");
        release.Set(); try { await read; } catch (OperationCanceledException) { }
        await retired;
        Require((await r.ReadAsync()).State == "unavailable" && !File.Exists(FilePath(f)), "late read cannot issue readiness or a review");
        await Expect("firstUse.context_changed", () => r.ConfirmAsync(Op(), Sections));
        f.AppStore.OnLoad = null;
    }
    private static async Task Composition()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture();
        using var a = new LocalAccountStopTests.Fixture(initialSession: false);
        await AccountBridgeRuntime.CreateWithFirstUseModeAsync(a.Root, _ => Task.FromResult(a.Runtime));
        a.Runtime.ConfigureFirstUseDeviceSetup(f.Application, f.Overlay, f.Notifications, f.Reminder);
        Require((await a.Runtime.FirstUseDeviceReview!.ReadAsync()).State == "choicesRequired", "actual configured owners supply choices");
        Require(f.Startup.Writes == 0 && f.Native.Commands == 0 && f.AccountReads == 0 && f.ProcessReads == 0 &&
            !AccountBridgeRuntime.AdvertisedCapabilities.Contains("onboarding.firstUse.v1"), "no completion advertisement or side effects");
        a.Runtime.Dispose(); Require((await a.Runtime.FirstUseDeviceReview.ReadAsync()).State == "unavailable", "actual runtime closes review");
        a.RequireLocalStateUnchanged();
    }
    private static async Task StrictDocuments()
    {
        using var f = new LocalDeviceSetupReaderTests.Fixture(); Chosen(f); var r = Runtime(f);
        await r.ConfirmAsync((await r.ReadAsync()).ReviewKey!, Sections);
        var saved = new LocalDeviceReviewStore(f.Device).Read();
        var json = new JsonSerializerOptions(JsonSerializerDefaults.Web);
        foreach (var document in new[] { "{}", "{\"schemaVersion\":1,\"schemaVersion\":1,\"value\":{}}",
            JsonSerializer.Serialize(new { schemaVersion = 2, value = saved }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = saved, unknown = true }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = saved with { Fingerprint = "invalid" } }, json),
            JsonSerializer.Serialize(new { schemaVersion = 1, value = saved with { SavedAt = DateTimeOffset.UtcNow.AddDays(1) } }, json) })
        {
            var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(document), Encoding.UTF8.GetBytes("StarBridge.first-use-device-review.v1"), DataProtectionScope.CurrentUser);
            File.WriteAllBytes(FilePath(f), bytes);
            await Expect("firstUse.device_review_read_failed", () => r.ReadAsync());
            Require(File.ReadAllBytes(FilePath(f)).SequenceEqual(bytes), "malformed protected document preserved");
        }
        await r.RetireAsync();
    }
}
