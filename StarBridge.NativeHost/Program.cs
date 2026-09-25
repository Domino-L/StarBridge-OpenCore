using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Updates;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;
using StarBridge.NativeHost;
using StarBridge.OverlayRuntime.Windows;
using System.Diagnostics;

if (!NativeHostStartupOptions.TryParse(args, out var options) || options is null)
{
    return 2;
}

Process parent;
try
{
    parent = Process.GetProcessById(options.ParentProcessId);
}
catch (ArgumentException)
{
    return 3;
}

using (parent)
using (var lifetime = new CancellationTokenSource())
{
    string? flutterExecutablePath = null;
    try
    {
        flutterExecutablePath = parent.MainModule?.FileName;
    }
    catch
    {
        // Application preferences remain available, but startup registration
        // will fail closed if Windows does not expose the Flutter parent path.
    }

    var updateReporter = FlutterUpdateStartupReporter.FromEnvironment(parent.Id, flutterExecutablePath);
    var isolatedHangar = Environment.GetEnvironmentVariable("STARBRIDGE_HANGAR_SANDBOX") == "1";
    if (isolatedHangar)
        HostDataRoot.UsePreparedRoot(@"G:\Development\tools\starbridge-profile-mysql\instance-hangar-20260903\client-data");
    if (!isolatedHangar)
        StarBridge.HostRuntime.Storage.StorageMigrationRecovery.RecoverPending(HostDataRoot.BootstrapDirectory, lifetime.Token);
    // Acquire before resolving the locator or constructing any product stores.
    // Reverse using order retains this until journals and dispatchers are closed.
    using var storageActivity = isolatedHangar ? null :
        StarBridge.HostRuntime.Storage.StorageActivityLease.AcquireWriter(HostDataRoot.BootstrapDirectory);
    var releaseAssembly = System.Reflection.Assembly.GetExecutingAssembly();
    var updateSource = FlutterReleaseUpdateSource.FromRelease(releaseAssembly,
        new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath).Read().ApplicationVersion,
        System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.X64
            ? "windows-x64" : "unsupported");
    using var installedUpdates = !isolatedHangar && FlutterReleaseUpdateSource.InstallationEnabled(releaseAssembly)
        ? FlutterInstalledUpdateInstallation.TryCreate(updateSource, parent, HostDataRoot.CurrentRoot) : null;
    using var legacyCleanup = isolatedHangar ? null :
        LegacyCleanupLauncher.TryCreate(releaseAssembly, parent, HostDataRoot.CurrentRoot);
    // Shared non-UI WPF journal; no new Game.log watcher. Dispose after the pipe stops.
    using var eventJournal = isolatedHangar ? null : new LocalGameEventJournal(
        Path.Combine(HostDataRoot.CurrentRoot, "local-event-log.json"));
    eventJournal?.Load();
    var account = isolatedHangar
        ? AccountBridgeRuntime.CreateIsolatedSandboxShell()
        : await AccountBridgeRuntime.CreateDefaultAsync(cancellationToken: lifetime.Token,
            eventJournal: eventJournal?.IsWritable == true ? eventJournal : null);
    account.ConfigureCommunityLogoPicker(new WindowsCommunityLogoPicker(parent.Id));
    var exportPicker = new WindowsGameplayExportPicker(() =>
    {
        parent.Refresh();
        return parent.HasExited ? 0 : parent.MainWindowHandle;
    });
    var storagePicker = new WindowsStorageFolderPicker(() =>
    {
        parent.Refresh();
        return parent.HasExited ? 0 : parent.MainWindowHandle;
    });
    var storageHelperPath = Path.Combine(AppContext.BaseDirectory, "maintenance", "StarBridge.UpdateHelper.exe");
    var storageMigration = isolatedHangar || !File.Exists(storageHelperPath) ? null :
        new StarBridge.HostRuntime.Storage.StorageMigrationBridgeDispatcher(
            new StarBridge.HostRuntime.Storage.StorageMigrationSelection(
                HostDataRoot.BootstrapDirectory, () => HostDataRoot.CurrentRoot,
                storagePicker.ChooseAsync,
                new StarBridge.HostRuntime.Storage.StorageMigrationInstallation(
                    HostDataRoot.BootstrapDirectory, storageHelperPath, parent).HandoffAsync),
            () => account.Generation,
            new StarBridge.HostRuntime.Storage.StorageMigrationResultStore(HostDataRoot.BootstrapDirectory));
    if (!isolatedHangar)
        account.ConfigureGameplayExportPicker(exportPicker, HostDataRoot.CurrentRoot);
    account.ConfigureOverlayCommunitySource(HostDataRoot.CurrentRoot);
    var applicationPreferences = new ApplicationPreferencesBridgeDispatcher(
        HostDataRoot.CurrentRoot,
        () => account.Generation,
        flutterExecutablePath);
    var overlayRuntime = WindowsInformationOverlayRuntimeFactory.Create(
        () => account.CurrentGameSession,
        () => account.CurrentOverlayEntitlements,
        () => account.CurrentRoomOverlay,
        () => account.CurrentCommunityOverlay,
        () => account.CurrentOverlaySceneMode,
        () => applicationPreferences.CurrentLocaleOverride);
    var reminderSink = overlayRuntime as IContinuousPlayReminderSink;
    if (!isolatedHangar && overlayRuntime is StarBridge.HostRuntime.Privacy.ISharedActivitySink sharedActivities)
        account.ConfigureSharedActivity(sharedActivities);
    var desktopNotifications = WindowsInformationOverlayRuntimeFactory.CreateDesktopNotifications(parent.Id);
    var activityEnvironment = new WindowsNotificationActivity(parent.Id);
    var playerActivity = isolatedHangar ? null : new PlayerActivityRuntime(
        HostDataRoot.CurrentRoot, () => account.Generation, desktopNotifications,
        () => activityEnvironment.ReadPlayerActivity(overlayRuntime as IRuntimeOverlayStatusReader));
    if (playerActivity is not null && !account.ConfigurePlayerActivity(playerActivity)) {
        playerActivity.Dispose(); playerActivity = null;
    }
    var lifecycle = new HostBridgeDispatcher(
        Guid.NewGuid().ToString("N"),
        () => account.Generation,
        [
            "host.lifecycle",
            .. playerActivity is null ? Array.Empty<string>() : PlayerActivityRuntime.Capabilities,
            "host.gamePresence",
            "communities.logo",
            "account.avatarImages",
            .. AccountBridgeRuntime.AdvertisedCapabilities,
            .. ApplicationPreferencesBridgeDispatcher.AdvertisedCapabilities,
            .. OverlayBridgeDispatcher.AdvertisedCapabilities,
            .. NotificationAudioBridgeDispatcher.AdvertisedCapabilities,
            .. NotificationSettingsBridgeDispatcher.AdvertisedCapabilities,
            .. NotificationPolicyBridgeDispatcher.Capabilities,
            .. ApplicationSupportBridgeDispatcher.AdvertisedCapabilities,
            .. storageMigration is null ? Array.Empty<string>() : new[] {
                StarBridge.HostRuntime.Storage.StorageMigrationBridgeDispatcher.ChooseRequest,
                StarBridge.HostRuntime.Storage.StorageMigrationBridgeDispatcher.ConfirmRequest,
                StarBridge.HostRuntime.Storage.StorageMigrationBridgeDispatcher.ResultRequest,
                StarBridge.HostRuntime.Storage.StorageMigrationBridgeDispatcher.AcknowledgeRequest },
            .. RuntimeFactsBridgeDispatcher.AdvertisedCapabilities,
            .. ClientLicenseBridgeDispatcher.AdvertisedCapabilities,
            "legal.testBuildNotice",
            .. FlutterUpdateBridgeDispatcher.AdvertisedCapabilities,
            .. installedUpdates is null ? Array.Empty<string>() : new[] { FlutterUpdateBridgeDispatcher.PrepareRequestName, FlutterUpdateBridgeDispatcher.HandoffRequestName },
            .. HelpSupportBridgeDispatcher.Capabilities,
            .. updateReporter is null && legacyCleanup is null ? Array.Empty<string>() : new[] { FlutterUpdateBridgeDispatcher.ReadyRequestName },
            .. overlayRuntime is IRuntimeOverlayStatusReader
                ? OverlayRuntimeStatusBridgeDispatcher.AdvertisedCapabilities
                : Array.Empty<string>(),
            .. LocalEventHistoryBridgeDispatcher.AdvertisedCapabilities,
            .. eventJournal?.IsWritable == true ? LocalEventClearDispatcher.AdvertisedCapabilities : Array.Empty<string>(),
            .. isolatedHangar ? Array.Empty<string>() : LocalEventExportDispatcher.AdvertisedCapabilities,
            .. reminderSink is null ? Array.Empty<string>() : ContinuousPlayBridgeDispatcher.AdvertisedCapabilities,
            .. isolatedHangar ? Array.Empty<string>() : GameplayDataExportDispatcher.AdvertisedCapabilities
        ], gamePresence: new StarBridge.HostRuntime.Presence.LocalGamePresenceReader(
            trustedVersion: () => account.ConfirmedGameVersion,
            journal: eventJournal?.IsWritable == true ? eventJournal : null));
    var hangarSandbox = StarBridge.HostRuntime.Hangar.HangarSandboxDispatcher.FromEnvironment(() => account.Generation);
    var overlay = new OverlayBridgeDispatcher(
        HostDataRoot.CurrentRoot,
        () => account.Generation,
        () => account.CurrentGameSession,
        overlayRuntime);
    await overlay.InitializeRuntimeAsync(lifetime.Token);
    var audio = NotificationAudioBridgeDispatcher.CreateDefault(HostDataRoot.CurrentRoot,
        Path.Combine(AppContext.BaseDirectory, "Assets", "Audio"), () => account.Generation,
        new WindowsNotificationActivity(parent.Id).CanNotify);
    var playReminder = reminderSink is null ? null : new ContinuousPlayReminderRuntime(
        HostDataRoot.CurrentRoot, () =>
        {
            var process = StarBridge.HostRuntime.Presence.GameLogIdentityReader.Probe();
            return new PlayProcessObservation(process.State, process.StartedAt);
        }, reminderSink);
    var notifications = new NotificationSettingsBridgeDispatcher(HostDataRoot.CurrentRoot, () => account.Generation,
        new WindowsNotificationActivity(parent.Id).CanNotify, overlayRuntime as IInformationOverlayReminderSink,
        desktopNotifications, account.NotificationActivation);
    if (!isolatedHangar) account.ConfigureCommunityNotifications(notifications);
    using var dispatcher = new CompositeBridgeDispatcher(
        lifecycle,
        account,
        applicationPreferences,
        hangarSandbox,
        overlay,
        audio,
        notifications,
        notificationPolicies: account.CreateNotificationPolicyDispatcher(notifications),
        playerActivity: playerActivity,
        localEventClear: eventJournal?.IsWritable == true ? new LocalEventClearDispatcher(eventJournal, () => account.Generation) : null,
        localEventExport: isolatedHangar ? null : new LocalEventExportDispatcher(
            new LocalEventJournalReader(HostDataRoot.CurrentRoot), () => account.Generation,
            exportPicker, HostDataRoot.CurrentRoot),
        localHistory: new LocalEventHistoryBridgeDispatcher(
            new LocalEventJournalReader(HostDataRoot.CurrentRoot), () => account.Generation),
        overlayRuntimeStatus: overlayRuntime is IRuntimeOverlayStatusReader statusReader
            ? new OverlayRuntimeStatusBridgeDispatcher(statusReader, () => account.Generation)
            : null,
        clientLicense: new ClientLicenseBridgeDispatcher(
            new ClientLicenseReader(AppContext.BaseDirectory), () => account.Generation,
            new TestBuildNoticeStore(HostDataRoot.CurrentRoot)),
        helpSupport: new HelpSupportBridgeDispatcher(account.DiagnosticsRelayUri, () => account.Generation),
        // Installed updates require explicit compiled release opt-in AND exact
        // per-user installer ownership; development/portable previews remain read-only.
        updates: new FlutterUpdateBridgeDispatcher(updateSource,
            () => new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath).Read().ApplicationVersion,
            () => account.Generation, updateReporter, installedUpdates?.Installation, progressEvent: account.UpdateProgress,
            firstFrameReady: legacyCleanup is null ? null : legacyCleanup.FirstFrameReady),
        runtimeFacts: new RuntimeFactsBridgeDispatcher(
            new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath, () => account.DiagnosticsRelayUri?.AbsoluteUri),
            () => account.Generation),
        support: new ApplicationSupportBridgeDispatcher(HostDataRoot.CurrentRoot, flutterExecutablePath,
            () => account.SelectedGameLogPathForDiagnostics, () => account.Generation, account.DiagnosticsRelayUri),
        playReminder: playReminder is null ? null : new ContinuousPlayBridgeDispatcher(playReminder, () => account.Generation),
        storageMigration: storageMigration);
    // Reverse using order stops ticks and invalidates callbacks before overlay disposal.
    using var ownedPlayReminder = playReminder;
    using var playReminderDriver = playReminder is null ? null : new ContinuousPlayReminderDriver(playReminder);
    await using var server = new NativeHostPipeServer(options.PipeName, dispatcher);
    var parentExit = parent.WaitForExitAsync();
    var hostRun = server.RunAsync(lifetime.Token);
    try
    {
        var completed = await Task.WhenAny(parentExit, hostRun);
        lifetime.Cancel();
        await hostRun;
        return completed == parentExit ? 0 : 4;
    }
    finally
    {
        // Parent cancellation/pipe errors must still attempt the bounded clear.
        await account.StopPrivacyPublicationAsync();
    }
}
