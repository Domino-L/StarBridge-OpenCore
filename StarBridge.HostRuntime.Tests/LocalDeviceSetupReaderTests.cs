using System.Security.Cryptography;
using System.Text.Json;
using StarBridge.Core.Overlay;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Onboarding;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Settings;
using StarBridge.NativeBridge;

internal static class LocalDeviceSetupReaderTests
{
    internal static async Task Run()
    {
        await Case("saved device choices, no startup/native/account/collection side effects", SavedChoices);
        await Case("defaults are observations, not reviewed choices or consent", Defaults);
        await Case("inspection does not migrate legacy floating presets", Migration);
        await Case("damaged settings remain unavailable and can be reread after repair", Damage);
        await Case("identity, source and Host generations invalidate old observations", ScopeChanges);
        await Case("overlapping device writes revoke the combined observation", SettingsChanges);
        await Case("cancelled and disposed reads do not return accepted defaults", CancellationAndDisposal);
        await Case("stores without a pure inspection seam never fall back to mutating reads", MissingInspection);
    }

    private static async Task Case(string name, Func<Task> run)
    { await run(); Console.WriteLine("PASS first-use device setup: " + name); }

    private static async Task SavedChoices()
    {
        using var f = new Fixture();
        var preferences = ApplicationPreferencesSnapshot.Default with {
            Revision = 7, LocaleOverride = "en-US", AppearanceMode = "light", MotionPreference = "reduce",
            LaunchAtStartup = true, KeepRunningInBackground = false, StartMinimized = true,
            StartupChoiceMade = true, CloseBehaviorChoiceMade = true, BackgroundHintShown = true
        };
        f.AppStore.Actual.Save(preferences);
        var workspace = f.Workspace.Inspect();
        f.Workspace.Apply(new(workspace.Revision, OverlayWorkspaceMutationKind.SaveActive,
            Settings: workspace.Settings with { Opacity = .64, AutoOpenOverlayOnGameStart = false,
                AutoOpenOverlayOnGameForeground = false, AutoCloseOverlayOnGameBackground = true },
            Layout: workspace.Layout, RenderMode: workspace.RenderMode,
            Hotkey: new("Ctrl+F9", false, "unavailable")));
        var notices = new LocalNotificationSettings(Revision: 4, InAppEnabled: false, Position: "topLeft",
            Preview: "hiddenDetails", WindowsEnabled: true, OverlayEnabled: false, DirectMessageWindowsEnabled: true);
        File.WriteAllText(Path.Combine(f.Device, "notification-settings.v1.json"),
            JsonSerializer.Serialize(notices, BridgeProtocol.JsonOptions));
        var reminder = new ContinuousPlaySettings(false, 90, 60, 3);
        new ContinuousPlayStore(f.Device).SaveSettings(reminder);
        var selected = f.Store.Read().Sources.Single();
        f.Store.SetListening(f.Store.Read().Revision, Op(), selected.SourceKey, true, () => true);
        var files = f.Files();

        var value = await f.Reader.ReadAsync();
        Require(value is { State: "observed", Choices: { ListeningEnabled: true, GameVersion: "LIVE" } }, "local binding");
        var choices = value.Choices!;
        Require(choices.Application is { State: "saved" } && choices.Application.Value == preferences, "actual saved behavior");
        Require(choices.Overlay is { State: "saved", Value: { HotkeyBinding: "Ctrl+F9", HotkeyEnabled: false,
            AutoOpenOnGameStart: false, AutoOpenOnGameForeground: false, AutoCloseOnGameBackground: true } } &&
            choices.Overlay.Value!.Opacity == .64, "actual saved overlay choices");
        Require(choices.Notifications.Value == notices && choices.PlayReminder.Value == reminder, "original device settings");
        f.Unchanged(files);
        Require(f.Startup.Writes == 0 && f.Native.Commands == 0 && f.ProcessReads == 0 && f.Sink.Calls == 0 && f.AccountReads == 0,
            "inspection cannot apply settings, sample the game or contact account owners");
        var wire = JsonSerializer.Serialize(value, BridgeProtocol.JsonOptions);
        Require(!wire.Contains(f.Root, StringComparison.OrdinalIgnoreCase) && !wire.Contains("Pilot-Example") &&
            !wire.Contains(selected.SourceKey) && !wire.Contains(f.Store.Read().ActiveProfileId!), "path and identity free observation");
    }

    private static async Task Defaults()
    {
        using var f = new Fixture();
        var files = f.Files();
        var value = (await f.Reader.ReadAsync()).Choices!;
        Require(value.Application is { State: "defaulted", Value: { StartupChoiceMade: false, CloseBehaviorChoiceMade: false } },
            "unreviewed application defaults");
        Require(value.Overlay is { State: "defaulted" } && value.ListeningEnabled is null, "no implicit listening choice");
        Require(value.Notifications.Value == new LocalNotificationSettings() && value.PlayReminder.Value == new ContinuousPlaySettings(),
            "retain existing device defaults, including enabled reminder; observation is not consent");
        f.Unchanged(files);

        // Reading does not poison the regular settings owner's cached snapshot.
        f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 1, AppearanceMode = "light" });
        Require(f.Application.CurrentAppearanceMode == "light", "inspection must not seed Current() with old defaults");
    }

    private static async Task Migration()
    {
        using var f = new Fixture(sourcePresets: true);
        File.WriteAllText(Path.Combine(f.Device, "overlay.settings"), OverlayDisplaySettings.Default.Serialize());
        File.WriteAllText(Path.Combine(f.Device, "overlay.layout"),
            InformationOverlayLayoutItem.SerializeMany(InformationOverlayDefaults.CreateLayout("preset1")));
        var files = f.Files();
        Require(f.Workspace.Inspect().StorageState == "migrationPending", "read-only pending migration fact");
        var value = await f.Reader.ReadAsync();
        Require(value.Choices?.Overlay is { State: "needsRepair", Value: null }, "no migrated or recovered settings receipt");
        f.Unchanged(files);
        Require(!Directory.Exists(Path.Combine(f.Device, "overlay.workspace-backup-v2")) &&
            !Directory.EnumerateFiles(f.Device, "*.workspace.json").Any(), "no backup or v2 document created by inspection");
    }

    private static async Task Damage()
    {
        using var f = new Fixture();
        foreach (var name in new[] { "application-preferences.v1.json", "notification-settings.v1.json", "local-play-session.json" })
            File.WriteAllText(Path.Combine(f.Device, name), "{");
        File.WriteAllText(Path.Combine(f.Device, "overlay.layout"), "invalid fixture layout");
        var files = f.Files();
        var value = (await f.Reader.ReadAsync()).Choices!;
        Require(value.Application is { State: "needsRepair", Value: null } && value.Overlay is { State: "needsRepair", Value: null } &&
            value.Notifications is { State: "unavailable", Value: null } && value.PlayReminder is { State: "unavailable", Value: null },
            "damaged owners must not look like accepted defaults");
        f.Unchanged(files);
        // Explicit fixture repair through the original owners; reader itself never repairs.
        f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 1 });
        File.WriteAllText(Path.Combine(f.Device, "overlay.layout"),
            InformationOverlayLayoutItem.SerializeMany(InformationOverlayDefaults.CreateLayout("preset1")));
        File.WriteAllText(Path.Combine(f.Device, "notification-settings.v1.json"),
            JsonSerializer.Serialize(new LocalNotificationSettings(Revision: 1), BridgeProtocol.JsonOptions));
        new ContinuousPlayStore(f.Device).SaveState(new ContinuousPlayState());
        value = (await f.Reader.ReadAsync()).Choices!;
        Require(value.Application.State == "saved" && value.Overlay.Value is not null &&
            value.Notifications.Value is not null && value.PlayReminder.Value is not null, "explicit reread recovers without stale cache");
    }

    private static async Task ScopeChanges()
    {
        foreach (var change in new[] { "generation", "source", "identity", "freshGate" })
        {
            using var f = new Fixture();
            f.AppStore.OnLoad = reads => {
                if (reads != 1) return;
                var state = f.Store.Read();
                switch (change)
                {
                    case "generation": f.Generation++; break;
                    case "source": f.Store.SelectSource(state.Revision, Op(), Path.Combine(f.Root, "install", "PTU", "Game.log"), "PTU", () => true); break;
                    case "identity": f.Store.InvalidateSourceIdentity(state.Revision, Op(), state.SelectedSourceKey!, () => true); break;
                    case "freshGate": f.Store.RequireFreshGameEvidence(state.Revision, Op(), state.SelectedSourceKey!, null, () => true); break;
                }
            };
            Require(await f.Reader.ReadAsync() is { State: "contextChanged", Choices: null }, "late " + change);
            Require(f.Store.Read().Profiles.Count == 1, "no implicit profile merge or deletion");
        }
        using var unknown = new Fixture();
        unknown.Generation = -1;
        Require(await unknown.Reader.ReadAsync() is { State: "contextChanged", Choices: null } && unknown.AppStore.Reads == 0, "unknown generation");
        unknown.ThrowGeneration = true;
        Require(await unknown.Reader.ReadAsync() is { State: "unavailable", Choices: null }, "failed generation read");
        unknown.ThrowGeneration = false; unknown.Generation = 1;
        var selected = unknown.Store.Read();
        unknown.Store.InvalidateSourceIdentity(selected.Revision, Op(), selected.SelectedSourceKey!, () => true);
        Require(await unknown.Reader.ReadAsync() is { State: "needsIdentity", Choices: null }, "unconfirmed profile cannot reach local review");
    }

    private static async Task SettingsChanges()
    {
        foreach (var changed in new[] { "application", "overlay", "notifications", "reminder" })
        {
            using var f = new Fixture();
            f.AppStore.OnLoad = reads => {
                if (reads != (changed == "application" ? 1 : 2)) return;
                switch (changed)
                {
                    case "application":
                        f.AppStore.Actual.Save(ApplicationPreferencesSnapshot.Default with { Revision = 1, LaunchAtStartup = true }); break;
                    case "overlay":
                        File.WriteAllText(Path.Combine(f.Device, "overlay.settings"),
                            (OverlayDisplaySettings.Default with { Opacity = .63 }).Serialize()); break;
                    case "notifications":
                        File.WriteAllText(Path.Combine(f.Device, "notification-settings.v1.json"),
                            JsonSerializer.Serialize(new LocalNotificationSettings(Revision: 1, InAppEnabled: false), BridgeProtocol.JsonOptions)); break;
                    case "reminder":
                        new ContinuousPlayStore(f.Device).SaveSettings(new(false, 90, 60, 1)); break;
                }
            };
            Require(await f.Reader.ReadAsync() is { State: "settingsChanged", Choices: null }, "mixed " + changed + " snapshot cannot escape");
            f.AppStore.OnLoad = null;
            Require(await f.Reader.ReadAsync() is { State: "observed", Choices: not null }, "explicit reread returns new " + changed + " choice");
            Require(f.Startup.Writes == 0, "even reread of enabled startup cannot apply it");
        }
    }

    private static async Task CancellationAndDisposal()
    {
        using var f = new Fixture();
        using var cancelled = new CancellationTokenSource(); cancelled.Cancel();
        await Cancelled(() => f.Reader.ReadAsync(cancelled.Token));
        Require(f.AppStore.Reads == 0, "pre-cancelled read does not enter settings owners");
        using var mid = new CancellationTokenSource();
        f.AppStore.OnLoad = reads => mid.Cancel();
        await Cancelled(() => f.Reader.ReadAsync(mid.Token));
        Require(f.AppStore.Reads == 1, "no second observation after cancellation");
        f.AppStore.OnLoad = null;
        f.Application.Dispose(); f.Overlay.Dispose(); f.Notifications.Dispose(); f.Reminder.Dispose();
        var value = (await f.Reader.ReadAsync()).Choices!;
        Require(value.Application is { State: "unavailable", Value: null } && value.Overlay is { State: "unavailable", Value: null } &&
            value.Notifications is { State: "unavailable", Value: null } && value.PlayReminder is { State: "unavailable", Value: null }, "disposed owners");
    }

    private static async Task MissingInspection()
    {
        using var f = new Fixture();
        var unsupported = new MutatingWorkspace();
        using var owner = new OverlayBridgeDispatcher(new OverlaySettingsStore(f.Device), unsupported, () => 1,
            () => throw new InvalidOperationException("Account must not be read"));
        var reader = new LocalDeviceSetupReader(f.Store, () => 1, f.Application, owner, f.Notifications, f.Reminder);
        Require((await reader.ReadAsync()).Choices?.Overlay is { State: "unavailable", Value: null } && unsupported.Loads == 0,
            "unsupported inspection cannot call legacy mutating Load");
    }

    private static async Task Cancelled(Func<ValueTask<LocalDeviceSetupObservation>> read)
    {
        try { await read(); } catch (OperationCanceledException) { return; }
        throw new InvalidOperationException("Expected cancellation");
    }
    private static string Op() => Guid.NewGuid().ToString("N");
    private static void Require(bool condition, string message) { if (!condition) throw new InvalidOperationException(message); }

    internal sealed class Fixture : IDisposable
    {
        internal string Root { get; } = Path.Combine(Path.GetTempPath(), "starbridge-first-use-device-setup", Op());
        internal string Device => Path.Combine(Root, "device");
        internal LocalFirstUseStore Store { get; }
        internal ApplicationStore AppStore { get; }
        internal Startup Startup { get; } = new();
        internal Native Native { get; } = new();
        internal ReminderSink Sink { get; } = new();
        internal OverlayWorkspaceStore Workspace { get; }
        internal ApplicationPreferencesBridgeDispatcher Application { get; }
        internal OverlayBridgeDispatcher Overlay { get; }
        internal NotificationSettingsBridgeDispatcher Notifications { get; }
        internal ContinuousPlayReminderRuntime Reminder { get; }
        internal LocalDeviceSetupReader Reader { get; }
        internal long Generation = 1;
        internal bool ThrowGeneration;
        internal int ProcessReads, AccountReads;
        internal Fixture(bool sourcePresets = false)
        {
            Directory.CreateDirectory(Device);
            Store = new(Device);
            var state = Store.SelectSource(0, Op(), Path.Combine(Root, "install", "LIVE", "Game.log"), "LIVE", () => true);
            Store.ConfirmIdentity(state.Revision, Op(), new(state.SelectedSourceKey!, Op(), "Pilot-Example",
                DateTimeOffset.UtcNow, "history", true, false), () => true);
            AppStore = new(new ApplicationPreferencesStore(Device));
            Application = new(AppStore, Startup, () => Generation);
            Workspace = new(Device, enableSourcePresets: sourcePresets);
            Overlay = new(new OverlaySettingsStore(Device), Workspace, () => Generation,
                () => { AccountReads++; throw new InvalidOperationException("Account must not be read"); }, Native);
            Notifications = new(Device, () => Generation);
            Reminder = new(Device, () => { ProcessReads++; throw new InvalidOperationException("Process must not be sampled"); }, Sink);
            Reader = new(Store, () => ThrowGeneration ? throw new InvalidOperationException("Private detail") : Generation,
                Application, Overlay, Notifications, Reminder);
        }
        internal Dictionary<string, string> Files() => Directory.GetFiles(Root, "*", SearchOption.AllDirectories)
            .ToDictionary(path => Path.GetRelativePath(Root, path), path => Convert.ToHexString(SHA256.HashData(File.ReadAllBytes(path))));
        internal void Unchanged(Dictionary<string, string> before)
        {
            var after = Files();
            Require(before.Count == after.Count && before.All(item => after.TryGetValue(item.Key, out var hash) && hash == item.Value), "inspection modified files");
        }
        public void Dispose()
        {
            Application.Dispose(); Overlay.Dispose(); Notifications.Dispose(); Reminder.Dispose();
            var full = Path.GetFullPath(Root);
            var parent = Path.GetFullPath(Path.Combine(Path.GetTempPath(), "starbridge-first-use-device-setup"));
            if (Path.GetDirectoryName(full) != parent || !Guid.TryParseExact(Path.GetFileName(full), "N", out _) ||
                File.GetAttributes(full).HasFlag(FileAttributes.ReparsePoint)) throw new InvalidOperationException("Unsafe fixture cleanup target");
            Directory.Delete(full, recursive: true);
        }
    }
    internal sealed class ApplicationStore(ApplicationPreferencesStore actual) : IApplicationPreferencesStore
    {
        internal ApplicationPreferencesStore Actual => actual;
        internal Action<int>? OnLoad;
        internal int Reads;
        public ApplicationPreferencesReadResult Load() { var value = actual.Load(); OnLoad?.Invoke(++Reads); return value; }
        public void Save(ApplicationPreferencesSnapshot value) => throw new InvalidOperationException("Reader cannot save");
    }
    internal sealed class Startup : IApplicationStartupRegistration
    {
        internal int Writes;
        public bool TrySetEnabled(bool enabled, out string? error) { Writes++; error = null; return true; }
    }
    internal sealed class Native : IInformationOverlayRuntime
    {
        internal int Commands;
        public ValueTask<InformationOverlayRuntimeSnapshot> ExecuteAsync(InformationOverlayRuntimeCommand command,
            InformationOverlayRuntimeWorkspace workspace, CancellationToken cancellationToken = default)
        { Commands++; throw new InvalidOperationException("Inspection cannot command native overlay"); }
        public void Dispose() { }
    }
    internal sealed class ReminderSink : IContinuousPlayReminderSink
    {
        internal int Calls;
        public ValueTask<bool> TryQueueAsync(ContinuousPlayNotice notice, CancellationToken cancellation)
        { Calls++; throw new InvalidOperationException("Inspection cannot queue reminders"); }
    }
    private sealed class MutatingWorkspace : IOverlayWorkspaceStore
    {
        internal int Loads;
        public OverlayWorkspaceReadResult Load() { Loads++; throw new InvalidOperationException("Mutating read"); }
        public OverlayWorkspaceReadResult Apply(OverlayWorkspaceMutation mutation, Func<bool>? isCurrent = null) => throw new InvalidOperationException("No writes");
    }
}
