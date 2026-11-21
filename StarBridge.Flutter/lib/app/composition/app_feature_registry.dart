import '../../features/gameplay_time/gameplay_identity_notice.dart';
import '../../features/onboarding/bridge_onboarding_adapter.dart';

import 'dart:async';

import '../../features/achievements/achievement_collection_session.dart';
import '../../features/achievements/swift_leaderboard.dart';
import '../../features/achievements/swift_leaderboard_page.dart';
import '../../features/communities/community_bridge_transport.dart';
import '../../features/official_fleet/bridge_official_fleet_announcement_management.dart';
import '../../features/official_fleet/bridge_official_fleet_governance.dart';

import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_port.dart';
import '../../features/settings/bridge_notification_sources.dart';
import '../../features/settings/help_support_settings_page.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../../features/settings/help_support_port.dart';
import '../../features/settings/daily_support_port.dart';

import 'package:flutter/foundation.dart';

import '../presence/manual_presence.dart';
import '../../features/onboarding/connection_mode_port.dart';
import '../../features/personal_profile/bridge_offline_personal_profile.dart';

import '../../features/settings/application_update_dialog.dart';
import '../../features/settings/entitlement_redemption_dialog.dart';

import '../../features/settings/gameplay_data_export_dialog.dart';
import '../../features/gameplay_time/gameplay_time_controller.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../features/game_log/game_log_panel.dart';
import '../../features/game_log/local_game_log_setup_panel.dart';
import '../../features/settings/usage_mode_settings_entry.dart';
import '../routing/open_destination_intent.dart';
import '../../features/onboarding/connection_mode_controller.dart';
import '../../features/account/account_models.dart';
import '../../features/account/account_relay_features.dart';
import 'account_scm_only.dart';
import 'computed_flag.dart';
import '../localization/account_card_title.dart';

import 'package:flutter/widgets.dart';

import '../../features/tools/key_bindings_labels.dart';
import '../../features/tools/mission_records_port.dart';
import '../../features/tools/catalog_recent.dart';
import '../../platform/catalog_recent_file_store.dart';
import 'catalog_recent_session.dart';
import '../../features/tools/key_bindings_port.dart';
import '../../features/game_log/game_session_overview.dart';
import '../../features/account/account_module.dart';
import '../../features/account/account_page.dart';
import '../../features/account/account_migration_controller.dart';
import '../../features/account/bridge_account_migration.dart';
import '../../features/account/bridge_game_identity_verification.dart';
import '../../features/account/account_safety_dialog.dart';
import '../../features/account/bridge_account_safety.dart';
import '../../features/account/account_avatar.dart';
import '../../features/achievements/achievements_feature.dart';
import '../../features/achievements/achievement_collection_port.dart';
import '../../features/achievements/bridge_achievement_collection.dart';
import '../../features/achievements/achievement_ideas_port.dart';
import '../../features/achievements/bridge_achievement_ideas.dart';
import '../../features/communities/communities_feature.dart';
import '../../features/communities/community_invite_flow.dart';
import '../../features/communities/community_invitation_send_dialog.dart';
import '../../features/communities/community_invitation_send_port.dart';
import '../../features/communities/community_invite_port.dart';
import '../../features/communities/community_hangar_sharing_port.dart';
import '../../features/communities/communities_module.dart';
import '../../features/friends/friends_feature.dart';
import '../../features/friends/friends_module.dart';
import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/hangar/hangar_feature.dart';
import '../../features/hangar/bridge_hangar_preview.dart';
import '../../features/hangar/bridge_hangar_inventory.dart';
import '../../features/hangar/bridge_local_hangar.dart';
import '../../features/home/home_feature.dart';
import '../../features/marketplace/marketplace_feature.dart';
import 'profile_trade_strip_host.dart';
import '../../features/notifications/notifications_feature.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import '../../features/notifications/notification_inbox_page.dart';
import '../../features/official_fleet/official_fleet_feature.dart';
import '../../features/official_fleet/official_fleet_module.dart';
import '../../features/communities/community_ships_port.dart';
import '../../features/common/organization_hangar_sharing.dart';
import '../../features/operations/operations_feature.dart';
import '../../features/overlay_settings/overlay_settings_feature.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import '../../features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import '../../features/party_rooms/party_rooms_feature.dart';
import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/personal_profile/personal_profile_feature.dart';
import '../../features/personal_profile/personal_profile_module.dart';
import '../../features/settings/client_license.dart';
import '../../features/settings/client_license_dialog.dart';
import '../../features/settings/client_version_dialog.dart';
import '../../features/settings/bridge_runtime_facts.dart';
import '../../features/settings/installation_check_dialog.dart';
import '../../features/settings/general_settings_page.dart';
import '../../features/settings/runtime_status_entry.dart';
import '../../features/settings/local_event_history_dialog.dart';
import '../../features/settings/diagnostics_settings_page.dart';
import '../../features/settings/notification_settings_module.dart';
import '../../features/settings/notification_audio_controller.dart';
import '../../features/settings/continuous_play_controller.dart';
import '../../features/settings/continuous_play_dialog.dart';
import '../../features/settings/player_activity_dialog.dart';
import '../../features/settings/notification_settings_page.dart';
import '../../features/settings/notification_editor_frame.dart';
import '../../features/settings/settings_capability_overview.dart';
import '../../features/settings/settings_feature.dart';
import '../../features/settings/application_support_module.dart';
import '../../features/settings/image_cache_maintenance_controller.dart';
import '../../features/settings/application_support_dialog.dart';
import '../../features/settings/data_location_port.dart';
import '../../features/settings/bridge_data_location.dart';
import '../../features/settings/scm_route_port.dart';
import '../../features/settings/data_location_dialog.dart';
import '../../features/settings/settings_models.dart';
import '../../features/settings/screen_reading_settings_page.dart';
import '../../features/settings/sync_privacy_module.dart';
import '../../features/settings/sync_privacy_page.dart';
import '../../features/settings/privacy_settings_page.dart';
import '../../features/tools/tools_feature.dart';
import '../../features/tools/catalog_port.dart';
import '../../features/tools/exec_hangar_port.dart';
import '../../platform/host/native_host_connector.dart';
import '../../platform/host/desktop_notification_port.dart';
import '../feature_registry.dart';
import '../preferences/app_preferences_port.dart';
import '../shell/chrome/shell_chrome_port.dart';
import 'social_privacy_composition.dart';
import 'first_use_setup_composition.dart';
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/settings/local_privacy_controller.dart';
import '../../features/settings/local_privacy_page.dart';

FeatureRegistry createAppFeatureRegistry(
  AccountModule account,
  PersonalProfileModule personalProfile,
  OfficialFleetModule officialFleet,
  PartyRoomsModule partyRooms,
  SyncPrivacyModule syncPrivacy,
  SocialPrivacyComposition? socialPrivacy,
  LocalPrivacyController? localPrivacy,
  NotificationSettingsModule notificationSettings,
  NotificationInboxController notificationInbox,
  NotificationAudioController? notificationAudio,
  ContinuousPlayController? continuousPlay,
  OverlaySettingsModule overlaySettings,
  AppPreferencesPort preferences,
  NativeHostLease? nativeHost,
  ShellChromePort shellChrome,
  GameplayTimeController? gameplayTime,
  GameLogController? gameLog,
  FriendsModule friends,
  CommunitiesModule communities,
  DirectMessagesPort Function() directMessagesPortFactory,
  ApplicationSupportModule applicationSupport,
  ValueNotifier<int> directMessageRequests, [
  ValueListenable<int>? directMessageUnread,
  ManualPresenceController? manualPresence,
  ConnectionModeControl? connectionMode,
  MarketplacePort Function()? marketplacePortFactory,
  CommunityShipsPort? officialFleetSharedShipsPort,
  OrganizationHangarSharingPort? officialFleetHangarSharingPort,
  ImageCacheMaintenanceController? imageMaintenance,
  MarketplaceChatController? tradeChat,
]) {
  final shared = communities.port;
  final recentCatalog = CatalogRecent(
    CatalogRecentFileStore.forDevice() ?? MemoryCatalogRecentStore(),
  );
  final recentSession = nativeHost == null
      ? null
      : CatalogRecentSession(nativeHost.session, recentCatalog);
  // Read again as the account is confirmed: a SCM-only account loses the entry,
  // and a linked one gets it back, without reopening the page.
  final inviteSending = communities.port is CommunityInvitationSendPort
      ? ComputedFlag(
          account.projection,
          () => (communities.port as CommunityInvitationSendPort)
              .invitationSendingAvailable,
        )
      : null;
  // The organization pages redraw disband when the account is confirmed
  // SCM-only (or linked) after they were shown.
  ComputedFlag(
    account.projection,
    () => relayAccountFeaturesBlocked(account.projection),
  ).addListener(communities.entriesChanged);
  final organizationNotificationSources = nativeHost == null
      ? null
      : () => BridgeNotificationSources(nativeHost.session);
  final gameIdentity = nativeHost == null
      ? null
      : BridgeGameIdentityVerification(nativeHost.session);
  // Old-account migration card (plan item 9); hidden while the relay does not offer it.
  final migration = nativeHost == null
      ? null
      : (AccountMigrationController(
          BridgeAccountMigration(nativeHost.session),
          account.projection,
        )..shareThrough(account.projection));
  // The prompts that send SCM-only users to the account card name its current
  // title, read from the same controller as the card itself. Both are
  // released with the account settings registration (accountDispose).
  final migrationOffered = migration == null
      ? null
      : ComputedFlag(migration, () => migration.value.offered);
  // Disband and the four relay account features open for SCM-only accounts
  // once the relay offers the migration.
  AccountMigrationController.offerChangesFor(account.projection)
      .addListener(communities.entriesChanged);
  final scmOnly = AccountScmOnly(account.projection);
  if (nativeHost != null && shared is CommunityBridgeTransport) {
    officialFleet.communication.configureGovernance(
      owner: shared,
      create: () => BridgeOfficialFleetGovernance(shared),
    );
    officialFleet.communication.configureAnnouncementManagement(
      owner: shared,
      create: () => BridgeOfficialFleetAnnouncementManagement(shared),
    );
  }
  // One hall controller, shared with the profile's trade strip.
  final market = createMarketplaceController(
    nativeHost?.session,
    connectionMode,
    port: marketplacePortFactory?.call(),
  );
  final leaderboard = nativeHost == null
      ? null
      : SwiftLeaderboardController.connected(
          nativeHost.session,
          account.projection,
          connectionMode,
        );
  // One achievement read, shared with the profile's achievement showcase.
  final AchievementCollectionPort achievementPort = nativeHost == null
      ? const UnavailableAchievementCollection()
      : BridgeAchievementCollection(
          nativeHost.session,
          displayHandoff: () => account.projection.value.hasDisplayHandoff
              ? account.projection.value.displayHandoff
              : null,
          mode: connectionMode,
          retainedReadId: () => account.projection.value.hasRetainedDisplayRead
              ? account.projection.value.retainedReadId
              : null,
        );
  final achievementSession = AchievementCollectionSession(
    account: account.projection,
    port: achievementPort,
    mode: connectionMode,
  );
  leaderboard?.watchAchievements(achievementSession.collection);
  // The SCM achievements, shared too, so the profile counts what the
  // achievements page counts (build 65: the profile header read 0).
  final scmAchievementSession = AchievementCollectionSession(
    account: account.projection,
    port: nativeHost == null
        ? const UnavailableAchievementCollection()
        : BridgeAchievementCollection(
            nativeHost.session,
            scm: true,
            displayHandoff: () => account.projection.value.hasDisplayHandoff
                ? account.projection.value.displayHandoff
                : null,
            mode: connectionMode,
            retainedReadId: () =>
                account.projection.value.hasRetainedDisplayRead
                ? account.projection.value.retainedReadId
                : null,
          ),
    mode: connectionMode,
    permanentMilestones: false,
  );
  Future<void> reconcileUsageMode() async {
    if (connectionMode is ConnectionModeController) {
      await connectionMode.refresh();
    }
    await account.refresh();
  }

  return FeatureRegistry([
    ...createFirstUseSetupFeatures(
      nativeHost?.session,
      FirstUseDeviceEditors(
        preferences: preferences,
        overlay: overlaySettings,
        notifications: notificationSettings,
        playReminder: continuousPlay,
        audio: notificationAudio,
        session: nativeHost?.session,
      ),
    ),
    createHomeFeature(partyRooms, shellChrome, presence: manualPresence),
    createPartyRoomsFeature(
      partyRooms,
      openCommunityInvite: communities.port is! CommunityInvitePort
          ? null
          : (context, code) => openCommunityInvitation(
              context,
              communities,
              code,
              createPrivacy: nativeHost == null
                  ? null
                  : () => BridgeLocalPrivacy(nativeHost.session),
            ),
    ),
    operationsFeature,
    createOfficialFleetFeature(
      officialFleet,
      sharedShipsPort: officialFleetSharedShipsPort,
      hangarSharingPort: officialFleetHangarSharingPort,
      privacy: localPrivacy,
      notificationSources: organizationNotificationSources,
      onPageShown: overlaySettings.scenes?.focusFleet,
    ),
    createMarketplaceFeature(
      account,
      nativeHost?.session,
      connectionMode,
      shared: market,
      chat: tradeChat,
    ),
    createCommunitiesFeature(
      module: communities,
      createAdmissionPrivacy: nativeHost == null
          ? null
          : () => BridgeLocalPrivacy(nativeHost.session),
      privacy: localPrivacy,
      notificationSources: organizationNotificationSources,
    ),
    createHangarFeature(
      account,
      () => nativeHost == null
          ? UnavailableHangarPreview()
          : BridgeHangarPreview(nativeHost.session),
      inventoryPort: nativeHost == null
          ? null
          : BridgeHangarInventory(nativeHost.session),
      connectionMode: connectionMode,
      offlineFactory: nativeHost == null
          ? null
          : (revision) =>
                BridgeLocalHangar.offline(nativeHost.session, revision),
      retainedFactory: nativeHost == null
          ? null
          : (id) => BridgeLocalHangar.retained(
              nativeHost.session,
              id,
              isCurrent: () =>
                  account.projection.value.retainedReadId == id &&
                  account.projection.value.hasRetainedDisplayRead &&
                  (connectionMode == null ||
                      connectionMode.allowsOnlineTraffic),
            ),
      sharingPort: communities.port is CommunityHangarSharingPort
          ? communities.port as CommunityHangarSharingPort
          : null,
      localFactory: nativeHost == null
          ? null
          : () => BridgeLocalHangar(
              nativeHost.session,
              readOrigin: HangarReadOrigin.feature,
              displayHandoff: () => account.projection.value.hasDisplayHandoff
                  ? account.projection.value.displayHandoff
                  : null,
            ),
    ),
    createOverlaySettingsFeature(overlaySettings, gameLog: gameLog),
    ...createToolsFeatures(
      recent: recentCatalog,
      onShown: () {
        unawaited(recentSession?.resolve());
      },
      disposeRecent: () {
        if (recentSession == null) {
          recentCatalog.dispose();
        } else {
          recentSession.dispose();
        }
      },
      createMissionRecords: nativeHost == null
          ? null
          : () => BridgeMissionRecordsPort(nativeHost.session, connectionMode),
      createCatalog: nativeHost == null
          ? null
          : () => BridgeCatalogPort(nativeHost.session, connectionMode),
      createPort: nativeHost == null
          ? null
          : () => BridgeExecHangar(nativeHost.session),
      createMenuPreferences:
          nativeHost == null ||
              !nativeHost.session.hostCapabilities.contains(
                'applicationPreferences.menu.update',
              )
          ? null
          : () => BridgeMenuWindowPreferences(nativeHost.session),
      createKeyBindings:
          nativeHost == null ||
              !nativeHost.session.hostCapabilities.contains('keyBindings.read')
          ? null
          : () => BridgeKeyBindings(nativeHost.session),
      readShortcuts: nativeHost == null
          ? null
          : () async => {
              ...fixedStarBridgeShortcuts,
              if ((await BridgeOverlayWorkspaceAdapter(
                    nativeHost.session,
                  ).read()).hotkey
                  case final hotkey? when hotkey.enabled)
                hotkey.binding,
            },
    ),
    ...createSettingsFeatures(
      accountDispose: migration == null
          ? null
          : () {
              migrationOffered?.dispose();
              migration.dispose();
            },
      accountScope: migrationOffered == null
          ? null
          : (child) => AccountCardTitle(
              migrationOffered: migrationOffered,
              child: child,
            ),
      helpSupportBuilder: (_) => HelpSupportSettingsPage(
        scmRoute:
            nativeHost != null &&
                nativeHost.session.hostCapabilities.contains(
                  BridgeScmRoute.readRequest,
                )
            ? BridgeScmRoute(nativeHost.session)
            : null,
        port: BridgeHelpSupport(nativeHost?.session),
        dailySupport: BridgeDailySupport(nativeHost?.session),
      ),
      diagnosticsBuilder: (_) => DiagnosticsSettingsPage(
        imageMaintenance: imageMaintenance,
        support: applicationSupport,
        session: nativeHost?.session,
        createRuntime: () => createRuntimeStatusController(
          preferences: preferences,
          session: nativeHost?.session,
          metadataAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.runtimeFacts',
              ) ??
              false,
          overlayStatusAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.overlayRuntimeStatus',
              ) ??
              false,
          overlay: nativeHost == null
              ? null
              : BridgeOverlayWorkspaceAdapter(nativeHost.session),
        ),
      ),
      entryOpeners: {
        'account-safety': (context) => showAccountSafetyDialog(
          context,
          BridgeAccountSafety(
            nativeHost?.session,
            scmOnly: () => scmOnly.value,
          ),
        ),
        'installation-update-repair': (context) =>
            showInstallationCheckDialog(context, applicationSupport),
        'client-version': (context) => showClientVersionDialog(
          context,
          read:
              nativeHost == null ||
                  !nativeHost.session.hostCapabilities.contains(
                    'diagnostics.runtimeFacts',
                  )
              ? null
              : () async => (await BridgeRuntimeFacts(
                  nativeHost.session,
                ).read()).applicationVersion,
        ),
        'client-license': (context) => showClientLicenseDialog(
          context,
          read: nativeHost == null
              ? null
              : BridgeClientLicense(
                  nativeHost.session,
                  available: nativeHost.session.hostCapabilities.contains(
                    'legal.clientLicense',
                  ),
                ).read,
        ),
        'runtime-status': (context) => showConnectedRuntimeStatus(
          context,
          preferences: preferences,
          session: nativeHost?.session,
          metadataAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.runtimeFacts',
              ) ??
              false,
          overlayStatusAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.overlayRuntimeStatus',
              ) ??
              false,
          overlay: nativeHost == null
              ? null
              : BridgeOverlayWorkspaceAdapter(nativeHost.session),
        ),
        'local-event-log': (context) => showLocalEventHistory(
          context,
          session: nativeHost?.session,
          available:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.localEvents',
              ) ??
              false,
          exportAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.localEventsExport',
              ) ??
              false,
          clearAvailable:
              nativeHost?.session.hostCapabilities.contains(
                'diagnostics.localEventsClear',
              ) ??
              false,
        ),
        if (nativeHost != null &&
            nativeHost.session.hostCapabilities.contains('playerActivity.read'))
          'player-activity': (context) =>
              showPlayerActivityDialog(context, nativeHost.session),
        if (continuousPlay != null)
          'continuous-play': (context) =>
              showContinuousPlayDialog(context, continuousPlay),
        'local-data-management': (context) => showGameplayDataExportDialog(
          context,
          account.projection,
          nativeHost?.session,
        ),
        'one-click-diagnostics': (context) =>
            showApplicationSupportDialog(context, applicationSupport),
        'local-data-storage': (context) => showDataLocationDialog(
          context,
          nativeHost == null ||
                  !nativeHost.session.hostCapabilities.contains(
                    'diagnostics.dataLocation',
                  )
              ? const UnavailableDataLocation()
              : BridgeDataLocation(nativeHost.session),
        ),
        'entitlement-redemption': (context) =>
            showLegacyEntitlementRedemptionDialog(
              context,
              account.projection,
              nativeHost?.session,
            ),
        'application-updates': (context) =>
            showApplicationUpdateDialog(context, nativeHost?.session),
      },
      accountAndIdentityBuilder: (_) => AccountPage(
        module: account,
        openUsageMode: nativeHost == null
            ? null
            : (context) => openUsageModeSettings(
                context,
                nativeHost.session,
                onModeChanged: reconcileUsageMode,
              ),
        usageModeEntry:
            nativeHost == null ||
                !nativeHost.session.hostCapabilities.contains(
                  BridgeOnboardingAdapter.capability,
                )
            ? null
            : UsageModeSettingsEntry(
                session: nativeHost.session,
                onModeChanged: reconcileUsageMode,
              ),
        gameIdentity: gameIdentity,
        migration: migration,
        localStatus: GameSessionOverview(controller: gameLog),
        localRecognition: nativeHost == null
            ? null
            : ValueListenableBuilder<AccountProjection>(
                valueListenable: account.projection,
                builder: (_, projection, _) =>
                    projection.failure?.code == 'account.local_mode' &&
                        nativeHost.session.hostCapabilities.contains(
                          BridgeOnboardingAdapter.capability,
                        )
                    ? LocalGameLogSetupPanel(
                        session: nativeHost.session,
                        onConfirmed: account.refresh,
                      )
                    : gameLog == null
                    ? const SizedBox.shrink()
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // Same notice and review entry as the gameplay
                          // panel: people with recording off never open it.
                          if (gameplayTime != null)
                            GameplayIdentityNotice(
                              controller: gameplayTime,
                              // The log Handle is checked in the panel right
                              // below; this re-reads after the person looked.
                              onConfirmIdentity: (_) => gameplayTime.retry(),
                            ),
                          GameLogPanel(controller: gameLog),
                        ],
                      ),
              ),
        footer: const PlannedSettingsCapabilities(
          section: SettingsSection.accountIdentity,
        ),
      ),
      screenReadingBuilder: (_) =>
          ScreenReadingSettingsPage(preferences: preferences),
      generalDataBuilder: (_) => GeneralSettingsPage(
        preferences: preferences,
        gameplayTime: gameplayTime,
        // Playtime waits on the same identity as Account & identity: send
        // the person there to check the log Handle, not to the guide review.
        openUsageMode: nativeHost == null
            ? null
            : (context) async {
                Actions.maybeInvoke(
                  context,
                  const OpenDestinationIntent('/settings/account'),
                );
              },
        scmRoute:
            nativeHost != null && BridgeScmRoute.supported(nativeHost.session)
            ? BridgeScmRoute(nativeHost.session)
            : null,
      ),
      syncPrivacyBuilder: (_) => localPrivacy == null
          ? SyncPrivacyPage(
              module: syncPrivacy,
              leaderboardSetting: leaderboard == null
                  ? null
                  : SwiftLeaderboardSetting(controller: leaderboard),
            )
          : PrivacySettingsPage(
              localPrivacy: localPrivacy,
              syncPrivacy: syncPrivacy,
              directMessagePrivacy: socialPrivacy?.directMessages,
              friendRequestPrivacy: socialPrivacy?.friendRequests,
              recentlyPlayedPrivacy: socialPrivacy?.recentlyPlayed,
              scmOnly: scmOnly,
              eventSession: nativeHost?.session,
              leaderboardSetting: leaderboard == null
                  ? null
                  : SwiftLeaderboardSetting(controller: leaderboard),
            ),
      confirmPrivacyLeave: localPrivacy == null
          ? null
          : (context) => confirmLocalPrivacyLeave(context, localPrivacy),
      notificationsBuilder: (_) => NotificationSettingsPage(
        module: notificationSettings,
        session: nativeHost?.session,
        audio: notificationAudio,
        desktop: nativeHost == null
            ? null
            : BridgeDesktopNotificationPort(nativeHost.session),
      ),
      confirmNotificationsLeave: (_) =>
          confirmNotificationLeave(notificationSettings),
    ),
    for (final messagesOnly in [true, false])
      createFriendsFeature(
        messagesOnly: messagesOnly,
        separateMessages: true,
        attentionCount: messagesOnly
            ? directMessageUnread
            : friends.incomingAttention,
        inboxRequests: messagesOnly ? directMessageRequests : null,
        openSection: messagesOnly && tradeChat != null
            ? (section) {
                if (section == 'trade') tradeChat.requestShow();
                // A trade-chat reminder (CX-T23) opens that conversation.
                if (section.startsWith('trade:')) {
                  tradeChat.requestShow();
                  unawaited(tradeChat.open(section.substring(6)));
                }
              }
            : null,
        module: friends,
        createChatPort: directMessagesPortFactory,
        sendCommunityInvite: inviteSending == null
            ? null
            : (context, chat) =>
                  sendCommunityInvitationInChat(context, communities, chat),
        communityInviteAvailable: inviteSending,
        openCommunityInvite: communities.port is! CommunityInvitePort
            ? null
            : (context, code) => openCommunityInvitation(
                context,
                communities,
                code,
                createPrivacy: nativeHost == null
                    ? null
                    : () => BridgeLocalPrivacy(nativeHost.session),
              ),
      ),
    createNotificationsFeature(
      attentionCount: notificationInbox.unread,
      buildContent: (context) => NotificationInboxPage(
        controller: notificationInbox,
        openSafety: () => showAccountSafetyDialog(
          context,
          BridgeAccountSafety(
            nativeHost?.session,
            scmOnly: () => scmOnly.value,
          ),
        ),
      ),
    ),
    createPersonalProfileFeature(
      personalProfile,
      connectionMode: connectionMode,
      offlineFactory: nativeHost == null || connectionMode == null
          ? null
          : () => BridgeOfflinePersonalProfile(
              nativeHost.session,
              connectionMode,
            ),
      retainedFactory: nativeHost == null || connectionMode == null
          ? null
          : (id) => BridgeOfflinePersonalProfile.retained(
              nativeHost.session,
              id,
              isCurrent: () =>
                  account.projection.value.retainedReadId == id &&
                  account.projection.value.hasRetainedDisplayRead &&
                  !connectionMode.failed &&
                  connectionMode.allowsOnlineTraffic,
            ),
      account: account.projection,
      avatar: nativeHost == null ? null : AccountAvatarPort(nativeHost.session),
      presence: shellChrome.projection,
      gameplayTime: gameplayTime,
      tradeStrip: (_, view) => ProfileTradeStripHost(market, view: view),
      achievements: achievementSession,
      scmAchievements: scmAchievementSession,
    ),
    createAchievementsFeature(
      account,
      mode: connectionMode,
      port: achievementPort,
      session: achievementSession,
      leaderboard: leaderboard,
      scmPort: scmAchievementSession.port,
      scmSession: scmAchievementSession,
      ideas: nativeHost == null
          ? const UnavailableAchievementIdeas()
          : BridgeAchievementIdeas(nativeHost.session),
    ),
  ]);
}
