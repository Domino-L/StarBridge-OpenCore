using StarBridge.HostRuntime;
using StarBridge.HostRuntime.Account;
using StarBridge.HostRuntime.Auth;
using StarBridge.HostRuntime.LegacyRelay;
using StarBridge.NativeBridge;
using StarBridge.Core.Profiles;
using System.Net;
using System.Net.Http.Json;

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

if (args is ["--profile-visibility-only"])
{
    await LegacyPasswordLoginTests.ProfileVisibility();
    Console.WriteLine("PASS profile visibility bridge ownership and transport");
    return 0;
}

if (args is ["--visitor-profile-only"])
{
    await LegacyPasswordLoginTests.VisitorProfile();
    await AvatarInteractionTests.Verify();
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
    await CommunityLogoBridgeTests.Verify();
    await AccountLifecycleIsEnabled();
    Console.WriteLine("PASS account avatar update, authority, failure and invalidation checks");
    return 0;
}

if (args is ["--community-read-efficiency-only"])
{
    await CommunityReadEfficiencyTests.Verify();
    return 0;
}

if (args is ["--account-dispatch-concurrency-only"])
{
    await AccountDispatchConcurrencyTests.Verify();
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

if (args is ["--manual-presence-only"])
{
    await AccountLifecycleIsEnabled();
    await CompositeBridgeDispatcherTests.RoutesPersonalProfileRequests();
    await ManualPresenceIntegrationTests.Verify();
    Console.WriteLine("PASS Manual presence routing and integrated publication");
    return 0;
}

if (args is ["--game-id-settings-only"])
{
    await GameIdSettingsTests.Run();
    Console.WriteLine("PASS game ID settings transport guards legacy servers, lost receipts and account changes");
    return 0;
}
if (args is ["--presence-recovery-only"])
{
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

if (args is ["--player-activity-sources-only"])
{
    await PlayerActivitySourcesTests.Verify();
    await CommunityWpfS2Tests.Verify();
    await LegacyPasswordLoginTests.VerifyPlayerActivity();
    Console.WriteLine("PASS Player activity complete-source, privacy, ordering and account gates");
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
    ("Community media and directory reads avoid duplicate upstream work", CommunityReadEfficiencyTests.Verify),
    ("Independent account reads retain mutation barriers and session isolation", AccountDispatchConcurrencyTests.Verify),
    ("Help support history and public endpoints", HelpSupportTests.RunAll),
    ("Independent event preferences reuse isolated revisioned persistence", SharedEventPreferencesStoreTests.Run),
    ("Independent event transport confirms one write without fallback or replay", EventSharingTransportTests.Run),
    ("Live event source excludes history and discards withdrawn session events", SharedActivityEventSourceTests.Run),
    ("Independent event runtime sends new events and confirms withdrawal before recovery", EventSharingRuntimeTests.Run),
    ("Event receiver baselines and revokes queued notifications", SharedActivityReceiverTests.Run),
    ("Storage migration destination preflight is non-mutating", StorageMigrationDestinationTests.ValidateWithoutMutation),
    ("Storage migration switches locator only after verified copy and recovers interruptions", StorageMigrationTransactionTests.Verify),
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
    ("Direct message notice source suppresses history, own sends and stale accounts", DirectMessageNotificationObserverTests.Run),
    ("Local notification settings persist and gate authenticated room reminders", NotificationSettingsTests.Run),
    ("Desktop notification tickets enforce privacy, expiry and single delivery", DesktopNotificationTests.Run),
    ("Friend publication gates consent and retires uncertain sessions", FriendSharingPublicationTests.Verify),
    ("Friend sharing runtime binds real source lifecycle and remote policy", FriendSharingRuntimeTests.Run),
    ("Game ID settings reuse guarded profile transport without unrelated writes", GameIdSettingsTests.Run),
    ("Privacy publication projects independent realtime axes without inventory writes", PrivacyPublicationTests.Projection),
    ("Privacy publication requires explicit consent and retries withdrawal only", PrivacyPublicationTests.Lifecycle),
    ("Privacy publication serializes stop after in-flight writes", PrivacyPublicationTests.Ordering),
    ("Privacy publication validates S2 group ownership and policy acknowledgement", PrivacyPublicationTests.Wire),
    ("Organization sharing binds membership, preserves account grants and verifies acknowledgments", CommunitySharingTests.Verify),
    ("Communities bounded reads and scoped membership commands", CommunityClientTests.Verify),
    ("Player activity sources require complete authorized identities", PlayerActivitySourcesTests.Verify),
    ("Manual presence shares publication gate and preserves consent", ManualPresenceIntegrationTests.Verify),
    ("Community WPF S2 membership and roster read compatibility", CommunityWpfS2Tests.Verify),
    ("Community WPF S2 discovery preserves filters and public visibility", CommunityWpfS2DiscoveryTests.Verify),
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
    ("Community workspace protects identity, scope, pagination and media chunks", CommunityWorkspaceClientTests.Verify),
    ("Community logs preserve bounded history, scope and single-attempt deletion", CommunityLogsClientTests.Verify),
    ("Community disband preserves credential authority and single-attempt confirmation", CommunityDisbandClientTests.Verify),
    ("Community chat preserves scoped pages and bounded original details", CommunityChatClientTests.Verify),
    ("Community announcements preserve scoped history and bounded original avatars", CommunityAnnouncementsClientTests.Verify),
    ("Community ships preserve private scoped instances and coherent pages", CommunityShipsClientTests.Verify),
    ("Community announcement writes bind intent and never replay uncertain operations", CommunityAnnouncementWriteClientTests.Verify),
    ("Community chat sending binds intent and reconciles lost replies without reposting", CommunityChatSendTests.Verify),
    ("Community profile preserves WPF fields and protects scoped editing intents", CommunityProfileClientTests.Verify),
    ("Community hangar sharing preserves scoped explicit choices and verifies saves", CommunityHangarSharingClientTests.Verify),
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
    ("Privacy publication automatically recovers from transport loss", PrivacyPublicationRecoveryTests.TransientDisconnect),
    ("Privacy publication remembers explicit account consent across restart", PrivacyPublicationRecoveryTests.Restart),
    ("Privacy publication revoked consent stays stopped across restart", PrivacyPublicationRecoveryTests.RevokedConsentRestart),
    ("Privacy consent storage, revocation and invisibility remain account-scoped", PrivacyConsentTests.Verify),
    ("Privacy publication recovery preserves consent and security boundaries", PrivacyPublicationRecoveryTests.Guards),
    ("Local privacy isolates owners and persists independent WPF axes", LocalPrivacyTests.Storage),
    ("Local privacy preserves corrupt records and rejects invalid audiences", LocalPrivacyTests.FailClosed),
    ("Local privacy bridge rejects stale consent without publication", LocalPrivacyTests.Contract),
    ("Local privacy account runtime routes and revokes local access", LocalPrivacyRuntimeScope),
    ("Overlay community source selects stable authorized targets", OverlayCommunitySourceTests.Selection),
    ("Overlay community source recovers silently and revokes stale content", OverlayCommunitySourceTests.Recovery),
    ("Overlay community source rejects account and selection races", OverlayCommunitySourceTests.AccountAndLateResponses),
    ("Overlay community source coalesces reads and preserves redaction", OverlayCommunitySourceTests.CoalescingAndProjection),
    ("Overlay community source reads on demand and cancels on disposal", OverlayCommunitySourceTests.DemandAndDisposal),
    ("Overlay scene choice bridge persistence and account isolation", OverlaySceneChoiceTests.BridgeAndPersistence),
    ("Overlay scene choice store guards corruption and late writes", OverlaySceneChoiceTests.StoreGuards),
    ("Party rooms overlay only accepts current authorized membership", RoomOverlaySessionTests.Membership),
    ("Party rooms overlay clears revoked stale and expired content", RoomOverlaySessionTests.Revocation),
    ("Party rooms overlay chat baselines history and bounds live messages", RoomOverlaySessionTests.Chat),
    ("Party rooms read projection protects membership and private fields", PartyRoomReaderTests.Projection),
    ("Party rooms display projects bounded avatars and explicit leader versions", PartyRoomDisplayTests.Projection),
    ("Party rooms rejects incomplete and contradictory data", PartyRoomReaderTests.InvalidData),
    ("Party rooms HTTP uses scoped bearer and safe bounded reads", PartyRoomReaderTests.HttpBoundary),
    ("Party rooms bridge requires current account and generation", PartyRoomsBridgeScope),
    ("Account safety reuses S2 appeal validation and rejects foreign fields", AccountSafetyRequestTests.Verify),
    ("Account safety reads preserve S2 facts without private report fields", AccountSafetyClientTests.Projection),
    ("Account safety transport is bounded scoped and cancellation safe", AccountSafetyClientTests.Transport),
    ("Account appeals reuse S2 intent and never replay uncertain writes", AccountSafetyClientTests.Submission),
    ("Friends read projection bounds data and hides private fields", FriendsReaderTests.Projection),
    ("Avatar menus resolve authoritative scoped users without writes", AvatarInteractionTests.Verify),
    ("Friends read HTTP is scoped read-only and cancellation safe", FriendsReaderTests.HttpAndRequest),
    ("Friends read bridge enforces account and generation", FriendsBridgeScope),
    ("Friends commands cover all seven authoritative transitions", FriendCommandTests.Lifecycle),
    ("Friends commands reject stale targets and changed accounts before writing", FriendCommandTests.Guards),
    ("Friends commands never replay uncertain or concurrent writes", FriendCommandTests.FailureAndConcurrency),
    ("Direct messages enforce read-only paging and opaque targets", DirectMessageReadTests.Paging),
    ("Composed inbox reads reach the notification observer", CompositeBridgeDispatcherTests.ObservesDirectMessages),
    ("Private desktop messages honor settings and activation boundaries", DirectMessageDesktopTests.Run),
    ("Organization notification reads and source importance are bounded", CommunityNotificationTests.Run),
    ("Organization background delivery honors saved source policy", CommunityNotificationDeliveryTests.Run),
    ("Notification source policy bridge validates membership and account", NotificationPolicyBridgeTests.Run),
    ("Direct messages reject cross-account and malformed history", DirectMessageReadTests.Guards),
    ("Direct message privacy uses the existing account-scoped Relay contract", DirectMessagePrivacyTests.Verify),
    ("Friend request privacy defaults open and remains account scoped", FriendRequestPrivacyTests.Verify),
    ("Recently played privacy is revisioned and account scoped", RecentlyPlayedPrivacyTests.Verify),
    ("Direct messages confirm plain text sends and deduplicate intents", DirectMessageSendTests.Confirmation),
    ("Direct messages preserve uncertain outcomes without replay", DirectMessageSendTests.Failures),
    ("Direct messages recheck permission and identity before sending", DirectMessageSendTests.Guards),
    ("Party rooms commands avoid replay and re-read authoritative membership", PartyRoomReaderTests.Commands),
    ("Party rooms command validation and uncertain responses fail safely", PartyRoomReaderTests.CommandValidation),
    ("Party rooms management protects host scope and password semantics", PartyRoomReaderTests.Management),
    ("Party rooms invitations scope targets and never replay writes", PartyRoomInvitationTests.Invitations),
    ("Party rooms chat protects membership cursors and uncertain sends", PartyRoomChatTests.Chat),
    ("Party rooms preset sharing preserves WPF format and additive import", OverlaySharedPresetTests.Sharing),
    ("Party rooms preset attachments validate before HTTP and retain unknown outcome", PartyRoomChatTests.Attachments),
    ("Overlay workspace reads every WPF setting and preset without mutation", OverlaySettingsTests.ReadsFullLegacyWorkspaceWithoutMutation),
    ("Overlay workspace defaults without creating legacy files", OverlaySettingsTests.DefaultsFullWorkspaceWithoutWriting),
    ("Overlay workspace saves legacy experimental render mode", OverlaySettingsTests.SavesWorkspaceLoadedFromLegacyExperimentalRenderMode),
    ("Overlay workspace writes atomically with backup and revision guard", OverlaySettingsTests.WritesFullWorkspaceWithBackupAndRevisionGuard),
    ("Overlay workspace supports every preset action", OverlaySettingsTests.ManagesEveryPresetAction),
    ("Overlay settings persist and reuse the current game session", OverlaySettingsTests.PersistsAndProjectsCurrentSession),
    ("Overlay runtime exposes native lifecycle and saved workspace", OverlaySettingsTests.ExposesRuntimeLifecycle),
    ("Overlay settings reject stale writes and unavailable previews", OverlaySettingsTests.RejectsStaleAndUnsupportedRequests),
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
    ("Gameplay reset legacy transport and owner boundary", LegacyPasswordLoginTests.GameplayResetTransport),
    ("Gameplay history storage failure, cancellation and account guards", GameplayHistoryRuntimeTests.FailureAndOwnership),
    ("Gameplay history old snapshot and explicit preference compatibility", GameplayHistoryRuntimeTests.OldSnapshotCompatibility),
    ("Gameplay history scanner bounds, identity and interval semantics", GameplayHistoryScannerTests.Verify),
    ("Local game presence is independent, versioned and confirms process exit", LocalGamePresenceTests.Verify),
    ("Saved hangar catalog and exact-hash bundled images are safe optional display facts", HangarCatalogTests.Verify),
    ("Local personal profile preserves ownership and atomic saves", LocalPersonalProfileTests.Storage),
    ("Local favorite modules enforce capacity, global uniqueness and reopen", LocalPersonalProfileTests.FavoriteModules),
    ("Local collaboration validates roles, schedules, exact days and reopen", LocalPersonalProfileTests.Collaboration),
    ("Local profile reads pre-collaboration files without changing integrity", LocalPersonalProfileTests.PreviousFormat),
    ("Local personal profile bridge validates current owner and favorite references", LocalPersonalProfileTests.Contract),
    ("Real reader saves a verified local scan and reopens it without leaking source keys", LocalHangarBridgeTests.Verify),
    ("Local hangar storage protects identity, revisions and atomic persistence", LocalHangarStoreTests.Verify),
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
    ("S2 compatibility read preserves identity, isolation and closed provisioning", S2CompatibilityReadTests.Verify),
    ("S2 existing account link reuses proof, preserves manual choice and cancellation", S2ExistingAccountLinkTests.Verify),
    ("S2 account password recovery preserves anonymous WPF contract and secret boundaries", PasswordRecoveryTests.Verify),
    ("S2 legacy account login preserves credentials without granting SCM access", LegacyPasswordLoginTests.Verify),
    ("Legacy hangar migration Bridge isolates pages and account changes", LegacyPasswordLoginTests.HangarMigrationBridge),
    ("Legacy hangar selection requires explicit owner consent without writes", LegacyHangarSelectionTests.Verify),
    ("Headless account owner restores an empty vault as signed out", EmptyVaultProjectsSignedOut),
    ("Transient SCM restore failure preserves credentials and projects a retry state", TransientRestoreProjectsRecoverableState),
    ("Rejected SCM refresh credential is deleted and requires authorization", AccountSessionRestoreTests.RejectedCredentialProjectsReauthorization),
    ("SCM identity mismatch is contained as a reauthorization state", AccountSessionRestoreTests.IdentityMismatchProjectsReauthorization),
    ("Runtime SCM invalidation advances generation and requires authorization", AccountSessionRestoreTests.RuntimeInvalidationProjectsReauthorization),
    ("Personal profile verification outage preserves the account without credential refresh", AccountSessionRestoreTests.PersonalProfileOutagePreservesAccount),
    ("SCM restore timeout is recoverable and never reports user cancellation", AccountSessionRestoreTests.RestoreTimeoutIsRecoverable),
    ("SCM restore caller cancellation remains cancelled", AccountSessionRestoreTests.RestoreCallerCancellationRemainsCancelled),
    ("Account completion allows bounded slow upstream responses", AccountCompletionTimeoutTests.SlowCompletionCanFinish),
    ("Account completion preserves cancellation and finite HTTP deadlines", AccountCompletionTimeoutTests.CancellationAndHttpDeadlineStillStop),
    ("Resource reads deliver slow valid profiles through their real callers", ResourceReadTimeoutTests.SlowReadsReachTheirCallers),
    ("Resource reads report timeout as retryable and retain the signed-in account", ResourceReadTimeoutTests.TimeoutIsRetryableWithoutLosingAccount),
    ("Resource reads preserve explicit caller cancellation", ResourceReadTimeoutTests.CallerCancellationStillStopsRead),
    ("Resource reads bound deadlines and preserve writes and queued account context", ResourceReadTimeoutTests.FiniteBudgetsAndQueueKeepTheirBoundaries),
    ("Unconfigured Host defaults to the production environment", UnconfiguredHostUsesProductionDefaults),
    ("Production Host rejects retained loopback service routes", ProductionHostRejectsLoopbackRoutes),
    ("Production account access can be explicitly disabled", ProductionAccountAccessCanBeExplicitlyDisabled),
    ("SCM runtime isolates production and IDEA development accounts", ScmRuntimeIsolatesProductionAndDevelopment),
    ("SCM regional routing preserves the stable account environment", ScmRegionalRoutePreservesStableEnvironment),
    ("Account lifecycle and scoped profile actions retain the retired-operation gate", AccountLifecycleIsEnabled),
    ("Account preference action crosses the real runtime gate", AccountPreferenceRuntimeRoute),
    ("Account profile cache action crosses the real runtime gate", AccountProfileCacheRuntimeRoute),
    ("Account preference write confirms without replacing the login", AccountPreferenceActionTests.SaveConfirmsWithoutReplacingLogin),
    ("Account preference authorization failures never write", AccountPreferenceActionTests.AuthorizationFailuresDoNotWrite),
    ("Account preference invalid inputs and stale contexts fail closed", AccountPreferenceActionTests.BadRequestsNeverAuthorize),
    ("Account preference write failure preserves cache and supports retry", AccountPreferenceActionTests.SaveFailureKeepsCacheAndCanRetry),
    ("Account profile cache clear is local and account-isolated", AccountPreferenceActionTests.ClearIsLocalAndIsolated),
    ("Account profile cache failure remains visible and retryable", AccountPreferenceActionTests.ClearFailureIsNotReportedAsSuccess),
    ("Account preference unconfirmed writes recover through a normal read", AccountPreferenceActionTests.UnconfirmedSaveNeverReplacesCache),
    ("Account preference browser decline retains callback state validation", AccountPreferenceActionTests.BrowserDeclineKeepsCallbackStateProtection),
    ("Official fleet projection preserves SCM authority and rejects invalid ranks", OfficialFleetProjectionPreservesAuthority),
    ("Official fleet projection distinguishes missing and conflicting membership", OfficialFleetProjectionRejectsAmbiguousMembership),
    ("SCM bootstrap projects only account-scoped active overlay appearances", ScmBootstrapProjectsOverlayEntitlements),
    ("Personal profile reads from the Java resource service without Relay", JavaPersonalProfileReadsWithoutRelay),
    ("Personal profile writes to Java with optimistic revision", JavaPersonalProfileWritesWithRevision),
    ("Manual migration uses Java and preserves scoped confirmation payload", LegacyProfileMigrationWire),
    ("Manual migration crosses the real runtime gate before reaching the account owner", LegacyProfileMigrationRuntimeRoute),
    ("Legacy Relay lease uses SCM bearer and reads the owner profile", LegacyRelayLeaseReadsOwnerProfile),
    ("Legacy Relay lease rejects a mismatched linked account", LegacyRelayLeaseRejectsAccountMismatch),
    ("Final Host layers remain independent from Desktop and WPF", HostLayersRemainWpfIndependent)
};

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
    using var dispatcher = new BlockingRequestDispatcher(requiredStarts: 4);
    using var lifetime = new CancellationTokenSource(TimeSpan.FromSeconds(5));
    var server = NativeHostPipeServer.ServeConnectionAsync(
        pair.Right,
        dispatcher,
        lifetime.Token);

    for (var index = 0; index < 4; index++)
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
        AssertEqual("privacy_local.account_changed", (await runtime.DispatchAsync(latest)).Response.Error?.Code, "disposed runtime cannot read settings");
    }
    finally { Directory.Delete(directory, recursive: true); }
}

static async Task FriendsBridgeScope()
{
    var host = new LifecycleAccountHost();
    await host.LoginAsync(default);
    using var runtime = new AccountBridgeRuntime(host);
    AssertEqual(true, AccountBridgeRuntime.AdvertisedCapabilities.Contains("friends.read"), "Friends advertised");
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
        AssertEqual(true, settings.RegionDiscoveryEnabled, "region discovery default");
        AssertEqual("scms.flowcld.com", settings.RegionApiUri?.Host, "region endpoint");
        AssertEqual("scm.flowcld.com", settings.WebBaseUri.Host, "SCM web endpoint");
        AssertEqual("flowcld.xyz", settings.ApiBaseUri.Host, "SCM API endpoint");
        AssertEqual("flowcld.xyz", settings.ResourceBaseUri.Host, "SCM resource endpoint");
        AssertEqual("api.scstarbridge.com", settings.RelayBaseUri.Host, "legacy relay endpoint");
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
        "STARBRIDGE_SCM_API_BASE_URL", "STARBRIDGE_SCM_RESOURCE_BASE_URL", "STARBRIDGE_SCM_REGION_API_URL" };
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
            DateTimeOffset.UtcNow)),
        CancellationToken.None);

    AssertEqual("production", configuration.EnvironmentId, "stable environment identity");
    AssertEqual("scm-production", configuration.OAuthOptions.AuthorityId, "stable authority identity");
    AssertEqual(regionalApi, configuration.OAuthOptions.ResourceServerBaseUri,
        "resolved resource endpoint");
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
                "account.read",
                "account.avatar",
                "account.compatibility.read",
                "account.passwordRecovery",
                "account.legacyLogin",
                "account.redeemLegacyEntitlements",
                "account.legacySession",
                "account.compatibility.linkExisting",
                "account.lifecycle",
                "account.preferences.write",
                "account.profileCache.clear",
                "personalProfile.read",
                "personalProfile.write",
                "officialFleet.read",
                "partyRooms.read",
                "friends.read",
                "accountSafety.read",
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
                "personalProfile.local",
                "privacy.local",
                "eventSharing.settings",
                "friendSharing.settings",
                "gameIdVisibility.settings",
                "privacy.publication",
                "privacy.communityScopes",
                "privacy.locationConfidence",
                "privacy.communityMemberScopes",
                "presence.visibility",
                "gameplayTime.local",
                "gameplayTime.history",
                "gameplayTime.reset",
                "gameLog.local"
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
    AssertEqual(4, projection.Fleet?.OfficialRankValue, "official fleet rank");
    AssertEqual(11L, projection.ResourceVersion, "official fleet resource version");

    var invalid = snapshot with
    {
        Fleets = [new ScmBootstrapFleet(7, "ASTER", "Aster's Wing", null, true, "Owner", 6, [])],
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
    AssertEqual("/app-api/starbridge/v1/legacy-profile-migration/confirm", handler.Requests[1].Path, "Only Java receives confirmation");
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
        CancellationToken cancellationToken, LegacyProfileCredential? credentials = null)
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
