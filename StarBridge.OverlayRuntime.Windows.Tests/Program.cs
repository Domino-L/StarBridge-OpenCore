using System.Reflection;
using StarBridge.Desktop.Tests;
using StarBridge.OverlayRuntime.Windows;
args = args.Where(a => a is not ("-nodeReuse:false" or "-p:UseSharedCompilation=false" or "--")).ToArray();
// 0.7.3 keeps ordinary announcements off the overlay; the announcement machinery stays under test
// for urgent announcements, so the suites run it switched on (OverlayAnnouncementOnceTests checks the off default).
StarBridge.Desktop.OverlayViewModel.OverlayShowsAnnouncements = true;
if (args is ["--announcement-card-only"]) { AnnouncementNotificationCardTests.Run(); return; }
if (args is ["--own-health-only"]) { SelfHealthReadingRuntimeTests.Run(); return; }
if (args is ["--cx-celcard-g1-offscreen", var output]) { AchievementCelebrationOffscreenProbe.Run(output); return; }
if (args is ["--celebration-receipt-recovery-only"]) { CelebrationReceiptRecoveryTests.Run(); return; }
if (args is ["--celebration-notification-environment-only"]) { NotificationEnvironmentPolicyTests.RunAll(); return; }
if (args.Length == 0) AnnouncementNotificationCardTests.Run();
if (args is ["--contract-host-only"]) {
    try { ContractAchievementCelebrationTests.Run(); }
    catch (Exception e) { Console.WriteLine("FAIL CONTRACT OVERLAY " + e.Message); Environment.ExitCode = 1; }
    return;
}

var rendering = typeof(WindowsInformationOverlayRuntimeFactory).Assembly;
#if STARBRIDGE_JOURNEY_ART
if (args is ["--cityhost-only"]) { JourneyAchievementCelebrationTests.Run(); return; }
#endif
#if STARBRIDGE_JOURNEY_ART
if (args.Length == 0) JourneyAchievementCelebrationTests.Run();
#endif
if (args is ["--achcel-only"])
{
    var cases = new (string Name, Action Run)[] {
        ("Playback", AchievementCelebrationPlaybackTests.Run),
        ("Dispatcher audio ownership", CelebrationAudioOwnershipTests.Run),
        ("Durable receipt recovery", CelebrationReceiptRecoveryTests.Run),
        ("Desktop deferral", CelebrationDesktopDeferralTests.Run),
        ("Bundled artwork", AchievementCelebrationCardTests.Run),
        ("Rally projection", RallyReminderTests.Run)
    };
    var failed = 0;
    foreach (var (name, run) in cases) {
        try { run(); Console.WriteLine("PASS ACHCEL " + name); }
        catch (Exception error) { failed++; Console.WriteLine("FAIL ACHCEL " + name + ": " + error.Message); }
    }
    Console.WriteLine($"SUMMARY ACHCEL passed={cases.Length - failed} failed={failed}");
    Environment.ExitCode = failed == 0 ? 0 : 1; return;
}
if (args is ["--achievement-playback-only"]) { AchievementCelebrationPlaybackTests.Run(); return; }
if (args is ["--celebration-desktop-queue-only"]) { CelebrationDesktopDeferralTests.Run(); return; }
if (args.Length == 0) CelebrationDesktopDeferralTests.Run();
if (args is ["--community-wide-image-only"]) { CommunityWideImageTests.Run(); return; }
if (args.Length == 0) CommunityWideImageTests.Run();
if (args is ["--overlay-rally-only"]) { RallyReminderTests.Run(); return; }
if (args is ["--overlay-usage-only"]) { OverlayUsageClockTests.Run(); return; }
if (args.Length == 0) OverlayUsageClockTests.Run();
if (args.Length == 0) RallyReminderTests.Run();
if (args is ["--member-paging-boundaries-only"]) { OverlayMemberPagingBoundaryTests.RunAll(); return; }
if (args.Length == 0) OverlayMemberPagingBoundaryTests.RunAll();
if (args is ["--visor-pictures"]) { OverlayVisorTests.Pictures(); return; }
if (args is ["--visor-intro-frames"]) { OverlayVisorTests.IntroFrames(); return; }
if (args is ["--visor-health-rings"]) { OverlayVisorTests.HealthRings(); return; }
if (args is ["--visor-health-motion"]) { OverlayVisorTests.HealthMotion(); return; }
if (args is ["--visor-catalog"]) { OverlayVisorTests.Catalog(); return; }
if (args is ["--visor-text-widths"]) { OverlayVisorTests.TextWidths(); return; }
if (args is ["--visor-only"]) { OverlayVisorTests.Run(); OverlayVisorUnknownTests.Run(); OverlayVisorEventTests.Run(); ReminderCardPictureTests.Run(); OverlayV2HiddenAppearanceTests.Run(); OverlayDeviceReleaseTests.Run(); OverlayVisorIntroHealthTests.Run(); OverlayVisorSelfRingWatchTests.Run(); return; }
if (args is ["--device-release-only"]) { OverlayDeviceReleaseTests.Run(); return; }
if (args is ["--visor-intro-health-only"]) { OverlayVisorIntroHealthTests.Run(); return; }
if (args is ["--visor-unknown-only"]) { OverlayVisorUnknownTests.Run(); return; }
if (args is ["--visor-self-ring-only"]) { OverlayVisorSelfRingWatchTests.Run(); return; }
if (args.Length == 0) { OverlayVisorTests.Run(); OverlayVisorUnknownTests.Run(); OverlayVisorEventTests.Run(); ReminderCardPictureTests.Run(); OverlayV2HiddenAppearanceTests.Run(); OverlayDeviceReleaseTests.Run(); OverlayVisorIntroHealthTests.Run(); OverlayVisorSelfRingWatchTests.Run(); }
if (args is ["--ship-display-boundary-only"]) { ShipDisplayNameBoundaryTests.RunAll(); return; }
if (args.Length == 0) ShipDisplayNameBoundaryTests.RunAll();
#if STARBRIDGE_JOURNEY_ART
if (args is ["--achievement-artwork-only"]) { AchievementCelebrationCardTests.Run(); return; }
#endif
if (args is ["--achievement-window-density-only"]) { AchievementCelebrationWindowTests.Run(); return; }
// Pure source/projection checks only: no Native runtime constructor, HWND,
// hotkey registration, process observation or default UI test group.
if (args is ["--first-use-local-source-only"])
{
    await LocalOverlaySourceTests.Run();
    LocalOverlayProjectionTests.Run();
    return;
}
if (args.Length == 0) LocalOverlayProjectionTests.Run();
if(args.Contains("--game-startup-hint-only")){GameStartupHintCardTests.Run();return;}
if(args.Length==0)GameStartupHintCardTests.Run();
if (args.Length == 0) SelfHealthReadingRuntimeTests.Run();
if(args.Contains("--exec-hangar-game-overlay-only")){ExecHangarGameOverlayTests.Run();return;}
if(args.Length==0)ExecHangarGameOverlayTests.Run();
if (args is ["--achievement-live-presentation-probe", var achievementAssetRoot]) { await AchievementCelebrationLiveProbe.Run(achievementAssetRoot); return; }
if (args is ["--achievement-live-grant-probe", var achievementGrantAssetRoot]) { await AchievementCelebrationLiveProbe.Run(achievementGrantAssetRoot, throughGrant: true); return; }
if (args.Contains("--achievement-show-lifecycle-probe")) { AchievementCelebrationWindowTests.RunShowLifecycleProbe(); return; }
#if STARBRIDGE_JOURNEY_ART
if (args is ["--achievement-celebration-only"])
{
    var cases = new (string Name, Action Run)[]
    {
        (nameof(AchievementCelebrationCardTests), AchievementCelebrationCardTests.Run),
        (nameof(AchievementCelebrationWindowTests), AchievementCelebrationWindowTests.Run),
        (nameof(AchievementCelebrationPlaybackTests), AchievementCelebrationPlaybackTests.Run),
        (nameof(ContractAchievementCelebrationTests), ContractAchievementCelebrationTests.Run),
        (nameof(JourneyAchievementCelebrationTests), JourneyAchievementCelebrationTests.Run),
        (nameof(CelebrationReceiptRecoveryTests), CelebrationReceiptRecoveryTests.Run),
        (nameof(CelebrationDesktopDeferralTests), CelebrationDesktopDeferralTests.Run),
        (nameof(NotificationEnvironmentPolicyTests), NotificationEnvironmentPolicyTests.RunAll)
    };
    var failed = 0;
    foreach (var (name, run) in cases)
    {
        try { run(); Console.WriteLine("PASS " + name); }
        catch (Exception error) { failed++; Console.WriteLine("FAIL " + name + ": " + error); }
    }
    Console.WriteLine($"SUMMARY achievement celebration passed={cases.Length - failed} failed={failed}");
    Environment.ExitCode = failed == 0 ? 0 : 1;
    return;
}
#endif
#if STARBRIDGE_JOURNEY_ART
if (args.Length == 0) { AchievementCelebrationPlaybackTests.Run(); AchievementCelebrationWindowTests.Run(); AchievementCelebrationCardTests.Run(); }
#endif
if (args.Contains("--desktop-notification-only")) { DesktopNotificationCardTests.RunAll(); NotificationEnvironmentPolicyTests.RunAll(); return; }
if (args.Contains("--frame-scheduler-lifecycle-only"))
{
    await OverlayFrameSchedulerLifecycleTests.Run();
    return;
}
if (args.Length == 0) await OverlayFrameSchedulerLifecycleTests.Run();
if (args.Contains("--installed-appearance-identity-only"))
{
    InstalledAppearanceIdentityTests.Run();
    return;
}
if (args.Length == 0) InstalledAppearanceIdentityTests.Run();
if (args.Contains("--appearance-activity-only"))
{
    OverlayAppearanceActivityRowTests.RunAll();
    OverlayCommunicationAppearanceTests.RunAll();
    return;
}
if (args.Contains("--event-final-frame-only")){OverlayEventFinalFrameTests.RunAll();return;}
if (args.Length == 0) OverlayEventFinalFrameTests.RunAll();
if (args.Length == 0) OverlayAppearanceActivityRowTests.RunAll();
if (args.Length == 0) OverlayCommunicationAppearanceTests.RunAll();
if (args.Contains("--menu-dialog-owner-only"))
{
    MenuDialogOwnerTests.Run();
    return;
}
if (args.Length == 0) MenuDialogOwnerTests.Run();
if (args.Contains("--editor-preview-only")) { await OverlayEditorPreviewTests.Run(); return; }
if (args.Length == 0) await OverlayEditorPreviewTests.Run();
if (args.Contains("--menu-hud-lifecycle-only"))
{
    await MenuHudLifecycleTests.Run();
    return;
}
// The real z-order check depends on the other windows on the desktop. A failure is reported
// and fails the run, but the groups after it still run.
if (args.Length == 0)
{
    try { await MenuHudLifecycleTests.Run(); }
    catch (Exception error) { Console.Error.WriteLine("FAIL menu HUD lifecycle: " + error); Environment.ExitCode = 1; }
}
if (args.Contains("--runtime-state-events-only"))
{
    await OverlayRuntimeStateEventTests.Run();
    return;
}
if (args.Length == 0) await OverlayRuntimeStateEventTests.Run();
if (args.Contains("--shared-hotkeys-only"))
{
    OverlaySharedHotkeyTests.RunAll();
    return;
}
if (args.Length == 0) OverlaySharedHotkeyTests.RunAll();
if (args.Contains("--module-lifecycle-only"))
{
    try { await OverlayModuleLifecycleTests.Run(); }
    catch (Exception error) { Console.Error.WriteLine("FAIL module lifecycle: " + error); Environment.ExitCode = 1; }
    return;
}
if (args.Contains("--module-sources-only"))
{
    OverlayModuleProjectionTests.RunAll();
    return;
}
if (args.Contains("--cold-open-recovery-only"))
{
    try { await OverlayColdOpenRecoveryTests.Run(); }
    catch (Exception error) { Console.Error.WriteLine("FAIL cold open recovery: " + error); Environment.ExitCode = 1; }
    return;
}
if (args.Contains("--cold-open-lifecycle-only"))
{
    try { await OverlayColdOpenLifecycleTests.Run(); }
    catch (Exception error) { Console.Error.WriteLine("FAIL cold open lifecycle: " + error); Environment.ExitCode = 1; }
    return;
}
if (args.Contains("--announcement-replay-only"))
{
    OverlayAnnouncementReplayTests.RunAll();
    return;
}
if (args.Contains("--cold-open-only"))
{
    OverlayColdOpenTests.RunAll();
    return;
}
if (args.Contains("--wpf-producer-parity-only"))
{
    WpfProducerParityTests.RunAll();
    return;
}
if (args.Contains("--shared-ship-cards-only"))
{
    SharedShipEventCardsTests.RunAll();
    return;
}
if (args.Contains("--comprehensive-audit-only"))
{
    OverlayComprehensiveAuditTests.RunAll();
    return;
}
if (args.Contains("--overview-facts-only"))
{
    OverlayOverviewFactsTests.RunAll();
    return;
}
if (args.Contains("--main-fleet-chat-only"))
{
    OverlayMainFleetChatTests.RunAll();
    return;
}
if (args.Contains("--main-fleet-only"))
{
    OverlayMainFleetTitleTests.RunAll();
    return;
}
if (args.Contains("--arrival-source-only"))
{
    OverlayArrivalSourceTests.RunAll();
    return;
}
if (args.Contains("--event-queue-audit-only"))
{
    EventQueueAuditTests.RunAll();
    return;
}
if (args.Contains("--continuous-play-only"))
{
    ContinuousPlayOverlayTests.RunAll();
    return;
}
if (args.Contains("--module-sync-only"))
{
    OverlayModuleSyncTests.RunAll();
    return;
}
if (args.Contains("--module-source-labels-only"))
{
    OverlayModuleSourceLabelTests.RunAll();
    return;
}
if (args.Contains("--calm-modules-only"))
{
    OverlayCalmModulesTests.RunAll();
    return;
}
if (args.Contains("--member-paging-only"))
{
    OverlayMemberPagingTests.RunAll();
    return;
}
if (args.Contains("--event-flicker-only"))
{
    OverlayEventFlickerTests.RunAll();
    return;
}
if (args.Contains("--region-summary-only"))
{
    OverlayRegionSummaryTests.RunAll();
    Console.WriteLine("PASS shared and local primary-region event vocabulary");
    return;
}
if (args is ["--ship-catalog-only", var catalogPath])
{
    OverlayShipNameTests.RunAll();
    OverlayShipNameTests.FullDisplayCatalog(catalogPath);
    SharedShipEventCardsTests.FullDisplayCatalog(catalogPath);
    return;
}
if (args.Contains("--ship-names-only"))
{
    OverlayShipNameTests.RunAll();
    Console.WriteLine("PASS ship names survive both scenes and event rendering");
    return;
}
if (args.Length == 0) OverlayModuleProjectionTests.RunAll();
if (args.Length == 0) OverlayModuleSourceLabelTests.RunAll();
OverlayServerActivityTests.RunAll();
if (args.Contains("--local-self-only"))
{
    OverlayActivityRefreshTests.RunAll();
    OverlayLocalSelfTests.RunAll();
    Console.WriteLine("PASS local self display ignores shared presence flicker");
    return;
}
if (args.Contains("--direct-reminder-only"))
{
    DirectMessageReminderTests.RunAll();
    Console.WriteLine("PASS direct-message native gates and privacy copy");
    return;
}
if (args.Contains("--location-content-only"))
{
    OverlayLocationContentTests.RunAll();
    Console.WriteLine("PASS localized organization overview, room/member rows and privacy-scoped location events");
    return;
}
if (args.Contains("--dpi-geometry-only"))
{
    OverlayDpiGeometryTests.RunAll();
    Console.WriteLine("PASS native DPI geometry without a visible window");
    return;
}
if (args.Contains("--room-semantics-only"))
{
    RoomOverlaySemanticsTests.RunAll();
    RoomOverlayProjectionTests.RunAll();
    CommunityOverlayProjectionTests.RunAll();
    OverlayStartupFocusPolicyTests.RunAll();
    Console.WriteLine("PASS room overview and events use authorized room semantics");
    return;
}
// The location test supplies a temporary minimal catalog. Run it in a fresh
// process so its lazy catalog cache cannot contaminate other renderer tests.
if (args.Length == 0)
{
    var child = new System.Diagnostics.ProcessStartInfo(Environment.ProcessPath!) { UseShellExecute = false, CreateNoWindow = true };
    if (string.Equals(System.IO.Path.GetFileNameWithoutExtension(Environment.ProcessPath), "dotnet", StringComparison.OrdinalIgnoreCase))
        child.ArgumentList.Add(Assembly.GetExecutingAssembly().Location);
    child.ArgumentList.Add("--location-content-only");
    using var process = System.Diagnostics.Process.Start(child)!;
    process.WaitForExit();
    if (process.ExitCode != 0) throw new InvalidOperationException("Location content regression failed.");
    Console.WriteLine("PASS isolated organization/room location regression included in default suite");
}
NotificationEnvironmentPolicyTests.RunAll();
OverlayColdOpenTests.RunAll();
await OverlayColdOpenLifecycleTests.Run();
await OverlayColdOpenRecoveryTests.Run();
OverlayAnnouncementReplayTests.RunAll();
WpfProducerParityTests.RunAll();
ContinuousPlayOverlayTests.RunAll();
EventQueueAuditTests.RunAll();
SharedShipEventCardsTests.RunAll();
OverlayComprehensiveAuditTests.RunAll();
OverlayArrivalSourceTests.RunAll();
OverlayMainFleetTitleTests.RunAll();
OverlayMainFleetChatTests.RunAll();
OverlayOverviewFactsTests.RunAll();
OverlayShipNameTests.RunAll();
OverlayRegionSummaryTests.RunAll();
OverlayEventFlickerTests.RunAll();
OverlayMemberPagingTests.RunAll();
OverlayCalmModulesTests.RunAll();
OverlayModuleSyncTests.RunAll();
OverlayActivityRefreshTests.RunAll();
DirectMessageReminderTests.RunAll();
OverlayLocalSelfTests.RunAll();
Console.WriteLine("PASS social sound/fullscreen policy preserves visual, quiet and desktop safety gates");
if (args.Contains("--notification-environment-only")) return;
foreach (var name in new[] { "App", "MainWindow", "OverlayWindow", "InGameMenuWindow", "DesktopAppConfig", "AccountSessionCoordinator" })
    if (rendering.GetType("StarBridge.Desktop." + name) is not null)
        throw new InvalidOperationException("Retired application type entered standalone renderer: " + name);
foreach (var reference in rendering.GetReferencedAssemblies())
    if (reference.Name is "Star Bridge" or "StarBridge.Desktop" or "StarBridge.Server")
        throw new InvalidOperationException("Forbidden application/service dependency: " + reference.Name);
if (!typeof(StarBridge.HostRuntime.Overlay.IInformationOverlayRuntime)
    .IsAssignableFrom(rendering.GetType("StarBridge.Desktop.NativeInformationOverlayRuntime")))
    throw new InvalidOperationException("Native information overlay contract is missing.");
Console.WriteLine("PASS independent renderer contains native overlay and excludes retired application/service types");

RoomOverlayProjectionTests.RunAll();
RoomOverlaySemanticsTests.RunAll();
Console.WriteLine("PASS room projection, live reminders and revoked-content clearing");
CommunityOverlayProjectionTests.RunAll();
Console.WriteLine("PASS community projection, room priority and source isolation");
OverlayStartupFocusPolicyTests.RunAll();
Console.WriteLine("PASS startup focus policy");
// STARBRIDGE_SKIP_DESKTOP_NOTIFICATION=1: run everything else when this group is known to fail for an unrelated reason.
if (Environment.GetEnvironmentVariable("STARBRIDGE_SKIP_DESKTOP_NOTIFICATION") != "1")
{
    DesktopNotificationCardTests.RunAll();
    Console.WriteLine("PASS notification resources and offscreen multi-DPI rendering");
}
else Console.WriteLine("SKIP notification resources (STARBRIDGE_SKIP_DESKTOP_NOTIFICATION=1)");
