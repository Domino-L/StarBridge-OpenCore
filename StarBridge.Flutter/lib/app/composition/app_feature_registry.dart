import 'dart:async';

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
import '../../features/game_log/game_session_overview.dart';
import '../../features/account/account_module.dart';
import '../../features/account/account_page.dart';
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
import '../../features/settings/sync_privacy_module.dart';
import '../../features/settings/sync_privacy_page.dart';
import '../../features/settings/privacy_settings_page.dart';
import '../../features/tools/tools_feature.dart';
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
  final organizationNotificationSources = nativeHost == null
      ? null
      : () => BridgeNotificationSources(nativeHost.session);
  final gameIdentity = nativeHost == null
      ? null
      : BridgeGameIdentityVerification(nativeHost.session);
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
    ),
    ...createSettingsFeatures(
      helpSupportBuilder: (_) => HelpSupportSettingsPage(
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
          BridgeAccountSafety(nativeHost?.session),
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
        gameIdentity: gameIdentity,
        localStatus: GameSessionOverview(controller: gameLog),
        localRecognition: gameLog == null
            ? null
            : GameLogPanel(controller: gameLog),
        footer: const PlannedSettingsCapabilities(
          section: SettingsSection.accountIdentity,
        ),
      ),
      generalDataBuilder: (_) => GeneralSettingsPage(
        preferences: preferences,
        gameplayTime: gameplayTime,
        scmRoute:
            nativeHost != null && BridgeScmRoute.supported(nativeHost.session)
            ? BridgeScmRoute(nativeHost.session)
            : null,
      ),
      syncPrivacyBuilder: (_) => localPrivacy == null
          ? SyncPrivacyPage(module: syncPrivacy)
          : PrivacySettingsPage(
              localPrivacy: localPrivacy,
              syncPrivacy: syncPrivacy,
              directMessagePrivacy: socialPrivacy?.directMessages,
              friendRequestPrivacy: socialPrivacy?.friendRequests,
              recentlyPlayedPrivacy: socialPrivacy?.recentlyPlayed,
              eventSession: nativeHost?.session,
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
        sendCommunityInvite:
            communities.port is CommunityInvitationSendPort &&
                (communities.port as CommunityInvitationSendPort)
                    .invitationSendingAvailable
            ? (context, chat) =>
                  sendCommunityInvitationInChat(context, communities, chat)
            : null,
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
          BridgeAccountSafety(nativeHost?.session),
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
    ),
    createAchievementsFeature(
      account,
      mode: connectionMode,
      port: nativeHost == null
          ? const UnavailableAchievementCollection()
          : BridgeAchievementCollection(
              nativeHost.session,
              displayHandoff: () => account.projection.value.hasDisplayHandoff
                  ? account.projection.value.displayHandoff
                  : null,
              mode: connectionMode,
              retainedReadId: () =>
                  account.projection.value.hasRetainedDisplayRead
                  ? account.projection.value.retainedReadId
                  : null,
            ),
      scmPort: nativeHost == null
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
      ideas: nativeHost == null
          ? const UnavailableAchievementIdeas()
          : BridgeAchievementIdeas(nativeHost.session),
    ),
  ]);
}
