using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.NativeBridge;
using StarBridge.Core.Profiles;

using System.Net;
using System.Net.Http.Json;
if (!HostDataRoot.IsIsolatedTestProcess || !Path.GetFullPath(HostDataRoot.CurrentRoot).StartsWith(
    Path.TrimEndingDirectorySeparator(Path.GetFullPath(Path.GetTempPath())) + Path.DirectorySeparatorChar, StringComparison.OrdinalIgnoreCase))
{ Console.Error.WriteLine("Host test data root is outside TEMP; refusing to run."); return 97; }
if (args is ["--cx-gov-3-only"]) { await ActivityWaitLaneTests.RunAsync(); await AccountDispatchConcurrencyTests.VerifyOfficialActivityLane(); return 0; }
if (args is ["--cx-gov-3-read-cancel-only"]) {
    await AccountPreferenceActionTests.StagedPipeCancellationReachesHttp();
    Console.WriteLine("PASS GOV3 read: active profile HTTP cancellation");
    await AccountPreferenceActionTests.StagedPipeCancelsBeforeQueueAdmission();
    Console.WriteLine("PASS GOV3 read: queued profile cancellation");
    await AccountPreferenceActionTests.StagedPipeCancellationCannotCrossConnectionOrWrite();
    Console.WriteLine("PASS GOV3 read: connection and write boundaries");
    return 0;
}
if (args.Length == 0) await ActivityWaitLaneTests.RunAsync();
if (args is ["--cx-gov-2-only"]) { await OfficialFleetGov2ClientTests.RunAsync(); await OfficialFleetCommunicationBridgeTests.Run(); await AccountDispatchConcurrencyTests.VerifyOfficialActivityLane(); return 0; }
if (args.Length == 0) await OfficialFleetGov2ClientTests.RunAsync();
if (args is ["--official-fleet-governance-management-only"]) { await OfficialFleetGovernanceManagementClientTests.RunAsync(); return 0; }
if (args.Length == 0) await OfficialFleetGovernanceManagementClientTests.RunAsync();
if (args is ["--achfu-only"]) { await FirstUseBusinessOwnerTests.RunAchievementConcurrencyRegression(); return 0; }
if (args is ["--overlay-fleet-only"]) { await OverlayFleetSourceTests.Run(); return 0; }
if (args is ["--overlay-fleet-affected-only"])
{
    await OverlaySceneChoiceTests.BridgeAndPersistence();
    await OverlaySceneChoiceTests.StoreGuards();
    await OverlaySceneChoiceTests.ClosedOverlayKeepsOrganizationSources();
    await OverlaySceneChoiceTests.LocalChoiceBypassesSlowCatalog();
    await OverlayModuleFrameTests.Run();
    await OverlayPresetSourceBridgeTests.Run();
    await OverlayTemporarySourceBridgeTests.Run();
    await OverlayPresetMigrationTests.Run();
    await OverlaySettingsTests.PassesSavedModuleSourcesToRuntime();
    await OfficialFleetReadTests.Run();
    Console.WriteLine("PASS overlay fleet affected: 10 groups, 0 failed");
    return 0;
}
#if STARBRIDGE_LOCATION_CATALOG
if (args is ["--cityhost-only"]) { await CityAchievementTests.Run(); return 0; }
#endif
if (args is ["--achievement-contract-only"]) { await AchievementReadContractTests.Run(); return 0; }
if (args is ["--game-identity-only"])
{
    try { await GameIdentityBridgeTests.Run(); return 0; }
    catch { return 1; }
}
if (args is ["--first-use-game-identity-only"])
{
    try { await FirstUseGameIdentityTests.Run(); return 0; }
    catch { return 1; }
}
#if STARBRIDGE_LOCATION_CATALOG
if (args.Length == 0) await CityAchievementTests.Run();
#endif
if (args is ["--scm-achievement-unlocks-only"]) { await ScmAchievementUnlockTests.Run(); return 0; }
if (args is ["--achcel-first-use-only"]) { await FirstUseBusinessOwnerTests.RunAchievementRefreshRegression(); return 0; }
if (args is ["--celebration-audio-queue-only"]) { await CelebrationNotificationAudioTests.Run(); return 0; }
if (args is ["--achcel-only"])
{
    var cases = new (string Name, Func<Task> Run)[] {
        ("SCM detection/schedule", ScmAchievementUnlockTests.Run),
        ("First-use refresh and publication exit", FirstUseBusinessOwnerTests.RunAchievementRefreshRegression),
        ("First-use Native installation graph", FirstUseBusinessOwnerTests.RunNativeInstallation),
        ("First-use product installation graph", FirstUseBusinessOwnerTests.RunProductOnlineProtocol),
        ("SCM composed startup/delivery", ScmAchievementCompositionTests.Run),
        ("Celebration audio queue", CelebrationNotificationAudioTests.Run),
        ("Trusted native delivery", () => { AchievementCelebrationTests.Run(); return Task.CompletedTask; }),
        ("Achievement audio policy", () => { AchievementCelebrationAudioTests.Run(); return Task.CompletedTask; }),
        ("SCM catalog/HTTP", ScmAchievementTests.Run),
        ("SCM shared resource business codes", ScmSpecHostTests.Run),
        ("Rally lifecycle", OverlayRallyTests.Run),
        ("Social audio", SocialNotificationAudioTests.Run),
        ("Community audio", CommunityNotificationAudioTests.Run),
        ("Room audio", RoomAudioTests.Run),
        ("Device audio", NotificationAudioTests.Run)
    };
    var failed = 0;
    foreach (var (name, run) in cases) {
        try { await run(); Console.WriteLine("PASS ACHCEL " + name); }
        catch (Exception error) { failed++; Console.WriteLine("FAIL ACHCEL " + name + ": " + error.Message); }
    }
    Console.WriteLine($"SUMMARY ACHCEL passed={cases.Length - failed} failed={failed}");
    return failed == 0 ? 0 : 1;
}
// Keep these slices isolated when dotnet run forwards MSBuild switches.
if (args.Contains("--market-trader-profile-only", StringComparer.Ordinal)) return await MarketTraderProfileTests.Run();
if (args.Contains("--marketplace-only", StringComparer.Ordinal)) args = ["--marketplace-only"];
if (args is ["--app-stats-heartbeat-only"]) args = ["--filter", "App stats heartbeat"];
if (args is ["--inbox-push-only"]) { await NotificationInboxPushTests.Run(); await NotificationInboxScmMessagesTests.Run(); return 0; }
if (args is ["--trade-notifications-only"]) { await TradeNotificationTests.Run(); return 0; }
if (args is ["--lane-recovery-only"]) { await PrivacyLaneRecoveryTests.Isolation(); await PrivacyLaneRecoveryTests.OwnerRecovery(); await PrivacyLaneRecoveryTests.FailureAndPrivacy(); await PrivacyLaneRecoveryTests.ExplicitResume(); return 0; }
if (args is ["--owner-recovery-only"]) { await PrivacyLaneRecoveryTests.OwnerRecovery(); await PrivacyLaneRecoveryTests.FailureAndPrivacy(); await PrivacyLaneRecoveryTests.ExplicitResume(); return 0; }
if (args is ["--official-sharing-defaults-only"]) { await OfficialSharingDefaultsTests.Run(); return 0; }
if (args is ["--privacy-rejected-only"]) { await PrivacyPublicationTests.RejectedBackoff(); return 0; }
if (args is ["--sharing-review-only"])
{
    await SharingReviewRegressionTests.Run();
    // Continue through the ordinary runner for the visibility receipt regressions.
    args = ["--filter", "CX-L11"];
}
if (args is ["--archived-appearance-only"]) { OverlayArchivedAppearanceMigrationTests.Run(); return 0; }
if (args.Length == 0) { await PrivacyLaneRecoveryTests.Isolation(); await PrivacyLaneRecoveryTests.OwnerRecovery(); await PrivacyLaneRecoveryTests.FailureAndPrivacy(); await PrivacyLaneRecoveryTests.ExplicitResume(); OverlayArchivedAppearanceMigrationTests.Run(); }
if (args is ["--visitor-decoration-races-only"]) { await VisitorDecorationRaceTests.Run(); return 0; }
if (args is ["--affiliation-logo-only"]) { await PublicOrganizationLogoTests.Run(); await LegacyPasswordLoginTests.VisitorOrganizationLogos(); await VisitorDecorationRaceTests.Run(); return 0; }
if (args.Length == 0) { await PublicOrganizationLogoTests.Run(); await LegacyPasswordLoginTests.VisitorOrganizationLogos(); await VisitorDecorationRaceTests.Run(); }
if (args is ["--community-wide-image-only"])
{
    await CommunityLogoBridgeTests.Verify();
    await CompositeBridgeDispatcherTests.RoutesCommunityRequests();
    Console.WriteLine("PASS wide image and existing logo routing regression: 2 groups, 0 failed");
    return 0;
}
// dotnet run can forward MSBuild switches as application arguments. Keep the
// explicitly requested local regression slice isolated in that case as well.
if (args.Contains("--sharing-m04k-only", StringComparer.Ordinal))
{
    try { await SharingReviewRegressionTests.M04k(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL M04k suite: " + error.Message); return 1; }
}
if (args.Contains("--sharing-m04j-only", StringComparer.Ordinal))
{
    try { await SharingReviewRegressionTests.M04j(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL M04j suite: " + error.Message); return 1; }
}
if (args.Contains("--sharing-m04h-only", StringComparer.Ordinal))
{
    try { await SharingReviewRegressionTests.M04h(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL M04h suite: " + error.Message); return 1; }
}
if (args.Contains("--sharing-m04g-only", StringComparer.Ordinal))
{
    try { await SharingReviewRegressionTests.M04g(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL M04g suite: " + error.Message); return 1; }
}
if (args.Contains("--sharing-m04f-only", StringComparer.Ordinal))
{
    await SharingReviewRegressionTests.M04f();
    return 0;
}
if (args.Contains("--sharing-m04e-only", StringComparer.Ordinal))
{
    await SharingReviewRegressionTests.M04e();
    return 0;
}
if (args.Contains("--sharing-auto-resume-only", StringComparer.Ordinal))
{
    var sharingTests = new (string Name, Func<Task> Run)[] {
        ("SharingReviewRegressionTests.M04k", () => SharingReviewRegressionTests.M04k()),
        ("SharingReviewRegressionTests.M04j", () => SharingReviewRegressionTests.M04j()),
        ("SharingReviewRegressionTests.M04h", () => SharingReviewRegressionTests.M04h()),
        ("FriendSharingPublicationTests.Verify", () => FriendSharingPublicationTests.Verify()),
        ("FriendSharingRuntimeTests.Run", () => FriendSharingRuntimeTests.Run()),
        ("EventSharingRuntimeTests.Run", () => EventSharingRuntimeTests.Run()),
        ("EventSharingTransportTests.Run", () => EventSharingTransportTests.Run()),
        ("SharingReviewRegressionTests.M04g", () => SharingReviewRegressionTests.M04g()),
        ("SharingReviewRegressionTests.M04f", () => SharingReviewRegressionTests.M04f()),
        ("SharingReviewRegressionTests.M04e", () => SharingReviewRegressionTests.M04e()),
        ("SharingReviewRegressionTests.Run", () => SharingReviewRegressionTests.Run()),
        ("AccountSessionRestoreTests.PrivacyRefresh", () => AccountSessionRestoreTests.PrivacyRefresh()),
        ("AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh", () => AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh()),
        ("LocalPrivacyTests.Storage", () => LocalPrivacyTests.Storage()),
        ("LocalPrivacyTests.FailClosed", () => LocalPrivacyTests.FailClosed()),
        ("LocalPrivacyTests.Contract", () => LocalPrivacyTests.Contract()),
        ("LegacyPasswordLoginTests.PrivacyQueueTimeoutKeepsConsent", () => LegacyPasswordLoginTests.PrivacyQueueTimeoutKeepsConsent()),
        ("PrivacyPublicationRecoveryTests.ServerAndSessionRecovery", () => PrivacyPublicationRecoveryTests.ServerAndSessionRecovery()),
        ("PrivacyPublicationRecoveryTests.SessionAndFailureBoundaries", () => PrivacyPublicationRecoveryTests.SessionAndFailureBoundaries()),
        ("SharingStatusDetailTests.Run", () => SharingStatusDetailTests.Run()),
        ("PrivacyPublicationRecoveryTests.AutomaticTimerRecovery", () => PrivacyPublicationRecoveryTests.AutomaticTimerRecovery()),
        ("PrivacyPublicationRecoveryTests.RevokedConsentRestart", () => PrivacyPublicationRecoveryTests.RevokedConsentRestart()),
        ("PrivacyPublicationRecoveryTests.SilentHeartbeat", () => PrivacyPublicationRecoveryTests.SilentHeartbeat()),
        ("PrivacyPublicationRecoveryTests.TransientDisconnect", () => PrivacyPublicationRecoveryTests.TransientDisconnect()),
        ("PrivacyPublicationRecoveryTests.Restart", () => PrivacyPublicationRecoveryTests.Restart()),
        ("PrivacyPublicationRecoveryTests.Guards", () => PrivacyPublicationRecoveryTests.Guards()),
        ("PrivacyPublicationTests.Lifecycle", () => PrivacyPublicationTests.Lifecycle()),
        ("PrivacyPublicationTests.Ordering", () => PrivacyPublicationTests.Ordering()),
        ("PrivacyPublicationTests.FailClosed", () => PrivacyPublicationTests.FailClosed()),
        ("PrivacyPublicationTests.Wire", () => PrivacyPublicationTests.Wire()),
        ("PrivacyPublicationTests.RejectedBackoff", () => PrivacyPublicationTests.RejectedBackoff()),
        ("PrivacyPublicationTests.Projection", () => PrivacyPublicationTests.Projection()),
        ("CommunitySharingTests.Verify", () => CommunitySharingTests.Verify()),
        ("PrivacyConsentTests.Verify", () => PrivacyConsentTests.Verify()),
        ("ManualPresenceIntegrationTests.Verify", () => ManualPresenceIntegrationTests.Verify()),
        ("AccountSessionRestoreTests.RejectedCredentialProjectsReauthorization", () => AccountSessionRestoreTests.RejectedCredentialProjectsReauthorization()),
        ("AccountSessionRestoreTests.UnavailableIdentityReusesCommittedRefresh", () => AccountSessionRestoreTests.UnavailableIdentityReusesCommittedRefresh()),
        ("AccountSessionRestoreTests.RestoreCallerCancellationRemainsCancelled", () => AccountSessionRestoreTests.RestoreCallerCancellationRemainsCancelled()),
    };
    var sharingFailures = 0;
    foreach (var (name, run) in sharingTests)
    {
        try { await run(); Console.WriteLine("PASS sharing group " + name); }
        catch (Exception error) { sharingFailures++; Console.WriteLine("FAIL sharing group " + name + ": " + error.Message); }
    }
    Console.WriteLine($"CX-M04g: {sharingTests.Length - sharingFailures} test groups passed, {sharingFailures} failed");
    return sharingFailures == 0 ? 0 : 1;
}
if (args is ["--guide-state-only"]) { await GuideStateTests.Run(); return 0; }
if (args.Length == 0)
{
    // GuideStateTests moves the process data root; restore it for the rest of the run.
    var guidePreviousRoot = StarBridge.HostRuntime.HostDataRoot.CurrentRoot;
    try { await GuideStateTests.Run(); }
    finally { StarBridge.HostRuntime.HostDataRoot.UsePreparedRoot(guidePreviousRoot); }
}
if (args is ["--safe-hotkeys-only"]) { SafeHotkeyPreferencesTests.Run(); return 0; }
if (args.Length == 0) SafeHotkeyPreferencesTests.Run();
if (args is ["--spec9-only"]) { await ScmSpecSection9Tests.Run(); return 0; }
if (args is ["--cx48-only"]) { await ScmSpecHostTests.Run(); return 0; }
if (args is ["--overlay-rally-only"]) { await OverlayRallyTests.Run(); return 0; }
if (args.Length == 0) await OverlayRallyTests.Run();
if (args is ["--image-cache-runtime-only"]) { await AccountSessionRestoreTests.ImageCacheRuntimeContracts(); return 0; }
if (args is ["--image-cache-runtime-worker", var imageWorkerRoot]) { await AccountSessionRestoreTests.ImageCacheRuntimeWorker(imageWorkerRoot); return 0; }
if (args is ["--remote-image-cache-worker", var imageCacheRoot, var imageCacheKey, var imageCacheHash]) return RemoteImageCacheStorageTests.Worker(imageCacheRoot, imageCacheKey, imageCacheHash);
if (args is ["--remote-image-cache-only"]) { RemoteImageCacheStorageTests.Run(); return 0; }
if (args is ["--remote-image-cache-races-only"]) { RemoteImageCacheRaceTests.Run(); return 0; }
if (args is ["--remote-image-cache-index-only"]) { RemoteImageCacheIndexTests.Run(); return 0; }
if (args is ["--remote-image-cache-wire-only"]) { await RemoteImageCacheBridgeTests.Run(); return 0; }
if (args is ["--profile-write-session-only"]) { await ProfileWriteSessionTests.Run(); return 0; }
if (args is ["--scm-achievements-only"]) { await ScmAchievementTests.Run(); return 0; }
if (args is ["--official-chat-archive-p0", var mode]) { if (mode == "isolated") await OfficialFleetChatArchiveTests.RunIsolated(); else await OfficialFleetChatArchiveTests.Run(mode); return 0; }
if (args is ["--hangar-read-failure-wire"])
{
    Console.Write(LocalHangarReadFailureTests.Wire());
    return 0;
}
if (args is ["--cold-first-content-observe" or "--cold-first-content-require", var coldContentStage])
{
    var probe = await AccountSessionRestoreTests.ColdFirstContent(coldContentStage);
    Console.WriteLine(probe.Json);
    if (args[0] == "--cold-first-content-require" && !probe.LocalFirstObserved)
    {
        Console.Error.WriteLine("FAIL Native restore display: cached profile is unavailable before the held root network request completes. This probe does not certify Flutter or whole-app G1.");
        return 1;
    }
    return 0;
}
if (args is ["--offline-community-pagination-wire"])
{
    Console.Write(OfflineCommunityPaginationTests.Wire());
    return 0;
}
if (args is ["--retained-display-renewal-wire"])
{
    Console.Write(await AccountSessionRestoreTests.RetainedDisplayRenewalWire());
    return 0;
}
if (args is ["--organization-policy-worker", var organizationRoot, var organizationOwner])
    return await FirstUseModeTests.OrganizationPolicyWorker(organizationRoot, organizationOwner);
if (args is ["--cx78-native-exit-259-child"]) { Console.ReadLine(); return 259; }
if (args is ["--cx78-idle-only"])
{
    try { await HostIdleTests.Processes(); await HostIdleTests.Diagnostics(); await AccountDispatchConcurrencyTests.CurrentDiagnostics(); return 0; }
    catch (Exception error) { Console.Error.WriteLine("FAIL CX78 idle: " + error.Message); return 1; }
}
if (args is ["--cx78-diagnostics-exit-child"]) { using var diagnostic = new AccountCurrentDiagnostics { Projected = true, Reason = CurrentProjectionReason.none }; return 0; }
if (args is ["--current-projection-diag-only"]) { await AccountDispatchConcurrencyTests.CurrentDiagnostics(); return 0; }
if (args is ["--pipe-request-guard-only"]) { await PipeRequestGuardTests.Run(); return 0; }
if (args is ["--account-dispatch-only"]) { await AccountDispatchConcurrencyTests.Verify(); return 0; }
if (args is ["--trade-profile-only"]) { await TradeProfileTests.Run(); return 0; }
if (args is ["--profile-public-header-only"]) { await ProfilePublicHeaderTests.Run(); return 0; }
if (args is ["--notification-inbox-scm-only"]) { await NotificationInboxScmMessagesTests.Run(); return 0; }
if (args is ["--marketplace-write-only"]) { await MarketplaceWriteTests.Run(); return 0; }
if (args is ["--marketplace-only"]) { await MarketplaceWriteTests.Run(); await ScmSpecHostTests.Run(); await MarketplaceTests.Run(); await MarketplaceListingTests.Run(); await TradeProfileTests.Run(); await ProfilePublicHeaderTests.Run(); await MarketplaceRecordsTests.Run(); await MarketplaceChatTests.Run(); await MarketplaceContractsTests.Run(); await MarketplaceWarehouseTests.Run(); await MarketplaceNoticesTests.Run(); await AccountDispatchConcurrencyTests.LiveEventSkipsDispatchWaitWithoutOvertaking(); Console.WriteLine("PASS trade-chat live pushes skip the dispatch wait without overtaking queued events"); await CompositeBridgeDispatcherTests.RoutesMarketplaceRequests(); Console.WriteLine("PASS composed Native Host routes every marketplace request to the account owner"); return 0; }
if (args is ["--ship-specifications-only"]) { await ShipSpecificationTests.Run(); return 0; }
if (args is ["--ship-specifications-live"]) { await ShipSpecificationTests.Live(); return 0; }
if (args is ["--ship-specifications-approved-live"]) { await ShipSpecificationApprovedMappingTests.Live(); return 0; }
if (args is ["--ship-specifications-audit", var cataloguePath]) { ShipSpecificationTests.Audit(cataloguePath); return 0; }
if (args is ["--ship-specifications-client-coverage", var clientCatalogue, var runtimeNames, var coverageOutput])
{ await ShipSpecificationCoverageAudit.Run(clientCatalogue, runtimeNames, coverageOutput); return 0; }
if (args is ["--profile-cache-storage-worker", var cacheMode, var cacheRoot])
{
    return await ScmProfileCacheStorageTests.Worker(cacheMode, cacheRoot);
}
if (args is ["--unknown-host-fault-wire"])
{
    Console.Write(await PersonalProfileReadFailureTests.UnknownFailureWire());
    return 0;
}
if (args is ["--fleet-read-failure-wire"])
{
    Console.Write(await OfficialFleetReadTests.FailureWire());
    return 0;
}
if (args is ["--fleet-profile-read-wire"])
{
    Console.Write(await OfficialFleetReadTests.ProfileReadWire());
    return 0;
}
if (args is ["--fleet-deferred-profile-wire"])
{
    Console.Write(await OfficialFleetReadTests.DeferredProfileWire());
    return 0;
}
if (args is ["--account-profile-cache-wire"])
{
    Console.Write(await AccountPreferenceActionTests.ReadCacheWire());
    return 0;
}
if (args is ["--preference-confirmation-wire"])
{
    Console.Write(await AccountPreferenceActionTests.PreferenceConfirmationWire());
    return 0;
}
if (args is ["--staged-account-profile-wire"])
{
    Console.Write(await AccountPreferenceActionTests.StagedProfileWire());
    return 0;
}
if (args is ["--profile-read-failures-only"])
{
    await PersonalProfileReadFailureTests.Run();
    return 0;
}
if (args is ["--official-fleet-runtime-ready-only"]) { await FirstUseBusinessOwnerTests.RunRuntimeReady(); return 0; }
if (args is ["--official-fleet-announcement-client-only"]) { await OfficialFleetAnnouncementManagementClientTests.RunAsync(); return 0; }
if (args is ["--official-fleet-rally-only"]) { await OfficialFleetRallyClientTests.RunAsync(); return 0; }
if (args is ["--official-fleet-activation-only"]) { await OfficialFleetActivationClientTests.RunAsync(); return 0; }
if (args is ["--official-fleet-projection-only"])
{
    try { await OfficialFleetProjectionNegotiationTests.RunAsync(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL CX-L03b " + error); return 1; }
}
if (args is ["--official-fleet-announcement-recovery-only"]) { await OfficialFleetAnnouncementRecoveryTests.RunAsync(); return 0; }
if (args is ["--official-fleet-communication-only"])
{
    await OfficialFleetCommunicationBridgeTests.Run();
    Console.WriteLine("PASS official fleet communication dispatcher, scope, command whitelist and account retirement");
    return 0;
}

if (args.Length is 1 or 2 && args[0] == "--official-fleet-identity-observations-only")
{
    await OfficialFleetIdentityObservationTests.Run(args.Length == 2 ? args[1] : null);
    return 0;
}
if (args is ["--official-fleet-notifications-only"])
{
    await OfficialFleetNotificationTests.Run();
    await NotificationPolicyBridgeTests.Run();
    await CommunityNotificationAudioTests.Run();
    Console.WriteLine("PASS official fleet notifications");
    return 0;
}

if (args is ["--official-fleet-activity-only"])
{
    await OfficialFleetCommunicationBridgeTests.Run();
    await SocialActivityReadTests.Run();
    Console.WriteLine("PASS official activity dispatcher plus existing social activity reader regression");
    return 0;
}

if (args is ["--official-fleet-only"])
{
    await OfficialFleetReadTests.Run();
    await OfficialFleetHangarSharingClientTests.Run();
    await OfficialFleetSharedShipsClientTests.Run();
    Console.WriteLine("PASS official fleet existing SCM reads, scope, privacy and retirement");
    return 0;
}

if (args is ["--account-lifecycle-only"])
{
    await AccountLifecycleIsEnabled();
    Console.WriteLine("PASS account lifecycle capability contract and retired-operation gate");
    return 0;
}

if (args is ["--visitor-profile-wire-fixture"])
{
    Console.InputEncoding = new System.Text.UTF8Encoding(false, true);
    Console.OutputEncoding = new System.Text.UTF8Encoding(false, true);
    var input = await Console.In.ReadToEndAsync();
    if (System.Text.Encoding.UTF8.GetByteCount(input) > 64 * 1024) return 2;
    await LegacyPasswordLoginTests.VisitorProfileWireFixture(input);
    return 0;
}

if (args is ["--page-edit-wire-fixture"])
{
    // Synthetic stdin/stdout transform only; no account, vault or network access.
    Console.InputEncoding = new System.Text.UTF8Encoding(false, true);
    Console.OutputEncoding = new System.Text.UTF8Encoding(false, true);
    var input = await Console.In.ReadToEndAsync();
    if (System.Text.Encoding.UTF8.GetByteCount(input) > 64 * 1024) return 2;
    using var json = System.Text.Json.JsonDocument.Parse(input);
    var edit = PageEditBridgeContract.Read(json.RootElement);
    Console.Write(System.Text.Encoding.UTF8.GetString(OAuthPkceClient.EncodePageEdit(edit)));
    return 0;
}

if (args is ["--page-presentation-only"])
{
    await PagePresentationClientTests.Verify();
    await LegacyPasswordLoginTests.ScmPagePresentationWrite();
    Console.WriteLine("PASS page presentation transport, authorization and readback");
    return 0;
}

if (args is ["--local-privacy-runtime-only"])
{
    await LocalPrivacyRuntimeScope();
    Console.WriteLine("PASS local privacy runtime routing and retirement");
    return 0;
}

if (args is ["--first-use-mode-recovery-child", var firstUseRecoveryRoot])
{ await FirstUseModeRecoveryTests.WriteCompletedStop(firstUseRecoveryRoot); return 0; }
if (args is ["--first-use-credential-checkpoint-child", var firstUseCheckpointRoot, var firstUseCheckpointScenario])
{ await FirstUseCredentialCheckpointTests.WriteChild(firstUseCheckpointRoot, firstUseCheckpointScenario); return 0; }

if (args is ["--first-use-local-store-only"]) { LocalFirstUseStoreTests.Run(); return 0; }
if (args is ["--first-use-startup-only"]) { await FirstUseStartupTests.Run(); return 0; }
if (args is ["--first-use-completion-store-only"]) { FirstUseCompletionStoreTests.Run(); return 0; }
if (args is ["--first-use-completion-runtime-only"]) { await FirstUseCompletionRuntimeTests.Run(); return 0; }
if (args is ["--first-use-product-online-protocol-only"]) { await FirstUseBusinessOwnerTests.RunProductOnlineProtocol(); return 0; }
if (args is ["--first-use-reauthorization-only"]) { await FirstUseBusinessOwnerTests.RunReauthorizationProtocol(); return 0; }
if (args is ["--device-network-offline-only"]) { await DeviceNetworkOfflineTests.Run(); return 0; }
if (args is ["--first-use-cold-online-recovery-only"]) { await FirstUseColdOnlineRecoveryTests.Run(); return 0; }
if (args is ["--first-use-online-recovery-child", var coldOnlineRoot]) { await FirstUseColdOnlineRecoveryTests.Child(coldOnlineRoot); return 0; }
if (args is ["--first-use-identity-discovery-only"]) { LocalIdentityDiscoveryTests.Run(); return 0; }
if (args is ["--first-use-evidence-owner-only"]) { LocalLogEvidenceOwnerTests.Run(); return 0; }
if (args is ["--first-use-local-game-only"]) { LocalGameLogRuntimeTests.Run(); return 0; }
if (args is ["--first-use-device-setup-only"]) { await LocalDeviceSetupReaderTests.Run(); return 0; }
if (args is ["--first-use-device-review-only"]) { await LocalDeviceSetupReviewTests.Run(); return 0; }
if (args is ["--first-use-device-review-bridge-only"]) { await LocalDeviceReviewBridgeTests.Run(); return 0; }
if (args is ["--first-use-statistics-choice-bridge-only"]) { await LocalStatisticsChoiceBridgeTests.Run(); return 0; }
if (args is ["--first-use-local-history-only"]) { await LocalHistoryImportTests.Run(); return 0; }
if (args is ["--first-use-recognition-only"]) { await LocalRecognitionCheckTests.Run(); return 0; }
if (args is ["--first-use-native-observation-only"]) { await NativeOverlayObservationBridgeTests.Run(); return 0; }
if (args is ["--first-use-account-stop-only"]) { await LocalAccountStopTests.Run(); return 0; }
if (args is ["--first-use-credential-retirement-only"]) { await ScmCredentialRetirementTests.Run(); return 0; }
if (args is ["--first-use-credential-checkpoint-only"]) { await FirstUseCredentialCheckpointTests.Run(); return 0; }
if (args is ["--first-use-background-stop-only"]) { await BackgroundRetirementTests.Run(); return 0; }
if (args is ["--first-use-sampling-stop-only"]) { await LocalSamplingRetirementTests.Run(); return 0; }
if (args is ["--first-use-log-lifetime-only"]) { await GameLogLifetimeTests.Run(); return 0; }
if (args is ["--first-use-deferred-timer-only"]) { await DeferredWorkTimerTests.Run(); return 0; }
if (args is ["--first-use-deferred-driver-only"]) { await DeferredAsyncDriverTests.Run(); return 0; }
if (args is ["--publication-retirement-only"]) { await PublicationRetirementTests.Run(); return 0; }
if (args is ["--first-use-online-candidate-only"]) { await FirstUseOnlineCandidateTests.Run(); return 0; }
if (args is ["--first-use-online-return-only"]) { await FirstUseOnlineReturnTests.Run(); return 0; }
if (args is ["--first-use-online-identity-only"]) { await FirstUseOnlineIdentityTests.Run(); return 0; }
if (args is ["--first-use-online-review-bridge-only"]) { await FirstUseOnlineReviewBridgeTests.Run(); return 0; }
if (args is ["--first-use-online-handoff-only"]) { await FirstUseOnlineHandoffTests.Run(); return 0; }
if (args is ["--first-use-business-owner-only"]) { await FirstUseBusinessOwnerTests.Run(); return 0; }
if (args is ["--first-use-installation-only"]) { await FirstUseBusinessOwnerTests.RunInstallation(); return 0; }
if (args is ["--first-use-native-installation-only"]) { await FirstUseBusinessOwnerTests.RunNativeInstallation(); return 0; }
if (args is ["--first-use-candidate-shutdown-only"]) { await FirstUseBusinessOwnerTests.RunCandidateShutdown(); return 0; }
if (args is ["--first-use-online-commit-only"]) { await FirstUseBusinessOwnerTests.RunOnlineCommit(); return 0; }
if (args is ["--first-use-online-installation-flow-only"]) { await FirstUseBusinessOwnerTests.RunOnlineInstallationFlow(); return 0; }
if (args is ["--first-use-online-installation-bridge-only"]) { await FirstUseBusinessOwnerTests.RunOnlineInstallationBridge(); return 0; }
if (args is ["--first-use-native-composition-only"]) { await FirstUseBusinessOwnerTests.RunNativeComposition(); return 0; }
if (args is ["--first-use-offline-only"]) { await FirstUseBusinessOwnerTests.RunOffline(); return 0; }
if (args is ["--first-use-retained-online-only"]) { await FirstUseBusinessOwnerTests.RunRetainedOnline(); return 0; }
if (args is ["--first-use-retained-account-first-only"]) { await FirstUseBusinessOwnerTests.RunRetainedAccountFirst(); return 0; }
if (args is ["--first-use-session-resume-only"]) { await FirstUseSessionResumeTests.Run(); return 0; }
if (args is ["--first-use-generation-only"]) { await FirstUseGenerationTests.Run(); return 0; }
if (args is ["--first-use-composition-only"]) { await FirstUseCompositionTests.Run(); return 0; }
if (args is ["--first-use-scm-owner-compatibility-only"]) { await FirstUseOnlineCandidateTests.OriginalScmLifecycle(); return 0; }
if (args is ["--first-use-local-statistics-only"]) { await LocalGameplayTimeTests.Run(); return 0; }
if (args is ["--first-use-local-overlay-only"]) { await LocalOverlaySourceTests.Run(); return 0; }
if (args is ["--first-use-disabled-host-only"]) { await FirstUseDisabledHostTests.Run(); return 0; }
if (args is ["--first-use-existing-user-only"]) { await FirstUseExistingUserUpgradeTests.Run(); return 0; }
if (args is ["--first-use-mode-only"]) { await FirstUseModeTests.Run(); return 0; }
if (args is ["--offline-account-only"]) { await FirstUseModeTests.RunRootOffline(); return 0; }
if (args is ["--offline-avatar-wire"]) { Console.WriteLine(await FirstUseModeTests.OfflineAvatarWire()); return 0; }
if (args is ["--offline-community-wire"]) { Console.WriteLine(await FirstUseModeTests.OfflineCommunityWire()); return 0; }
if (args is ["--offline-community-denial-wire"]) { Console.WriteLine(await FirstUseModeTests.OfflineCommunityDenialWire()); return 0; }
if (args is ["--community-directory-failure-wire"]) { Console.WriteLine(await CommunityDirectoryFailureTests.Wire()); return 0; }
if (args is ["--data-root-isolation-only"]) { HostDataRootIsolationTests.Verify(); return 0; }
if (args is ["--expired-session-only"]) { await AccountSessionRestoreTests.RejectedCredentialAsksToSignInAgainAfterRestart(); return 0; }
if (args is ["--retained-refresh-only"]) { await AccountSessionRestoreTests.UnavailableIdentityReusesCommittedRefresh(); return 0; }
if (args is ["--offline-display-selection-only"]) { await AccountSessionRestoreTests.OfflineDisplaySelection(); return 0; }
if (args is ["--restore-account-race-only"]) { await AccountSessionRestoreTests.RestoreCannotReplaceConcurrentLogin(); return 0; }
if (args is ["--account-restore-only"])
{
    await EmptyVaultProjectsSignedOut();
    await TransientRestoreProjectsRecoverableState();
    await AccountSessionRestoreTests.RejectedCredentialProjectsReauthorization();
    await AccountSessionRestoreTests.IdentityMismatchProjectsReauthorization();
    await AccountSessionRestoreTests.UnauthorizedIdentityProjectsReauthorization();
    await AccountSessionRestoreTests.RuntimeInvalidationProjectsReauthorization();
    await AccountSessionRestoreTests.PersonalProfileOutagePreservesAccount();
    await AccountSessionRestoreTests.RestoreTimeoutIsRecoverable();
    await AccountSessionRestoreTests.RestoreCallerCancellationRemainsCancelled();
    await AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh();
    await AccountSessionRestoreTests.OfflineDisplaySelection();
    await AccountSessionRestoreTests.UnavailableIdentityReusesCommittedRefresh();
    await AccountSessionRestoreTests.RejectedCredentialAsksToSignInAgainAfterRestart();
    await AccountSessionRestoreTests.NetworkOutageRetainsDisplayThroughBridge();
    await AccountSessionRestoreTests.RestoreCannotReplaceConcurrentLogin();
    await AccountSessionRestoreTests.ManualOfflineCredentialSelection();
    Console.WriteLine("PASS 14 account restoration regression cases including 30 concurrent credential changes");
    return 0;
}
if (args is ["--first-use-installation-diagnostics-only"]) { await FirstUseBusinessOwnerTests.RunInstallationFailureDiagnostics(); return 0; }
if (args is ["--first-use-mode-bridge-only"]) { await FirstUseModeTests.RunModeBridge(); return 0; }
if (args is ["--first-use-mode-recovery-only"]) { await FirstUseModeRecoveryTests.Run(); return 0; }
if (args is ["--first-use-missing-mode-only"]) { await FirstUseMissingModeTests.Run(); return 0; }
if (args is ["--first-use-recovery-guide-only"]) { await FirstUseRecoveryGuideTests.Run(); return 0; }
if (args is ["--first-use-background-owner-compatibility-only"])
{
    await HangarAutoSyncTests.Verify();
    await HangarAutoSyncIntegrationTests.Verify();
    await SharedActivityReceiverTests.Run();
    await CommunityNotificationTests.Run();
    await CommunityNotificationDeliveryTests.Run();
    await CommunityNotificationAudioTests.Run();
    await PlayerActivityTransitionReliabilityTests.Run();
    await PlayerActivityPolicyTests.Run();
    Console.WriteLine("PASS first-use background owners retain their original publication, delivery and policy contracts");
    return 0;
}
if (args is ["--first-use-foundations-only"])
{
    LocalFirstUseStoreTests.Run();
    LocalIdentityDiscoveryTests.Run();
    LocalLogEvidenceOwnerTests.Run();
    LocalGameLogRuntimeTests.Run();
    await LocalDeviceSetupReaderTests.Run();
    await LocalDeviceSetupReviewTests.Run();
    await LocalDeviceReviewBridgeTests.Run();
    await LocalStatisticsChoiceBridgeTests.Run();
    await LocalHistoryImportTests.Run();
    await LocalRecognitionCheckTests.Run();
    await NativeOverlayObservationBridgeTests.Run();
    await LocalAccountStopTests.Run();
    await ScmCredentialRetirementTests.Run();
    await FirstUseCredentialCheckpointTests.Run();
    await BackgroundRetirementTests.Run();
    await LocalSamplingRetirementTests.Run();
    await GameLogLifetimeTests.Run();
    await DeferredWorkTimerTests.Run();
    await DeferredAsyncDriverTests.Run();
    await PublicationRetirementTests.Run();
    await FirstUseOnlineCandidateTests.Run();
    await FirstUseOnlineReturnTests.Run();
    await FirstUseSessionResumeTests.Run();
    await FirstUseOnlineIdentityTests.Run();
    await FirstUseOnlineReviewBridgeTests.Run();
    await FirstUseOnlineHandoffTests.Run();
    await FirstUseBusinessOwnerTests.Run();
    await FirstUseGenerationTests.Run();
    await FirstUseCompositionTests.Run();
    await LocalGameplayTimeTests.Run();
    await LocalOverlaySourceTests.Run();
    await FirstUseModeTests.Run();
    await FirstUseModeRecoveryTests.Run();
    await FirstUseMissingModeTests.Run();
    await FirstUseRecoveryGuideTests.Run();
    return 0;
}

if (args is ["--first-use-device-owner-compatibility-only"])
{
    await ApplicationPreferencesTests.DefaultsAndPersistence();
    await ApplicationPreferencesTests.LegacyApplicationBehaviorIsProjectedWithoutWpf();
    await ApplicationPreferencesTests.InvalidUpdateFailsClosed();
    await ApplicationPreferencesTests.CorruptFileRecoversToDefaults();
    await ApplicationPreferencesTests.RevisionConflictFailsClosed();
    await ApplicationPreferencesTests.ReadFailureIsExplicitAndRetryable();
    await ApplicationPreferencesTests.StartupRegistrationRollsBackWhenSaveFails();
    await ApplicationPreferencesTests.StartupRegistrationWaitsForTheFirstChoice();
    await ApplicationPreferencesTests.DecliningStartupIsAppliedOnlyOnContinue();
    await OverlayPresetMigrationTests.Run();
    await OverlaySettingsTests.DefaultHotkeyPreservesSavedBindings();
    await NotificationSettingsTests.Run();
    await ContinuousPlayReminderTests.DefaultsAndRepeat();
    await ContinuousPlayReminderTests.DisabledAndReenabled();
    await ContinuousPlayReminderTests.BridgePersistsWithRevisionAndRejectsAccount();
    await ContinuousPlayReminderTests.WpfSettingsCompatibilityAndCorruption();
    await OverlayRuntimeStatusTests.ReadOnlyBoundaryAndExactRouting();
    await OverlayRuntimeStatusTests.StaleCancelledDisposedAndFailure();
    Console.WriteLine("PASS first-use device owners retain their original settings and runtime contracts");
    return 0;
}

if (args is ["--regional-fallback-only"])
{
    var regionalCases = new (string Name, Func<Task> Run)[]
    {
        ("routing", ScmRegionFallbackTests.Verify),
        ("login", ScmRouteStateTests.LoginFailures),
        ("bridge", ScmRouteStateTests.PreferencesAndBridge)
    };
    var regionalFailed = 0;
    foreach (var regional in regionalCases)
    {
        try { await regional.Run(); }
        catch (Exception error) { regionalFailed++; Console.WriteLine($"FAIL regional {regional.Name}: {error.Message}"); }
    }
    Console.WriteLine($"SUMMARY PASS {regionalCases.Length - regionalFailed}/{regionalCases.Length}; FAIL {regionalFailed}");
    return regionalFailed == 0 ? 0 : 1;
}

if (args is ["--friends-read-probe-only"]) { await FriendsReadProbeTests.Verify(); return 0; }
if (args is ["--friends-read-probe-disabled-only"]) { await FriendsReadProbeTests.VerifyDisabled(); return 0; }

if (args is ["--exec-hangar-game-overlay-only"]) { await ExecHangarGameOverlayTests.Run(); return 0; }
if (args is ["--exec-hangar-only"]) { await ExecHangarTests.Run(); await ExecHangarGameOverlayTests.Run(); return 0; }

if (args is ["--daily-support-only"])
{
    await DailySupportTests.Verify();
    return 0;
}

if (args is ["--bound-legacy-login-only"])
{
    await LegacyPasswordLoginTests.BoundLoginRequiresScm();
    return 0;
}

if (args is ["--achievements-only"])
{
    await AchievementRuntimeTests.ConfirmedCacheNeverFlashesLocked();
    await HangarAchievementTests.Run();
    AchievementCelebrationTests.Run();
    AchievementCelebrationAudioTests.Run();
    await AchievementRemoteTests.Run();
    await AchievementIdeaContentionTests.Run();
    await CompositeBridgeDispatcherTests.RoutesAchievementRequests();
    await AchievementRuntimeTests.RecognitionAndDevices();
    await AchievementRuntimeTests.NewGrantSurvivesOutboxCleanupFailure();
    await AchievementRuntimeTests.InvalidGameEvidence();
    await AchievementRuntimeTests.OfflineRestartAndLostAcknowledgement();
    await AchievementRuntimeTests.AccountChangeDuringReadAndProtocol();
    await AchievementRuntimeTests.CorruptOutboxAndIsolation();
    await AchievementRuntimeTests.ShortEntryAndRetryBackoff();
    await AccountLifecycleIsEnabled();
    Console.WriteLine("PASS account achievements: game entry, cloud restore, offline restart and account isolation");
    return 0;
}

if (args is ["--compatibility-owner-sharing-recovery-only"])
{
    await S2CompatibilityReadTests.VerifySharingAfterOwnerRecovery();
    return 0;
}

if (args is ["--compatibility-local-inheritance-only"])
{
    await S2CompatibilityReadTests.VerifyLocalPrivacyInheritance();
    Console.WriteLine("PASS verified linked account inherits local data and stopped choices without migration");
    return 0;
}

if (args is ["--compatibility-gameplay-time-only"])
{
    await CompatibilityGameplayTimeTests.Verify();
    await GameplayTimeRuntimeTests.ConsentAndReopen();
    await GameplayTimeRuntimeTests.OwnershipAndProtocol();
    await GameplayTimeRuntimeTests.StorageFailures();
    Console.WriteLine("PASS compatible gameplay time ownership, consent and file leases");
    return 0;
}

if (args is ["--compatibility-game-log-only"])
{
    await GameLogRuntimeTests.PublicationWake();
    await GameLogRuntimeTests.OfflineRecentIdentity();
    await GameLogRuntimeTests.Recognition();
    await GameLogRuntimeTests.AutomaticVersions();
    await GameLogRuntimeTests.Lifecycle();
    await GameLogRuntimeTests.SessionContext();
    await GameLogRuntimeTests.OwnershipAndFailures();
    await GameLogRuntimeTests.DiagnosticsSelection();
    Console.WriteLine("PASS game log recognition, stopped choices, ownership and lifecycle");
    return 0;
}

if (args is ["--compatibility-community-only"])
{
    await CommunityDeferredLogoTests.Verify();
    await CommunityWorkspaceClientTests.Verify();
    await CommunityWpfS2Tests.Verify();
    Console.WriteLine("PASS compatibility community directory, workspace, media and isolation");
    return 0;
}

if (args is ["--compatibility-login-only"])
{
    CompatibilityPublicationIdentityTests.Verify();
    await IdentityLinkProofOutageTests.Verify();
    await S2CompatibilityReadTests.Verify();
    await S2ExistingAccountLinkTests.Verify();
    Console.WriteLine("PASS compatibility binding, original business reads and revoked access");
    return 0;
}

if (args is ["--selected-profile-import-only"])
{
    await FullProfilePresentationImportTests.Run();
    await SelectedProfileImportTests.Run();
    await SelectedLocalProfileImportTests.Run();
    await SelectedProfileImportRecoveryTests.Run();
    await LocalPersonalProfileTests.Collaboration();
    return 0;
}

if (args is ["--overlay-preset-sharing-only"])
{
    await OverlaySharedPresetTests.Sharing();
    Console.WriteLine("PASS legacy and source-aware preset sharing");
    return 0;
}

if (args is ["--menu-hotkeys-only"])
{
    await OverlaySettingsTests.DefaultHotkeyPreservesSavedBindings();
    await MenuHotkeyBridgeTests.Run();
    await GameStartupHintTests.Run();
    return 0;
}

if (args is ["--overlay-source-build-gate", var expectedSourceGate])
{
    await OverlaySourceBuildGateTests.Run(bool.Parse(expectedSourceGate));
    return 0;
}
if (args is ["--overlay-runtime-events-only"])
{
    await OverlayRuntimeEventTests.Run();
    return 0;
}
if (args is ["--overlay-startup-isolation-only"])
{
    await OverlayStartupIsolationTests.Run();
    return 0;
}
if (args is ["--interaction-preferences-only"])
{
    await ApplicationInteractionPreferencesTests.Run();
    await ApplicationPreferencesTests.DefaultsAndPersistence();
    await ApplicationPreferencesTests.PreviewGuidePersistsIndependently();
    return 0;
}

if (args is ["--preview-guide-only"])
{
    await ApplicationPreferencesTests.PreviewGuidePersistsIndependently();
    await ApplicationPreferencesTests.OlderV1PreferencesRemainReadable();
    await ApplicationPreferencesTests.RevisionConflictFailsClosed();
    await ApplicationPreferencesTests.ReadFailureIsExplicitAndRetryable();
    return 0;
}

if (args is ["--privacy-queue-timeout-only"])
{
    try { await LegacyPasswordLoginTests.PrivacyQueueTimeoutKeepsConsent(); Console.WriteLine("PASS actual Host queue timeout retains consent"); return 0; }
    catch (Exception error) { Console.Error.WriteLine("FAIL privacy queue timeout: " + error.Message); return 1; }
}

if (args is ["--overlay-management-latency-only"])
{
    try { await LegacyPasswordLoginTests.OverlayRosterDoesNotWaitForManagementIdentity(); return 0; }
    catch (Exception error) { Console.Error.WriteLine("FAIL overlay management latency: " + error.GetType().Name + ": " + error.Message); return 1; }
}

if (args is ["--overlay-workspace-reuse-only"])
{
    try
    {
    await LegacyPasswordLoginTests.OverlayReusesWorkspace();
    await OverlayWorkspaceReuseTests.Run();
    Console.WriteLine("PASS client workspace and first overlay frame share authorized members");
    return 0;
    }
    catch (Exception error) { Console.Error.WriteLine("FAIL overlay roster reuse: " + error.Message); return 1; }
}

if (args is ["--overlay-sync-latency-only"])
{
    await OverlaySyncLatencyTests.Run();
    return 0;
}
if (args is ["--location-compatibility-only", var expectedCompatibility])
{
    await LocationDisplayCompatibilityTests.Run();
    LocationDisplayCompatibilityTests.CheckResource(bool.Parse(expectedCompatibility));
    return 0;
}

if (args is ["--navigation-stations-only"])
{
    await NavigationStationDisplayTests.Run();
    return 0;
}

if (args is ["--overlay-config-audit-only"])
{
    await OverlayConfigurationAuditTests.Run();
    await OverlayPresetMigrationTests.Run();
    Console.WriteLine("PASS legacy overlay configuration recovery");
    return 0;
}

if (args is ["--overlay-appearance-options-only"])
{
    await OverlayAppearanceOptionsTests.Run();
    return 0;
}

if (args is ["--overlay-appearance-preview-only"])
{
    await OverlayAppearancePreviewTests.Run();
    await OverlayAppearanceLivePreviewTests.Run();
    return 0;
}

if (args is ["--chat-room-invitation-only"])
{
    try { await DirectMessageReadTests.RoomInvitationCards(); Console.WriteLine("PASS room invitation bridge cards"); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL room invitation bridge cards: " + error); return 1; }
}

if (args is ["--local-game-overlay-only"])
{
    await LocalGameOverlayEventTests.Verify();
    await GameLogJournalSourceTests.LifeEvidenceUsesSameParser();
    await GameLogJournalSourceTests.ServerNavigationAndPrivateProjection();
    Console.WriteLine("PASS live local game events reach the overlay sink without remote sharing");
    return 0;
}

if (args is ["--room-overlay-identity-only"])
{
    await LegacyPasswordLoginTests.RoomOverlayIdentityPipeline();
    Console.WriteLine("PASS room read/chat identity and presence reach Native overlay");
    return 0;
}

if (args is ["--party-room-keepalive-only"])
{
    await PartyRoomKeepaliveTests.Transport();
    return 0;
}

if (args is ["--party-room-chat-only"])
{
    await PartyRoomChatTests.Chat();
    await PartyRoomChatTests.Attachments();
    Console.WriteLine("PASS room chat identity, cursors, membership and uncertain-send regression");
    return 0;
}

if (args is ["--room-overlay-transient-only"])
{
    await LegacyPasswordLoginTests.RoomOverlayTransientReadPipeline();
    await RoomOverlaySessionTests.Revocation();
    Console.WriteLine("PASS transient room reads preserve only the still-authorized bounded snapshot");
    return 0;
}

if (args is ["--runtime-ship-labels-only"])
{
    try { await RuntimeShipLabelsTests.Verify(); return 0; }
    catch (Exception error) { Console.WriteLine("FAIL runtime ship labels: " + error); return 1; }
}

if (args is ["--ship-identity-only"])
{
    await GameLogJournalSourceTests.ShipNamesAndRelease();
    Console.WriteLine("PASS ship names and cross-format release use the same catalog identity");
    return 0;
}

if (args is ["--overlay-arrival-only"])
{
    await GameLogJournalSourceTests.ServerNavigationAndPrivateProjection();
    await GameLogJournalSourceTests.CurrentF8CMatchesJournal();
    Console.WriteLine("PASS current local session preserves quantum arrival confirmation");
    return 0;
}

if (args is ["--overlay-roster-route-only"])
{
    await CompositeBridgeDispatcherTests.RoutesPersonalProfileRequests();
    await OverlayRosterPreferencesTests.Run();
    Console.WriteLine("PASS composite roster read/write route and persistence");
    return 0;
}

if (args is ["--overlay-source-latency-only"])
{
    await OverlaySceneChoiceTests.LocalChoiceBypassesSlowCatalog();
    await OverlaySceneChoiceTests.ClosedOverlayKeepsOrganizationSources();
    await OverlaySceneChoiceTests.BridgeAndPersistence();
    Console.WriteLine("PASS local scene selection remains responsive during pending catalog IO");
    return 0;
}

if (args is ["--local-self-source-only"])
{
    await LocalGamePresenceTests.Verify();
    await RoomOverlaySessionTests.Membership();
    await RoomOverlaySessionTests.Revocation();
    await RoomOverlaySessionTests.Chat();
    Console.WriteLine("PASS local process confirmation and authorized self source");
    return 0;
}

if (args is ["--direct-overlay-only"])
{
    await DirectMessageOverlayTests.Run();
    Console.WriteLine("PASS direct-message overlay delivery and privacy gates");
    return 0;
}

if (args is ["--overlay-communication-only"])
{
    await AccountLifecycleIsEnabled();
    await OverlayCommunitySourceTests.Communication();
    await OverlayRosterPreferencesTests.Run();
    await OverlayCommunitySourceTests.Selection();
    await OverlayCommunitySourceTests.AccountAndLateResponses();
    Console.WriteLine("PASS authorized overlay communication and source isolation");
    return 0;
}
if (args is ["--overlay-community-schedule-only"])
{
    try
    {
        await OverlayCommunityRefreshScheduleTests.Run();
        await OverlayCommunityProgressiveReadTests.Run();
        await OverlayCommunitySourceTests.Recovery();
        await OverlayCommunitySourceTests.AccountAndLateResponses();
        await OverlayCommunitySourceTests.DemandAndDisposal();
        Console.WriteLine("PASS organization driver retries within unchanged authority lease and still revokes immediately");
        return 0;
    }
    catch (Exception error) { Console.WriteLine("FAIL organization refresh schedule: " + error.Message); return 1; }
}
if (args is ["--party-room-transfer-host-only"])
{
    await PartyRoomHostTransferTests.Authority();
    await PartyRoomHostTransferTests.Confirmation();
    await PartyRoomHostTransferTests.Unknown();
    Console.WriteLine("PASS party room host transfer contract regression");
    return 0;
}
if (args is ["--party-room-readback-only"])
{
    await PartyRoomReaderTests.PublicTwoMemberCreateReadback();
    await PartyRoomReaderTests.Projection();
    await PartyRoomReaderTests.InvalidData();
    await PartyRoomReaderTests.Commands();
    await PartyRoomReaderTests.CommandValidation();
    await PartyRoomReaderTests.HttpBoundary();
    Console.WriteLine("PASS party room create/readback contract regression");
    return 0;
}
if (args is ["--party-room-invitations-only"])
{
    await PartyRoomInvitationTests.Invitations();
    Console.WriteLine("PASS party room invitation target regression");
    return 0;
}

if (args is ["--friend-presence-read-only"])
{
    await LegacyPasswordLoginTests.VerifyBackgroundPlayerActivity();
    await GameLogLocationCatalogTests.SyntheticAndAbsentCatalog();
    await LegacyPasswordLoginTests.VerifyPlayerActivity();
    await FriendsReaderTests.HttpAndRequest();
    await PlayerActivitySourcesTests.Verify();
    Console.WriteLine("PASS friend presence and sharing read regression");
    return 0;
}
if (args is ["--scm-participant-enrollment-only"])
{
    await LegacyPasswordLoginTests.ScmParticipantEnrollment();
    Console.WriteLine("PASS SCM participant lifecycle enrollment");
    return 0;
}
if (args is ["--friend-search-privacy-only"])
{
    await LegacyPasswordLoginTests.ScmFriendDiscovery();
    await FriendsReaderTests.Projection();
    await FriendsReaderTests.HttpAndRequest();
    Console.WriteLine("PASS friend search privacy projection and request boundary");
    return 0;
}

if (args is ["--handle-mismatch-only"])
{
    await LegacyPasswordLoginTests.HandleMismatchProjection();
    await LegacyPasswordLoginTests.HandleChangeCompatibility();
    await LegacyPasswordLoginTests.OfflineHandleChange();
    await GameIdentityNotificationTests.Run();
    return 0;
}

if (args is ["--social-notifications-only"])
{
    await CommunityNotificationAudioTests.Run();
    await LocalGamePresenceTests.Verify();
    await SocialNotificationAudioTests.Run();
    await SocialActivityReadTests.Run();
    await FriendRequestNotificationTests.Run();
    await AccountDispatchConcurrencyTests.Verify();
    await DirectMessageDesktopTests.Run();
    await RoomAudioTests.Run();
    Console.WriteLine("PASS social notification delivery regression");
    return 0;
}

if (args is ["--local-chat-history-only"])
{
    await LocalChatHistoryTests.Verify();
    await DirectMessageReadTests.Paging();
    await DirectMessageReadTests.Guards();
    await CommunityChatClientTests.Verify();
    await CommunityChatSendTests.Verify();
    Console.WriteLine("PASS direct and community chat transport, scope and send regression");
    return 0;
}

if (args is ["--menu-preferences-only"])
{
    await MenuPreferencesTests.Verify();
    await MenuStartupTests.Verify();
    await MenuRecoveryTests.Verify();
    await MenuBrowserResumeTests.Verify();
    await MenuScreenshotDirectoryTests.Verify();
    return 0;
}

if (args is ["--first-use-notice-only"])
{
    await TestBuildNoticeTests.Verify();
    return 0;
}

if (args is ["--applicant-identity-only"])
{
    await CommunityWpfS2ManagementTests.Verify();
    await AvatarInteractionTests.Verify();
    Console.WriteLine("PASS applicant identity references and avatar interaction regression");
    return 0;
}

if (args is ["--friend-request-privacy-only"])
{
    await FriendRequestPrivacyTests.Verify();
    Console.WriteLine("PASS friend request privacy transport and pure SCM runtime");
    return 0;
}

if (args is ["--profile-visibility-only"])
{
    await LegacyPasswordLoginTests.ProfileVisibility();
    Console.WriteLine("PASS profile visibility bridge ownership and transport");
    return 0;
}

if (args is ["--visitor-profile-only"])
{
    await VisitorReadDiagnosticsTests.Verify();
    await LegacyPasswordLoginTests.VisitorProfile();
    await AvatarInteractionTests.Verify();
    await CommunityWorkspaceClientTests.Verify();
    Console.WriteLine("PASS visitor profile reference, read-only transport, privacy and account isolation");
    return 0;
}

if (args is ["--community-profile-only"])
{
    await CommunityProfileClientTests.Verify();
    Console.WriteLine("PASS community profile bridge and Unicode name edits");
    return 0;
}

if (args is ["--avatar-only"])
{
    await LegacyPasswordLoginTests.AvatarUpdate();
    await LegacyPasswordLoginTests.ScmAvatarWrite();
    await FirstUseModeTests.OfflineAvatarSurvivesDownloadOutage();
    await FirstUseModeTests.OfflineAvatarConfirmedAbsent();
    await CommunityLogoBridgeTests.Verify();
    await AccountLifecycleIsEnabled();
    Console.WriteLine("PASS account avatar update, authority, failure and invalidation checks");
    return 0;
}

if (args is ["--callsign-only"])
{
    await LegacyPasswordLoginTests.ScmCallSignWrite();
    Console.WriteLine("PASS SCM callsign owner, scope, CAS, acknowledgement and invalidation checks");
    return 0;
}

if (args is ["--community-read-efficiency-only"])
{
    await CommunityReadEfficiencyTests.Verify();
    return 0;
}

if (args is ["--installed-appearance-progress-boundary-only"])
{
    StarBridge.HostRuntime.Tests.InstalledAppearanceProgressBoundaryTests.Verify();
    await OverlayAppearanceProgressTests.Run();
    return 0;
}

if (args is ["--account-dispatch-concurrency-only"])
{
    await AccountDispatchConcurrencyTests.Verify();
    return 0;
}

if (args is ["--legacy-login-retirement-only"])
{
    await LegacyPasswordLoginTests.Retirement();
    await LegacyPasswordLoginTests.Verify();
    Console.WriteLine("PASS retired login transport/Bridge/session isolation and existing legacy login compatibility");
    return 0;
}

if (args is ["--sharing-queue-probe-only"])
{
    await LegacyPasswordLoginTests.SharingQueueProbe();
    Console.WriteLine("PASS sharing lanes preserve mutation barriers and independent renewal");
    return 0;
}

if (args is ["--concurrent-auth-refresh-only"])
{
    await AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh();
    Console.WriteLine("PASS delayed unauthorized response reuses refreshed SCM session");
    return 0;
}

if (args is ["--selected-import-java-client", var importFixtureAddress])
{
    await SelectedImportJavaClient.Run(importFixtureAddress);
    return 0;
}

if (args is ["--compatibility-login-only"])
{
    await IdentityLinkProofOutageTests.Verify();
    await S2CompatibilityReadTests.Verify();
    await S2ExistingAccountLinkTests.Verify();
    Console.WriteLine("PASS compatibility binding, original business reads and revoked access");
    return 0;
}

if (args is ["--selected-profile-import-only"])
{
    await SelectedProfileImportTests.Run();
    await SelectedLocalProfileImportTests.Run();
    await SelectedProfileImportRecoveryTests.Run();
    await LocalPersonalProfileTests.Collaboration();
    return 0;
}

if (args is ["--scm-community-wire-client", var fixtureAddress])
{
    await ScmCommunityWireClient.Run(fixtureAddress);
    return 0;
}

if (args is ["--community-announcements-only"])
{
    await CommunityAnnouncementsClientTests.Verify();
    Console.WriteLine("PASS community announcement pages, detail and pure SCM redaction");
    return 0;
}

if (args is ["--community-admission-only"])
{
    await CommunityClientTests.Verify();
    await CommunityAdmissionsClientTests.Verify();
    await CommunityAdmissionCommandTests.Verify();
    Console.WriteLine("PASS community admission authority and bounded generation receipts");
    return 0;
}

if (args is ["--hangar-media-only"])
{
    await HangarMediaTransportTests.Verify();
    Console.WriteLine("PASS hangar media transport ownership, cancellation and uncertain writes");
    return 0;
}


if (args is ["--menu-hotkeys-only"])
{
    await OverlaySettingsTests.DefaultHotkeyPreservesSavedBindings();
    await MenuHotkeyBridgeTests.Run();
    return 0;
}










if (args is ["--room-overlay-identity-only"])
{
    await LegacyPasswordLoginTests.RoomOverlayIdentityPipeline();
    await PartyRoomKeepaliveTests.Transport();
    Console.WriteLine("PASS room read/chat identity and presence reach Native overlay");
    return 0;
}












if (args is ["--social-notifications-only"])
{
    await LocalGamePresenceTests.Verify();
    await SocialNotificationAudioTests.Run();
    await SocialActivityReadTests.Run();
    await FriendRequestNotificationTests.Run();
    await AccountDispatchConcurrencyTests.Verify();
    await DirectMessageDesktopTests.Run();
    await RoomAudioTests.Run();
    Console.WriteLine("PASS social notification delivery regression");
    return 0;
}






if (args is ["--visitor-profile-only"])
{
    await LegacyPasswordLoginTests.VisitorProfile();
    await AvatarInteractionTests.Verify();
    Console.WriteLine("PASS visitor profile reference, read-only transport, privacy and account isolation");
    return 0;
}


if (args is ["--avatar-only"])
{
    await LegacyPasswordLoginTests.AvatarUpdate();
    await CommunityLogoBridgeTests.Verify();
    await AccountLifecycleIsEnabled();
    Console.WriteLine("PASS account avatar update, authority, failure and invalidation checks");
    return 0;
}



if (args is ["--release-configuration-only"])
{
    await UnconfiguredHostUsesProductionDefaults();
    await ProductionHostRejectsLoopbackRoutes();
    await ProductionAccountAccessCanBeExplicitlyDisabled();
    await ScmRuntimeIsolatesProductionAndDevelopment();
    await WpfMigrationPreflightTests.Verify();
    await WpfMigrationConfirmationTests.Verify();
    await FlutterStartupReceiptTests.Verify();
    Console.WriteLine("PASS 7 release configuration and migration safety groups; isolated fixtures only.");
    return 0;
}

if (args is ["--help-support-only"])
{
    await HelpSupportTests.RunAll();
    return 0;
}

if (args is ["--hangar-migration-bridge-only"])
{
    await LegacyPasswordLoginTests.HangarMigrationBridge();
    return 0;
}

if (args is ["--hangar-selection-only"])
{
    await LegacyHangarSelectionTests.Verify();
    return 0;
}

if (args is ["--diagnostics-open-directory-only"])
{
    await ApplicationSupportTests.ReusedExplorerWindowReportsOpenSuccess();
    Console.WriteLine("PASS reused Explorer window is acknowledged; shell errors remain failures");
    return 0;
}

if (args is ["--flutter-installation-inspect-only", var auditDirectory, var expectedMode])
{
    FlutterInstallationMaintenanceTests.InspectIsolatedInstallation(auditDirectory, expectedMode);
    Console.WriteLine("PASS isolated Flutter installation read: " + expectedMode);
    return 0;
}
if (args is ["--flutter-installation-clean-isolated", var staleAuditDirectory])
{
    FlutterInstallationMaintenanceTests.CleanIsolatedStaleInstallation(staleAuditDirectory);
    Console.WriteLine("PASS isolated Flutter stale registration cleanup");
    return 0;
}

if (args is ["--privacy-wire-only"])
{
    void RequireFields(object value, int expected)
    {
        var json = System.Text.Json.JsonSerializer.SerializeToElement(value, BridgeProtocol.JsonOptions);
        if (json.EnumerateObject().Count() != expected)
            throw new Exception("Bridge privacy payload omitted required nullable fields: " + value.GetType().Name);
    }
    RequireFields(new StarBridge.HostRuntime.Privacy.EventSharingRemoteSnapshot(1, 0, null, null, false, null), 6);
    RequireFields(new StarBridge.HostRuntime.Privacy.FriendSharingRemoteSnapshot(1, 0, null, null, null), 5);
    RequireFields(new StarBridge.HostRuntime.Friends.FriendRequestPrivacyView(true, null), 3);
    RequireFields(new StarBridge.HostRuntime.Friends.RecentlyPlayedPrivacyView(false, null, null, 0), 5);
    await LegacyPasswordLoginTests.Verify();
    await LegacyPasswordLoginTests.Verify();
    Console.WriteLine("PASS privacy Bridge wire preserves required nullable fields");
    return 0;
}
if (args is ["--event-preferences-only"])
{
    await SharedActivityEventSourceTests.Run();
    await EventSharingRuntimeTests.Run();
    await SharedActivityReceiverTests.Run();
    await GameLogJournalSourceTests.WarmupThenRealEvents();
    await GameLogJournalSourceTests.InvalidIdentityAndAccountDoNotCommit();
    await EventSharingTransportTests.Run();
    await SharedEventPreferencesStoreTests.Run();
    await LocalPrivacyTests.Storage();
    await LocalPrivacyTests.FailClosed();
    await LocalPrivacyTests.Contract();
    Console.WriteLine("PASS event preferences and existing local privacy storage/contract");
    return 0;
}
if (args is ["--isolated-storage-helper", var storageHelper, var storageFixture])
{
    await StorageMigrationHelperIntegration.Run(storageHelper, storageFixture);
    return 0;
}
if (args is ["--legacy-entitlements-only"])
{
    await LegacyEntitlementTests.Verify();
    await LegacyPasswordLoginTests.EntitlementLifecycle();
    Console.WriteLine("PASS legacy entitlement transport boundaries");
    return 0;
}
if (args is ["--compatibility-entitlements-only"])
{
    await LegacyEntitlementTests.Verify();
    await LegacyPasswordLoginTests.EntitlementLifecycle();
    await ScmBootstrapProjectsOverlayEntitlements();
    Console.WriteLine("PASS compatibility entitlement authority, original account and expiry boundaries");
    return 0;
}
if (args is ["--overlay-entitlement-refresh-only"])
{
    await OverlayEntitlementRefreshTests.Verify();
    return 0;
}
if (args is ["--gameplay-history-only"])
{
    await GameplayHistoryRuntimeTests.ResetBridgeConfirmation();
    await LegacyPasswordLoginTests.GameplayResetTransport();
    await GameplayHistoryRuntimeTests.ResetRecovery();
    await GameplayHistoryScannerTests.Verify();
    await GameplayHistoryRuntimeTests.OnceOnlyAndMigration();
    await GameplayHistoryRuntimeTests.FailureAndOwnership();
    await GameplayHistoryRuntimeTests.OldSnapshotCompatibility();
    return 0;
}
if (args is ["--storage-migration-only"])
{
    await StorageMigrationDestinationTests.ValidateWithoutMutation();
    await StorageMigrationDestinationTests.VerifiedCopyPreservesSource();
    await StorageMigrationTransactionTests.Verify();
    await StorageMigrationCompletedRecoveryTests.Verify();
    await StorageMigrationSelectionTests.Verify();
    await StorageMigrationProtocolTests.Verify();
    Console.WriteLine("PASS storage destination, verified copy, handoff protocol, locator switch and interrupted migration recovery");
    return 0;
}

if (args is ["--isolated-update-helper", var helperPath, var fixturePath])
{
    await FlutterUpdateHelperIntegration.Run(helperPath, fixturePath);
    Console.WriteLine("PASS isolated helper processes: upgrade receipt and startup-failure rollback");
    return 0;
}

if (args is ["--flutter-updates-only"])
{
    await InstalledUpdateTransactionTests.Verify();
    await FlutterInstallerUpdateTests.Verify();
    await FlutterInstallerDownloadTests.Verify();
    await FlutterUpdateTests.Verify();
    await FlutterUpdateTransactionTests.Verify();
    await FlutterUpdateBridgeTests.Verify();
    Console.WriteLine("PASS Flutter signed manifest, isolated package staging and transport guards");
    return 0;
}

if (args is ["--verify-flutter-update-publisher", var signedFile, var signedVersion, var binaryKind])
{
    if (binaryKind == "installer") await StarBridge.HostRuntime.Updates.FlutterInstallerPublisherVerifier.VerifyAsync(signedFile, signedVersion, CancellationToken.None);
    else if (binaryKind == "binary") await StarBridge.HostRuntime.Updates.FlutterInstallerPublisherVerifier.VerifyInstalledBinaryAsync(signedFile, signedVersion, CancellationToken.None);
    else return 2;
    Console.WriteLine("PASS read-only publisher, timestamp and release-version verification; no executable launched");
    return 0;
}

if (args is ["--account-safety-only"])
{
    await AccountSafetyRequestTests.Verify();
    await AccountSafetyClientTests.Projection();
    await AccountSafetyClientTests.Transport();
    await AccountSafetyClientTests.Submission();
    await NotificationInboxTests.Verify();
    await CompositeBridgeDispatcherTests.RoutesPersonalProfileRequests();
    await AccountLifecycleIsEnabled();
    if (!AccountBridgeRuntime.AdvertisedCapabilities.Contains("accountSafety.read"))
        throw new Exception("Account safety capability missing.");
    Console.WriteLine("PASS Account safety requests, S2 reads, transport and composition");
    return 0;
}

if (args is ["--hangar-cards-only"])
{
    await LocalHangarStoreTests.Verify();
    await LocalHangarBridgeTests.Verify();
    await HangarReaderDispatcherTests.ReadOnlyPreviewMatrix();
    Console.WriteLine("PASS Hangar instance bookmarks, persistence, guarded bridge and reader");
    return 0;
}

if (args is ["--hangar-auto-sync-only"])
{
    try
    {
        await LocalHangarBridgeTests.Verify();
        await LocalHangarStoreTests.Verify();
        await HangarReaderDispatcherTests.ReadOnlyPreviewMatrix();
        await HangarAutoSyncIntegrationTests.Verify();
        await HangarAutoSyncTests.Verify();
        await CommunityHangarSharingClientTests.Verify();
        Console.WriteLine("PASS Local hangar automatic publication lifecycle");
        return 0;
    }
    catch (Exception error) { Console.Error.WriteLine("FAIL Hangar auto sync: " + error); return 1; }
}

if (args is ["--hangar-review-only"])
{
    await HangarReaderDispatcherTests.ReadOnlyPreviewMatrix();
    Console.WriteLine("PASS Hangar ship-only extraction and read-only isolation");
    return 0;
}

if (args is ["--probe-wpf-ships", "--production-relay-read-only"])
    return await WpfCommunityShipsProbe.Run();

if (args is ["--probe-hangar-sharing", "--production-relay-read-only"])
    return await HangarSharingReadProbe.Run();

if (args is ["--probe-community-sharing", "--production-relay-read-only"])
    return await CommunitySharingReadProbe.Run();

if (args is ["--probe-wpf-community-contract", "--production-relay-read-only"])
{
    return await WpfCommunityContractProbe.Run();
}

if (args is ["--desktop-notifications-only"])
{
    await CommunityNotificationAudioTests.Run();
    await PlayerActivitySourcesTests.Verify();
    await RoomAudioTests.Run();
    await CommunityNotificationTests.Run();
    await CommunityNotificationDeliveryTests.Run();
    await NotificationPolicyBridgeTests.Run();
    await DirectMessageNotificationObserverTests.Run();
    await DirectMessageDesktopTests.Run();
    await DirectMessageReadTests.NotificationMetadata();
    await DirectMessageReadTests.Paging();
    await DirectMessageReadTests.Guards();
    await CompositeBridgeDispatcherTests.ObservesDirectMessages();
    await DesktopNotificationTests.Run();
    Console.WriteLine("PASS Desktop notification tickets and shared sink isolation");
    return 0;
}

if (args is ["--realtime-client-only"]) { await RealtimeClientRecoveryTests.Verify(); return 0; }
if (args is ["--scm-realtime-only"])
{
    await ScmRealtimeLifecycleTests.Verify();
    return 0;
}
if (args is ["--vault-concurrency-only"]) { await WindowsTokenVaultConcurrencyTests.Verify(); return 0; }
if (args is ["--store-file-commit-only"]) { await StoreFileCommitTests.Verify(); return 0; }

if (args is ["--session-probe-only"])
{
    await ScmSessionProbeTests.Verify();
    return 0;
}

if (args is ["--account-read-timing-only"])
{
    await AccountDispatchConcurrencyTests.ReadTiming();
    return 0;
}

if (args is ["--session-probe-disabled-only"])
{
    await ScmSessionProbeTests.VerifyDisabled();
    return 0;
}

if (args is ["--manual-presence-only"])
{
    await ScmRealtimeLifecycleTests.Verify();
    await AccountLifecycleIsEnabled();
    await CompositeBridgeDispatcherTests.RoutesPersonalProfileRequests();
    await ManualPresenceIntegrationTests.Verify();
    Console.WriteLine("PASS Manual presence routing and integrated publication");
    return 0;
}

if (args is ["--sharing-queue-probe-only"])
{
    await AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh();
    await LegacyPasswordLoginTests.SharingQueueProbe();
    Console.WriteLine("PASS sharing queue isolation");
    return 0;
}
if (args is ["--game-id-settings-only"])
{
    await GameIdSettingsTests.Run();
    await LegacyPasswordLoginTests.ScmHandlePrivacy();
    Console.WriteLine("PASS game ID settings transport guards legacy servers, lost receipts and account changes");
    return 0;
}
if (args is ["--location-confidence-hidden-only"])
{
    try
    {
        await PrivacyPublicationTests.Projection();
        await PartyRoomReaderTests.Projection();
        Console.WriteLine("PASS confidence-hidden location reason preserves privacy boundaries");
        return 0;
    }
    catch (Exception exception)
    {
        Console.Error.WriteLine("FAIL confidence-hidden location reason: " + exception.Message);
        return 1;
    }
}
if (args is ["--community-sharing-only"])
{
    await CommunitySharingTests.Verify();
    Console.WriteLine("PASS Community sharing failure isolation");
    return 0;
}
if (args is ["--presence-recovery-only"])
{
    await PrivacyPublicationRecoveryTests.ServerAndSessionRecovery();
    await PrivacyPublicationRecoveryTests.SessionAndFailureBoundaries();
    await SharingStatusDetailTests.Run();
    await PrivacyPublicationRecoveryTests.AutomaticTimerRecovery();
    await PrivacyPublicationRecoveryTests.RevokedConsentRestart();
    await GameLogRuntimeTests.PublicationWake();
    await PresenceChangeWakesFriendPublication();
    await PrivacyPublicationRecoveryTests.SilentHeartbeat();
    await FriendSharingPublicationTests.Verify();
    await FriendSharingRuntimeTests.Run();
    await CommunitySharingTests.Verify();
    await PrivacyPublicationRecoveryTests.Restart();
    await PrivacyConsentTests.Verify();
    await PrivacyPublicationRecoveryTests.TransientDisconnect();
    await PrivacyPublicationRecoveryTests.Guards();
    await PrivacyPublicationTests.Projection();
    await PrivacyPublicationTests.Lifecycle();
    await PrivacyPublicationTests.Ordering();
    await PrivacyPublicationTests.FailClosed();
    await PrivacyPublicationTests.Wire();
    Console.WriteLine("PASS Presence recovers without manual apply");
    return 0;
}
if (args is ["--sharing-status-only"])
{
    await SharingStatusDetailTests.Run();
    Console.WriteLine("PASS sharing status detail and recovery contract");
    return 0;
}

if (args is ["--player-activity-sources-only"])
{
    await PlayerActivitySourcesTests.Verify();
    await CommunityWpfS2Tests.Verify();
    await LegacyPasswordLoginTests.VerifyPlayerActivity();
    Console.WriteLine("PASS Player activity complete-source, privacy, ordering and account gates");
    return 0;
}

if (args is ["--player-activity-transition-reliability-only"])
{
    await PlayerActivityTransitionReliabilityTests.Run();
    await PlayerActivityPolicyTests.Run();
    Console.WriteLine("PASS Player activity transitions and audience policy gates");
    return 0;
}

if (args is ["--communities-only"])
{
    try
    {
        await CommunityClientTests.Verify();
        await HangarAutoSyncTests.Verify();
        await HangarAutoSyncIntegrationTests.Verify();
        await PlayerActivitySourcesTests.Verify();
        await CommunityWpfS2Tests.Verify();
        await CommunityWpfS2DiscoveryTests.Verify();
        await CommunityWpfS2CommunicationTests.Verify();
        await CommunityWpfS2WriteTests.Verify();
        await CommunityWpfS2ShipTests.Verify();
        await CommunityWpfS2AdmissionTests.Verify();
        await CommunityWpfS2InviteTests.Verify();
        await CommunityWpfS2LeaveTests.Verify();
        await CommunityCreationClientTests.Verify();
        await CommunityWpfS2CreationTests.Verify();
        await CommunityWpfS2InvitationSendTests.Verify();
        await CommunityWpfS2ProfileTests.Verify();
        await CommunityWpfS2ManagementTests.Verify();
        await CommunityWpfS2GovernanceTests.Verify();
        await CommunityWorkspaceClientTests.Verify();
        await CommunityLogsClientTests.Verify();
        await CommunityDisbandClientTests.Verify();
        await CommunityChatClientTests.Verify();
        await CommunityAnnouncementsClientTests.Verify();
        await CommunityShipsClientTests.Verify();
        await CommunityAnnouncementWriteClientTests.Verify();
        await CommunityChatSendTests.Verify();
        await CommunityProfileClientTests.Verify();
        await CommunityHangarSharingClientTests.Verify();
        await CommunityRolesClientTests.Verify();
        await CommunityMemberRoleClientTests.Verify();
        await CommunityMemberRemovalClientTests.Verify();
        await CommunityOwnershipTransferClientTests.Verify();
        await CommunityOwnershipTransferClientTests.VerifyExit();
        await CommunityInviteClientTests.Verify();
        await CommunityAdmissionsClientTests.Verify();
        await CommunityAdmissionCommandTests.Verify();
        await CommunityInvitationGenerationTests.Verify();
        await CommunityInvitationDeliveryTests.Verify();
        await InvitationSendWorkflowTests.Verify();
        await InvitationAccountBridgeTests.Verify();
        await CompositeBridgeDispatcherTests.RoutesCommunityRequests();
        await CommunityLogoBridgeTests.Verify();
        Console.WriteLine("PASS Communities bounded reads and scoped membership commands");
        return 0;
    }
    catch (Exception exception)
    {
        Console.Error.WriteLine($"FAIL Communities regression: {exception}");
        return 1;
    }
}

if (args.Length == 2 && args[0] == "--java-personal-profile-wire")
{
    return await JavaPersonalProfileWireCheck.RunAsync(args[1]);
}

if (args.Length == 1 && args[0] == "--hangar-sandbox-probe")
{
    await HangarSandboxTests.LiveProbe();
    return 0;
}

if (args.Length == 1 && args[0] == "--hangar-locked-scan")
{
    await HangarLockedScanTests.Verify();
    return 0;
}

if (args.Length == 1 && args[0] == "--hangar-ship-presentation")
{
    await HangarShipNameTests.Verify();
    await HangarShipNameTests.FullRsiTitles();
    return 0;
}

if (args.Length == 2 && args[0] == "--hangar-reader-probe")
{
    return await HangarIdentityGuardTests.RunNativeProbe(args[1]);
}

if (args.Length == 2 && args[0] is "--hangar-interaction-probe" or "--hangar-interaction-window")
{
    return await HangarInteractionProbe.RunAsync(args[1], args[0] == "--hangar-interaction-window");
}

if (args.Length == 2 && args[0] == "--hangar-catalog-bundle")
{
    HangarCatalogTests.Bundle(args[1]);
    return 0;
}

var tests = new (string Name, Func<Task> Test)[]
{
    ("SCM game identity bridge, session and participant enrollment", GameIdentityBridgeTests.Run),
    ("Visitor fleet affiliation status and old-server compatibility", VisitorFleetAffiliationTests.Run),
    ("Official sharing defaults require explicit choice and preserve fail-closed storage", OfficialSharingDefaultsTests.Run),
    ("CX78 game process observations", HostIdleTests.Processes),
    ("CX78 account diagnostic aggregation", HostIdleTests.Diagnostics),
    ("SCM inbox push acknowledgements and reconnect", NotificationInboxPushTests.Run),
    ("SCM messages merge into notification inbox with isolated leases", NotificationInboxScmMessagesTests.Run),
    ("Current projection diagnostics are bounded and private", AccountDispatchConcurrencyTests.CurrentDiagnostics),
    ("One failing bridge request answers alone and keeps the pipe session", PipeRequestGuardTests.Run),
    ("Trading hall trader references read a visitor page without exposing an identity", async () => { if (await MarketTraderProfileTests.Run() != 0) throw new InvalidOperationException("market trader profile failed"); }),
    ("Marketplace write wire contracts and failure matrix", MarketplaceWriteTests.Run),
    ("Trade profile privacy, merge, permissions and authoritative read-back", TradeProfileTests.Run),
    ("Composed Native Host routes every marketplace request to the account owner", CompositeBridgeDispatcherTests.RoutesMarketplaceRequests),
    ("Profile writes reuse refreshable daily login without temporary grants", ProfileWriteSessionTests.Run),
    ("Friends command paging preserves accepted ACK and bounded complete directory with one POST", AccountSessionRestoreTests.FriendsCommandPagingFrame),
    ("Friends command paging preserves small legacy shapes and bounds large legacy acknowledgements", AccountSessionRestoreTests.FriendsCommandPagingCompatibility),
    ("Friends command paging rejects nonboolean options before POST", AccountSessionRestoreTests.FriendsCommandPagingValidation),
    ("Friends command paging result snapshots require original owner generation and live binding", AccountSessionRestoreTests.FriendsCommandPagingResultFences),
    ("Friends paged large directory respects frame bounds without repeated HTTP", AccountSessionRestoreTests.FriendsPagedDirectory),
    ("Friends paged command boundary retires both existing and in-flight snapshots", AccountSessionRestoreTests.FriendsPagedCommandRetirement),
    ("Friends paged snapshots enforce scope capacity expiry and complete rows", AccountSessionRestoreTests.FriendsPagedStoreBoundaries),
    ("Friends paged online cache stays bounded and tied to original directory HTTP", AccountSessionRestoreTests.FriendsPagedOnlineDisplay),
    ("Friends paged retained directory reuses verified disk data within original readId", AccountSessionRestoreTests.FriendsPagedRetainedDirectory),
    ("Friends paged retained directory fences selection credential policy and cancellation", AccountSessionRestoreTests.FriendsPagedRetainedFences),
    ("Friends online cached display arrives before original directory HTTP completes", AccountSessionRestoreTests.FriendsOnlineDisplay),
    ("Friends online cached display rejects invalid scopes options cache and cancellation", AccountSessionRestoreTests.FriendsOnlineDisplayBoundaries),
    ("Friends online cached display honors original refusal outage and abandonment", AccountSessionRestoreTests.FriendsOnlineDisplayOutcomes),
    ("Friends online cached display cannot overtake queued invalidations", AccountDispatchConcurrencyTests.DisplayProgressPreservesInvalidations),
    ("Friends online cached display capture preserves pending and refusal epoch fences", AccountSessionRestoreTests.FriendsOnlineDisplayLeaseEpoch),
    ("Friends online cached display respects the original transport frame budget", AccountDispatchConcurrencyTests.DisplayProgressFrameBudget),
    ("Trade-chat live pushes skip the dispatch wait without overtaking queued events", AccountDispatchConcurrencyTests.LiveEventSkipsDispatchWaitWithoutOvertaking),
    ("Friends snapshot accepted command updates the next cold display without replay", AccountSessionRestoreTests.FriendsSnapshotAcceptedCommand),
    ("Friends snapshot unknown command quarantines the next cold display without replay", AccountSessionRestoreTests.FriendsSnapshotUnknownCommand),
    ("Friends snapshot rejected command preserves the prior cold directory without replay", AccountSessionRestoreTests.FriendsSnapshotRejectedCommand),
    ("Friends snapshot command guard failure prevents POST and reports definite rejection", AccountSessionRestoreTests.FriendsSnapshotCommandGuard),
    ("Friends snapshot is readable during original cold authentication without granting authority", AccountSessionRestoreTests.FriendsSnapshotColdRead),
    ("Friends snapshot protection bounds overlapping reads refusal retirement and owner changes", FriendsSnapshotStoreTests.Run),
    ("Friends snapshot retained reads reject forged cancelled corrupt and replaced scopes", AccountSessionRestoreTests.FriendsSnapshotReadBoundaries),
    ("Directory compression actual HTTP fixture roundtrips gzip deflate and Brotli", DirectoryCompressionTests.FixtureControl),
    ("Directory compression friends negotiates and preserves decoded limits and denial", DirectoryCompressionTests.Friends),
    ("Directory compression communities negotiates and preserves decoded limits and denial", DirectoryCompressionTests.Communities),
    ("Directory compression rooms negotiates and preserves decoded limits and denial", DirectoryCompressionTests.Rooms),
    ("Unknown Host faults are distinct from retryable transport failure", PersonalProfileReadFailureTests.UnexpectedHostFailure),
    ("Friends loading cache failures preserve authorization and classify only recoverable HTTP status", FriendsLoadingFailureTests.Run),
    ("Friends relationship recheck failures quarantine cached directory while initial outages retain it", AccountSessionRestoreTests.FriendsRelationshipRecheckFailures),
    ("Friends relationship recheck preserves 401 identity rejection and clears cache", AccountSessionRestoreTests.FriendsRelationshipRecheck401),
    ("Friends relationship recheck preserves 403 permission rejection and clears cache", AccountSessionRestoreTests.FriendsRelationshipRecheck403),
    ("Friends relationship recheck preserves invalid JSON rejection and clears cache", AccountSessionRestoreTests.FriendsRelationshipRecheckDataInvalid),
    ("Friends relationship recheck rejection retires previously fresh pages", AccountSessionRestoreTests.FriendsRelationshipRecheckPageRetirement),
    ("Personal profile reads classify transient failure separately from authorization and protocol failure", PersonalProfileReadFailureTests.Run),
    ("First-use local profiles preserve independent identity, protection and explicit progress", () => { LocalFirstUseStoreTests.Run(); return Task.CompletedTask; }),
    ("Publication owners retain physical callback and timer retirement receipts", PublicationRetirementTests.Run),
    ("First-use identity discovery requires complete consistent bounded log scope", () => { LocalIdentityDiscoveryTests.Run(); return Task.CompletedTask; }),
    ("First-use source gates survive reopening and require real session evidence before profile confirmation", () => { LocalLogEvidenceOwnerTests.Run(); return Task.CompletedTask; }),
    ("First-use local game recognition shares one sampler without account authority or implicit collection", () => { LocalGameLogRuntimeTests.Run(); return Task.CompletedTask; }),
    ("First-use local device setup inspects real settings without applying or granting completion", LocalDeviceSetupReaderTests.Run),
    ("First-use device review requires explicit current choices without granting functional readiness", LocalDeviceSetupReviewTests.Run),
    ("First-use device review bridge exposes only actual shared choices", LocalDeviceReviewBridgeTests.Run),
    ("First-use local statistics bridge requires explicit scoped choice", LocalStatisticsChoiceBridgeTests.Run),
    ("First-use local history import is explicit, previewed, once only and never clears saved time", LocalHistoryImportTests.Run),
    ("First-use recognition check is read-only and honest", LocalRecognitionCheckTests.Run),
    ("First-use Native observations never grant functional or human acceptance", NativeOverlayObservationBridgeTests.Run),
    ("First-use account retirement drains foreground requests and actual SCM session loops", LocalAccountStopTests.Run),
    ("First-use credential retirement fences the original stored login version", ScmCredentialRetirementTests.Run),
    ("First-use credential checkpoint recovers real exited owners without restoring authorization", FirstUseCredentialCheckpointTests.Run),
    ("First-use business background retirement waits for actual transports and native submissions", BackgroundRetirementTests.Run),
    ("First-use account sampling drains before the single local log sampler takes over", LocalSamplingRetirementTests.Run),
    ("First-use runtime replacement awaits the original log timer and both sampling slots", GameLogLifetimeTests.Run),
    ("Deferred work starts and drains exactly one original physical timer", DeferredWorkTimerTests.Run),
    ("Deferred async drivers activate once and drain their original physical work", DeferredAsyncDriverTests.Run),
    ("First-use login candidate has no business startup or online feature authority", FirstUseOnlineCandidateTests.Run),
    ("First-use pending sign-in preserves local functions and awaits actual candidate cancellation", FirstUseOnlineReturnTests.Run),
    ("First-use retained session resume stays deferred and preserves credential ownership", FirstUseSessionResumeTests.Run),
    ("First-use authoritative identity review and confirmation preserve independent owners", FirstUseOnlineIdentityTests.Run),
    ("First-use candidate game verification preserves authentication and installation ownership", FirstUseGameIdentityTests.Run),
    ("First-use online review bridge exposes actual auth and identity without installation authority", FirstUseOnlineReviewBridgeTests.Run),
    ("First-use handoff seals and drains the actual confirmed authentication owner", FirstUseOnlineHandoffTests.Run),
    ("Official runtime Ready follows the actual installed Native owner", FirstUseBusinessOwnerTests.RunRuntimeReady),
    ("First-use business preparation reads current existing storage ownership and drains physical IO", FirstUseBusinessOwnerTests.Run),
    ("First-use candidate lifecycles retain noncolliding actual account generations", FirstUseGenerationTests.Run),
    ("First-use Native composition skips sealed account consumers and retains device routes", FirstUseCompositionTests.Run),
    ("First-use local statistics preserve explicit consent and independent profile ownership", LocalGameplayTimeTests.Run),
    ("First-use local overlay reads actual local facts without account source authority", LocalOverlaySourceTests.Run),
    ("First-use mode intent guards cold startup and requires actual account retirement", FirstUseModeTests.Run),
    ("A Host built without first-use ignores saved modes without rewriting them", FirstUseDisabledHostTests.Run),
    ("An upgrading existing user meets no automatic setup and keeps account startup", FirstUseExistingUserUpgradeTests.Run),
    ("First-use cold recovery requires durable real retirement and actual process exit", FirstUseModeRecoveryTests.Run),
    ("Missing original mode is unknown and cannot restore account startup", FirstUseMissingModeTests.Run),
    ("The actual guide recovers only an explicitly chosen originally stopped local owner", FirstUseRecoveryGuideTests.Run),
    ("SCM public ship specifications preserve exact model identity", ShipSpecificationTests.Run),
    ("Executive hangar schedules independent device reminders", ExecHangarTests.Run),
    ("Executive hangar game overlay display grants", ExecHangarGameOverlayTests.Run),
    ("Achievement authenticated SCM transport and cloud receipt", AchievementRemoteTests.Run),
    ("Achievement read sample shared with Flutter and the server", AchievementReadContractTests.Run),
    ("Achievement idea waits for account reads without replay", AchievementIdeaContentionTests.Run),
    ("First-use startup distinguishes fresh install, update and saved use", FirstUseStartupTests.Run),
    ("First-use completion records survive reopen without granting domain permission", () => { FirstUseCompletionStoreTests.Run(); return Task.CompletedTask; }),
    ("First-use completion checks actual installed mode, identity and domain choices", FirstUseCompletionRuntimeTests.Run),
    ("First-use product online protocol installs original owners and persists completion", FirstUseBusinessOwnerTests.RunProductOnlineProtocol),
    ("First-use retained reauthorization binds original account and credential version", FirstUseBusinessOwnerTests.RunReauthorizationProtocol),
    ("Offline mode drains original device network and preserves local cache", DeviceNetworkOfflineTests.Run),
    ("First-use cold online recovery preserves unknown credentials and requires original process exit", FirstUseColdOnlineRecoveryTests.Run),
    ("SCM achievement unlock detection and bounded daily refresh", ScmAchievementUnlockTests.Run),
    ("SCM achievement composed startup and native sink delivery", ScmAchievementCompositionTests.Run),
    ("Celebration queues private and rally audio until complete", CelebrationNotificationAudioTests.Run),
    ("Achievement new-grant delivery, deduplication and account expiry", () => { AchievementCelebrationTests.Run(); return Task.CompletedTask; }),
    ("Achievement sound bypasses DND but preserves explicit mute and verified gain", () => { AchievementCelebrationAudioTests.Run(); return Task.CompletedTask; }),
    ("Achievement composed route preserves account authority", CompositeBridgeDispatcherTests.RoutesAchievementRequests),
    ("Achievement confirmed cache survives refresh without locked-image flash", AchievementRuntimeTests.ConfirmedCacheNeverFlashesLocked),
    ("Achievement live game entry and another-device cloud restore", AchievementRuntimeTests.RecognitionAndDevices),
    ("Hangar achievement five ranks and simultaneous inventory ownership", HangarAchievementTests.Run),
    ("Achievement trusted grant survives local outbox cleanup failure", AchievementRuntimeTests.NewGrantSurvivesOutboxCleanupFailure),
    ("Achievement rejects mismatched or historical game evidence", AchievementRuntimeTests.InvalidGameEvidence),
    ("Achievement offline restart and lost cloud acknowledgement", AchievementRuntimeTests.OfflineRestartAndLostAcknowledgement),
    ("Achievement account transition and read-only Bridge protocol", AchievementRuntimeTests.AccountChangeDuringReadAndProtocol),
    ("Achievement pending storage corruption and owner isolation", AchievementRuntimeTests.CorruptOutboxAndIsolation),
    ("Achievement short game entry survives exit and respects retry backoff", AchievementRuntimeTests.ShortEntryAndRetryBackoff),
    ("Browser resume has encrypted explicit consent and current account isolation", MenuBrowserResumeTests.Verify),
    ("Screenshot directory uses native selection, encrypted local persistence and current-generation CAS", MenuScreenshotDirectoryTests.Verify),
    ("Menu hotkey lease lifecycle", MenuHotkeyBridgeTests.Run),
    ("Game startup shortcut hint", GameStartupHintTests.Run),
    ("Handle correction from existing offline game log", LegacyPasswordLoginTests.OfflineHandleChange),
    ("Handle mismatch remains actionable without inventing SCM binding", LegacyPasswordLoginTests.HandleMismatchProjection),
    ("Compatibility Handle change uses explicit one-use confirmation and verified readback", LegacyPasswordLoginTests.HandleChangeCompatibility),
    ("Identity mismatch desktop notifications are current and deduplicated", GameIdentityNotificationTests.Run),
    ("Social audio reaches authenticated private and friend events", SocialNotificationAudioTests.Run),
    ("Social activity cursor uses authenticated cancellable waits", SocialActivityReadTests.Run),
    ("Friend requests notify once with privacy-safe delivery", FriendRequestNotificationTests.Run),
    ("Community media and directory reads avoid duplicate upstream work", CommunityReadEfficiencyTests.Verify),
    ("Independent account reads retain mutation barriers and session isolation", AccountDispatchConcurrencyTests.Verify),
    ("Account timing separates queued roots without changing admission", AccountDispatchConcurrencyTests.ReadTiming),
    ("Help support history and public endpoints", HelpSupportTests.RunAll),
    ("Independent event preferences reuse isolated revisioned persistence", SharedEventPreferencesStoreTests.Run),
    ("Independent event transport confirms one write without fallback or replay", EventSharingTransportTests.Run),
    ("Live event source excludes history and discards withdrawn session events", SharedActivityEventSourceTests.Run),
    ("Independent event runtime sends new events and confirms withdrawal before recovery", EventSharingRuntimeTests.Run),
    ("Event receiver baselines and revokes queued notifications", SharedActivityReceiverTests.Run),
    ("Storage migration destination preflight is non-mutating", StorageMigrationDestinationTests.ValidateWithoutMutation),
    ("Storage migration switches locator only after verified copy and recovers interruptions", StorageMigrationTransactionTests.Verify),
    ("Storage completed recovery is read-only while retiring writers hold shared activity", StorageMigrationCompletedRecoveryTests.Verify),
    ("Storage selection confirms exact source and destination once without mutating data", StorageMigrationSelectionTests.Verify),
    ("Storage migration plan and durable result use a strict acknowledged protocol", StorageMigrationProtocolTests.Verify),
    ("WPF migration confirmation binds consent and prevents install replay", WpfMigrationConfirmationTests.Verify),
    ("WPF migration preflight is read-only and never authorizes removal", WpfMigrationPreflightTests.Verify),
    ("Flutter startup receipt rejects incomplete or mismatched evidence", FlutterStartupReceiptTests.Verify),
    ("Flutter updates isolate package identity, signatures and staging", FlutterUpdateTests.Verify),
    ("Installed updates retain registry, uninstaller and recoverable startup", InstalledUpdateTransactionTests.Verify),
    ("Flutter installer update checks preserve release identity and trust", FlutterInstallerUpdateTests.Verify),
    ("Flutter installer downloads preserve integrity, cancellation and publisher gates", FlutterInstallerDownloadTests.Verify),
    ("Flutter update transaction preserves rollback and recovers interrupted renames", FlutterUpdateTransactionTests.Verify),
    ("Flutter update checks enforce strict generation and read-only contracts", FlutterUpdateBridgeTests.Verify),
    ("Storage verified copy preserves source and rejects unsafe publication", StorageMigrationDestinationTests.VerifiedCopyPreservesSource),
    ("Exact client license and no writes", ClientLicenseTests.PreservesDocumentAndDoesNotWrite),
    ("First-use notice persists and reuses WPF acknowledgement", TestBuildNoticeTests.Verify),
    ("Missing client license never searches parent", ClientLicenseTests.MissingNeverSearchesParent),
    ("Invalid oversized and locked license is unreadable", ClientLicenseTests.RejectsInvalidOversizeAndLockedFiles),
    ("Client license is fixed and bounded", ClientLicenseTests.FixedFileOnlyAndReadOnlySharing),
    ("Client license strict device protocol", ClientLicenseTests.StrictDeviceProtocol),
    ("Client license cancellation generation and lifetime", ClientLicenseTests.CancellationGenerationAndLifetime),
    ("Overlay snapshot is read-only and routed exactly", OverlayRuntimeStatusTests.ReadOnlyBoundaryAndExactRouting),
    ("Overlay snapshot rejects stale cancelled disposed and failed reads", OverlayRuntimeStatusTests.StaleCancelledDisposedAndFailure),
    ("Composite routes runtime facts exactly", ApplicationRuntimeFactsTests.CompositeRoutesOnlyExactRuntimeRequest),
    ("Runtime facts use the configured executable without creating folders", ApplicationRuntimeFactsTests.ReadsOnlyConfiguredExecutableAndDoesNotCreateFolders),
    ("Runtime facts sanitize versions and server origins", ApplicationRuntimeFactsTests.VersionAndEndpointNeverLeakUntrustedText),
    ("Runtime facts Bridge is accountless and strict", ApplicationRuntimeFactsTests.BridgeIsAccountlessReadOnlyAndStrict),
    ("Runtime facts reject stale cancelled and disposed reads", ApplicationRuntimeFactsTests.StaleCancelledAndDisposedNeverReturnFacts),
    ("Runtime facts tolerate missing metadata", ApplicationRuntimeFactsTests.MissingMetadataDoesNotHideOtherFacts),
    ("Process journal ConfirmedLifecyclePersists", LocalGameProcessJournalTests.ConfirmedLifecyclePersists),
    ("Process journal UnknownRestartsExitConfirmation", LocalGameProcessJournalTests.UnknownRestartsExitConfirmation),
    ("Process journal UnknownRecoveryDoesNotInventStart", LocalGameProcessJournalTests.UnknownRecoveryDoesNotInventStart),
    ("Process journal FailedProbeIsNotExit", LocalGameProcessJournalTests.FailedProbeIsNotExit),
    ("Process journal ConcurrentReadsAreSerialized", LocalGameProcessJournalTests.ConcurrentReadsAreSerialized),
    ("Process journal ClearDuringProbeDoesNotResurrect", LocalGameProcessJournalTests.ClearDuringProbeDoesNotResurrect),
    ("Process journal AccountAndVersionDoNotDriveLifecycle", LocalGameProcessJournalTests.AccountAndVersionDoNotDriveLifecycle),
    ("Process journal DisposalDoesNotEmitExitOrOwnJournal", LocalGameProcessJournalTests.DisposalDoesNotEmitExitOrOwnJournal),
    ("Process journal StorageAndVersionFailuresDoNotBreakObservation", LocalGameProcessJournalTests.StorageAndVersionFailuresDoNotBreakObservation),
    ("Process journal BackwardClockAndSharedGameLogJournal", LocalGameProcessJournalTests.BackwardClockAndSharedGameLogJournal),
    ("GameLog journal WarmupThenRealEvents", GameLogJournalSourceTests.WarmupThenRealEvents),
    ("GameLog journal LifeEvidenceUsesSameParser", GameLogJournalSourceTests.LifeEvidenceUsesSameParser),
    ("GameLog journal InvalidIdentityAndAccountDoNotCommit", GameLogJournalSourceTests.InvalidIdentityAndAccountDoNotCommit),
    ("GameLog journal PauseResetAndPartialLines", GameLogJournalSourceTests.PauseResetAndPartialLines),
    ("GameLog catalog synthetic and absent data", GameLogLocationCatalogTests.SyntheticAndAbsentCatalog),
    ("GameLog journal ServerNavigationAndPrivateProjection", GameLogJournalSourceTests.ServerNavigationAndPrivateProjection),
    ("GameLog journal ClearAndAccountRace", GameLogJournalSourceTests.ClearAndAccountRace),
    ("GameLog journal RecoveryAndBoundedQueue", GameLogJournalSourceTests.RecoveryAndBoundedQueue),
    ("GameLog journal WpfPresentationParity", GameLogJournalSourceTests.WpfPresentationParity),
    ("GameLog journal MultiReadBatchPreservesEvents", GameLogJournalSourceTests.MultiReadBatchPreservesEvents),
    ("Local clear confirms device scope and uses shared writer", LocalEventClearBridgeTests.ExactScopeConfirmationAndSharedOwner),
    ("Local clear cancellation and disposal preserve records", LocalEventClearBridgeTests.CancellationAndDisposedAreNotSuccess),
    ("Shared WPF journal retains rules and one writer", SharedLocalEventJournalTests.ReusesWpfRulesAndSingleWriter),
    ("Shared journal clear commits primary and backup", SharedLocalEventJournalTests.ClearCommitsBothFilesAndNeverResurrects),
    ("Shared journal clear failures retain history", SharedLocalEventJournalTests.FailureAndCancellationKeepReadableHistory),
    ("Shared journal handles backup and corruption honestly", SharedLocalEventJournalTests.BackupOnlyAndCorruptionAreHonest),
    ("Shared journal queued saves do not resurrect cleared history", SharedLocalEventJournalTests.PendingPersistsCannotRestorePreClearState),
    ("Local event export has exact route and device scope", LocalEventExportTests.CompositeAndAccountlessPolicy),
    ("Local event export writes complete fresh UTF8 history", LocalEventExportTests.ExportsFreshCompleteHistoryWithBom),
    ("Local event export handles empty corrupt and backup sources", LocalEventExportTests.MissingEmptyCorruptAndBackup),
    ("Local event export rejects cancelled stale and cleared snapshots", LocalEventExportTests.CancelSwitchAndChangedSourceWriteNothing),
    ("Local event export protects destinations and failed commits", LocalEventExportTests.DestinationProtectionAndFailedCommit),
    ("Local event export serializes pickers and cancels lifetime", LocalEventExportTests.BusyCancellationAndDispose),
    ("Local event export validates device scoped requests", LocalEventExportTests.StrictDeviceScopeAndCancelledRequests),
    ("Local journal supports BOM and rejects torn writer reads", LocalEventJournalReaderTests.Utf8BomAndBusyWriterAreHandled),
    ("Local journal distinguishes missing and unreadable", LocalEventJournalReaderTests.MissingAndMalformedRemainDistinct),
    ("Local journal preserves WPF history without rewriting", LocalEventJournalReaderTests.WpfCompatibilityRetentionFilteringAndNoRewrite),
    ("Local journal reports backup without restoring", LocalEventJournalReaderTests.BackupIsExplicitAndNeverRestored),
    ("Local journal preserves identity dedup and bounded history", LocalEventJournalReaderTests.IdentityDedupAndBoundedLatestHistory),
    ("Local journal rejects untrusted and oversized data", LocalEventJournalReaderTests.LargeOrUntrustedDataDoesNotBecomeExportable),
    ("Local history paginates and filters within bounds", LocalEventHistoryBridgeTests.PaginationAndFilter),
    ("Local history rejects mixed revisions", LocalEventHistoryBridgeTests.RevisionChangesNeverMixPages),
    ("Local history preserves missing corrupt and backup states", LocalEventHistoryBridgeTests.MissingCorruptBackupAndRejectedQueries),
    ("Local history rejects cancelled stale and disposed reads", LocalEventHistoryBridgeTests.CancellationGenerationAndDispose),
    ("Local game events have an independent overlay source", LocalGameOverlayEventTests.Verify),
    ("Play reminder preserves WPF defaults and repeat", ContinuousPlayReminderTests.DefaultsAndRepeat),
    ("Play reminder disabling and reenabling", ContinuousPlayReminderTests.DisabledAndReenabled),
    ("Play reminder interval changes", ContinuousPlayReminderTests.IntervalChangeUsesSessionAndLastAccepted),
    ("Play reminder short restart and 15 minute reset", ContinuousPlayReminderTests.ShortRestartAndFifteenMinuteReset),
    ("Play reminder restores checkpoint", ContinuousPlayReminderTests.RestartRecoversCheckpoint),
    ("Play reminder suppression and failure backoff", ContinuousPlayReminderTests.SuppressionAndFailureAreBounded),
    ("Play reminder unknown and storage failure", ContinuousPlayReminderTests.UnknownAndStorageFailureDoNotNotify),
    ("Play reminder save invalidates pending queue", ContinuousPlayReminderTests.SaveInvalidatesPendingQueue),
    ("Play reminder Bridge revision and device scope", ContinuousPlayReminderTests.BridgePersistsWithRevisionAndRejectsAccount),
    ("Play reminder WPF file compatibility", ContinuousPlayReminderTests.WpfSettingsCompatibilityAndCorruption),
    ("Device audio preferences, integrity, gain and scoped preview", NotificationAudioTests.Run),
    ("Room audio observes authenticated fresh events without replay", RoomAudioTests.Run),
    ("Trade Windows notifications use live pushes with privacy and account fencing", TradeNotificationTests.Run),
    ("Direct message notice source suppresses history, own sends and stale accounts", DirectMessageNotificationObserverTests.Run),
    ("Local notification settings persist and gate authenticated room reminders", NotificationSettingsTests.Run),
    ("Desktop notification tickets enforce privacy, expiry and single delivery", DesktopNotificationTests.Run),
    ("Friend publication gates consent and retires uncertain sessions", FriendSharingPublicationTests.Verify),
    ("Friend sharing runtime binds real source lifecycle and remote policy", FriendSharingRuntimeTests.Run),
    ("Game ID settings reuse guarded profile transport without unrelated writes", GameIdSettingsTests.Run),
    ("SCM Handle privacy uses Java consent and preserves account authority", LegacyPasswordLoginTests.ScmHandlePrivacy),
    ("Room pause without policy persists and retries failed storage", SharingReviewRegressionTests.M04k),
    ("Room pause restart and admission timeout retry", SharingReviewRegressionTests.M04j),
    ("Privacy visibility observations persist across every read boundary", SharingReviewRegressionTests.M04f),
    ("Privacy publication projects independent realtime axes without inventory writes", PrivacyPublicationTests.Projection),
    ("Privacy publication requires explicit consent and retries withdrawal only", PrivacyPublicationTests.Lifecycle),
    ("Privacy publication serializes stop after in-flight writes", PrivacyPublicationTests.Ordering),
    ("Privacy publication validates S2 group ownership and policy acknowledgement", PrivacyPublicationTests.Wire),
    ("Organization sharing binds membership, preserves account grants and verifies acknowledgments", CommunitySharingTests.Verify),
    ("Communities bounded reads and scoped membership commands", CommunityClientTests.Verify),
    ("SCM community omitted logos retain bounded media loading", CommunityDeferredLogoTests.Verify),
    ("SCM account and sharing identity policy agree before game launch", () => { CompatibilityPublicationIdentityTests.Verify(); return Task.CompletedTask; }),
    ("Player activity sources require complete authorized identities", PlayerActivitySourcesTests.Verify),
    ("Player activity preserves every real transition without replay", PlayerActivityTransitionReliabilityTests.Run),
    ("Background social activity observes friends without a page", LegacyPasswordLoginTests.VerifyBackgroundPlayerActivity),
    ("Manual presence shares publication gate and preserves consent", ManualPresenceIntegrationTests.Verify),
    ("SCM realtime Host lifecycle and authority observation", ScmRealtimeLifecycleTests.Verify),
    ("Windows token vault lease and commit under concurrency", WindowsTokenVaultConcurrencyTests.Verify),
    ("Store commits under lease-free readers", StoreFileCommitTests.Verify),
    ("Realtime client retries after an unexpected attempt failure", RealtimeClientRecoveryTests.Verify),
    ("Direct message push hints preserve REST authority and legacy fallback", DirectMessageRealtimeHintTests.Verify),
    ("Community WPF S2 membership and roster read compatibility", CommunityWpfS2Tests.Verify),
    ("Community WPF S2 discovery preserves filters and public visibility", CommunityWpfS2DiscoveryTests.Verify),
    ("Image cache directory references rebind after actual Native maintenance", CommunityWpfS2DiscoveryTests.ImageMaintenanceReferences),
    ("Community WPF S2 multi-organization admission preserves other memberships", CommunityWpfS2DiscoveryTests.AdmissionCommands),
    ("Community WPF S2 chat and announcements reuse existing reads", CommunityWpfS2CommunicationTests.Verify),
    ("Community WPF S2 communication writes reuse original receipts", CommunityWpfS2WriteTests.Verify),
    ("Community WPF S2 ships preserve instances and existing filters", CommunityWpfS2ShipTests.Verify),
    ("Community WPF S2 admission reuses original membership flow", CommunityWpfS2AdmissionTests.Verify),
    ("Community WPF S2 invitations reuse original preview and confirmed admission", CommunityWpfS2InviteTests.Verify),
    ("Community WPF S2 ordinary exit verifies identity and never replays uncertainty", CommunityWpfS2LeaveTests.Verify),
    ("Community WPF S2 creation reuses the original snapshot contract and confirms ownership", CommunityWpfS2CreationTests.Verify),
    ("Community WPF S2 invitation cards reuse original generation and chat routes without unsafe replay", CommunityWpfS2InvitationSendTests.Verify),
    ("Community WPF S2 profile editing reuses the original full update without unsafe replay", CommunityWpfS2ProfileTests.Verify),
    ("Community WPF S2 admissions expose bounded management and reuse original decisions", CommunityWpfS2ManagementTests.Verify),
    ("Community WPF S2 governance preserves original permissions and one-shot mutations", CommunityWpfS2GovernanceTests.Verify),
    ("Community creation preserves WPF options and never replays an uncertain write", CommunityCreationClientTests.Verify),
    ("CX-L13 workspace member identity survives authorization lease expiry", CommunityMemberReferenceTests.WorkspaceLease),
    ("CX-L13b invisible announcement authors omit retained member references", CommunityMemberReferenceAuthorTests.InvisibleAnnouncementAuthors),
    ("CX-L13b full mapping reuses oldest member before adding a new member", CommunityMemberReferenceTests.CapacityReusesOldestBatch),
    ("CX-L13b official chat messages and author updates share usable sender references", CommunityMemberReferenceAuthorTests.ChatReferencesAgree),
    ("CX-L13 ships announcements and chat reuse workspace member identity", CommunityMemberReferenceTests.OtherIssuers),
    ("CX-L13 rejected reads cannot renew member authorization", CommunityMemberReferenceTests.RejectedReadsDoNotRenew),
    ("CX-L13 member references isolate organization and account generation", CommunityMemberReferenceTests.Isolation),
    ("CX-L13 leaving retires retained identities before rejoining", CommunityMemberReferenceTests.LeaveClears),
    ("CX-L13 member identities have sliding 24 hour retention", CommunityMemberReferenceTests.Retention),
    ("CX-L13 member identity capacity and disposal stay bounded", CommunityMemberReferenceTests.Capacity),
    ("CX-L13 official author identity lookup cannot authorize media", CommunityMemberReferenceTests.AuthorLookupDoesNotAuthorize),
    ("Community workspace protects identity, scope, pagination and media chunks", CommunityWorkspaceClientTests.Verify),
    ("Room and workspace ship labels use the Native vocabulary without expanding sharing", RuntimeShipLabelsTests.Verify),
    ("Community logs preserve bounded history, scope and single-attempt deletion", CommunityLogsClientTests.Verify),
    ("Community disband preserves credential authority and single-attempt confirmation", CommunityDisbandClientTests.Verify),
    ("Official chat archive keeps identities out of durable display", OfficialFleetChatArchiveTests.RunIsolated),
    ("Community chat preserves scoped pages and bounded original details", CommunityChatClientTests.Verify),
    ("Community announcements preserve scoped history and bounded original avatars", CommunityAnnouncementsClientTests.Verify),
    ("Community ships preserve private scoped instances and coherent pages", CommunityShipsClientTests.Verify),
    ("Official announcement native codec rejects uncorrelated outcomes", OfficialFleetAnnouncementManagementClientTests.RunAsync),
    ("Official fleet rally bridge keeps the counts-only projection", OfficialFleetRallyClientTests.RunAsync),
    ("Official fleet governance activation and account boundaries", OfficialFleetActivationClientTests.RunAsync),
    ("Official fleet projection negotiation preserves legacy Flutter shapes", OfficialFleetProjectionNegotiationTests.RunAsync),
    ("Official announcement durable recovery is protected bounded and non-replayed", OfficialFleetAnnouncementRecoveryTests.RunAsync),
    ("Community announcement writes bind intent and never replay uncertain operations", CommunityAnnouncementWriteClientTests.Verify),
    ("Community chat sending binds intent and reconciles lost replies without reposting", CommunityChatSendTests.Verify),
    ("Community profile preserves WPF fields and protects scoped editing intents", CommunityProfileClientTests.Verify),
    ("Community hangar sharing preserves scoped explicit choices and verifies saves", CommunityHangarSharingClientTests.Verify),
    ("Official own-sharing protects scoped inventory and one-shot grants", OfficialFleetHangarSharingClientTests.Run),
    ("Official public ships preserve typed source, identity deadlines and complete query semantics", OfficialFleetSharedShipsClientTests.Run),
    ("Hangar background publication retries only safe failures and cancels obsolete work", HangarAutoSyncTests.Verify),
    ("Local hangar save returns before remote publication and emits an isolated refresh", HangarAutoSyncIntegrationTests.Verify),
    ("Community roles protect definitions, revisions and uncertain writes", CommunityRolesClientTests.Verify),
    ("Community member role assignment protects identities and uncertain writes", CommunityMemberRoleClientTests.Verify),
    ("Community member removal scopes confirmation and uncertain writes", CommunityMemberRemovalClientTests.Verify),
    ("Community ownership transfer scopes confirmation and uncertain writes", CommunityOwnershipTransferClientTests.Verify),
    ("Community ownership exit binds intent and never replays uncertain departure", CommunityOwnershipTransferClientTests.VerifyExit),
    ("Community invitation preview and admission use scoped non-replayed intents", CommunityInviteClientTests.Verify),
    ("Community management queues and applicant media are scoped and bounded", CommunityAdmissionsClientTests.Verify),
    ("Community admission commands recheck authority and never replay uncertain writes", CommunityAdmissionCommandTests.Verify),
    ("Community invitation generation reconciles the same durable intent and enforces card permission", CommunityInvitationGenerationTests.Verify),
    ("Community invitation delivery verifies server support and confirms without replay", CommunityInvitationDeliveryTests.Verify),
    ("Invitation send journal survives failures and restarts without automatic replay", InvitationSendWorkflowTests.Verify),
    ("Invitation account Bridge binds current identity and safely projects recovery", InvitationAccountBridgeTests.Verify),
    ("Privacy publication fails closed on invalid acknowledgements and unreadable policy", PrivacyPublicationTests.FailClosed),
    ("Privacy publication rejection uses long backoff and accurate status", PrivacyPublicationTests.RejectedBackoff),
    ("Verified local owner recovery resumes only remembered sharing", S2CompatibilityReadTests.VerifySharingAfterOwnerRecovery),
    ("Privacy publication production timer automatically recovers", PrivacyPublicationRecoveryTests.AutomaticTimerRecovery),
    ("Privacy publication HTTP restart and session recovery", PrivacyPublicationRecoveryTests.ServerAndSessionRecovery),
    ("Privacy publication session failure retains user consent", PrivacyPublicationRecoveryTests.SessionAndFailureBoundaries),
    ("Sharing status distinguishes causes and bounds authorized recovery", SharingStatusDetailTests.Run),
    ("Privacy publication healthy heartbeat is silent", PrivacyPublicationRecoveryTests.SilentHeartbeat),
    ("Host queue timeout preserves remembered sharing consent", LegacyPasswordLoginTests.PrivacyQueueTimeoutKeepsConsent),
    ("Privacy publication automatically recovers from transport loss", PrivacyPublicationRecoveryTests.TransientDisconnect),
    ("Privacy publication remembers explicit account consent across restart", PrivacyPublicationRecoveryTests.Restart),
    ("Privacy publication revoked consent stays stopped across restart", PrivacyPublicationRecoveryTests.RevokedConsentRestart),
    ("Privacy consent storage, revocation and invisibility remain account-scoped", PrivacyConsentTests.Verify),
    ("Privacy publication recovery preserves consent and security boundaries", PrivacyPublicationRecoveryTests.Guards),
    ("Local privacy isolates owners and persists independent WPF axes", LocalPrivacyTests.Storage),
    ("Local privacy preserves corrupt records and rejects invalid audiences", LocalPrivacyTests.FailClosed),
    ("Local privacy bridge rejects stale consent without publication", LocalPrivacyTests.Contract),
    ("Local privacy account runtime routes and revokes local access", LocalPrivacyRuntimeScope),
    ("Confirmed visibility change wakes friend publication without heartbeat", PresenceChangeWakesFriendPublication),
    ("Overlay community source selects stable authorized targets", OverlayCommunitySourceTests.Selection),
    ("Overlay community communication baselines history and clears withdrawals", OverlayCommunitySourceTests.Communication),
    ("Overlay roster preferences persist and reject revoked or stale writes", OverlayRosterPreferencesTests.Run),
    ("Overlay community source recovers silently and revokes stale content", OverlayCommunitySourceTests.Recovery),
    ("Overlay community source rejects account and selection races", OverlayCommunitySourceTests.AccountAndLateResponses),
    ("Overlay community source coalesces reads and preserves redaction", OverlayCommunitySourceTests.CoalescingAndProjection),
    ("Overlay community source reads on demand and cancels on disposal", OverlayCommunitySourceTests.DemandAndDisposal),
    ("Overlay community driver recovers within bounded authorization", OverlayCommunityRefreshScheduleTests.Run),
    ("Overlay community roster does not wait for communication", OverlayCommunityProgressiveReadTests.Run),
    ("Overlay first frame reuses the client authorized workspace", LegacyPasswordLoginTests.OverlayReusesWorkspace),
    ("Overlay roster does not depend on management identity", LegacyPasswordLoginTests.OverlayRosterDoesNotWaitForManagementIdentity),
    ("Overlay shared workspace preserves lifetime, ordering and authority", OverlayWorkspaceReuseTests.Run),
    ("Overlay live changes avoid periodic sampling, publication and roster delays", OverlaySyncLatencyTests.Run),
    ("Optional WPF location display overrides preserve English and independent canonical locations", LocationDisplayCompatibilityTests.Run),
    ("Navigation targets use actual station names across the Host and Flutter bridge", NavigationStationDisplayTests.Run),
    ("Overlay scene choice bridge persistence and account isolation", OverlaySceneChoiceTests.BridgeAndPersistence),
    ("Overlay local choice bypasses slow catalog", OverlaySceneChoiceTests.LocalChoiceBypassesSlowCatalog),
    ("Overlay closed overlay keeps organization sources", OverlaySceneChoiceTests.ClosedOverlayKeepsOrganizationSources),
    ("Overlay F8C journal matches current session", GameLogJournalSourceTests.CurrentF8CMatchesJournal),
    ("Overlay scene choice store guards corruption and late writes", OverlaySceneChoiceTests.StoreGuards),
    ("Party rooms actual Host identity pipeline", LegacyPasswordLoginTests.RoomOverlayIdentityPipeline),
    ("Party room keepalive carries only Host-owned current membership", PartyRoomKeepaliveTests.Transport),
    ("Transient room reads preserve only the original valid overlay lease", LegacyPasswordLoginTests.RoomOverlayTransientReadPipeline),
    ("Game log ship names and cross-format release share catalog identity", GameLogJournalSourceTests.ShipNamesAndRelease),
    ("Party rooms actual Host peer avatar pipeline", LegacyPasswordLoginTests.RoomAvatarPipeline),
    ("Party rooms overlay only accepts current authorized membership", RoomOverlaySessionTests.Membership),
    ("Party room keepalive carries only Host-owned current membership", PartyRoomKeepaliveTests.Transport),
    ("Party rooms overlay clears revoked stale and expired content", RoomOverlaySessionTests.Revocation),
    ("Party rooms overlay chat baselines history and bounds live messages", RoomOverlaySessionTests.Chat),
    ("Public two-member room create and dual-view readback", PartyRoomReaderTests.PublicTwoMemberCreateReadback),
    ("Party rooms read projection protects membership and private fields", PartyRoomReaderTests.Projection),
    ("Party rooms display projects bounded avatars and explicit leader versions", PartyRoomDisplayTests.Projection),
    ("Party rooms rejects incomplete and contradictory data", PartyRoomReaderTests.InvalidData),
    ("Party rooms HTTP uses scoped bearer and safe bounded reads", PartyRoomReaderTests.HttpBoundary),
    ("Party rooms bridge requires current account and generation", PartyRoomsBridgeScope),
    ("Daily support receipts and authenticated non-replayed transport", DailySupportTests.Verify),
    ("Account safety reuses S2 appeal validation and rejects foreign fields", AccountSafetyRequestTests.Verify),
    ("Account safety reads preserve S2 facts without private report fields", AccountSafetyClientTests.Projection),
    ("Account safety transport is bounded scoped and cancellation safe", AccountSafetyClientTests.Transport),
    ("Account appeals reuse S2 intent and never replay uncertain writes", AccountSafetyClientTests.Submission),
    ("Selected profile import preserves explicit selection across transport", SelectedProfileImportTests.Run),
    ("Selected local profile import preserves unrelated fields and inventory references", SelectedLocalProfileImportTests.Run),
    ("Selected profile import recovery survives restart and preserves local edits", SelectedProfileImportRecoveryTests.Run),
    ("Friends read projection bounds data and hides private fields", FriendsReaderTests.Projection),
    ("SCM participant discovery and friend action preflight respect identity and privacy", LegacyPasswordLoginTests.ScmFriendDiscovery),
    ("SCM session enrolls only itself without replaying uncertain registration", LegacyPasswordLoginTests.ScmParticipantEnrollment),
    ("SCM participant root read does not wait for background discovery", LegacyPasswordLoginTests.ScmParticipantRootReadDoesNotWaitForDiscovery),
    ("SCM participant root read still waits for verified local owner", LegacyPasswordLoginTests.ScmParticipantRootReadStillWaitsForOwner),
    ("Avatar menus resolve authoritative scoped users without writes", AvatarInteractionTests.Verify),
    ("Friends read HTTP is scoped read-only and cancellation safe", FriendsReaderTests.HttpAndRequest),
    ("Friends read bridge enforces account and generation", FriendsBridgeScope),
    ("Friends commands cover all seven authoritative transitions", FriendCommandTests.Lifecycle),
    ("Friends commands reject stale targets and changed accounts before writing", FriendCommandTests.Guards),
    ("Friends commands never replay uncertain or concurrent writes", FriendCommandTests.FailureAndConcurrency),
    ("Direct messages enforce read-only paging and opaque targets", DirectMessageReadTests.Paging),
    ("Composed inbox reads reach the notification observer", CompositeBridgeDispatcherTests.ObservesDirectMessages),
    ("Private desktop messages honor settings and activation boundaries", DirectMessageDesktopTests.Run),
    ("Private messages reach enabled information overlay without replay or privacy leaks", DirectMessageOverlayTests.Run),
    ("CX81 direct unread counts, deduplication and read receipts", DirectUnreadOverlayTests.Summaries),
    ("CX81 direct unread preview and callsign limits", DirectUnreadOverlayTests.Privacy),
    ("CX81 direct unread account, source policy and overlay gates", DirectUnreadOverlayTests.Gates),
    ("CX81 direct unread full response and generation boundaries", DirectUnreadOverlayTests.ResponseBoundaries),
    ("CX81 direct unread lifecycle invalidation and sink failures", DirectUnreadOverlayTests.LifecycleAndFailures),
    ("Official fleet notifications reuse current authorized reads and the shared lifecycle", OfficialFleetNotificationTests.Run),
    ("Organization notification reads and source importance are bounded", CommunityNotificationTests.Run),
    ("Organization background delivery honors saved source policy", CommunityNotificationDeliveryTests.Run),
    ("Organization management sound honors saved policy and freshness", CommunityNotificationAudioTests.Run),
    ("Notification source policy bridge validates membership and account", NotificationPolicyBridgeTests.Run),
    ("Direct messages reject cross-account and malformed history", DirectMessageReadTests.Guards),
    ("Direct message privacy uses the existing account-scoped Relay contract", DirectMessagePrivacyTests.Verify),
    ("Friend request privacy defaults open and remains account scoped", FriendRequestPrivacyTests.Verify),
    ("Recently played privacy is revisioned and account scoped", RecentlyPlayedPrivacyTests.Verify),
    ("Direct messages confirm plain text sends and deduplicate intents", DirectMessageSendTests.Confirmation),
    ("Direct messages preserve uncertain outcomes without replay", DirectMessageSendTests.Failures),
    ("Direct messages recheck permission and identity before sending", DirectMessageSendTests.Guards),
    ("Party rooms commands avoid replay and re-read authoritative membership", PartyRoomReaderTests.Commands),
    ("Party rooms host transfer checks advertised capability and fresh authority", PartyRoomHostTransferTests.Authority),
    ("Party rooms host transfer confirms once and safely handles readback failure", PartyRoomHostTransferTests.Confirmation),
    ("Party rooms host transfer never replays unknown writes", PartyRoomHostTransferTests.Unknown),
    ("Party rooms command validation and uncertain responses fail safely", PartyRoomReaderTests.CommandValidation),
    ("Party rooms management protects host scope and password semantics", PartyRoomReaderTests.Management),
    ("Party rooms invitations scope targets and never replay writes", PartyRoomInvitationTests.Invitations),
    ("Party rooms chat protects membership cursors and uncertain sends", PartyRoomChatTests.Chat),
    ("Party rooms preset sharing preserves WPF format and additive import", OverlaySharedPresetTests.Sharing),
    ("Party rooms preset attachments validate before HTTP and retain unknown outcome", PartyRoomChatTests.Attachments),
    ("Overlay legacy configuration recovers finite complete rendering modules", OverlayConfigurationAuditTests.Run),
    ("Overlay v2 preset migration preserves policies and isolates transferred organizations", OverlayPresetMigrationTests.Run),
    ("Overlay appearance options follow local preset transactions and runtime", OverlayAppearanceOptionsTests.Run),
    ("Live appearance preview is isolated and session-owned", OverlayAppearancePreviewTests.Run),
    ("Common appearance preview preserves finite leases and receipt ownership", OverlayAppearanceLivePreviewTests.Run),
    ("Overlay module frames share reads and preserve per-source authority", OverlayModuleFrameTests.Run),
    ("Overlay module sources are named for the HUD without new authority", OverlayModuleSourceDisplayTests.Run),
    ("Overlay actual Host names module sources and account states", LegacyPasswordLoginTests.OverlaySourceDisplay),
    ("Overlay preset source Bridge preserves policy and draft isolation", OverlayPresetSourceBridgeTests.Run),
    ("Overlay temporary source session preserves draft and account isolation", OverlayTemporarySourceBridgeTests.Run),
    ("Overlay event subscription follows module source", LegacyPasswordLoginTests.OverlayEventSources),
    ("Overlay multi-community demand loads without a page", OverlaySyncLatencyTests.ModuleCommunityDemandWithoutFirstFrame),
    ("Overlay multi-community healthy sources renew through slow peers", OverlayCommunityModuleRefreshTests.SlowPeerDoesNotBlockRenewal),
    ("Overlay and client page share in-flight roster HTTP", LegacyPasswordLoginTests.OverlayAndPageShareInflightRoster),
    ("Overlay multi-community resources update and revoke independently", OverlayCommunityModuleRefreshTests.Run),
    ("Overlay shared workspace does not swallow new chat", OverlayCommunityModuleRefreshTests.WorkspaceObservationDoesNotSwallowChat),
    ("Overlay default Alt+O preserves saved bindings", OverlaySettingsTests.DefaultHotkeyPreservesSavedBindings),
    ("Overlay workspace reads every WPF setting and preset without mutation", OverlaySettingsTests.ReadsFullLegacyWorkspaceWithoutMutation),
    ("Overlay workspace defaults without creating legacy files", OverlaySettingsTests.DefaultsFullWorkspaceWithoutWriting),
    ("Overlay workspace saves legacy experimental render mode", OverlaySettingsTests.SavesWorkspaceLoadedFromLegacyExperimentalRenderMode),
    ("Overlay workspace writes atomically with backup and revision guard", OverlaySettingsTests.WritesFullWorkspaceWithBackupAndRevisionGuard),
    ("Overlay workspace supports every preset action", OverlaySettingsTests.ManagesEveryPresetAction),
    ("Overlay settings persist and reuse the current game session", OverlaySettingsTests.PersistsAndProjectsCurrentSession),
    ("Overlay runtime exposes native lifecycle and saved workspace", OverlaySettingsTests.ExposesRuntimeLifecycle),
    ("Overlay startup isolates incompatible migrated workspace", OverlayStartupIsolationTests.Run),
    ("Overlay runtime changes are pushed with the getState payload", OverlayRuntimeEventTests.Run),
    ("Overlay runtime carries saved module sources without trusting draft authority", OverlaySettingsTests.PassesSavedModuleSourcesToRuntime),
    ("Overlay settings reject stale writes and unavailable previews", OverlaySettingsTests.RejectsStaleAndUnsupportedRequests),
    ("Game log publication wakes only on meaningful live changes", GameLogRuntimeTests.PublicationWake),
    ("Game log offline recent identity without starting game", GameLogRuntimeTests.OfflineRecentIdentity),
    ("Game log current-session identity recognition", GameLogRuntimeTests.Recognition),
    ("Game log malformed UTF8 lines recover without false identity", GameLogRuntimeTests.MalformedUtf8Lines),
    ("Application support borrows scoped Game log selection", GameLogRuntimeTests.DiagnosticsSelection),
    ("Game log displays authoritative Handle casing", GameLogExpectedHandlePreservesCase),
    ("Game log automatic LIVE PTU selection and preserved choices", GameLogRuntimeTests.AutomaticVersions),
    ("Game log lifecycle, persistent choice and expiry", GameLogRuntimeTests.Lifecycle),
    ("Game log server and current ship stay local, scoped and evidence-based", GameLogRuntimeTests.SessionContext),
    ("Game log ownership, protocol and storage failures", GameLogRuntimeTests.OwnershipAndFailures),
    ("Game log bounded snapshots and rotation", GameLogRuntimeTests.LargeAndRotatedLogs),
    ("Gameplay time runtime consent, independent timer and reopen", GameplayTimeRuntimeTests.ConsentAndReopen),
    ("Compatible time preserves old ownership without duplicate leases", CompatibilityGameplayTimeTests.Verify),
    ("Gameplay time runtime ownership and protocol guards", GameplayTimeRuntimeTests.OwnershipAndProtocol),
    ("Gameplay time runtime storage failures, retry and exclusive writer", GameplayTimeRuntimeTests.StorageFailures),
    ("Gameplay time consent and ownership isolate account samples", GameplayTimeAccumulatorTests.ConsentAndOwnership),
    ("Gameplay time sampling excludes sleep and preserves WPF boundaries", GameplayTimeAccumulatorTests.Sampling),
    ("Gameplay time uncertainty and invalid storage stop accumulation", GameplayTimeAccumulatorTests.Uncertainty),
    ("Gameplay history one-time confirmation and migrated opportunity", GameplayHistoryRuntimeTests.OnceOnlyAndMigration),
    ("Gameplay reset journal and restored LIVE import", GameplayHistoryRuntimeTests.ResetRecovery),
    ("Gameplay reset requires scoped one-use confirmation", GameplayHistoryRuntimeTests.ResetBridgeConfirmation),
    ("Legacy entitlement transport and owner boundary", LegacyEntitlementTests.Verify),
    ("Legacy entitlement account lifecycle", LegacyPasswordLoginTests.EntitlementLifecycle),
    ("Global account avatar update and owner isolation", LegacyPasswordLoginTests.AvatarUpdate),
    ("SCM avatar comes from RSI only; custom upload refused", LegacyPasswordLoginTests.ScmAvatarWrite),
    ("SCM callsign Java ownership, grant and CAS", LegacyPasswordLoginTests.ScmCallSignWrite),
    ("Page presentation bounded transport and provenance", PagePresentationClientTests.Verify),
    ("Page presentation normal authority readback and isolation", LegacyPasswordLoginTests.ScmPagePresentationWrite),
    ("Hangar media transport preserves ownership and uncertain write outcomes", HangarMediaTransportTests.Verify),
    ("Profile visibility and background publication preserve owner boundaries", LegacyPasswordLoginTests.ProfileVisibility),
    ("Gameplay reset legacy transport and owner boundary", LegacyPasswordLoginTests.GameplayResetTransport),
    ("Gameplay history storage failure, cancellation and account guards", GameplayHistoryRuntimeTests.FailureAndOwnership),
    ("Gameplay history old snapshot and explicit preference compatibility", GameplayHistoryRuntimeTests.OldSnapshotCompatibility),
    ("Gameplay history scanner bounds, identity and interval semantics", GameplayHistoryScannerTests.Verify),
    ("Local game presence is independent, versioned and confirms process exit", LocalGamePresenceTests.Verify),
    ("Saved hangar catalog and exact-hash bundled images are safe optional display facts", HangarCatalogTests.Verify),
    ("Local personal profile preserves ownership and atomic saves", LocalPersonalProfileTests.Storage),
    ("Profile hangar presentation preserves explicit inventory and display-only status", ProfileHangarPresentationTests.Verify),
    ("Local favorite modules enforce capacity, global uniqueness and reopen", LocalPersonalProfileTests.FavoriteModules),
    ("Local collaboration validates roles, schedules, exact days and reopen", LocalPersonalProfileTests.Collaboration),
    ("Local profile reads pre-collaboration files without changing integrity", LocalPersonalProfileTests.PreviousFormat),
    ("Local personal profile bridge validates current owner and favorite references", LocalPersonalProfileTests.Contract),
    ("Real reader saves a verified local scan and reopens it without leaking source keys", LocalHangarBridgeTests.Verify),
    ("Local hangar storage protects identity, revisions and atomic persistence", LocalHangarStoreTests.Verify),
    ("Local hangar read failure separates busy storage from hard rejection", LocalHangarReadFailureTests.Verify),
    ("Hangar sandbox isolates credentials and rejects stale requests", HangarSandboxTests.GuardsAndProjection),
    ("Hangar live and complete previews use the bundled Chinese name catalog", HangarShipNameTests.Verify),
    ("Full RSI titles retain their Chinese model names", HangarShipNameTests.FullRsiTitles),
    ("Hangar verifies identity once and confines the locked scan", HangarLockedScanTests.Verify),
    ("Hangar in-app read-only preview rejects mismatches, stale callbacks and writes", HangarReaderDispatcherTests.ReadOnlyPreviewMatrix),
    ("Hangar reader compares the current SCM verified Handle without Game.log", HangarIdentityGuardTests.MatchesVerifiedSession),
    ("Hangar reader invalidates stale navigation observations", HangarIdentityGuardTests.NavigationInvalidatesObservation),
    ("Hangar reader cancels imports on account and environment changes", HangarIdentityGuardTests.AccountSwitchAndCancelInvalidateImport),
    ("Hangar reader rejects public profiles and malformed observations", HangarIdentityGuardTests.UntrustedDocumentsAndMessagesAreRejected),
    ("Headless Host negotiates Bridge v1 without WPF", HostNegotiatesVersionOne),
    ("Headless Host rejects incompatible protocol ranges", HostRejectsIncompatibleVersion),
    ("Composite Host routes personal profile reads and writes to the account owner", CompositeBridgeDispatcherTests.RoutesPersonalProfileRequests),
    ("Composite Host routes organization reads, writes and image selection", CompositeBridgeDispatcherTests.RoutesCommunityRequests),
    ("Organization logo bridge rejects paths and stale or concurrent image requests", CommunityLogoBridgeTests.Verify),
    ("Composite Host preserves settings routing and rejects unknown capabilities", CompositeBridgeDispatcherTests.PreservesOtherRoutes),
    ("Application preferences default and persist through the Host", ApplicationPreferencesTests.DefaultsAndPersistence),
    ("Application preferences persist holiday appearance independently", ApplicationPreferencesTests.HolidayAppearancePersistsIndependently),
    ("Application preferences reject invalid holiday values and unknown fields", ApplicationPreferencesTests.HolidayAppearanceRejectsInvalidPatches),
    ("Preview help acknowledgement preserves independent local preferences", ApplicationPreferencesTests.PreviewGuidePersistsIndependently),
    ("Application preferences publish committed native presentation language", ApplicationPreferencesTests.LivePresentationLanguage),
    ("Application preferences project legacy WPF behavior without a Desktop dependency", ApplicationPreferencesTests.LegacyApplicationBehaviorIsProjectedWithoutWpf),
    ("Application preferences keep older v1 files readable", ApplicationPreferencesTests.OlderV1PreferencesRemainReadable),
    ("Application preferences reject unsupported values without mutation", ApplicationPreferencesTests.InvalidUpdateFailsClosed),
    ("Application preferences recover corrupt local JSON to safe defaults", ApplicationPreferencesTests.CorruptFileRecoversToDefaults),
    ("Application preferences reject stale revisions without mutation", ApplicationPreferencesTests.RevisionConflictFailsClosed),
    ("Application preferences expose retryable read failures", ApplicationPreferencesTests.ReadFailureIsExplicitAndRetryable),
    ("Application preferences reject account context", ApplicationPreferencesTests.AccountContextIsRejected),
    ("Application preferences roll back Windows startup when saving fails", ApplicationPreferencesTests.StartupRegistrationRollsBackWhenSaveFails),
    ("Application preferences do not touch Windows startup before the first choice", ApplicationPreferencesTests.StartupRegistrationWaitsForTheFirstChoice),
    ("Application preferences apply an explicit startup decline only on continue", ApplicationPreferencesTests.DecliningStartupIsAppliedOnlyOnContinue),
    ("Windows startup command targets the Flutter client", () =>
    {
        ApplicationPreferencesTests.StartupCommandTargetsTheFlutterExecutable();
        return Task.CompletedTask;
    }),
    ("Flutter installation enforces ownership, confirmation and replay guards", FlutterInstallationMaintenanceTests.OwnershipConfirmationAndReplayGuards),
    ("Reused Explorer window reports open success", ApplicationSupportTests.ReusedExplorerWindowReportsOpenSuccess),
    ("Diagnostic connection probe is bounded and unauthenticated", ApplicationSupportTests.ConnectionProbeIsBoundedAndDoesNotAuthenticate),
    ("Cache cleanup preserves user and unknown files", () => { ApplicationSupportTests.CacheCleanupPreservesUserAndUnknownFiles(); return Task.CompletedTask; }),
    ("Image cache safety preserves prefix lookalikes", () => { ImageCacheMaintenanceSafetyTests.PrefixLookalikesArePreserved(); return Task.CompletedTask; }),
    ("Image cache safety preserves imported and user asset locations", () => { ImageCacheMaintenanceSafetyTests.ManagedTypesDoNotIncludeImportedOrUserAssets(); return Task.CompletedTask; }),
    ("Image cache safety handles an unused root without creation", () => { ImageCacheMaintenanceSafetyTests.MissingRootDoesNotCreateData(); return Task.CompletedTask; }),
    ("Image cache safety rejects invalid directory shapes", () => { ImageCacheMaintenanceSafetyTests.InvalidDirectoryShapesAreNotReportedAsEmpty(); return Task.CompletedTask; }),
    ("Image cache safety preflights linked candidates", () => { ImageCacheMaintenanceSafetyTests.LinksAreRejectedBeforeAnyCandidateIsRemoved(); return Task.CompletedTask; }),
    ("Image cache organization maintenance preserves metadata and excluded sources", ImageCacheOrganizationMaintenanceTests.ProtectedImagesAreClearedWithoutRemovingDirectory),
    ("Image cache organization maintenance rejects pre-clear directory images", ImageCacheOrganizationMaintenanceTests.OldDirectoryCannotRepersistImage),
    ("Image cache organization maintenance fences empty pending work", ImageCacheOrganizationMaintenanceTests.ZeroCountStillFencesPendingImages),
    ("Image cache organization maintenance preserves refusal and offline selection", ImageCacheOrganizationMaintenanceTests.RefusalAndOfflineSelectionRemainAuthoritative),
    ("Image cache organization maintenance rejects old media observation", ImageCacheOrganizationMaintenanceTests.OldMediaObservationCannotRepersistImage),
    ("Image cache organization maintenance fences late Native directory images", ImageCacheOrganizationMaintenanceTests.SlowNativeDirectoryCannotRefillMemory),
    ("Image cache organization maintenance retains pagination through image-only change", ImageCacheOrganizationMaintenanceTests.ContinuationSurvivesImageOnlyChange),
    ("Image cache organization maintenance rejects corrupt policy before file deletion", ImageCacheOrganizationMaintenanceTests.CorruptPolicyDoesNotReportSuccessOrDeleteLegacyFiles),
    ("Image cache organization maintenance fences media before first directory", ImageCacheOrganizationMaintenanceTests.MediaAdmittedBeforeFirstDirectoryIsFenced),
    ("Image cache organization maintenance uses actual Native multi-chunk media fence", FirstUseModeTests.ActualNativeMediaMaintenanceFence),
    ("Image cache organization maintenance rejects writer contention", ImageCacheOrganizationMaintenanceTests.WriterContentionCannotConfirmCleanup),
    ("Image cache organization maintenance rejects protected directory junction", ImageCacheOrganizationMaintenanceTests.ProtectedDirectoryJunctionIsRejectedBeforeDeletion),
    ("Application support projects a path-free diagnostic snapshot", ApplicationSupportTests.DispatcherProjectsStructuredSafeSnapshot),
    ("Data location is explicit and read-only", ApplicationSupportTests.DataLocationIsExplicitAndDoesNotCreateOrEnumerateData),
    ("Gameplay export whitelists current owner statistics", GameplayDataExportTests.ExportsOnlyWhitelistedCurrentStatistics),
    ("Gameplay export cancellation and account switch write nothing", GameplayDataExportTests.CancellationAndAccountSwitchWriteNothing),
    ("Gameplay export rejects unreadable statistics before picker", GameplayDataExportTests.InvalidDataDoesNotOpenPicker),
    ("Gameplay export protects existing files and owned storage", GameplayDataExportTests.ExistingFilesAndOwnedStorageAreProtected),
    ("Gameplay export prevents duplicate dialogs", GameplayDataExportTests.DuplicateRequestsDoNotOpenAnotherPicker),
    ("Gameplay export responds to cancellation", GameplayDataExportTests.CancellationTokenStopsBeforeWrite),
    ("Gameplay export rejects unsigned and injected requests", GameplayDataExportTests.RequestRequiresCurrentAccountAndNoInjectedData),
    ("Gameplay export removes uncommitted temporary files", () => { GameplayDataExportTests.FailedCommitCleansTemporaryFile(); return Task.CompletedTask; }),
    ("Gameplay export canonical route reuses statistics and cancels on switch", GameplayExportIntegrationTests.ReusesAccountOwner),
    ("Application support checks writable data and readable Game.log", () =>
    {
        ApplicationSupportTests.WindowsInspectorChecksFilesWithoutReturningPaths();
        return Task.CompletedTask;
    }),
    ("Application support distinguishes missing Game.log selection", () =>
    {
        ApplicationSupportTests.WindowsInspectorDistinguishesMissingLogSelection();
        return Task.CompletedTask;
    }),
    ("Application support opens only the owned data root", () =>
    {
        ApplicationSupportTests.WindowsInspectorOpensOnlyItsOwnedDataRoot();
        return Task.CompletedTask;
    }),
    ("Application support preserves valid portable installations", () =>
    {
        ApplicationSupportTests.InstallationClassificationPreservesPortableMode();
        return Task.CompletedTask;
    }),
    ("Application support parses the Flutter startup command", () =>
    {
        ApplicationSupportTests.StartupCommandParserAcceptsFlutterExecutable();
        return Task.CompletedTask;
    }),
    ("Application support inspection fails closed", ApplicationSupportTests.DispatcherFailsClosed),
    ("Application support rejects paths supplied by Flutter", ApplicationSupportTests.DispatcherOpensOwnedDirectoryWithoutAcceptingAPath),
    ("Named Pipe owner accepts a fresh Flutter connection after disconnect", PipeOwnerAcceptsReconnect),
    ("Long-running login does not block cancellation on the same connection", LongRunningLoginAcceptsCancellation),
    ("Saturated request queue returns explicit backpressure", SaturatedQueueReturnsBackpressure),
    ("Legacy proof HTTP outage retains its distinct failure classification", IdentityLinkProofOutageTests.Verify),
    ("S2 compatibility read preserves identity, isolation and closed provisioning", S2CompatibilityReadTests.Verify),
    ("Verified compatible login inherits local privacy without migration", S2CompatibilityReadTests.VerifyLocalPrivacyInheritance),
    ("S2 existing account link reuses proof, preserves manual choice and cancellation", S2ExistingAccountLinkTests.Verify),
    ("S2 account password recovery preserves anonymous WPF contract and secret boundaries", PasswordRecoveryTests.Verify),
    ("Retired legacy login projects a stable hint without writing credentials or changing SCM", LegacyPasswordLoginTests.Retirement),
    ("S2 legacy account login preserves credentials without granting SCM access", LegacyPasswordLoginTests.Verify),
    ("Bound legacy login and restart require SCM", LegacyPasswordLoginTests.BoundLoginRequiresScm),
    ("Legacy hangar migration Bridge isolates pages and account changes", LegacyPasswordLoginTests.HangarMigrationBridge),
    ("Legacy hangar selection requires explicit owner consent without writes", LegacyHangarSelectionTests.Verify),
    ("Headless account owner restores an empty vault as signed out", EmptyVaultProjectsSignedOut),
    ("Transient SCM restore failure preserves credentials and projects a retry state", TransientRestoreProjectsRecoverableState),
    ("Rejected SCM refresh credential is deleted and requires authorization", AccountSessionRestoreTests.RejectedCredentialProjectsReauthorization),
    ("Explicit refresh invalid_grant retires credentials without retry", AccountSessionRestoreTests.RefreshStatusRejection),
    ("Ambiguous refresh failures retain credentials and recover", AccountSessionRestoreTests.RefreshStatusTransient),
    ("Privacy refresh preserves transient credentials and existing backoff", () => AccountSessionRestoreTests.PrivacyRefresh()),
    ("SCM identity mismatch is contained as a reauthorization state", AccountSessionRestoreTests.IdentityMismatchProjectsReauthorization),
    ("First restored account root persists display at its Native generation", async () => { await AccountSessionRestoreTests.ColdFirstContent("none"); }),
    ("Authenticated cached avatar stays owner-scoped and optional", AccountSessionRestoreTests.AuthenticatedCachedAvatarGuards),
    ("First restored account display observes cancellation retirement and optional storage failure", AccountSessionRestoreTests.FirstRootDisplayObservationGuards),
    ("Restore display reads actual cached profile while token and identity requests are pending", async () =>
    {
        foreach (var stage in new[] { "token", "identity" })
        {
            var result = await AccountSessionRestoreTests.ColdFirstContent(stage);
            if (!result.LocalFirstObserved) throw new InvalidOperationException("Cached profile was not published while " + stage + " was held.");
        }
    }),
    ("Restore display withdraws cancelled retired and replaced credentials before late replies", AccountSessionRestoreTests.RestoreDisplayBoundaries),
    ("Restore display remains read-only through its own authenticated owner preparation", AccountSessionRestoreTests.RestoreDisplayOwnerPreparation),
    ("Restore display requires original credential and matching saved owner admission", AccountSessionRestoreTests.RestoreDisplayAdmission),
    ("Restore display completion preserves actual outage and rejection boundaries", AccountSessionRestoreTests.RestoreDisplayOutcomes),
    ("Restore display retires historical files when fresh local storage ownership changes", AccountSessionRestoreTests.RestoreDisplayStorageOwnerChange),
    ("Restore display opt-in validates finite schema without selecting an account", AccountSessionRestoreTests.RestoreDisplayOptionValidation),
    ("Cold SCM identity 401 rejects only the original credential and respects its writer", AccountSessionRestoreTests.UnauthorizedIdentityProjectsReauthorization),
    ("Runtime SCM invalidation advances generation and requires authorization", AccountSessionRestoreTests.RuntimeInvalidationProjectsReauthorization),
    ("Personal profile verification outage preserves the account without credential refresh", AccountSessionRestoreTests.PersonalProfileOutagePreservesAccount),
    ("SCM restore timeout is recoverable and never reports user cancellation", AccountSessionRestoreTests.RestoreTimeoutIsRecoverable),
    ("SCM offline display selection follows exact retained credential version", AccountSessionRestoreTests.OfflineDisplaySelection),
    ("SCM restore reuses a committed refresh while identity is temporarily unavailable", AccountSessionRestoreTests.UnavailableIdentityReusesCommittedRefresh),
    ("SCM rejected credential asks to sign in again after restart", AccountSessionRestoreTests.RejectedCredentialAsksToSignInAgainAfterRestart),
    ("Host test processes never fall back to the configured data root", () => { HostDataRootIsolationTests.Verify(); return Task.CompletedTask; }),
    ("Manual offline selection requires original retained credential", AccountSessionRestoreTests.ManualOfflineCredentialSelection),
    ("Offline avatar bytes survive avatar-only preparation and cold restart", FirstUseModeTests.OfflineAvatarSurvivesColdStart),
    ("Offline avatar read failure distinguishes denial from transient outage", FirstUseModeTests.OfflineAvatarReadFailure),
    ("Offline avatar survives a download outage after restart", FirstUseModeTests.OfflineAvatarSurvivesDownloadOutage),
    ("Offline avatar confirmed absent keeps the saved profile", FirstUseModeTests.OfflineAvatarConfirmedAbsent),
    ("Offline avatar cache preserves ownership protection and byte budgets", FirstUseModeTests.OfflineAvatarCacheGuards),
    ("Offline organization directory and logo bytes survive actual warm and cold reads", FirstUseModeTests.OfflineCommunityColdRead),
    ("Offline organization denial withdraws persisted display before warm and cold reads", FirstUseModeTests.OfflineCommunityDenialWithdraws),
    ("Offline organization denial withdraws locked persisted display before warm and cold reads", FirstUseModeTests.OfflineCommunityLockedDenialWithdraws),
    ("Offline organization read policy retains transient data and survives failed withdrawal writes", FirstUseModeTests.OfflineCommunityPolicyFaults),
    ("Offline organization read policy fences older success and refusal races", FirstUseModeTests.OfflineCommunityPolicyReadRaces),
    ("Offline organization read policy bounds consumers and isolates owner admission", FirstUseModeTests.OfflineCommunityPolicyBounds),
    ("Offline organization read policy preserves failed withdrawal across independent stores", FirstUseModeTests.OfflineCommunityCrossStoreFailedWithdrawal),
    ("Offline organization actual reads preserve transient cache and guard admission failures", FirstUseModeTests.OfflineCommunityReadAdmissionAndTransient),
    ("Offline organization writer contention waits for a brief ordinary cache write", FirstUseModeTests.OfflineCommunityWriterContention),
    ("Offline organization writer contention preserves cancellation before remote IO", FirstUseModeTests.OfflineCommunityWriterWaitCancellation),
    ("Offline organization writer contention rechecks retirement before remote IO", FirstUseModeTests.OfflineCommunityWriterWaitRetirement),
    ("Offline organization writer contention remains bounded without unprotected HTTP", FirstUseModeTests.OfflineCommunityWriterWaitBounded),
    ("Offline organization actual late HTTP success cannot revive a refusal", FirstUseModeTests.OfflineCommunityLateHttpSuccess),
    ("Offline organization read policy survives actual process exit and failed refusal publication", FirstUseModeTests.OfflineCommunityPolicyActualProcess),
    ("Offline organization display isolates owners and retired writes, bounds pages and media, and heals corruption", FirstUseModeTests.OfflineCommunityGuards),
    ("Offline organization deferred media publishes only complete matching content", FirstUseModeTests.OfflineCommunityDeferredLogo),
    ("Organization directory read failures classify modern and legacy transport without retaining caller cancellation", CommunityDirectoryFailureTests.Classify),
    ("Organization directory read failures cross the actual runtime without retiring the root owner", CommunityDirectoryFailureTests.ActualRuntime),
    ("Network-outage Bridge retains only exact-owner display", AccountSessionRestoreTests.NetworkOutageRetainsDisplayThroughBridge),
    ("Offline organization pagination keeps exact snapshot and missing-page semantics", OfflineCommunityPaginationTests.Run),
    ("SCM restore cannot replace a concurrent login", AccountSessionRestoreTests.RestoreCannotReplaceConcurrentLogin),
    ("SCM restore caller cancellation remains cancelled", AccountSessionRestoreTests.RestoreCallerCancellationRemainsCancelled),
    ("Concurrent delayed unauthorized responses reuse the refreshed session", AccountSessionRestoreTests.ConcurrentUnauthorizedRefresh),
    ("Account completion allows bounded slow upstream responses", AccountCompletionTimeoutTests.SlowCompletionCanFinish),
    ("Account completion preserves cancellation and finite HTTP deadlines", AccountCompletionTimeoutTests.CancellationAndHttpDeadlineStillStop),
    ("Resource reads deliver slow valid profiles through their real callers", ResourceReadTimeoutTests.SlowReadsReachTheirCallers),
    ("Resource reads report timeout as retryable and retain the signed-in account", ResourceReadTimeoutTests.TimeoutIsRetryableWithoutLosingAccount),
    ("Resource reads preserve explicit caller cancellation", ResourceReadTimeoutTests.CallerCancellationStillStopsRead),
    ("Resource reads bound deadlines and preserve writes and queued account context", ResourceReadTimeoutTests.FiniteBudgetsAndQueueKeepTheirBoundaries),
    ("Unconfigured Host defaults to the production environment", UnconfiguredHostUsesProductionDefaults),
    ("Regional discovery failures preserve the configured SCM fallback", ScmRegionFallbackTests.Verify),
    ("Regional login failures select overseas on next startup", ScmRouteStateTests.LoginFailures),
    ("Regional preferences and safe bridge projections", ScmRouteStateTests.PreferencesAndBridge),
    ("SCM section 9 offline Host contracts", ScmSpecSection9Tests.Run),
    ("SCM spec H1-H3: stable chat ids, business codes on direct DTOs, no server text in logs", ScmSpecHostTests.Run),
    ("Production Host rejects retained loopback service routes", ProductionHostRejectsLoopbackRoutes),
    ("Production account access can be explicitly disabled", ProductionAccountAccessCanBeExplicitlyDisabled),
    ("SCM runtime isolates production and IDEA development accounts", ScmRuntimeIsolatesProductionAndDevelopment),
    ("SCM regional routing preserves the stable account environment", ScmRegionalRoutePreservesStableEnvironment),
    ("Account lifecycle and scoped profile actions retain the retired-operation gate", AccountLifecycleIsEnabled),
    ("Account preference action crosses the real runtime gate", AccountPreferenceRuntimeRoute),
    ("Account profile cache action crosses the real runtime gate", AccountProfileCacheRuntimeRoute),
    ("Account preference write confirms without replacing the login", AccountPreferenceActionTests.SaveConfirmsWithoutReplacingLogin),
    ("Account preference confirmed write survives cache persistence failure", AccountPreferenceActionTests.ConfirmedWriteSurvivesCacheFailure),
    ("Account preference confirmed write does not reread auxiliary directory", AccountPreferenceActionTests.ConfirmedWriteDoesNotReadDirectory),
    ("Account preference cancellation reconciles the remote value without replay", AccountPreferenceActionTests.CancelledConfirmationDoesNotReplayWrite),
    ("Account preference authorization failures never write", AccountPreferenceActionTests.AuthorizationFailuresDoNotWrite),
    ("Account preference invalid inputs and stale contexts fail closed", AccountPreferenceActionTests.BadRequestsNeverAuthorize),
    ("Account preference write failure preserves cache and supports retry", AccountPreferenceActionTests.SaveFailureKeepsCacheAndCanRetry),
    ("Account profile cache clear is local and account-isolated", AccountPreferenceActionTests.ClearIsLocalAndIsolated),
    ("Account profile cache failure remains visible and retryable", AccountPreferenceActionTests.ClearFailureIsNotReportedAsSuccess),
    ("Account preference unconfirmed writes recover through a normal read", AccountPreferenceActionTests.UnconfirmedSaveNeverReplacesCache),
    ("Account preference browser decline retains callback state validation", AccountPreferenceActionTests.BrowserDeclineKeepsCallbackStateProtection),
    ("Account settings profile cache retains only explicitly transient read failures", AccountPreferenceActionTests.ReadCacheFailureMatrix),
    ("Account settings profile cache preserves fresh network content on disk failure", AccountPreferenceActionTests.ReadCacheWriteFailure),
    ("Account settings profile cache cannot revive rejected content after a failed delete", AccountPreferenceActionTests.ReadCacheHardDenial),
    ("Account settings profile read cancellation and retirement do not restore authorization", AccountPreferenceActionTests.ReadCacheLifecycle),
    ("Account settings profile cache follows confirmed preference writes and explicit clears", AccountPreferenceActionTests.ReadCacheMutations),
    ("Account profile persistent cache cleans only owned temporary files and isolates subjects", ScmProfileCacheStorageTests.Storage),
    ("Account profile persistent cache coordinates independent writer processes without blocking readers", ScmProfileCacheStorageTests.Processes),
    ("Account profile persistent cache validates bounded opaque owner data", ScmProfileCacheStorageTests.OwnerAndBounds),
    ("Account profile persistent cache recovers its owned files after an interrupted writer", ScmProfileCacheStorageTests.InterruptedWriter),
    ("Account staged profile cached display is local and strictly scoped", AccountPreferenceActionTests.StagedCacheIsLocalAndScoped),
    ("Account staged profile fresh display does not read auxiliary directory", AccountPreferenceActionTests.StagedLiveDoesNotReadDirectory),
    ("Account staged profile public directory neither blocks account IO nor survives retirement", AccountPreferenceActionTests.StagedDirectoryIsIndependentAndRetired),
    ("Account staged profile cancellation reaches actual pipe HTTP and frees private account queue", AccountPreferenceActionTests.StagedPipeCancellationReachesHttp),
    ("Account staged profile cancellation prevents queued private IO before worker admission", AccountPreferenceActionTests.StagedPipeCancelsBeforeQueueAdmission),
    ("Account staged profile bounded local display retains capacity with every ordinary pipe worker held", AccountPreferenceActionTests.StagedPipeLocalDisplayHasCapacity),
    ("Account staged profile canceled work still delivers independent real account retirement", AccountPreferenceActionTests.StagedPipePreservesIndependentRootRetirement),
    ("Account staged profile cancellation cannot cross pipe connections or cancel writes", AccountPreferenceActionTests.StagedPipeCancellationCannotCrossConnectionOrWrite),
    ("Account staged profile public directory failures never retire or clear independent private data", AccountPreferenceActionTests.StagedDirectoryFailuresStayIndependent),
    ("Account staged profile cancellation keeps ownership through actual callback completion", AccountPreferenceActionTests.StagedReadCancellationOwnsCallbackExit),
    ("Account staged profile confirmed memory remains visible while older disk data is suppressed", AccountPreferenceActionTests.StagedConfirmedMemorySurvivesSuppressedDisk),
    ("Account staged profile confirmed preference response and cache share the real observation time", AccountPreferenceActionTests.StagedConfirmedWriteObservationIsShared),
    ("Official fleet V2 observations retain original per-row deadlines", () => OfficialFleetIdentityObservationTests.Run()),
    ("Official fleet existing SCM reads preserve scope and unknown private facts", OfficialFleetReadTests.Run),
    ("Official fleet read failures distinguish transient transport and invalid authorization or data", OfficialFleetReadTests.Failures),
    ("Official fleet optional profile failures preserve identity with independent read metadata", OfficialFleetReadTests.ProfileReads),
    ("Official fleet identity and other reads do not wait for deferred public profile IO", OfficialFleetReadTests.DeferredProfile),
    ("Official fleet production Runtime admits existing member and communication routes", OfficialFleetReadTests.RuntimeFleetRoutes),
    ("Official fleet deferred public read cannot delay logout events or cross retirement", OfficialFleetReadTests.DeferredProfileLifecycle),
    ("Official fleet communication dispatcher preserves scope and retirement", OfficialFleetCommunicationBridgeTests.Run),
    ("CX-PREVIEW-BRAKE context, single read, references, validation and error mapping", OfficialFleetPreviewAuthorTests.Run),
    ("CX-CHAT-COST surfaces, bounds, references and old relay compatibility", OfficialFleetPreviewAuthorTests.ChatRenewalContract),
    ("CX-CHAT-COST archive and uncertain send confirmation", OfficialFleetPreviewAuthorTests.ChatRenewalArchiveAndConfirmation),
    ("CX-CHAT-COST exact brake fallback and unavailable renewal", OfficialFleetPreviewAuthorTests.ChatAuthorsBrakeFallback),
    ("CX-CHAT-LAPSED announcements expired remain unavailable", () => CommunityMemberReferenceAuthorTests.LapsedAnnouncementAuthors(-6)),
    ("CX-CHAT-LAPSED announcements future remain unavailable", () => CommunityMemberReferenceAuthorTests.LapsedAnnouncementAuthors(2)),
    ("Official fleet projection preserves SCM authority and rejects invalid ranks", OfficialFleetProjectionPreservesAuthority),
    ("Official fleet projection distinguishes missing and conflicting membership", OfficialFleetProjectionRejectsAmbiguousMembership),
    ("SCM bootstrap projects only account-scoped active overlay appearances", ScmBootstrapProjectsOverlayEntitlements),
    ("Automatic token refresh revalidates overlay qualification without stale or cross-account grants", OverlayEntitlementRefreshTests.Verify),
    ("Personal profile reads from the Java resource service without Relay", JavaPersonalProfileReadsWithoutRelay),
    ("Personal profile writes to Java with optimistic revision", JavaPersonalProfileWritesWithRevision),
    ("Manual migration uses Java and preserves scoped confirmation payload", LegacyProfileMigrationWire),
    ("Manual migration crosses the real runtime gate before reaching the account owner", LegacyProfileMigrationRuntimeRoute),
    ("Legacy Relay lease uses SCM bearer and reads the owner profile", LegacyRelayLeaseReadsOwnerProfile),
    ("Legacy Relay lease rejects a mismatched linked account", LegacyRelayLeaseRejectsAccountMismatch),
    ("Final Host layers remain independent from Desktop and WPF", HostLayersRemainWpfIndependent)
};

tests = tests.Concat(AppStatsHeartbeatTests.Cases).Concat(SharingReviewRegressionTests.VisibilityResumeCases)
    .Concat(OfficialHangarDiagnosticTests.Cases).Concat(PublicationReceiptDiagnosticTests.Cases)
    .Concat(OfficialFleetReadTests.MemberDiagnosticCases())
    .Concat(OfficialFleetEntryDiagnosticTests.Cases()).Concat(OfficialFleetActivationDiagnosticTests.Cases())
    .Concat(OfficialHangarShapeDiagnosticTests.Cases()).Concat(OfficialAnnouncementDiagnosticTests.Cases())
    .Concat(OfficialChatAuthorDiagnosticTests.Cases()).ToArray();

var failures = new List<string>();
var executed = 0;
foreach (var (name, test) in tests)
{
    if (args.Length == 2 && args[0] == "--filter" &&
        !name.Contains(args[1], StringComparison.OrdinalIgnoreCase))
    {
        continue;
    }
    executed++;
    try
    {
        await test();
        Console.WriteLine($"PASS {name}");
    }
    catch (Exception exception)
    {
        failures.Add($"{name}: {exception}");
        Console.WriteLine($"FAIL {name}: {exception.Message}");
    }
}

if (executed == 0)
{
    Console.Error.WriteLine("No test matched the requested filter.");
    return 1;
}
Console.WriteLine($"SUMMARY PASS {executed - failures.Count}/{executed}");
if (failures.Count != 0)
{
    Console.WriteLine();
    foreach (var failure in failures)
    {
        Console.WriteLine(failure);
    }

    return 1;
}

return 0;

static async Task HostNegotiatesVersionOne()
{
    using var dispatcher = new HostBridgeDispatcher("host-test", () => 7);
    var request = HelloRequest("hello-1");
    var batch = await dispatcher.DispatchAsync(request);
    AssertEqual(BridgeResponseStatuses.Ok, batch.Response.Status, "response status");
    AssertEqual(1, batch.Response.Payload.GetProperty("selectedProtocol").GetInt32(), "selected protocol");
    AssertEqual("host-test", batch.Response.Payload.GetProperty("hostInstanceId").GetString(), "host instance");
    AssertEqual(7L, batch.Response.Payload.GetProperty("sessionGeneration").GetInt64(), "generation");
    AssertEqual(1, batch.Response.Payload.GetProperty("hostCapabilities").GetArrayLength(), "capability count");
}

static async Task HostRejectsIncompatibleVersion()
{
    using var dispatcher = new HostBridgeDispatcher("host-test");
    var request = BridgeEnvelope.Request(
        "host.hello",
        "hello-incompatible",
        0,
        new
        {
            protocols = new { minimum = 2, maximum = 3 },
            capabilities = Array.Empty<string>()
        });
    var batch = await dispatcher.DispatchAsync(request);
    AssertEqual(BridgeResponseStatuses.Error, batch.Response.Status, "response status");
    AssertEqual(
        BridgeErrorCodes.ProtocolIncompatible,
        batch.Response.Error?.Code,
        "stable error code");
}

static async Task PipeOwnerAcceptsReconnect()
{
    var pipeName = $"starbridge-host-test-{Guid.NewGuid():N}";
    using var dispatcher = new HostBridgeDispatcher("host-reconnect");
    await using var server = new NativeHostPipeServer(pipeName, dispatcher);
    using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(10));
    var serverTask = server.RunAsync(lifetime.Token);

    await RoundTrip(pipeName, "first");
    await RoundTrip(pipeName, "second");

    lifetime.Cancel();
    await serverTask;
}

static async Task LongRunningLoginAcceptsCancellation()
{
    var pair = InMemoryBridgeConnection.CreatePair();
    using var dispatcher = new CancellableLoginDispatcher();
    using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    var server = NativeHostPipeServer.ServeConnectionAsync(
        pair.Right,
        dispatcher,
        lifetime.Token);

    await pair.Left.SendAsync(
        BridgeEnvelope.Request(
            "account.login",
            "login-pending",
            0,
            new { schemaVersion = 1 }),
        lifetime.Token);
    await dispatcher.LoginStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));
    await pair.Left.SendAsync(
        BridgeEnvelope.Request(
            "account.cancelLogin",
            "login-cancel",
            0,
            new { schemaVersion = 1 }),
        lifetime.Token);

    var responses = new Dictionary<string, BridgeEnvelope>(StringComparer.Ordinal);
    await foreach (var response in pair.Left
        .ReadAllAsync(lifetime.Token)
        .WithCancellation(lifetime.Token))
    {
        responses[response.CorrelationId!] = response;
        if (responses.Count == 2)
        {
            break;
        }
    }

    AssertEqual(BridgeResponseStatuses.Ok, responses["login-cancel"].Status, "cancel status");
    AssertEqual(BridgeResponseStatuses.Error, responses["login-pending"].Status, "login status");
    AssertEqual(
        "account.login_cancelled",
        responses["login-pending"].Error?.Code,
        "login cancellation code");

    lifetime.Cancel();
    await pair.Left.DisposeAsync();
    try
    {
        await server;
    }
    catch (OperationCanceledException) when (lifetime.IsCancellationRequested)
    {
        // Expected when the test closes the synthetic connection.
    }
}

static async Task SaturatedQueueReturnsBackpressure()
{
    var pair = InMemoryBridgeConnection.CreatePair(capacity: 512);
    using var dispatcher = new BlockingRequestDispatcher(requiredStarts: NativeHostPipeServer.RequestWorkerCount);
    using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    var server = NativeHostPipeServer.ServeConnectionAsync(
        pair.Right,
        dispatcher,
        lifetime.Token);

    for (var index = 0; index < NativeHostPipeServer.RequestWorkerCount; index++)
    {
        await pair.Left.SendAsync(
            BridgeEnvelope.Request(
                "test.blocking",
                $"running-{index}",
                0,
                new { schemaVersion = 1 }),
            lifetime.Token);
    }

    await dispatcher.RequiredRequestsStarted.Task.WaitAsync(TimeSpan.FromSeconds(2));

    for (var index = 0; index <= BridgeProtocol.DefaultQueueCapacity; index++)
    {
        await pair.Left.SendAsync(
            BridgeEnvelope.Request(
                "test.blocking",
                $"queued-{index}",
                0,
                new { schemaVersion = 1 }),
            lifetime.Token);
    }

    var response = await ReadNext(pair.Left);
    AssertEqual(
        $"queued-{BridgeProtocol.DefaultQueueCapacity}",
        response.CorrelationId,
        "rejected request correlation");
    AssertEqual(BridgeResponseStatuses.Error, response.Status, "backpressure response status");
    AssertEqual(
        BridgeErrorCodes.Backpressure,
        response.Error?.Code,
        "stable backpressure code");
    AssertEqual(true, response.Error?.Retryable, "backpressure retryable flag");

    dispatcher.Release();
    await pair.Left.DisposeAsync();
    await server;
}

static async Task PresenceChangeWakesFriendPublication()
{
    var root = CreateIsolatedDataRoot();
    try {
        var host = new LifecycleAccountHost();
        await host.LoginAsync(default);
        using var runtime = new AccountBridgeRuntime(host);
        var store = new StarBridge.HostRuntime.Settings.PresenceVisibilityStore(root);
        store.Save(StarBridge.Core.Presence.PlayerPresenceVisibilityMode.Invisible, store.Read().Revision, () => {});
        var bridge = new StarBridge.HostRuntime.Settings.PresenceVisibilityBridge(store,
            () => (host.CurrentContext, host.Generation),
            async (_, _, change, token) => { await change(token); return true; },
            (_, _, mode, _) => Task.FromResult(mode));
        var remote = new FriendSharingRuntimeTests.Remote();
        var publisher = new StarBridge.HostRuntime.Privacy.FriendSharingRuntime(remote,
            () => new(host.CurrentContext!, host.Generation, "Fixture", true, null,
                StarBridge.HostRuntime.Presence.GameLogSessionSnapshot.Empty),
            () => true, () => bridge.PublicationMode, false);
        // Inject timer-free, synthetic authority at the composition seam. The
        // production DispatchAsync route must do the wake; no test wake is sent.
        const System.Reflection.BindingFlags flags = System.Reflection.BindingFlags.Instance | System.Reflection.BindingFlags.NonPublic;
        typeof(AccountBridgeRuntime).GetField("_presenceVisibility", flags)!.SetValue(runtime, bridge);
        typeof(AccountBridgeRuntime).GetField("_friendSharing", flags)!.SetValue(runtime, publisher);
        var request = BridgeEnvelope.Request("presence.set", "wake-fixture", host.Generation,
            new { schemaVersion = 1, expectedRevision = store.Read().Revision, mode = "online" }, host.CurrentContext);
        var reply = await runtime.DispatchAsync(request);
        AssertEqual("ready", reply.Response.Payload.GetProperty("state").GetString(), "visibility confirmed");
        AssertEqual(1, remote.Sources.Count, "confirmed online wakes friends without waiting for timer");
        AssertEqual("AppOnline", remote.Sources.Single().Presence, "fresh friend source");
        var before = remote.Calls.Count;
        await runtime.DispatchAsync(request); // stale revision must not publish
        AssertEqual(before, remote.Calls.Count, "rejected visibility write does not wake publication");
    } finally { Directory.Delete(root, true); }
}

static async Task LocalPrivacyRuntimeScope()
{
    var directory = CreateIsolatedDataRoot();
    try
    {
        var host = new LifecycleAccountHost();
        await host.LoginAsync(default);
        using var runtime = new AccountBridgeRuntime(host, privacy: new StarBridge.HostRuntime.Privacy.LocalPrivacyStore(directory));
        var request = BridgeEnvelope.Request("privacy.localRead", "privacy-scope", host.Generation,
            new { schemaVersion = 1 }, host.CurrentContext);
        AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(request)).Response.Status, "local privacy routed");
        AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("privacy.local"), "local capability advertised");
        var save = BridgeEnvelope.Request("privacy.localSave", "privacy-save", host.Generation,
            new { schemaVersion = 1, expectedRevision = 0, operationId = Guid.NewGuid().ToString("N"),
                settings = StarBridge.HostRuntime.Privacy.LocalPrivacySettings.EditorDefaults }, host.CurrentContext);
        AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(save)).Response.Status, "local save routed");
        AssertEqual(0, host.PreferenceWrites, "no remote preference writer");
        AssertEqual(0, host.RoomCommands, "no room publication command");
        var status = BridgeEnvelope.Request("privacy.publicationStatus", "privacy-status", host.Generation,
            new { schemaVersion = 1 }, host.CurrentContext);
        AssertEqual("inactive", (await runtime.DispatchAsync(status)).Response.Payload.GetProperty("state").GetString(), "saved settings never activate publication");
        var injected = status with { Payload = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, online = true }) };
        AssertEqual("privacy_publication.invalid_request", (await runtime.DispatchAsync(injected)).Response.Error?.Code, "Flutter cannot author live state");
        await host.LogoutAsync(host.CurrentContext!, default);
        AssertEqual("privacy_publication.account_changed", (await runtime.DispatchAsync(status)).Response.Error?.Code, "logout revokes publication status");
        AssertEqual("privacy_local.account_changed", (await runtime.DispatchAsync(request)).Response.Error?.Code, "logout revokes local access");
        await host.LoginAsync(default);
        AssertEqual("privacy_local.account_changed", (await runtime.DispatchAsync(save)).Response.Error?.Code, "relogin rejects old lease");
        var latest = request with { SessionGeneration = host.Generation, AccountContext = host.CurrentContext };
        AssertEqual(1L, (await runtime.DispatchAsync(latest)).Response.Payload.GetProperty("revision").GetInt64(), "same owner reopens local record");
        runtime.Dispose();
        // The runtime-wide retirement gate rejects before any local dispatcher.
        AssertEqual("account.local_mode", (await runtime.DispatchAsync(latest)).Response.Error?.Code, "disposed runtime cannot read settings");
    }
    finally { Directory.Delete(directory, recursive: true); }
}

static async Task FriendsBridgeScope()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(default);
    using var runtime = new AccountBridgeRuntime(host);
    AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("friends.read"), "Friends advertised");
    var activity = BridgeEnvelope.Request("presence.activity", "activity", host.Generation,
        new { schemaVersion = 1, away = true }, host.CurrentContext);
    AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(activity)).Response.Status,
        "Account-scoped app inactivity is accepted without changing settings.");
    foreach (var invalid in new[] {
        activity with { SessionGeneration = host.Generation - 1 },
        activity with { AccountContext = new BridgeAccountContext("test", "scm", "other") },
        activity with { Payload = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, away = "true" }) },
        activity with { Payload = System.Text.Json.JsonSerializer.SerializeToElement(new { schemaVersion = 1, away = true, handle = "injected" }) }
    }) AssertEqual("presence.activity_invalid", (await runtime.DispatchAsync(invalid)).Response.Error?.Code,
        "Stale, foreign or overbroad activity reports are rejected.");
    var response = await runtime.DispatchAsync(BridgeEnvelope.Request("friends.read", "friends", host.Generation,
        new { schemaVersion = 1 }, host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, response.Response.Status, "Friends wired");
    foreach (var request in new[] {
        BridgeEnvelope.Request("friends.read", "missing", host.Generation, new { schemaVersion = 1 }),
        BridgeEnvelope.Request("friends.read", "stale", host.Generation - 1, new { schemaVersion = 1 }, host.CurrentContext),
        BridgeEnvelope.Request("friends.read", "other", host.Generation, new { schemaVersion = 1 }, new BridgeAccountContext("test", "scm", "other")),
        BridgeEnvelope.Request("friends.execute", "write", host.Generation, new { schemaVersion = 1 }, host.CurrentContext) })
        AssertEqual(BridgeResponseStatuses.Error, (await runtime.DispatchAsync(request)).Response.Status, "Scope and read-only guard");
    AssertEqual(1, host.FriendsReads, "No invalid request reached reader");
    var command = new { schemaVersion = 1, action = "remove", targetRef = "00000000000000000000000000000001" };
    foreach (var request in new[] {
        BridgeEnvelope.Request("friends.execute", "cmd-missing", host.Generation, command),
        BridgeEnvelope.Request("friends.execute", "cmd-stale", host.Generation - 1, command, host.CurrentContext),
        BridgeEnvelope.Request("friends.execute", "cmd-other", host.Generation, command, new BridgeAccountContext("test", "scm", "other")) })
        AssertEqual(BridgeResponseStatuses.Error, (await runtime.DispatchAsync(request)).Response.Status, "Command scope guard");
    AssertEqual(0, host.FriendCommands, "Invalid scope never reaches command owner");
    AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(BridgeEnvelope.Request("friends.execute", "cmd-current", host.Generation, command, host.CurrentContext))).Response.Status, "Command routed");
    AssertEqual(1, host.FriendCommands, "One valid command");
    foreach (var request in new[] {
        BridgeEnvelope.Request("directMessages.read", "chat-missing", host.Generation, new { schemaVersion = 1 }),
        BridgeEnvelope.Request("directMessages.read", "chat-stale", host.Generation - 1, new { schemaVersion = 1 }, host.CurrentContext),
        BridgeEnvelope.Request("directMessages.read", "chat-other", host.Generation, new { schemaVersion = 1 }, new BridgeAccountContext("test", "scm", "other")) })
        AssertEqual(BridgeResponseStatuses.Error, (await runtime.DispatchAsync(request)).Response.Status, "Chat scope guard");
    AssertEqual(0, host.DirectReads, "Invalid chat context never reaches owner");
    AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(BridgeEnvelope.Request("directMessages.read", "chat-current", host.Generation, new { schemaVersion = 1 }, host.CurrentContext))).Response.Status, "Chat routed");
    AssertEqual(1, host.DirectReads, "One chat read");
    foreach (var request in new[] {
        BridgeEnvelope.Request("directMessages.send", "send-missing", host.Generation, command),
        BridgeEnvelope.Request("directMessages.send", "send-stale", host.Generation - 1, command, host.CurrentContext),
        BridgeEnvelope.Request("directMessages.send", "send-other", host.Generation, command, new BridgeAccountContext("test", "scm", "other")) })
        AssertEqual(BridgeResponseStatuses.Error, (await runtime.DispatchAsync(request)).Response.Status, "Send scope guard");
    AssertEqual(0, host.DirectSends, "Invalid send context never reaches owner");
    var send = new { schemaVersion = 1, targetRef = "00000000000000000000000000000001", clientMessageId = "00000000000000000000000000000002", text = "example" };
    AssertEqual(BridgeResponseStatuses.Ok, (await runtime.DispatchAsync(BridgeEnvelope.Request("directMessages.send", "send-current", host.Generation, send, host.CurrentContext))).Response.Status, "Send routed");
    AssertEqual(1, host.DirectSends, "One valid send");
}

static async Task PartyRoomsBridgeScope()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(default);
    using var runtime = new AccountBridgeRuntime(host);
    AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("partyRooms.read"), "room capability advertised");
    AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("partyRooms.commands"), "room commands advertised");
    AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("partyRooms.manage"), "room management advertised separately");
    var ok = await runtime.DispatchAsync(BridgeEnvelope.Request("partyRooms.getDirectory", "room-read", host.Generation,
        new { schemaVersion = 1 }, host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, ok.Response.Status, "room read routed");
    AssertEqual(0, ok.Response.Payload.GetProperty("rooms").GetArrayLength(), "real empty projection");
    foreach (var request in new[] {
        BridgeEnvelope.Request("partyRooms.getDirectory", "missing-account", host.Generation, new { schemaVersion = 1 }),
        BridgeEnvelope.Request("partyRooms.getDirectory", "stale", host.Generation - 1, new { schemaVersion = 1 }, host.CurrentContext),
        BridgeEnvelope.Request("partyRooms.getDirectory", "other-account", host.Generation, new { schemaVersion = 1 }, new BridgeAccountContext("test", "scm", "other")) })
    {
        var rejected = await runtime.DispatchAsync(request);
        AssertEqual(BridgeResponseStatuses.Error, rejected.Response.Status, "invalid room scope rejected");
    }
    var command = new { schemaVersion = 1, operation = "leave", data = new { roomId = "one" } };
    var executed = await runtime.DispatchAsync(BridgeEnvelope.Request("partyRooms.execute", "room-command", host.Generation, command, host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, executed.Response.Status, "room command routed");
    AssertEqual(1, host.RoomCommands, "one scoped command");
    foreach (var request in new[] {
        BridgeEnvelope.Request("partyRooms.execute", "missing-command-account", host.Generation, command),
        BridgeEnvelope.Request("partyRooms.execute", "stale-command", host.Generation - 1, command, host.CurrentContext),
        BridgeEnvelope.Request("partyRooms.execute", "other-command-account", host.Generation, command, new BridgeAccountContext("test", "scm", "other")) })
    {
        var rejected = await runtime.DispatchAsync(request);
        AssertEqual(BridgeResponseStatuses.Error, rejected.Response.Status, "invalid command scope rejected");
    }
    AssertEqual(1, host.RoomCommands, "invalid scope never reaches room command host");
}

static async Task EmptyVaultProjectsSignedOut()
{
    var directory = CreateIsolatedDataRoot();
    try
    {
        var settings = CreateEnvironmentSettings("development");
        var configuration = await ScmRuntimeConfiguration.ResolveAsync(
            settings,
            directory,
            static (current, _) => Task.FromResult(new ScmRegionRoute(
                current.ApiBaseUri,
                current.ResourceBaseUri,
                "test",
                DateTimeOffset.UtcNow)),
            CancellationToken.None);
        using var account = CreateAccountRuntime(configuration);
        var batch = await account.DispatchAsync(
            BridgeEnvelope.Request(
                "account.getCurrent",
                "account-read",
                0,
                new { schemaVersion = 1 }));
        AssertEqual(BridgeResponseStatuses.Ok, batch.Response.Status, "account response status");
        AssertEqual("signedOut", batch.Response.Payload.GetProperty("state").GetString(), "account state");
        var wire = System.Text.Json.JsonSerializer.Serialize(
            batch.Response,
            BridgeProtocol.JsonOptions);
        AssertEqual(false, wire.Contains("token", StringComparison.OrdinalIgnoreCase), "token excluded");
    }
    finally
    {
        Directory.Delete(directory, recursive: true);
    }
}

static async Task TransientRestoreProjectsRecoverableState()
{
    var settings = CreateEnvironmentSettings("development");
    var options = ScmOAuthOptions.Create(settings);
    var accountKey = $"{options.AuthorityId}:subject-1";
    var vault = new MemoryTokenVault();
    vault.SaveRefreshToken(accountKey, "refresh-offline");
    var handler = new ScriptedHttpMessageHandler(
        _ => throw new HttpRequestException("offline"));
    var oauth = new OAuthPkceClient(
        new ScmHttpClient(handler),
        vault,
        options);
    using var account = new AccountBridgeRuntime(
        new ScmAccountBridgeHost(
            oauth,
            new ScmProfileCacheStore(),
            settings.EnvironmentName,
            () => null));

    var first = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.getCurrent",
            "account-temporarily-unavailable",
            0,
            new { schemaVersion = 1 }));
    AssertEqual(BridgeResponseStatuses.Ok, first.Response.Status, "temporary restore response status");
    AssertEqual(
        "credentialTemporarilyUnavailable",
        first.Response.Payload.GetProperty("state").GetString(),
        "temporary restore state");
    AssertEqual<BridgeAccountContext?>(null, first.Response.AccountContext,
        "temporary restore account context");
    AssertEqual("refresh-offline", vault.LoadRefreshToken(accountKey),
        "temporary restore retained credential");

    var requestsAfterFirstAttempt = handler.Requests.Count;
    var second = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.getCurrent",
            "account-temporarily-unavailable-retry",
            0,
            new { schemaVersion = 1 }));
    AssertEqual(BridgeResponseStatuses.Ok, second.Response.Status, "retry response status");
    AssertEqual(true, handler.Requests.Count > requestsAfterFirstAttempt,
        "retry performed a fresh restore attempt");
}

static Task UnconfiguredHostUsesProductionDefaults()
{
    var names = new[]
    {
        "STARBRIDGE_ENVIRONMENT",
        "STARBRIDGE_SCM_REGION_DISCOVERY_ENABLED",
        "STARBRIDGE_SCM_REGION_API_URL",
        "STARBRIDGE_SCM_REGION_FALLBACK_API_URL",
        "STARBRIDGE_SCM_WS_BASE_URL",
        "STARBRIDGE_SCM_WEB_BASE_URL",
        "STARBRIDGE_SCM_API_BASE_URL",
        "STARBRIDGE_SCM_RESOURCE_BASE_URL",
        "STARBRIDGE_RELAY_BASE_URL",
        "STARBRIDGE_SCM_TRUSTED_REGION_HOSTS",
        "STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED"
    };
    var previous = names.ToDictionary(
        name => name,
        Environment.GetEnvironmentVariable,
        StringComparer.Ordinal);
    try
    {
        foreach (var name in names)
        {
            Environment.SetEnvironmentVariable(name, null);
        }

        var settings = ScmEnvironmentSettings.Load();
        AssertEqual("production", settings.EnvironmentName, "default environment");
        AssertEqual(true, settings.AccountAccessEnabled, "production account access");
        AssertEqual(true, settings.RegionDiscoveryEnabled, "region discovery defaults on with guarded domestic routing");
        AssertEqual("scms.flowcld.com", settings.RegionApiUri?.Host, "region endpoint");
        AssertEqual<Uri?>(null, settings.RegionFallbackApiUri, "secondary region endpoint disabled by default");
        AssertEqual("scmk.flowcld.com", settings.EffectiveWebSocketBaseUri.Host, "default WS host");
        AssertEqual(true, settings.TrustedRegionHosts.Contains("ws.flowcld.xyz"), "approved domestic WS trusted by default");
        AssertEqual("scm.flowcld.com", settings.WebBaseUri.Host, "SCM web endpoint");
        AssertEqual("scmk.flowcld.com", settings.ApiBaseUri.Host, "SCM API fallback endpoint");
        AssertEqual("scmk.flowcld.com", settings.ResourceBaseUri.Host, "SCM resource fallback endpoint");
        AssertEqual("api.scstarbridge.com", settings.RelayBaseUri.Host, "legacy relay endpoint");
        Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "development");
        var development = ScmEnvironmentSettings.Load();
        AssertEqual(false, development.RegionDiscoveryEnabled, "development discovery remains disabled by default");
        AssertEqual<Uri?>(null, development.RegionFallbackApiUri, "development secondary discovery default");
        AssertEqual("127.0.0.1", development.EffectiveWebSocketBaseUri.Host, "development WS host");
        AssertEqual(18081, development.EffectiveWebSocketBaseUri.Port, "development WS port");
        AssertEqual("ws", ScmOAuthOptions.Create(development).WebSocketEndpoint.Scheme, "development WS scheme");
    }
    finally
    {
        foreach (var (name, value) in previous)
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }

    return Task.CompletedTask;
}

static Task ProductionHostRejectsLoopbackRoutes()
{
    var routes = new[] { "STARBRIDGE_RELAY_BASE_URL", "STARBRIDGE_SCM_WEB_BASE_URL",
        "STARBRIDGE_SCM_API_BASE_URL", "STARBRIDGE_SCM_RESOURCE_BASE_URL", "STARBRIDGE_SCM_REGION_API_URL",
        "STARBRIDGE_SCM_REGION_FALLBACK_API_URL", "STARBRIDGE_SCM_WS_BASE_URL" };
    var names = routes.Append("STARBRIDGE_ENVIRONMENT").ToArray();
    var previous = names.ToDictionary(name => name, Environment.GetEnvironmentVariable, StringComparer.Ordinal);
    try
    {
        foreach (var name in routes) Environment.SetEnvironmentVariable(name, null);
        foreach (var route in routes)
        foreach (var address in new[] { "http://127.0.0.1:5058/", "https://localhost/", "http://[::1]/" })
        {
            Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "production");
            Environment.SetEnvironmentVariable(route, address);
            try
            {
                _ = ScmEnvironmentSettings.Load();
                throw new Exception("Production accepted a retained loopback service route.");
            }
            catch (InvalidOperationException error)
            {
                AssertEqual(true, error.Message.Contains("loopback", StringComparison.Ordinal),
                    "production loopback rejection");
            }
            Environment.SetEnvironmentVariable(route, null);
        }

        Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "development");
        Environment.SetEnvironmentVariable("STARBRIDGE_RELAY_BASE_URL", "http://127.0.0.1:5058/");
        AssertEqual("127.0.0.1", ScmEnvironmentSettings.Load().RelayBaseUri.Host,
            "development loopback relay remains available for explicit local tests");
    }
    finally
    {
        foreach (var (name, value) in previous)
        {
            Environment.SetEnvironmentVariable(name, value);
        }
    }

    return Task.CompletedTask;
}

static async Task ProductionAccountAccessCanBeExplicitlyDisabled()
{
    var previousEnvironment = Environment.GetEnvironmentVariable("STARBRIDGE_ENVIRONMENT");
    var previousOptIn = Environment.GetEnvironmentVariable(
        "STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED");
    try
    {
        Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", "production");
        Environment.SetEnvironmentVariable("STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED", null);
        AssertEqual(true, ScmEnvironmentSettings.Load().AccountAccessEnabled,
            "production access default");

        Environment.SetEnvironmentVariable("STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED", "false");
        AssertEqual(false, ScmEnvironmentSettings.Load().AccountAccessEnabled,
            "production access explicit opt-out");
    }
    finally
    {
        Environment.SetEnvironmentVariable("STARBRIDGE_ENVIRONMENT", previousEnvironment);
        Environment.SetEnvironmentVariable(
            "STARBRIDGE_SCM_PRODUCTION_ACCESS_ENABLED",
            previousOptIn);
    }

    var routeResolutionCalled = false;
    var lockedSettings = CreateEnvironmentSettings("production") with
    {
        AccountAccessEnabled = false,
        RegionDiscoveryEnabled = true
    };
    var configuration = await ScmRuntimeConfiguration.ResolveAsync(
        lockedSettings,
        Path.GetTempPath(),
        (_, _) =>
        {
            routeResolutionCalled = true;
            throw new InvalidOperationException("Locked production must not resolve a route.");
        },
        CancellationToken.None);
    AssertEqual(false, routeResolutionCalled, "locked production route resolution");
    AssertEqual(false, configuration.AccountAccessEnabled, "locked production configuration");
    AssertEqual("environment-locked", configuration.RouteSource, "locked route source");

    using var account = new AccountBridgeRuntime(
        new EnvironmentLockedAccountBridgeHost("production"));

    var current = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.getCurrent",
            "production-current",
            0,
            new { schemaVersion = 1 }));
    AssertEqual(BridgeResponseStatuses.Ok, current.Response.Status, "locked current response status");
    AssertEqual("signedOut", current.Response.Payload.GetProperty("state").GetString(),
        "locked environment projects signed out");

    var login = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.login",
            "production-login",
            0,
            new { schemaVersion = 1 }));
    AssertEqual(BridgeResponseStatuses.Error, login.Response.Status, "locked login response status");
    AssertEqual(
        AccountBridgeStableErrors.EnvironmentNotEnabled,
        login.Response.Error?.Code,
        "locked login error code");
}

static async Task ScmRuntimeIsolatesProductionAndDevelopment()
{
    var root = Path.Combine(Path.GetTempPath(), $"starbridge-runtime-config-{Guid.NewGuid():N}");
    var production = await ScmRuntimeConfiguration.ResolveAsync(
        CreateEnvironmentSettings("production"),
        root,
        static (settings, _) => Task.FromResult(new ScmRegionRoute(
            settings.ApiBaseUri,
            settings.ResourceBaseUri,
            "test-production",
            DateTimeOffset.UtcNow)),
        CancellationToken.None);
    var development = await ScmRuntimeConfiguration.ResolveAsync(
        CreateEnvironmentSettings("development"),
        root,
        static (settings, _) => Task.FromResult(new ScmRegionRoute(
            settings.ApiBaseUri,
            settings.ResourceBaseUri,
            "test-development",
            DateTimeOffset.UtcNow)),
        CancellationToken.None);

    AssertEqual("production", production.EnvironmentId, "production environment identity");
    AssertEqual("development", development.EnvironmentId, "development environment identity");
    AssertEqual("scm-production", production.OAuthOptions.AuthorityId, "production authority");
    AssertEqual("scm-development", development.OAuthOptions.AuthorityId, "development authority");
    AssertEqual(false, production.TokenVaultPath.Equals(
        development.TokenVaultPath,
        StringComparison.OrdinalIgnoreCase), "environment token vault isolation");
    AssertEqual("scm-token-vault.json", Path.GetFileName(production.TokenVaultPath),
        "production vault compatibility path");
    AssertEqual("scm-token-vault.development.json", Path.GetFileName(development.TokenVaultPath),
        "IDEA development vault path");
    AssertEqual(false, production.LegacyMigrationCredentialPath.Equals(
        development.LegacyMigrationCredentialPath,
        StringComparison.OrdinalIgnoreCase), "legacy migration credential isolation");
    AssertEqual("legacy-migration-credential.dat", Path.GetFileName(
        production.LegacyMigrationCredentialPath), "production migration credential compatibility path");
    AssertEqual("legacy-migration-credential.development.dat", Path.GetFileName(
        development.LegacyMigrationCredentialPath), "IDEA development migration credential path");

    var productionRoute = AccountRouteIdentity.Create(
        production.EnvironmentId,
        production.OAuthOptions.AuthorityId,
        "shared-subject",
        null);
    var developmentRoute = AccountRouteIdentity.Create(
        development.EnvironmentId,
        development.OAuthOptions.AuthorityId,
        "shared-subject",
        null);
    AssertEqual(false, productionRoute.CacheNamespace.Equals(
        developmentRoute.CacheNamespace,
        StringComparison.Ordinal), "environment cache isolation");
}

static async Task ScmRegionalRoutePreservesStableEnvironment()
{
    var root = Path.Combine(Path.GetTempPath(), $"starbridge-runtime-route-{Guid.NewGuid():N}");
    var settings = CreateEnvironmentSettings("production");
    var regionalApi = new Uri("https://scmk.flowcld.com/");
    var configuration = await ScmRuntimeConfiguration.ResolveAsync(
        settings,
        root,
        (_, _) => Task.FromResult(new ScmRegionRoute(
            regionalApi,
            regionalApi,
            "region-api",
            DateTimeOffset.UtcNow,
            new Uri("https://ws.flowcld.xyz/"))),
        CancellationToken.None);

    AssertEqual("production", configuration.EnvironmentId, "stable environment identity");
    AssertEqual("scm-production", configuration.OAuthOptions.AuthorityId, "stable authority identity");
    AssertEqual(regionalApi, configuration.OAuthOptions.ResourceServerBaseUri,
        "resolved resource endpoint");
    AssertEqual("ws.flowcld.xyz", configuration.OAuthOptions.WebSocketEndpoint.Host,
        "headless Host regional WS endpoint");
    AssertEqual("wss", configuration.OAuthOptions.WebSocketEndpoint.Scheme, "headless Host WS scheme");
    AssertEqual("scmk.flowcld.com", configuration.OAuthOptions.WebSocketTicketEndpoint.Host,
        "headless Host HTTP ticket endpoint");
    AssertEqual(settings.WebBaseUri, configuration.OAuthOptions.WebBaseUri, "stable web UI endpoint");
    AssertEqual(settings.RelayBaseUri, configuration.LegacyRelayBaseUri, "stable legacy relay endpoint");
    AssertEqual("region-api", configuration.RouteSource, "route source");
}

static ScmEnvironmentSettings CreateEnvironmentSettings(string environment) => new(
    environment,
    AccountAccessEnabled: true,
    RegionDiscoveryEnabled: false,
    RegionApiUri: null,
    WebBaseUri: environment == "production"
        ? new Uri("https://scm.flowcld.com/")
        : new Uri("http://127.0.0.1:3000/"),
    ApiBaseUri: environment == "production"
        ? new Uri("https://flowcld.xyz/")
        : new Uri("http://127.0.0.1:18080/"),
    ResourceBaseUri: environment == "production"
        ? new Uri("https://flowcld.xyz/")
        : new Uri("http://127.0.0.1:18081/"),
    RelayBaseUri: environment == "production"
        ? new Uri("https://api.scstarbridge.com/")
        : new Uri("http://127.0.0.1:5058/"),
    TrustedRegionHosts: new HashSet<string>(StringComparer.OrdinalIgnoreCase)
    {
        environment == "production" ? "flowcld.xyz" : "127.0.0.1",
        "scmk.flowcld.com"
    },
    RegionRequestTimeout: TimeSpan.FromSeconds(1),
    RegionCacheDuration: TimeSpan.FromHours(1));

static AccountBridgeRuntime CreateAccountRuntime(ScmRuntimeConfiguration configuration)
{
    var oauth = new OAuthPkceClient(
        new ScmHttpClient(),
        new WindowsTokenVault(configuration.TokenVaultPath),
        configuration.OAuthOptions,
        () => "host-runtime-test-device");
    return new AccountBridgeRuntime(
        new ScmAccountBridgeHost(
            oauth,
            new ScmProfileCacheStore(),
            configuration.EnvironmentId,
            () => null));
}

static async Task GameLogExpectedHandlePreservesCase()
{
    var root = Path.Combine(Path.GetTempPath(), "starbridge-handle-case-" + Guid.NewGuid().ToString("N"));
    Directory.CreateDirectory(root);
    try
    {
        var host = new LifecycleAccountHost();
        using var account = new AccountBridgeRuntime(host,
            gameLog: new StarBridge.HostRuntime.Presence.GameLogSettingsStore(root));
        await account.DispatchAsync(BridgeEnvelope.Request("account.login", "case-login", 0,
            new { schemaVersion = 1 }));
        var owner = host.CurrentContext!;
        var response = (await account.DispatchAsync(BridgeEnvelope.Request("gameLog.read", "case-read",
            host.Generation, new { schemaVersion = 1 }, owner))).Response;
        AssertEqual("domino_CN", response.Payload.GetProperty("expectedHandle").GetString(),
            "authoritative Handle display casing");
    }
    finally { Directory.Delete(root, true); }
}

static async Task AccountLifecycleIsEnabled()
{
    AssertEqual(
        true,
        AccountBridgeRuntime.AdvertisedCapabilities.SequenceEqual(
            [
                "overlayScenes.read",
                "overlayScenes.select",
                "overlayScenes.focusCommunity",
                "overlayScenes.focusFleet",
                "overlayScenes.fleet",
                "overlayRoster.read",
                "overlayRoster.update",
                "account.read",
                "account.offlineData.read",
                "imageCache.resources.v1",
                "account.restoreDisplay",
                "gameIdentity.prepareHandleChange",
                "gameIdentity.confirmHandleChange",
                "gameIdentity.cancelHandleChange",
                "account.avatar",
                "account.avatar.read",
                "account.callSign",
                "account.compatibility.read",
                "account.passwordRecovery",
                "account.legacyLogin",
                "account.redeemLegacyEntitlements",
                "account.legacySession",
                "account.compatibility.linkExisting",
                "account.lifecycle",
                "account.scmRouteRead",
                "account.scmRouteSave",
                "account.preferences.write",
                "account.profileCache.clear",
                "profile.stagedRead",
                "personalProfile.read",
                "personalProfile.write",
                "personalProfile.presentation.write.v1",
                "officialFleet.read",
                "officialFleet.deferredProfile",
                "officialFleet.ships",
                "officialFleet.shipImage",
                "officialFleet.reportShipImage",
                "officialFleet.shipImageReportStatus",
                "officialFleet.hangarSharing",
                "officialFleet.hangarSharingPage",
                "officialFleet.saveHangarSharing",
                "partyRooms.read",
                "friends.read",
                "friends.readDisplay",
                "friends.readPages",
                "friends.commandPages",
                "accountSafety.read",
                "account.supportRead",
                "account.supportClaim",
                "account.achievementIdeaSubmit",
                "notificationInbox.read",
                "notificationInbox.markRead",
                "accountSafety.appeal",
                "communities.read",
                "communities.commands",
                "communities.create",
                "communities.workspace",
                "communities.memberPersonalProfile",
                "users.interaction",
                "communities.logs",
                "communities.deleteLog",
                "communities.disbandPreview",
                "communities.chat",
                "communities.announcements",
                "communities.ships",
                "communities.hangarSharing",
                "communities.saveHangarSharing",
                "communities.shipImage",
                "communities.reportShipImage",
                "communities.announcementDetail",
                "communities.manageAnnouncements",
                "communities.chatDetail",
                "communities.markChatRead",
                "officialFleet.communication",
                "officialFleet.communication.authorIdentities",
                "officialFleet.communication.previewAuthors",
                "officialFleet.communication.chatAuthorRenewal",
                "officialFleet.readGovernanceContext",
                "officialFleet.governanceCapabilitiesV2",
                "officialFleet.rolePolicyV2",
                "officialFleet.readRankPolicy",
                "officialFleet.writeRankPolicy",
                "officialFleet.updateRolePermissions",
                "officialFleet.readMemberRoles",
                "officialFleet.assignRole",
                "officialFleet.revokeRole",
                "officialFleet.readGovernanceAudit",
                "officialFleet.readGovernanceOutcome",
                "officialFleet.wait",
                "officialFleet.governanceRole",
                "officialFleet.readRoleTemplates",
                "officialFleet.manageRoleTemplates",
                "officialFleet.readRoleTemplateOutcome",
                "officialFleet.readAnnouncementEditor",
                "officialFleet.manageAnnouncements",
                "officialFleet.readAnnouncementOutcome",
                "officialFleet.rally",
                "officialFleet.rallyStarter",
                "communities.sendChat",
                "communities.disband",
                "communities.media",
                "communities.profile",
                "communities.roles",
                "communities.saveRoles",
                "communities.memberRole",
                "communities.saveMemberRole",
                "communities.memberRemoval",
                "communities.removeMember",
                "communities.ownershipTransfer",
                "communities.transferOwnership",
                "communities.ownershipExit",
                "communities.leaveWithSuccessor",
                "communities.invites",
                "communities.sendInvite",
                "communities.admissions",
                "communities.manageAdmissions",
                "friends.commands",
                "directMessages.read",
                "social.wait",
                "communities.wait",
                "directMessages.send",
                "directMessages.markRead",
                "directMessages.privacyRead",
                "directMessages.privacyWrite",
                "friendRequests.privacyRead",
                "friendRequests.privacyWrite",
                "recentlyPlayed.privacyRead",
                "recentlyPlayed.privacyWrite",
                "partyRooms.commands",
                "partyRooms.manage",
                "partyRooms.invitations",
                "partyRooms.chat",
                "partyRooms.chatAttachments",
                "hangarReader.preview",
                "hangar.local",
                "hangar.localImages",
                "hangar.localFavorites",
                "hangar.localReconciliation",
                "hangar.localPersonalData",
                "ships.specifications",
                "marketplace.read",
                "marketplace.trade",
                "marketplace.records",
                "marketplace.notices",
                "marketplace.warehouse",
                "marketplace.contracts",
                "marketplace.chat",
                "marketplace.listings",
                "tradeProfile.read",
                "tradeProfile.write",
                "marketplace.preferences",
                "personalProfile.local",
                "privacy.local",
                "eventSharing.settings",
                "friendSharing.settings",
                "gameIdVisibility.settings",
                "privacy.publication",
                "privacy.publicationEvents",
                "privacy.communityScopes",
                "privacy.locationConfidence",
                "privacy.communityMemberScopes",
                "presence.visibility",
                "presence.activity",
                "gameplayTime.local",
                "gameplayTime.history",
                "gameplayTime.historyProgress",
                "gameplayTime.reset",
                "gameLog.local",
                "achievements.read",
                "scmAchievements.read"
            ],
            StringComparer.Ordinal),
        "advertised account capabilities");

    var host = new LifecycleAccountHost();
    using var account = new AccountBridgeRuntime(host);
    var login = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.login",
            "account-login",
            0,
            new { schemaVersion = 1 }));
    AssertEqual(BridgeResponseStatuses.Ok, login.Response.Status, "login response status");
    AssertEqual("signedIn", login.Response.Payload.GetProperty("state").GetString(), "login state");
    AssertEqual(1, login.Events.Count, "login invalidation count");
    AssertEqual(1L, login.Events[0].SessionGeneration, "login generation");

    foreach (var inviteName in new[] { "communities.previewInvite", "communities.acceptInvite", "communities.admissions", "communities.manageAdmissions", "communities.roles", "communities.saveRoles", "communities.memberRole", "communities.saveMemberRole", "communities.memberRemoval", "communities.removeMember", "communities.ownershipTransfer", "communities.transferOwnership", "communities.ownershipExit", "communities.leaveWithSuccessor", "communities.logs", "communities.deleteLog", "communities.disbandPreview", "communities.disband", "communities.chat", "communities.chatDetail", "communities.markChatRead", "communities.sendChat" })
    {
        var dispatched = await account.DispatchAsync(BridgeEnvelope.Request(inviteName,
            Guid.NewGuid().ToString("N"), host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
        AssertEqual("communities.unavailable", dispatched.Response.Error?.Code,
            "Enabled invitation request reaches the account contract, not capability-missing: " + inviteName);
    }

    foreach (var announcementName in new[] { "communities.announcements", "communities.announcementDetail", "communities.manageAnnouncements", "communities.ships", "communities.shipImage", "communities.reportShipImage", "communities.hangarSharing", "communities.saveHangarSharing" })
    {
        var result = await account.DispatchAsync(BridgeEnvelope.Request(announcementName, Guid.NewGuid().ToString("N"),
            host.Generation, new { schemaVersion = 1 }, host.CurrentContext));
        AssertEqual("communities.unavailable", result.Response.Error?.Code, "Announcement read reaches account contract: " + announcementName);
    }

    foreach (var retiredName in new[] { "account.createCompatibilityIdentity" })
    {
        var retired = await account.DispatchAsync(BridgeEnvelope.Request(
            retiredName, "retired-compatibility", host.Generation,
            new { schemaVersion = 1 }, host.CurrentContext));
        AssertEqual(BridgeErrorCodes.CapabilityUnavailable, retired.Response.Error?.Code,
            "Retired compatibility must not run: " + retiredName);
    }

    AssertEqual<AccountBridgeLegacyCredential?>(null, host.LastLegacyCredential,
        "Retired operations never forward old credentials");

    var officialFleet = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "officialFleet.getCurrent",
            "official-fleet-current",
            host.Generation,
            new { schemaVersion = 1 },
            host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, officialFleet.Response.Status,
        "official fleet response status");
    AssertEqual("member", officialFleet.Response.Payload.GetProperty("state").GetString(),
        "official fleet membership state");
    var fleet = officialFleet.Response.Payload.GetProperty("fleet");
    AssertEqual("officialFleet:7", fleet.GetProperty("sourceRef").GetString(),
        "official fleet stable source reference");
    AssertEqual("TEST", fleet.GetProperty("sid").GetString(), "official fleet SID");
    AssertEqual(4, fleet.GetProperty("officialRankValue").GetInt32(),
        "official RSI rank value");
    AssertEqual(false, fleet.TryGetProperty("capabilities", out _),
        "raw SCM capabilities stay inside the Host");

    var profileWrite = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "profile.patchPreferences",
            "profile-write",
            host.Generation,
            new
            {
                schemaVersion = 1,
                patch = new { locale = "en-US" }
            },
            host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, profileWrite.Response.Status, "scoped profile write status");
    AssertEqual(1, host.PreferenceWrites, "only the requested scoped action is delegated");

    var logout = await account.DispatchAsync(
        BridgeEnvelope.Request(
            "account.logout",
            "account-logout",
            host.Generation,
            new { schemaVersion = 1 },
            host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, logout.Response.Status, "logout response status");
    AssertEqual("signedOut", logout.Response.Payload.GetProperty("state").GetString(), "logout state");
    AssertEqual(2L, logout.Events[0].SessionGeneration, "logout generation");
}

static async Task AccountPreferenceRuntimeRoute()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(CancellationToken.None);
    using var runtime = new AccountBridgeRuntime(host);
    using var dispatcher = new CompositeBridgeDispatcher(
        new HostBridgeDispatcher("preference-route-test"), runtime,
        new HostBridgeDispatcher("unused-local-settings"));
    var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
        "profile.patchPreferences", "preference-route", host.Generation,
        new { schemaVersion = 1, patch = new { locale = "en-US" } },
        host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, result.Response.Status,
        "Saving preferences through the product route; error=" + result.Response.Error?.Code);
    AssertEqual(1, host.PreferenceWrites, "Exactly one delegated preference write");
    AssertEqual("en-US", result.Response.Payload.GetProperty("profile").GetProperty("locale").GetString(),
        "Authoritative preference result returns to Flutter");
}

static async Task AccountProfileCacheRuntimeRoute()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(CancellationToken.None);
    using var runtime = new AccountBridgeRuntime(host);
    using var dispatcher = new CompositeBridgeDispatcher(
        new HostBridgeDispatcher("cache-route-test"), runtime,
        new HostBridgeDispatcher("unused-local-settings"));
    var result = await dispatcher.DispatchAsync(BridgeEnvelope.Request(
        "profile.clearLocalCache", "cache-route", host.Generation,
        new { schemaVersion = 1 }, host.CurrentContext));
    AssertEqual(BridgeResponseStatuses.Ok, result.Response.Status,
        "Clearing profile cache through the product route; error=" + result.Response.Error?.Code);
    AssertEqual(1, host.CacheClears, "Exactly one delegated cache clear");
    AssertEqual(true, result.Response.Payload.GetProperty("cleared").GetBoolean(), "Cache result");
    AssertEqual(1L, host.Generation, "Clearing a profile cache does not sign out");
}

static Task OfficialFleetProjectionPreservesAuthority()
{
    var snapshot = new ScmBootstrapSnapshot(
        new ScmBootstrapProfile("subject", "Aster Lin", null, true),
        new ScmBootstrapIdentityLink(false, null),
        [new ScmBootstrapFleet(7, "ASTER", "Aster's Wing", null, true, "Officer", 4, ["raw.manage"])],
        new ScmBootstrapFleet(7, "ASTER", "Aster's Wing", null, true, "Officer", 4, ["raw.manage"]),
        0,
        12,
        new Dictionary<string, long> { ["fleets"] = 11 },
        DateTimeOffset.Parse("2026-09-01T12:00:00Z"),
        ["bootstrap.raw"]);
    var projection = ScmAccountBridgeHost.ProjectOfficialFleet(
        snapshot,
        DateTimeOffset.Parse("2026-09-01T12:01:00Z"));
    AssertEqual("member", projection.State, "official fleet state");
    AssertEqual("officialFleet:7", projection.Fleet?.SourceRef, "official fleet source reference");
    AssertEqual<int?>(null, projection.Fleet?.OfficialRankValue, "raw SCM rank is not an RSI star projection");
    AssertEqual("Officer", projection.Fleet?.OfficialRankName, "official title is preserved");
    AssertEqual(11L, projection.ResourceVersion, "official fleet resource version");

    foreach (var rawRank in new int?[] { null, 0, 1, 4, 5, 6, 99, 127 })
    {
        var rawFleet = snapshot.Fleets[0] with { RankValue = rawRank };
        var current = ScmAccountBridgeHost.ProjectOfficialFleet(
            snapshot with { Fleets = [rawFleet], PrimaryFleet = rawFleet }, DateTimeOffset.UtcNow);
        AssertEqual("member", current.State, "valid raw rank does not erase membership");
        AssertEqual<int?>(null, current.Fleet?.OfficialRankValue, "raw rank is not a star count");
        AssertEqual("Officer", current.Fleet?.OfficialRankName, "rank name remains available");
    }

    var invalid = snapshot with
    {
        Fleets = [new ScmBootstrapFleet(7, "ASTER", "Aster's Wing", null, true, "Owner", 128, [])],
        PrimaryFleet = null
    };
    try
    {
        _ = ScmAccountBridgeHost.ProjectOfficialFleet(invalid, DateTimeOffset.UtcNow);
        throw new InvalidOperationException("Invalid RSI rank was accepted.");
    }
    catch (AccountBridgeHostException exception)
    {
        AssertEqual(
            AccountBridgeStableErrors.OfficialFleetDataInvalid,
            exception.Code,
            "invalid official fleet stable error");
    }

    return Task.CompletedTask;
}

static Task OfficialFleetProjectionRejectsAmbiguousMembership()
{
    var fleet = new ScmBootstrapFleet(7, "ASTER", "Aster's Wing", null, true, "Officer", 4, []);
    var snapshot = new ScmBootstrapSnapshot(
        new ScmBootstrapProfile("subject", "Test viewer", null, true),
        new ScmBootstrapIdentityLink(false, null), [fleet], fleet, 0, 0,
        new Dictionary<string, long> { ["fleets"] = 11 }, DateTimeOffset.UtcNow, []);
    foreach (var invalid in new[]
    {
        snapshot with { Fleets = null!, PrimaryFleet = null },
        snapshot with { Fleets = [null!], PrimaryFleet = null },
        snapshot with { Fleets = [] },
        snapshot with { Fleets = [fleet, fleet with { Id = 8 }] },
        snapshot with { PrimaryFleet = fleet with { Id = 8 } },
        snapshot with { PrimaryFleet = fleet with { RankValue = 5 } },
        snapshot with { PrimaryFleet = fleet with { Sid = "OTHER" } },
        snapshot with { PrimaryFleet = fleet with { Name = "Other fleet" } },
        snapshot with { ResourceVersions = new Dictionary<string, long> { ["fleets"] = -1 } },
        snapshot with { Fleets = [fleet with { LogoUrl = "https://user:password@example.invalid/logo" }], PrimaryFleet = null },
        snapshot with { Fleets = [fleet with { LogoUrl = "http://example.invalid/logo" }], PrimaryFleet = null }
    })
    {
        try
        {
            _ = ScmAccountBridgeHost.ProjectOfficialFleet(invalid, DateTimeOffset.UtcNow);
        }
        catch (AccountBridgeHostException exception)
        {
            AssertEqual(AccountBridgeStableErrors.OfficialFleetDataInvalid, exception.Code,
                "ambiguous official fleet identity must be unavailable");
            continue;
        }
        throw new InvalidOperationException("Ambiguous official fleet identity was accepted.");
    }

    var empty = ScmAccountBridgeHost.ProjectOfficialFleet(
        snapshot with { Fleets = [], PrimaryFleet = null }, DateTimeOffset.UtcNow);
    AssertEqual("notMember", empty.State, "explicit empty membership is known absence");
    var unknownRank = ScmAccountBridgeHost.ProjectOfficialFleet(
        snapshot with { Fleets = [fleet with { RankName = null, RankValue = null }], PrimaryFleet = null },
        DateTimeOffset.UtcNow);
    AssertEqual("member", unknownRank.State, "unknown rank does not erase valid membership");
    AssertEqual<int?>(null, unknownRank.Fleet?.OfficialRankValue, "unknown rank remains unknown");
    return Task.CompletedTask;
}

static async Task ScmBootstrapProjectsOverlayEntitlements()
{
    var now = DateTimeOffset.UtcNow;
    var settings = CreateEnvironmentSettings("development");
    var handler = new ScriptedHttpMessageHandler(
        request => request.RequestUri?.AbsolutePath == "/app-api/starbridge/v1/bootstrap"
            ? JsonResponse(CreateOverlayBootstrapPayload("legacy-42", now))
            : new HttpResponseMessage(HttpStatusCode.NotFound));
    var oauth = new OAuthPkceClient(
        new ScmHttpClient(handler),
        new MemoryTokenVault(),
        ScmOAuthOptions.Create(settings));

    var result = await oauth.LoadBootstrapAsync(
        CreateRelaySession("synthetic-scm-bearer"),
        CancellationToken.None);

    AssertEqual(
        "overlay.skin.night-shadow|overlay.skin.verdict",
        string.Join('|', result.ActiveSession.ActiveOverlayEntitlements),
        "active permanent and temporary appearances");

    var original = LegacyPasswordLoginClient.ParseLegacyEntitlements(System.Text.Json.JsonSerializer.SerializeToElement(new
    {
        accountId = "legacy-42",
        entitlements = new[] { "overlay.skin.night-shadow" },
        temporaryEntitlements = new[] {
            new { entitlement = "overlay.skin.verdict", expiresAt = now.AddHours(1) },
            new { entitlement = "overlay.skin.expired", expiresAt = now.AddMinutes(-1) }
        }
    }), "legacy-42");
    foreach (var instant in new[] { now, now.AddHours(1).AddTicks(-1), now.AddHours(1), now.AddDays(1) })
        AssertEqual(string.Join('|', original.ResolveActive(instant)),
            string.Join('|', result.ActiveSession.OverlayEntitlements!.ResolveActive(instant)),
            "same original grants retain exact expiry through SCM projection");

    // No client-side fallback to a previous login's grants when Java cannot confirm them.
    var withoutGrants = System.Text.Json.Nodes.JsonNode.Parse(System.Text.Json.JsonSerializer.Serialize(CreateOverlayBootstrapPayload("legacy-42", now)))!.AsObject();
    withoutGrants.Remove("overlayEntitlements");
    var missingOAuth = new OAuthPkceClient(new ScmHttpClient(new ScriptedHttpMessageHandler(_ => JsonResponse(withoutGrants))),
        new MemoryTokenVault(), ScmOAuthOptions.Create(settings));
    var missing = await missingOAuth.LoadBootstrapAsync(result.ActiveSession, CancellationToken.None);
    AssertEqual(0, missing.ActiveSession.ActiveOverlayEntitlements.Count, "missing fresh grant projection cannot retain previous authorizations");

    var mismatchHandler = new ScriptedHttpMessageHandler(
        _ => JsonResponse(CreateOverlayBootstrapPayload("different-account", now)));
    var mismatchOAuth = new OAuthPkceClient(
        new ScmHttpClient(mismatchHandler),
        new MemoryTokenVault(),
        ScmOAuthOptions.Create(settings));
    try
    {
        _ = await mismatchOAuth.LoadBootstrapAsync(
            CreateRelaySession("synthetic-scm-bearer"),
            CancellationToken.None);
        throw new InvalidOperationException("Cross-account overlay entitlements were accepted.");
    }
    catch (InvalidOperationException exception)
    {
        AssertEqual(
            true,
            exception.Message.Contains("外观资格", StringComparison.Ordinal),
            "mismatched overlay qualification is rejected explicitly");
    }
}

static object CreateOverlayBootstrapPayload(string entitlementAccountId, DateTimeOffset now) => new
{
    profile = new
    {
        subject = "scm-subject",
        displayName = "Aster Lin",
        gameIdentityVerified = false
    },
    identityLink = new { linked = true, legacyAccountId = "legacy-42" },
    fleets = Array.Empty<object>(),
    primaryFleet = (object?)null,
    unreadNotifications = 0,
    blacklistVersion = 1,
    resourceVersions = new Dictionary<string, long>(),
    serverTime = now,
    capabilities = Array.Empty<string>(),
    overlayEntitlements = new
    {
        status = "ready",
        accountId = entitlementAccountId,
        entitlements = new[] { "overlay.skin.night-shadow" },
        temporaryEntitlements = new[]
        {
            new { entitlement = "overlay.skin.verdict", expiresAt = now.AddHours(1) },
            new { entitlement = "overlay.skin.expired", expiresAt = now.AddMinutes(-1) }
        },
        observedAt = now
    }
};

static async Task LegacyRelayLeaseReadsOwnerProfile()
{
    const string bearer = "synthetic-scm-bearer";
    var profile = CreatePersonalProfileDocument();
    var handler = new ScriptedHttpMessageHandler(
        request => request.RequestUri?.AbsolutePath switch
        {
            "/api/auth/session" => JsonResponse(
                new { accountId = "legacy-account-one" }),
            "/api/profile/me" => JsonResponse(profile),
            _ => new HttpResponseMessage(HttpStatusCode.NotFound)
        });
    using var http = new HttpClient(handler);
    using var relay = new LegacyRelayAccountClient(
        http,
        new Uri("http://127.0.0.1:5058/"));
    var session = CreateRelaySession(bearer);

    var established = await relay.EstablishAsync(
        session,
        "legacy-account-one",
        CancellationToken.None);
    var cachedEstablishment = await relay.EstablishAsync(
        session,
        "legacy-account-one",
        CancellationToken.None);
    var result = await relay.ReadOwnProfileAsync(
        session,
        "legacy-account-one",
        CancellationToken.None);

    AssertEqual(LegacyRelayAccessState.Ready, established, "relay lease state");
    AssertEqual(LegacyRelayAccessState.Ready, cachedEstablishment, "cached relay lease state");
    AssertEqual(LegacyRelayAccessState.Ready, result.State, "personal profile relay state");
    AssertEqual("Aster Lin", result.Profile?.Identity.Callsign, "personal profile callsign");
    AssertEqual(2, handler.Requests.Count, "one probe and one profile request");
    AssertEqual(
        true,
        handler.Requests.All(request => request.Scheme == "Bearer" && request.Parameter == bearer),
        "SCM bearer stays on Host-owned Relay requests");
}

static async Task JavaPersonalProfileReadsWithoutRelay()
{
    const string bearer = "synthetic-scm-bearer";
    var settings = CreateEnvironmentSettings("development");
    var handler = new ScriptedHttpMessageHandler(
        request => request.RequestUri?.AbsolutePath == "/app-api/starbridge/v1/personal-profile"
            ? JsonResponse(CreatePersonalProfileDocument())
            : new HttpResponseMessage(HttpStatusCode.NotFound));
    var oauth = new OAuthPkceClient(
        new ScmHttpClient(handler),
        new MemoryTokenVault(),
        ScmOAuthOptions.Create(settings));

    var result = await oauth.LoadPersonalProfileAsync(
        CreateRelaySession(bearer),
        CancellationToken.None);

    AssertEqual("Aster Lin", result.Profile.Identity.Callsign, "Java personal profile callsign");
    AssertEqual(1, handler.Requests.Count, "one Java personal profile request");
    AssertEqual(
        "/app-api/starbridge/v1/personal-profile",
        handler.Requests.Single().Path,
        "personal profile route excludes legacy Relay");
    AssertEqual("Bearer", handler.Requests.Single().Scheme, "SCM bearer remains Host-owned");
}

static async Task LegacyProfileMigrationWire()
{
    var bodies = new List<string>();
    var settings = CreateEnvironmentSettings("development");
    var handler = new ScriptedHttpMessageHandler(request =>
    {
        bodies.Add(request.Content?.ReadAsStringAsync().GetAwaiter().GetResult() ?? "");
        return JsonResponse(new LegacyProfileMigrationView("completed", CompletedRevision: 1));
    });
    var oauth = new OAuthPkceClient(new ScmHttpClient(handler), new MemoryTokenVault(), ScmOAuthOptions.Create(settings));
    var readSession = CreateRelaySession("synthetic-read-bearer");
    await oauth.ExecuteLegacyProfileMigrationAsync(readSession, "preview", null, false, CancellationToken.None,
        new LegacyProfileCredential("synthetic-old", " synthetic-only "));
    var grant = readSession with { AccessToken = "synthetic-write-grant", Capabilities = ["profile.write"] };
    var result = await oauth.ExecuteLegacyProfileMigrationAsync(grant, "confirm", "synthetic-preview", true, CancellationToken.None);
    AssertEqual("completed", result.View.State, "Migration result");
    AssertEqual("/app-api/starbridge/v1/legacy-profile-migration/preview", handler.Requests[0].Path, "Only Java receives preview");
    AssertEqual("/app-api/starbridge/v1/legacy-profile-migration/selected-confirm", handler.Requests[1].Path, "Only selected Java previews can be confirmed");
    using var previewPayload = System.Text.Json.JsonDocument.Parse(bodies[0]);
    AssertEqual("synthetic-old", previewPayload.RootElement.GetProperty("accountName").GetString(), "Manual old account");
    AssertEqual(" synthetic-only ", previewPayload.RootElement.GetProperty("password").GetString(), "Password preserved exactly");
    AssertEqual(false, bodies[1].Contains("synthetic-only"), "No password in confirmation");
    using var payload = System.Text.Json.JsonDocument.Parse(bodies[1]);
    AssertEqual("synthetic-preview", payload.RootElement.GetProperty("previewId").GetString(), "Preview ticket");
    AssertEqual(true, payload.RootElement.GetProperty("replaceExisting").GetBoolean(), "Explicit conflict decision");
    AssertEqual(false, payload.RootElement.TryGetProperty("legacyAccountId", out _), "No client-selected legacy id");
    AssertEqual(false, payload.RootElement.TryGetProperty("profile", out _), "No caller-supplied import data");
    var restored = await oauth.TryRestoreSessionAsync(CancellationToken.None);
    AssertEqual(readSession.AccessToken, restored?.AccessToken, "The one-time write grant must not replace login");
}

static async Task LegacyProfileMigrationRuntimeRoute()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(CancellationToken.None);
    using var runtime = new AccountBridgeRuntime(host);
    var context = host.CurrentContext!;
    var preview = await runtime.DispatchAsync(BridgeEnvelope.Request(
        "personalProfile.migrationPreview", "migration-preview-test", host.Generation,
        new { schemaVersion = 1, accountName = "synthetic-old", password = " synthetic-only " }, context));
    AssertEqual(BridgeResponseStatuses.Ok, preview.Response.Status,
        "Click Verify and preview must reach the account owner; error=" + preview.Response.Error?.Code);
    AssertEqual("previewed", preview.Response.Payload.GetProperty("migration").GetProperty("state").GetString(),
        "Preview result must return through the actual runtime");
    AssertEqual(1, host.MigrationCalls.Count, "Exactly one preview request");
    AssertEqual(" synthetic-only ", host.LastMigrationCredential?.Password, "Password is forwarded unchanged");
    AssertEqual(false, preview.Response.Payload.GetRawText().Contains("synthetic-only"), "No credential in response");

    var status = await runtime.DispatchAsync(BridgeEnvelope.Request(
        "personalProfile.migrationStatus", "migration-status-test", host.Generation,
        new { schemaVersion = 1 }, context));
    AssertEqual(BridgeResponseStatuses.Ok, status.Response.Status, "Status route is enabled");
    var confirm = await runtime.DispatchAsync(BridgeEnvelope.Request(
        "personalProfile.migrationConfirm", "migration-confirm-test", host.Generation,
        new { schemaVersion = 1, previewId = "synthetic-ticket", replaceExisting = true }, context));
    AssertEqual(BridgeResponseStatuses.Ok, confirm.Response.Status, "Explicit confirmation route is enabled");
    AssertEqual(3, host.MigrationCalls.Count, "Preview, status, confirmation reach the owner");
    AssertEqual(1, confirm.Events.Count, "Completed import publishes profile invalidation");

    var stale = await runtime.DispatchAsync(BridgeEnvelope.Request(
        "personalProfile.migrationPreview", "migration-stale-test", host.Generation - 1,
        new { schemaVersion = 1, accountName = "synthetic-old", password = "synthetic-only" }, context));
    AssertEqual(BridgeResponseStatuses.Error, stale.Response.Status, "Stale account is still rejected");
    AssertEqual(3, host.MigrationCalls.Count, "Rejected request never verifies credentials");
}

static async Task JavaPersonalProfileWritesWithRevision()
{
    string? requestBody = null;
    var settings = CreateEnvironmentSettings("development");
    var handler = new ScriptedHttpMessageHandler(request =>
    {
        requestBody = request.Content?.ReadAsStringAsync().GetAwaiter().GetResult();
        return request.RequestUri?.AbsolutePath == "/app-api/starbridge/v1/personal-profile"
            ? JsonResponse(CreatePersonalProfileDocument())
            : new HttpResponseMessage(HttpStatusCode.NotFound);
    });
    var oauth = new OAuthPkceClient(
        new ScmHttpClient(handler),
        new MemoryTokenVault(),
        ScmOAuthOptions.Create(settings));
    var session = CreateRelaySession("synthetic-scm-bearer") with
    {
        Capabilities = ["profile.write"]
    };
    var update = new PersonalProfilePresentationUpdateContract(
        4,
        "friendsOnly",
        "Domino",
        2,
        "stanton-orbit",
        "远征与协作。",
        [new PersonalProfileModuleContract("favorite-ships", 3, true, 0, 0)]);

    var result = await oauth.UpdatePersonalProfileAsync(session, update, CancellationToken.None);

    AssertEqual("Aster Lin", result.Profile.Identity.Callsign, "updated personal profile response");
    AssertEqual(
        "/app-api/starbridge/v1/personal-profile",
        handler.Requests.Single().Path,
        "personal profile write route");
    using var json = System.Text.Json.JsonDocument.Parse(requestBody!);
    AssertEqual(4L, json.RootElement.GetProperty("expectedRevision").GetInt64(),
        "optimistic revision wire value");
    AssertEqual("stanton-orbit", json.RootElement.GetProperty("wallpaperId").GetString(),
        "wallpaper wire value");
}

static async Task LegacyRelayLeaseRejectsAccountMismatch()
{
    var handler = new ScriptedHttpMessageHandler(
        _ => JsonResponse(new { accountId = "different-account" }));
    using var http = new HttpClient(handler);
    using var relay = new LegacyRelayAccountClient(
        http,
        new Uri("http://127.0.0.1:5058/"));
    var session = CreateRelaySession("synthetic-scm-bearer");

    var state = await relay.EstablishAsync(
        session,
        "expected-account",
        CancellationToken.None);
    var profile = await relay.ReadOwnProfileAsync(
        session,
        "expected-account",
        CancellationToken.None);

    AssertEqual(LegacyRelayAccessState.AccountMismatch, state, "mismatch state");
    AssertEqual(LegacyRelayAccessState.NotEstablished, profile.State, "mismatch blocks profile read");
    AssertEqual(1, handler.Requests.Count, "profile endpoint not called after mismatch");
}

static ScmOAuthSession CreateRelaySession(string bearer) => new(
    "scm-development",
    "scm-subject",
    "Aster Lin",
    bearer,
    DateTimeOffset.UtcNow.AddHours(1),
    [],
    CorrelationId: "relay-test-correlation");

static PersonalProfileDocumentContract CreatePersonalProfileDocument() => new(
    PersonalProfileContractPolicy.CurrentSchemaVersion,
    "public-profile-id",
    true,
    4,
    DateTimeOffset.UtcNow,
    new PersonalProfileIdentityContract("Aster Lin", "Aster-Lin"),
    PersonalProfileContentContract.Empty with
    {
        Introduction = "Synthetic profile",
        SkilledRoles = ["驾驶员"]
    },
    null,
    new PersonalProfileHangarContract([]),
    new PersonalProfileGameplayStatisticsContract(3600, 0, 0, DateTimeOffset.UtcNow),
    true);

static HttpResponseMessage JsonResponse<T>(T payload) => new(HttpStatusCode.OK)
{
    Content = JsonContent.Create(payload)
};

static Task HostLayersRemainWpfIndependent()
{
    var root = FindRepositoryRoot();
    foreach (var relativeProject in new[]
             {
                 "StarBridge.NativeHost/StarBridge.NativeHost.csproj",
                 "StarBridge.HostRuntime/StarBridge.HostRuntime.csproj"
             })
    {
        var project = File.ReadAllText(Path.Combine(root, relativeProject));
        AssertEqual(false, project.Contains("<UseWPF>", StringComparison.OrdinalIgnoreCase),
            $"{relativeProject} UseWPF");
        // Pure, conditionally-namespaced source catalogs are shared with WPF via
        // Compile/Link. Check actual assembly/project dependencies, not filenames.
        var references = System.Xml.Linq.XDocument.Parse(project).Descendants()
            .Where(element => element.Name.LocalName is "ProjectReference" or "Reference")
            .Select(element => (string?)element.Attribute("Include") ?? "");
        AssertEqual(false, references.Any(reference => reference.Contains("StarBridge.Desktop", StringComparison.OrdinalIgnoreCase)),
            $"{relativeProject} Desktop dependency");
    }

    AssertEqual(false, typeof(AccountBridgeRuntime).Assembly.GetReferencedAssemblies().Any(reference =>
        reference.Name is "StarBridge.Desktop" or "PresentationFramework" or "PresentationCore"),
        "compiled Host has no Desktop or WPF assembly dependency");

    foreach (var relativeDirectory in new[] { "StarBridge.NativeHost", "StarBridge.HostRuntime" })
    {
        foreach (var sourcePath in Directory.EnumerateFiles(
                     Path.Combine(root, relativeDirectory),
                     "*.cs",
                     SearchOption.AllDirectories))
        {
            if (sourcePath.Contains($"{Path.DirectorySeparatorChar}obj{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase) ||
                sourcePath.Contains($"{Path.DirectorySeparatorChar}bin{Path.DirectorySeparatorChar}", StringComparison.OrdinalIgnoreCase))
            {
                continue;
            }

            var source = File.ReadAllText(sourcePath);
            AssertEqual(false, source.Contains("using System.Windows", StringComparison.Ordinal),
                $"{Path.GetRelativePath(root, sourcePath)} WPF namespace");
            AssertEqual(false, source.Contains("namespace StarBridge.Desktop", StringComparison.Ordinal),
                $"{Path.GetRelativePath(root, sourcePath)} Desktop namespace");
        }
    }

    return Task.CompletedTask;
}

static string FindRepositoryRoot()
{
    // Isolated --artifacts-path builds are outside the checkout. An explicit
    // test source root retains the same checks without searching an unrelated parent.
    var explicitRoot = Environment.GetEnvironmentVariable("STARBRIDGE_HOST_TEST_SOURCE_ROOT");
    if (!string.IsNullOrWhiteSpace(explicitRoot))
    {
        if (!Path.IsPathFullyQualified(explicitRoot) ||
            !File.Exists(Path.Combine(explicitRoot, "StarBridge.HostRuntime", "StarBridge.HostRuntime.csproj")) ||
            !File.Exists(Path.Combine(explicitRoot, "StarBridge.NativeHost", "StarBridge.NativeHost.csproj")))
            throw new InvalidOperationException("Invalid explicit Host test source root.");
        return Path.GetFullPath(explicitRoot);
    }
    for (var directory = new DirectoryInfo(AppContext.BaseDirectory);
         directory is not null;
         directory = directory.Parent)
    {
        // Identify this source tree by its projects, not the old solution name.
        // An exported client tree can live beneath the private repository; never
        // walk past that tree and accidentally validate the private parent's files.
        if (File.Exists(Path.Combine(directory.FullName, "StarBridge.HostRuntime", "StarBridge.HostRuntime.csproj")) &&
            File.Exists(Path.Combine(directory.FullName, "StarBridge.NativeHost", "StarBridge.NativeHost.csproj")))
        {
            return directory.FullName;
        }
    }

    throw new InvalidOperationException("Could not locate the client source projects from the test output directory.");
}

static string CreateIsolatedDataRoot()
{
    var directory = Path.Combine(
        Path.GetTempPath(),
        $"starbridge-host-account-{Guid.NewGuid():N}");
    Directory.CreateDirectory(directory);
    HostDataRoot.UsePreparedRoot(directory);
    return directory;
}

static async Task RoundTrip(string pipeName, string correlationId)
{
    var connector = new NamedPipeBridgeConnector(pipeName);
    await using var connection = await connector.ConnectAsync(TimeSpan.FromSeconds(3));
    await connection.SendAsync(HelloRequest(correlationId));
    var response = await ReadNext(connection);
    AssertEqual(correlationId, response.CorrelationId, "correlation");
    AssertEqual(BridgeResponseStatuses.Ok, response.Status, "response status");
}

static BridgeEnvelope HelloRequest(string correlationId) =>
    BridgeEnvelope.Request(
        "host.hello",
        correlationId,
        0,
        new
        {
            protocols = new { minimum = 1, maximum = 1 },
            capabilities = new[] { "account.read" }
        });

static async Task<BridgeEnvelope> ReadNext(IBridgeConnection connection)
{
    await foreach (var envelope in connection.ReadAllAsync())
    {
        return envelope;
    }

    throw new InvalidOperationException("Connection closed before a response arrived.");
}

static void AssertEqual<T>(T expected, T actual, string label)
{
    if (!EqualityComparer<T>.Default.Equals(expected, actual))
    {
        throw new InvalidOperationException($"{label}: expected {expected}, got {actual}");
    }
}

file sealed class CancellableLoginDispatcher : IBridgeRequestDispatcher
{
    private readonly TaskCompletionSource<bool> _cancelled =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    internal TaskCompletionSource<bool> LoginStarted { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public event Action<BridgeEnvelope>? EventReady
    {
        add { }
        remove { }
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        if (request.Name == "account.login")
        {
            LoginStarted.TrySetResult(true);
            await _cancelled.Task.WaitAsync(cancellationToken);
            return new BridgeDispatchBatch(
                BridgeEnvelope.ErrorResponse(
                    request,
                    new BridgeError("account.login_cancelled", "Sign-in was cancelled.")),
                []);
        }

        if (request.Name == "account.cancelLogin")
        {
            _cancelled.TrySetResult(true);
            return new BridgeDispatchBatch(
                BridgeEnvelope.Response(request, new { schemaVersion = 1, cancelled = true }),
                []);
        }

        throw new InvalidOperationException($"Unexpected request {request.Name}.");
    }

    public void Dispose() => _cancelled.TrySetCanceled();
}

file sealed class BlockingRequestDispatcher : IBridgeRequestDispatcher
{
    private readonly int _requiredStarts;
    private readonly TaskCompletionSource<bool> _release =
        new(TaskCreationOptions.RunContinuationsAsynchronously);
    private int _started;

    internal BlockingRequestDispatcher(int requiredStarts)
    {
        _requiredStarts = requiredStarts;
    }

    internal TaskCompletionSource<bool> RequiredRequestsStarted { get; } =
        new(TaskCreationOptions.RunContinuationsAsynchronously);

    public event Action<BridgeEnvelope>? EventReady
    {
        add { }
        remove { }
    }

    public async ValueTask<BridgeDispatchBatch> DispatchAsync(
        BridgeEnvelope request,
        CancellationToken cancellationToken = default)
    {
        if (Interlocked.Increment(ref _started) == _requiredStarts)
        {
            RequiredRequestsStarted.TrySetResult(true);
        }

        await _release.Task.WaitAsync(cancellationToken);
        return new BridgeDispatchBatch(
            BridgeEnvelope.Response(request, new { schemaVersion = 1 }),
            []);
    }

    internal void Release() => _release.TrySetResult(true);

    public void Dispose()
    {
        RequiredRequestsStarted.TrySetCanceled();
        _release.TrySetResult(true);
    }
}

file sealed class LifecycleAccountHost : StarBridge.HostRuntime.Account.IAccountBridgeHost
{
    public int FriendsReads { get; private set; }
    public int DirectSends { get; private set; }
    public Task<object> SendDirectMessageAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        StarBridge.HostRuntime.Friends.FriendsReader.ParseChatSend(payload); DirectSends++;
        return Task.FromResult<object>(new StarBridge.HostRuntime.Friends.DirectSendView("00000000000000000000000000000001", "rejected", "forbidden"));
    }
    public int DirectReads { get; private set; }
    public Task<object> ReadDirectMessagesAsync(BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        StarBridge.HostRuntime.Friends.FriendsReader.ParseChatRead(payload); DirectReads++;
        return Task.FromResult<object>(new StarBridge.HostRuntime.Friends.ConversationsView([], 0, DateTimeOffset.UtcNow));
    }
    public int FriendCommands { get; private set; }
    public Task<StarBridge.HostRuntime.Friends.FriendCommandView> ExecuteFriendAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        StarBridge.HostRuntime.Friends.FriendsReader.ParseCommand(payload);
        FriendCommands++;
        return Task.FromResult(new StarBridge.HostRuntime.Friends.FriendCommandView("rejected", "targetChanged"));
    }
    public Task<StarBridge.HostRuntime.Friends.FriendsView> ReadFriendsAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken token)
    {
        FriendsReads++;
        return Task.FromResult(StarBridge.HostRuntime.Friends.FriendsReader.Parse(FriendsReaderTests.Directory()));
    }
    public int RoomCommands { get; private set; }
    public Task<StarBridge.HostRuntime.PartyRooms.RoomCommandView> ExecutePartyRoomAsync(
        BridgeAccountContext context, System.Text.Json.JsonElement payload, CancellationToken cancellationToken)
    {
        RoomCommands++;
        return Task.FromResult(new StarBridge.HostRuntime.PartyRooms.RoomCommandView("left", null,
            new StarBridge.HostRuntime.PartyRooms.RoomDirectoryView(null, DateTimeOffset.UtcNow, []), null));
    }
    public Task<StarBridge.HostRuntime.PartyRooms.RoomDirectoryView> GetPartyRoomsAsync(
        BridgeAccountContext context, CancellationToken cancellationToken) =>
        Task.FromResult(new StarBridge.HostRuntime.PartyRooms.RoomDirectoryView(null, DateTimeOffset.UtcNow, []));
    private bool _signedIn;
    public int PreferenceWrites { get; private set; }
    public int CacheClears { get; private set; }
    public List<string> MigrationCalls { get; } = [];
    public LegacyProfileCredential? LastMigrationCredential { get; private set; }

    public Task<LegacyProfileMigrationView> MigrateLegacyProfileAsync(
        BridgeAccountContext context, string action, string? previewId, bool replaceExisting,
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null,
        LegacyProfileImportSelection? selection = null)
    {
        MigrationCalls.Add(action);
        LastMigrationCredential = credentials;
        var summary = new LegacyProfileMigrationSummary("Synthetic captain", "", 0, 0, null);
        return Task.FromResult(action switch
        {
            "preview" => new LegacyProfileMigrationView("previewed", "synthetic-ticket", "Synthetic-Handle",
                ExpiresAt: DateTimeOffset.UtcNow.AddMinutes(15), Source: summary, Target: summary),
            "confirm" => new LegacyProfileMigrationView("completed", CompletedRevision: 1),
            _ => new LegacyProfileMigrationView("credentialRequired")
        });
    }

    public long Generation { get; private set; }

    public BridgeAccountContext? CurrentContext => _signedIn
        ? new BridgeAccountContext("test", "scm", "subject")
        : null;

    public StarBridge.HostRuntime.Hangar.HangarAccountIdentity? HangarIdentity => !_signedIn
        ? null
        : new(CurrentContext!, Generation, new StarBridge.Core.Identity.ScmGameIdentitySnapshot(
            StarBridge.Core.Identity.ScmGameIdentityStatus.Verified, "domino_CN", "domino_cn"));

    public event Action<long>? AccountChanged;

    public StarBridge.HostRuntime.Account.AccountBridgeLegacyCredential? LastLegacyCredential
    {
        get;
        private set;
    }

    public Task<StarBridge.HostRuntime.Account.AccountBridgeSessionProjection> GetCurrentAsync(
        CancellationToken cancellationToken) => Task.FromResult(Project());

    public Task<StarBridge.HostRuntime.Account.AccountBridgeSessionProjection> LoginAsync(
        CancellationToken cancellationToken)
    {
        _signedIn = true;
        PublishChange();
        return Task.FromResult(Project());
    }

    public Task CancelLoginAsync() => Task.CompletedTask;

    public Task LogoutAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        _signedIn = false;
        PublishChange();
        return Task.CompletedTask;
    }

    public Task<StarBridge.HostRuntime.Account.AccountBridgeProfileProjection> GetProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => throw Unexpected();

    public Task<StarBridge.Core.Profiles.PersonalProfileDocumentContract> GetPersonalProfileAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => throw Unexpected();

    public Task<StarBridge.Core.Profiles.PersonalProfileDocumentContract> UpdatePersonalProfileAsync(
        BridgeAccountContext context,
        StarBridge.Core.Profiles.PersonalProfilePresentationUpdateContract update,
        CancellationToken cancellationToken) => throw Unexpected();

    public Task<StarBridge.HostRuntime.Account.AccountBridgeOfficialFleetProjection> GetOfficialFleetAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Task.FromResult(
            new StarBridge.HostRuntime.Account.AccountBridgeOfficialFleetProjection(
                "member",
                new StarBridge.HostRuntime.Account.AccountBridgeOfficialFleetSummary(
                    "officialFleet:7",
                    "TEST",
                    "Test Fleet",
                    null,
                    "Officer",
                    4),
                "live",
                11,
                DateTimeOffset.Parse("2026-09-01T12:00:00Z")));

    public Task<StarBridge.HostRuntime.Account.AccountBridgeCompatibilityProjection> GetCompatibilityStateAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => throw Unexpected();

    public Task<StarBridge.HostRuntime.Account.AccountBridgeCompatibilityProjection> LinkLegacyAccountAsync(
        BridgeAccountContext context,
        StarBridge.HostRuntime.Account.AccountBridgeLegacyCredential? credential,
        CancellationToken cancellationToken)
    {
        LastLegacyCredential = credential;
        return Task.FromResult(LinkedCompatibility());
    }

    public Task<StarBridge.HostRuntime.Account.AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => Task.FromResult(LinkedCompatibility());

    public Task<StarBridge.HostRuntime.Account.AccountBridgeProfileProjection> PatchPreferencesAsync(
        BridgeAccountContext context,
        StarBridge.HostRuntime.Account.AccountBridgePreferencePatch patch,
        CancellationToken cancellationToken)
    {
        PreferenceWrites++;
        return Task.FromResult(new AccountBridgeProfileProjection(
            new AccountBridgeProfile("Test User", null, null, patch.Locale.Value, "UTC"),
            "scm", null, ["en-US"], []));
    }

    public Task<bool> ClearProfileCacheAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken)
    {
        CacheClears++;
        return Task.FromResult(true);
    }

    public Task<StarBridge.HostRuntime.Account.AccountBridgeIdentityProjection> GetGameIdentityPolicyAsync(
        BridgeAccountContext context,
        CancellationToken cancellationToken) => throw Unexpected();

    private StarBridge.HostRuntime.Account.AccountBridgeSessionProjection Project() => new(
        _signedIn ? "signedIn" : "signedOut",
        Generation,
        CurrentContext,
        _signedIn ? "Test User" : null,
        null);

    private static StarBridge.HostRuntime.Account.AccountBridgeCompatibilityProjection LinkedCompatibility() =>
        new(
            "linked",
            "notEstablished",
            false,
            false,
            [],
            "host-internal-legacy-id");

    private void PublishChange()
    {
        Generation++;
        AccountChanged?.Invoke(Generation);
    }

    private static InvalidOperationException Unexpected() =>
        new("Profile and identity methods must not be called by this lifecycle test.");
}

file sealed class ScriptedHttpMessageHandler(
    Func<HttpRequestMessage, HttpResponseMessage> respond) : HttpMessageHandler
{
    internal List<(string? Scheme, string? Parameter, string? Path)> Requests { get; } = [];

    protected override Task<HttpResponseMessage> SendAsync(
        HttpRequestMessage request,
        CancellationToken cancellationToken)
    {
        cancellationToken.ThrowIfCancellationRequested();
        Requests.Add((
            request.Headers.Authorization?.Scheme,
            request.Headers.Authorization?.Parameter,
            request.RequestUri?.AbsolutePath));
        return Task.FromResult(respond(request));
    }
}

file sealed class MemoryTokenVault : ITokenVault
{
    private readonly Dictionary<string, string> _tokens = new(StringComparer.Ordinal);
    private string? _activeAccountKey;

    public void SaveRefreshToken(string accountKey, string refreshToken)
    {
        _tokens[accountKey] = refreshToken;
        _activeAccountKey = accountKey;
    }

    public string? LoadRefreshToken(string accountKey) =>
        _tokens.TryGetValue(accountKey, out var refreshToken) ? refreshToken : null;

    public string? LoadActiveAccountKey() => _activeAccountKey;

    public void DeleteRefreshToken(string accountKey)
    {
        _tokens.Remove(accountKey);
        if (string.Equals(_activeAccountKey, accountKey, StringComparison.Ordinal))
        {
            _activeAccountKey = null;
        }
    }
}

file sealed class TestCompatibilityReader : IAccountCompatibilityCoordinator
{
    public Task<AccountBridgeCompatibilityProjection> ReadAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken) => Task.FromResult(
            new AccountBridgeCompatibilityProjection(
                "unlinked",
                "notApplicable",
                false,
                false,
                ["linkExistingAccount", "createCompatibilityIdentity"],
                null));

    public Task<AccountBridgeCompatibilityProjection> LinkExistingAsync(
        ScmOAuthSession session,
        LegacyIdentityLinkPasswordCredential? credential,
        CancellationToken cancellationToken) => throw new InvalidOperationException(
            "Compatibility mutation is outside this read-only host test.");

    public Task<AccountBridgeCompatibilityProjection> CreateCompatibilityIdentityAsync(
        ScmOAuthSession session,
        CancellationToken cancellationToken) => throw new InvalidOperationException(
            "Compatibility mutation is outside this read-only host test.");
}



