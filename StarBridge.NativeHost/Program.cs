using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Settings;
using StarBridge.HostRuntime.Support;
using StarBridge.HostRuntime.Updates;
using StarBridge.HostRuntime.Overlay;
using StarBridge.HostRuntime.Notifications;
using StarBridge.HostRuntime.Reminders;
using StarBridge.HostRuntime.Tools;
using StarBridge.NativeHost;
using StarBridge.OverlayRuntime.Windows;
using System.Diagnostics;

// Packaging probe: exit before parent validation, storage, account or UI startup.
if (args is ["--overlay-source-build-info"])
{
    var flag = System.Reflection.CustomAttributeExtensions.GetCustomAttributes<System.Reflection.AssemblyMetadataAttribute>(
        typeof(OverlayBridgeDispatcher).Assembly)
        .SingleOrDefault(attribute => attribute.Key == "StarBridgeEnableOverlaySourcePresets")?.Value;
    if (!bool.TryParse(flag, out var enabled)) return 2;
    Console.WriteLine("overlay-source-presets=" + enabled.ToString().ToLowerInvariant());
    return 0;
}

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
    var firstUseEnabled = bool.TryParse(System.Reflection.CustomAttributeExtensions.GetCustomAttributes<System.Reflection.AssemblyMetadataAttribute>(releaseAssembly)
        .SingleOrDefault(attribute => attribute.Key == "StarBridgeEnableFirstUse")?.Value, out var enableFirstUse) && enableFirstUse;
    var updateSource = FlutterReleaseUpdateSource.FromRelease(releaseAssembly,
        new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath).Read().ApplicationVersion,
        System.Runtime.InteropServices.RuntimeInformation.ProcessArchitecture == System.Runtime.InteropServices.Architecture.X64
            ? "windows-x64" : "unsupported");
    using var installedUpdates = !isolatedHangar && FlutterReleaseUpdateSource.InstallationEnabled(releaseAssembly)
        ? FlutterInstalledUpdateInstallation.TryCreate(updateSource, parent, HostDataRoot.CurrentRoot) : null;
    using var legacyCleanup = isolatedHangar ? null :
        LegacyCleanupLauncher.TryCreate(releaseAssembly, parent, HostDataRoot.CurrentRoot);
    var firstUseStartupReader = isolatedHangar || !firstUseEnabled ? null : new StarBridge.HostRuntime.Onboarding.FirstUseStartupReader(
        HostDataRoot.CurrentRoot, () => StarBridge.HostRuntime.Onboarding.FirstUseStartupReader.ReadInstalledSource(
            flutterExecutablePath, Environment.ProcessPath!, HostDataRoot.CurrentRoot));
    // Shared non-UI WPF journal; no new Game.log watcher. Dispose after the pipe stops.
    using var eventJournal = isolatedHangar ? null : new LocalGameEventJournal(
        Path.Combine(HostDataRoot.CurrentRoot, "local-event-log.json"));
    eventJournal?.Load();
    var account = isolatedHangar
        ? AccountBridgeRuntime.CreateIsolatedSandboxShell()
        : await AccountBridgeRuntime.CreateDefaultAsync(cancellationToken: lifetime.Token,
            eventJournal: eventJournal?.IsWritable == true ? eventJournal : null, enableFirstUseModes: firstUseEnabled);
    await using var accountBinding = new NativeAccountRuntimeBinding(account);
    using var firstUseModeDispatcher = isolatedHangar || !firstUseEnabled ? null : accountBinding.CreateModeDispatcher();
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
            () => accountBinding.Generation,
            new StarBridge.HostRuntime.Storage.StorageMigrationResultStore(HostDataRoot.BootstrapDirectory));
    var applicationPreferences = new ApplicationPreferencesBridgeDispatcher(
        HostDataRoot.CurrentRoot,
        () => accountBinding.Generation,
        flutterExecutablePath);
    var menuBrowserResume = new MenuBrowserResumeBridgeDispatcher(
        HostDataRoot.CurrentRoot, () => accountBinding.Read(owner => owner.CurrentOverlaySourceScope, (OwnerKey: (string?)null, Generation: -1L)));
    var screenshotPicker = new WindowsStorageFolderPicker(() =>
    {
        parent.Refresh();
        return parent.HasExited ? 0 : WindowsStorageFolderPicker.ClientOwner(parent.Id, parent.MainWindowHandle);
    });
    var menuScreenshotDirectory = isolatedHangar ? null : new MenuScreenshotDirectoryBridgeDispatcher(
        HostDataRoot.CurrentRoot, () => accountBinding.Generation, screenshotPicker.ChooseAsync);
    var localGamePresence = new StarBridge.HostRuntime.Presence.LocalGamePresenceReader(
        trustedVersion: () => accountBinding.Read(owner => owner.ConfirmedGameVersion, (string?)null),
        journal: eventJournal?.IsWritable == true ? eventJournal : null);
    var overlayRuntime = WindowsInformationOverlayRuntimeFactory.Create(
        () => accountBinding.Read(owner => owner.CurrentGameSession, StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty),
        () => accountBinding.Read(owner => owner.CurrentOverlayEntitlements, Array.Empty<string>()),
        () => accountBinding.Read(owner => owner.CurrentRoomOverlay, (InformationOverlayRoomContent?)null),
        () => accountBinding.Read(owner => owner.CurrentCommunityOverlay, (InformationOverlayCommunityContent?)null),
        () => accountBinding.Read(owner => owner.CurrentOverlaySceneMode, (string?)null),
        () => applicationPreferences.CurrentLocaleOverride,
        () => accountBinding.Read(owner => owner.CurrentOverlayRosterPreferences, InformationOverlayRosterPreferences.Empty),
        localGamePresence.Read,
        token => accountBinding.RunAsync((owner, cancellation) => owner.PrepareCommunityOverlayAsync(cancellation), token),
        workspace => accountBinding.Read(owner => owner.ReadOverlayModules(workspace), new InformationOverlayModuleReadResult(null, "overlay.identity_unavailable")),
        installedAppearanceDataRoot: HostDataRoot.CurrentRoot,
        installedAppearanceProgress: isolatedHangar ? null : account.CreateInstalledAppearanceProgress(),
        localSource: account.FirstUseOverlaySource);
    var reminderSink = overlayRuntime as IContinuousPlayReminderSink;
    var menuHotkeys = !isolatedHangar && overlayRuntime is IMenuHotkeyRuntime menuRuntime
        ? new MenuHotkeyBridgeDispatcher(menuRuntime, () => accountBinding.Read(owner => owner.CurrentOverlaySourceScope, (OwnerKey: (string?)null, Generation: -1L)),
            accountBinding.DeviceMenuHotkeyIntent, parent.Id, applicationPreferences.MenuHotkeyPreferences) : null;
    if (menuHotkeys is not null) account.ConfigureMenuHotkeys(menuHotkeys);
    var desktopNotifications = WindowsInformationOverlayRuntimeFactory.CreateDesktopNotifications(parent.Id);
    var activityEnvironment = new WindowsNotificationActivity(parent.Id);
    // One device-only preferences/test entry also exists on a local cold start.
    // It never receives social observations; those belong to each account graph.
    var playerActivity = isolatedHangar ? null : new PlayerActivityRuntime(
        HostDataRoot.CurrentRoot, () => accountBinding.Generation, desktopNotifications,
        () => activityEnvironment.ReadPlayerActivity(overlayRuntime as IRuntimeOverlayStatusReader));
    var previewClient = new WindowsOverlayPreviewRegisteredClient(parent.Id, Environment.ProcessId, () => !parent.HasExited);
    var appearanceLivePreview = !isolatedHangar && overlayRuntime is IInformationOverlayLivePreviewRuntime previewRuntime &&
        overlayRuntime is IInformationOverlayLivePreviewControls && overlayRuntime is IInformationOverlayLivePreviewPlayback
        ? new OverlayAppearanceLivePreviewDispatcher(previewRuntime, () => accountBinding.Generation,
            () => accountBinding.Read(owner => owner.CurrentOverlaySourceScope, (OwnerKey: (string?)null, Generation: -1L)), previewClient.Resolve, previewClient.Capture) : null;
    var lifecycle = new HostBridgeDispatcher(
        Guid.NewGuid().ToString("N"),
        () => accountBinding.Generation,
        [
            "host.lifecycle",
            .. firstUseEnabled && firstUseModeDispatcher is not null && reminderSink is not null
                ? new[] { StarBridge.HostRuntime.Onboarding.FirstUseBridgeDispatcher.Capability } : Array.Empty<string>(),
            .. firstUseStartupReader is null ? Array.Empty<string>() : new[] { StarBridge.HostRuntime.Onboarding.FirstUseStartupBridgeDispatcher.Capability },
            .. menuHotkeys is null ? Array.Empty<string>() : new[] { MenuHotkeyBridgeDispatcher.Capability },
            .. playerActivity is null ? Array.Empty<string>() : PlayerActivityRuntime.Capabilities,
            "host.gamePresence",
            "communities.logo",
            "communities.wideImage",
            "account.avatarImages",
            "achievementIdeas.images",
            .. AccountBridgeRuntime.AdvertisedCapabilities,
            .. ApplicationPreferencesBridgeDispatcher.AdvertisedCapabilities,
            .. MenuBrowserResumeBridgeDispatcher.Capabilities,
            .. menuScreenshotDirectory is null ? Array.Empty<string>() : MenuScreenshotDirectoryBridgeDispatcher.Capabilities,
            .. OverlayBridgeDispatcher.AdvertisedCapabilities,
            .. appearanceLivePreview is null ? Array.Empty<string>() : new[] { OverlayAppearanceLivePreviewDispatcher.Capability },
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
            .. firstUseEnabled && !isolatedHangar && reminderSink is not null ? new[] { StarBridge.HostRuntime.Onboarding.LocalDeviceReviewBridgeDispatcher.Capability } : Array.Empty<string>(),
            .. account.GuideStateDispatcher is not null ? new[] { StarBridge.HostRuntime.Onboarding.GuideStateBridgeDispatcher.Capability } : Array.Empty<string>(),
            .. account.FirstUseStatisticsDispatcher is not null ? new[] { StarBridge.HostRuntime.Onboarding.LocalStatisticsChoiceBridgeDispatcher.Capability,
                StarBridge.HostRuntime.Onboarding.LocalStatisticsChoiceBridgeDispatcher.HistoryCapability,
                StarBridge.HostRuntime.Onboarding.LocalStatisticsChoiceBridgeDispatcher.ResetCapability,
                StarBridge.HostRuntime.Onboarding.LocalStatisticsChoiceBridgeDispatcher.RecognitionCapability } : Array.Empty<string>(),
            .. !isolatedHangar && account.FirstUseOnlineReviewDispatcher is not null ? StarBridge.HostRuntime.Onboarding.FirstUseOnlineReviewBridgeDispatcher.AdvertisedCapabilities : Array.Empty<string>(),
            .. firstUseModeDispatcher is not null ? new[] { StarBridge.HostRuntime.Onboarding.FirstUseModeBridgeDispatcher.Capability,
                StarBridge.HostRuntime.Onboarding.FirstUseModeBridgeDispatcher.OrganizationsCapability } : Array.Empty<string>(),
            .. firstUseModeDispatcher is not null ? new[] { StarBridge.HostRuntime.Onboarding.FirstUseOnlineInstallationBridgeDispatcher.Capability } : Array.Empty<string>(),
            .. firstUseEnabled && !isolatedHangar && overlayRuntime is StarBridge.HostRuntime.Onboarding.INativeOverlayObservationReader
                ? new[] { StarBridge.HostRuntime.Onboarding.NativeOverlayObservationBridgeDispatcher.Capability } : Array.Empty<string>(),
            .. ExecHangarBridgeDispatcher.Capabilities,
            .. isolatedHangar ? Array.Empty<string>() : GameplayDataExportDispatcher.AdvertisedCapabilities
        ], gamePresence: localGamePresence, additionalCapabilities: () =>
            accountBinding.Read(owner => owner.AdditionalHostCapabilities, (IReadOnlyList<string>)Array.Empty<string>()));
    var hangarSandbox = StarBridge.HostRuntime.Hangar.HangarSandboxDispatcher.FromEnvironment(() => accountBinding.Generation);
    var overlay = new OverlayBridgeDispatcher(
        HostDataRoot.CurrentRoot,
        () => accountBinding.Generation,
        () => accountBinding.Read(owner => owner.CurrentGameSession, StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty),
        overlayRuntime,
        () => accountBinding.Read(owner => owner.CurrentOverlayPresetTrigger, (OverlayPresetTrigger?)null),
        () => accountBinding.Read(owner => owner.CurrentOverlaySourceScope, (OwnerKey: (string?)null, Generation: -1L)));
    await overlay.InitializeRuntimeAsync(lifetime.Token);
    var audio = NotificationAudioBridgeDispatcher.CreateDefault(HostDataRoot.CurrentRoot,
        Path.Combine(AppContext.BaseDirectory, "Assets", "Audio"), () => accountBinding.Generation,
        activityEnvironment.CanNotify,
        activityEnvironment.CanPlaySocialSound, () => menuHotkeys?.IsMenuVisible == true);
    using var achievementCelebration = new NativeAchievementCelebrationRuntime(
        () => applicationPreferences.CurrentLocaleOverride,
        () => applicationPreferences.CurrentAppearanceMode == "light",
        () => applicationPreferences.CurrentReduceMotion,
        audio.TryPlayAchievement, audio.StopAchievement);
    var playReminder = reminderSink is null ? null : new ContinuousPlayReminderRuntime(
        HostDataRoot.CurrentRoot, () =>
        {
            var process = StarBridge.HostRuntime.Presence.GameLogIdentityReader.Probe();
            return new PlayProcessObservation(process.State, process.StartedAt);
        }, reminderSink);
    var notifications = new NotificationSettingsBridgeDispatcher(HostDataRoot.CurrentRoot, () => accountBinding.Generation,
        activityEnvironment.CanNotify, overlayRuntime as IInformationOverlayReminderSink,
        desktopNotifications, accountBinding.DeviceNotificationActivation, accountBinding.SocialNotification,
        gameIdentityPolicy: (context, token) => accountBinding.ReadAsync((owner, cancellation) => owner.ReadGameIdentityNotificationPolicyAsync(context, cancellation), token),
        canNotifyGameIdentity: activityEnvironment.CanNotifyGameIdentity,
        isGameIdentityCurrent: (context, expected) => accountBinding.Read(owner => owner.IsGameIdentityNotificationCurrent(context, expected), false),
        desktopSuppressionReason: activityEnvironment.DesktopSuppressionReason,
        rallyBanner: overlayRuntime as IRallyBannerSink, playRally: audio.TryPlayRally,
        hotkeys: overlayRuntime as ISafeHotkeyRuntime, hostEvent: accountBinding.HostEvent,
        directUnread: overlayRuntime as IInformationOverlayDirectUnreadSink,
        tradeSuppressionReason: activityEnvironment.TradeSuppressionReason, playTrade: audio.TryPlayTrade);
    if (firstUseEnabled && !isolatedHangar && playReminder is not null)
        account.ConfigureFirstUseDeviceSetup(applicationPreferences, overlay, notifications, playReminder);
    var accountComposition = isolatedHangar ? null : new AccountBridgeRuntime.NativeBusinessComposition(
        HostDataRoot.CurrentRoot, () => new WindowsCommunityLogoPicker(parent.Id), exportPicker,
        owner => new PlayerActivityRuntime(HostDataRoot.CurrentRoot, () => owner.Generation, desktopNotifications,
            () => activityEnvironment.ReadPlayerActivity(overlayRuntime as IRuntimeOverlayStatusReader)),
        overlayRuntime as IInformationOverlayLiveUpdateSink,
        overlayRuntime as StarBridge.HostRuntime.Privacy.ISharedActivitySink,
        achievementCelebration, notifications, audio);
    if (accountComposition is not null) account.TryConfigureAccountBusiness(accountComposition.Configure);
    var firstUse = firstUseEnabled && firstUseModeDispatcher is not null && firstUseStartupReader is not null &&
        accountComposition is not null && account.FirstUseCompletion is not null
        ? account.CreateFirstUseDispatcher(accountBinding, firstUseStartupReader, new WindowsFirstUseLogPicker(parent.Id),
            accountComposition, () => applicationPreferences.CurrentLocaleOverride ?? "zh-CN") : null;
    using var execConfigClient = new ExecHangarConfigClient(
        StarBridge.HostRuntime.Auth.ScmOAuthOptions.CreateDefault().AuthorizationServerBaseUri);
    var execHangar = new ExecHangarRuntime(HostDataRoot.CurrentRoot, execConfigClient, async (delivery, token) => {
        var state = await notifications.PresentExecHangarAsync(delivery, activityEnvironment.CanNotifyExecHangar, token);
        var played = audio.TryPlayExecHangar(delivery.IsCurrent, activityEnvironment.CanNotifyExecHangar);
        return state == "submitted" ? state : played ? "soundOnly" : state;
    }, game: StarBridge.HostRuntime.Presence.GameLogIdentityReader.Probe, network: account.DeviceNetwork);
    using var execHangarGameOverlay = new ExecHangarGameOverlay(
        token => execHangar.ReadAsync(false, token),
        new NativeExecHangarGameOverlay(() => menuHotkeys?.IsMenuVisible == true, () => applicationPreferences.CurrentLocaleOverride),
        () => accountBinding.Generation);
    var appStatsCapability = new AppStatsHeartbeatRuntime.RelayCapability();
    using var dispatcher = new CompositeBridgeDispatcher(
        lifecycle,
        accountBinding,
        applicationPreferences,
        hangarSandbox,
        overlay,
        audio,
        notifications,
        menuHotkeys: menuHotkeys,
        menuBrowserResume: menuBrowserResume,
        menuScreenshotDirectory: menuScreenshotDirectory,
        notificationPolicies: accountBinding.CreateNotificationPolicyDispatcher(notifications),
        playerActivity: playerActivity,
        localEventClear: eventJournal?.IsWritable == true ? new LocalEventClearDispatcher(eventJournal, () => accountBinding.Generation) : null,
        localEventExport: isolatedHangar ? null : new LocalEventExportDispatcher(
            new LocalEventJournalReader(HostDataRoot.CurrentRoot), () => accountBinding.Generation,
            exportPicker, HostDataRoot.CurrentRoot),
        localHistory: new LocalEventHistoryBridgeDispatcher(
            new LocalEventJournalReader(HostDataRoot.CurrentRoot), () => accountBinding.Generation),
        overlayRuntimeStatus: overlayRuntime is IRuntimeOverlayStatusReader statusReader
            ? new OverlayRuntimeStatusBridgeDispatcher(statusReader, () => accountBinding.Generation)
            : null,
        clientLicense: new ClientLicenseBridgeDispatcher(
            new ClientLicenseReader(AppContext.BaseDirectory), () => accountBinding.Generation,
            new TestBuildNoticeStore(HostDataRoot.CurrentRoot)),
        helpSupport: new HelpSupportBridgeDispatcher(account.DiagnosticsRelayUri, () => accountBinding.Generation,
            network: account.DeviceNetwork, appStatsCapability: appStatsCapability),
        // Installed updates require explicit compiled release opt-in AND exact
        // per-user installer ownership; development/portable previews remain read-only.
        updates: new FlutterUpdateBridgeDispatcher(updateSource,
            () => new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath).Read().ApplicationVersion,
            () => accountBinding.Generation, updateReporter, installedUpdates?.Installation, progressEvent: accountBinding.DeviceUpdateProgress,
            firstFrameReady: legacyCleanup is null ? null : legacyCleanup.FirstFrameReady, network: account.DeviceNetwork),
        runtimeFacts: new RuntimeFactsBridgeDispatcher(
            new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath, () => accountBinding.Read(owner => owner.DiagnosticsRelayUri?.AbsoluteUri, (string?)null)),
            () => accountBinding.Generation),
        support: new ApplicationSupportBridgeDispatcher(HostDataRoot.CurrentRoot, flutterExecutablePath,
            () => accountBinding.Read(owner => owner.SelectedGameLogPathForDiagnostics, (string?)null), () => accountBinding.Generation, account.DiagnosticsRelayUri, network: account.DeviceNetwork,
            clearImageReadCaches: () => { accountBinding.Read(owner => { owner.ClearDownloadableImageReadCaches(); return true; }, false); }),
        playReminder: playReminder is null ? null : new ContinuousPlayBridgeDispatcher(playReminder, () => accountBinding.Generation),
        storageMigration: storageMigration,
        appearanceLivePreview: appearanceLivePreview,
        execHangar: new ExecHangarBridgeDispatcher(execHangar, () => accountBinding.Generation, execHangarGameOverlay),
        firstUseDeviceReview: account.FirstUseDeviceReviewDispatcher,
        firstUseStatistics: account.FirstUseStatisticsDispatcher,
        guideState: account.GuideStateDispatcher,
        firstUseOnlineReview: isolatedHangar ? null : account.FirstUseOnlineReviewDispatcher,
        firstUseMode: firstUseModeDispatcher,
        firstUse: firstUse,
        firstUseStartup: firstUseStartupReader is null ? null : new StarBridge.HostRuntime.Onboarding.FirstUseStartupBridgeDispatcher(firstUseStartupReader, () => accountBinding.Generation),
        firstUseOnlineInstallation: !firstUseEnabled || accountComposition is null ? null : accountBinding.CreateOnlineInstallationDispatcher(accountComposition),
        firstUseOverlayObservation: firstUseEnabled && !isolatedHangar && overlayRuntime is StarBridge.HostRuntime.Onboarding.INativeOverlayObservationReader overlayObservation
            ? new StarBridge.HostRuntime.Onboarding.NativeOverlayObservationBridgeDispatcher(overlayObservation, () => accountBinding.Generation) : null);
    // Reverse using order stops ticks and invalidates callbacks before overlay disposal.
    using var appStatsHeartbeat = isolatedHangar ? null : new AppStatsHeartbeatRuntime(
        account.DiagnosticsRelayUri, overlayRuntime as IInformationOverlayUsageMeter, account.DeviceNetwork,
        new ApplicationRuntimeFactsReader(HostDataRoot.CurrentRoot, flutterExecutablePath).Read().ApplicationVersion,
        TimeProvider.System, HostDataRoot.CurrentRoot,
        visibility: () => accountBinding.Read(owner => owner.AppStatsPresenceVisibilityMode,
            StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Offline), capability: appStatsCapability);
    using var localOverlayEvents = eventJournal?.IsWritable == true && overlayRuntime is ILocalGameOverlayEventSink localEventSink
        ? new LocalGameOverlayEventSource(eventJournal, localEventSink, () => accountBinding.Generation) : null;
    using var ownedPlayReminder = playReminder;
    using var playReminderDriver = playReminder is null ? null : new ContinuousPlayReminderDriver(playReminder);
    using var ownedExecHangar = execHangar;
    using var execHangarDriver = new ExecHangarDriver(execHangar);
    using var execHangarGameOverlayDriver = new ExecHangarGameOverlayDriver(execHangarGameOverlay);
    using var gameStartupHint = new GameStartupHintRuntime(WindowsInformationOverlayRuntimeFactory.ReadGameStartupSession,
        () => menuHotkeys?.ReadGameStartupHint(), desktopNotifications,
        () => (applicationPreferences.CurrentLocaleOverride ?? "zh-CN", applicationPreferences.CurrentAppearanceMode, applicationPreferences.CurrentReduceMotion));
    using var gameStartupHintDriver = new GameStartupHintDriver(gameStartupHint);
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
        Exception? shutdownFailure = null;
        try { await accountBinding.StopPrivacyPublicationAsync(); }
        catch (Exception error) { shutdownFailure = error; }
        // Composite owns borrowed device resources. Await the actual account
        // consumers/configuration here, before Composite's synchronous Dispose.
        try { await accountBinding.DisposeAsync(); }
        catch (Exception error)
        { shutdownFailure = shutdownFailure is null ? error : new AggregateException(shutdownFailure, error); }
        if (shutdownFailure is not null) throw shutdownFailure;
    }
}
