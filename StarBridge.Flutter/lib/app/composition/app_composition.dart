import '../../features/marketplace/marketplace_chat_controller.dart';
import '../../features/marketplace/marketplace_port.dart';

import 'dart:async';

import '../../shared/remote_image_loader.dart';
import '../../features/settings/image_cache_maintenance_controller.dart';
import '../../shared/downloadable_image_cache.dart';
import 'remote_image_owner.dart';
import 'app_composition_disposal.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/native_remote_image_disk_cache.dart';

import '../../platform/window/taskbar_attention_binding.dart';
import 'taskbar_attention_composition.dart';
import 'friend_request_refresh.dart';
import 'menu_sources_composition.dart';

import 'app_feature_registry.dart';
import '../menu_overlay/menu_friends_session.dart';
import '../../features/common/bridge_user_interaction.dart';

import 'package:flutter/foundation.dart';

import '../presence/connected_manual_presence.dart';
import '../runtime/sharing_status_monitor.dart';
import '../../features/account/account_models.dart';
import '../../features/gameplay_time/gameplay_time_controller.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../features/account/account_module.dart';
import 'handle_mismatch_module.dart';
import 'handle_mismatch_composition.dart';
import 'official_fleet_composition.dart';
import 'official_fleet_self_presence_composition.dart';
import '../../features/account/account_port.dart';
import '../../features/account/bridge_account_adapter.dart';
import '../../features/account/host_unavailable_account_adapter.dart';
import '../../features/account/in_memory_account_adapter.dart';
import '../../features/communities/communities_module.dart';
import 'community_bridge_composition.dart';
import '../../features/communities/example_communities.dart';
import '../../features/friends/friends_module.dart';
import '../../features/friends/bridge_friends_adapter.dart';
import '../../features/friends/example_friends_adapter.dart';
import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/direct_messages/bridge_direct_messages.dart';
import '../../features/direct_messages/example_direct_messages.dart';
import '../../features/hangar/bridge_local_hangar.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import '../../features/official_fleet/official_fleet_module.dart';
import '../../features/official_fleet/official_fleet_rally.dart';
import '../../features/communities/community_ships_port.dart';
import '../../features/common/organization_hangar_sharing.dart';
import '../../features/common/organization_communication_port.dart';
import '../../features/official_fleet/official_fleet_port.dart';
import '../../features/official_fleet/bridge_official_fleet_adapter.dart';
import '../../features/official_fleet/bridge_official_fleet_members_adapter.dart';
import '../../features/official_fleet/bridge_official_fleet_communication_adapter.dart';
import '../../features/official_fleet/host_unavailable_official_fleet_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_members_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_overview_adapter.dart';
import '../../features/official_fleet/in_memory_official_fleet_ships_adapter.dart';
import '../../features/official_fleet/official_fleet_members_port.dart';
import '../../features/official_fleet/official_fleet_overview_port.dart';
import '../../features/official_fleet/official_fleet_ships_port.dart';
import '../../features/official_fleet/unavailable_official_fleet_members_adapter.dart';
import '../../features/official_fleet/unavailable_official_fleet_overview_adapter.dart';
import '../../features/official_fleet/unavailable_official_fleet_ships_adapter.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import 'overlay_settings_composition.dart';
import '../../features/overlay_settings/overlay_settings_port.dart';
import '../../features/overlay_settings/bridge_overlay_settings_adapter.dart';
import '../../features/overlay_settings/bridge_overlay_workspace_adapter.dart';
import '../../features/overlay_settings/host_unavailable_overlay_settings_adapter.dart';
import '../../features/overlay_settings/in_memory_overlay_settings_adapter.dart';
import '../../features/overlay_settings/overlay_workspace_port.dart';
import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/bridge_party_rooms_adapter.dart';
import '../../features/party_rooms/example_party_rooms_adapter.dart';
import '../../features/personal_profile/in_memory_personal_profile_adapter.dart';
import 'personal_profile_bridge_composition.dart';
import '../../features/personal_profile/personal_profile_module.dart';
import '../../features/personal_profile/personal_profile_port.dart';
import '../../features/settings/host_unavailable_notification_settings_adapter.dart';
import '../../features/settings/host_unavailable_sync_privacy_adapter.dart';
import '../../features/settings/in_memory_notification_settings_adapter.dart';
import '../../features/settings/in_memory_sync_privacy_adapter.dart';
import '../../features/settings/notification_settings_module.dart';
import '../../features/settings/notification_audio_controller.dart';
import '../../features/settings/continuous_play_controller.dart';
import '../../features/settings/bridge_continuous_play.dart';
import '../../features/settings/bridge_notification_settings_adapter.dart';
import '../../features/settings/notification_settings_port.dart';
import '../../features/settings/application_support_module.dart';
import 'application_support_composition.dart';
import '../../features/settings/sync_privacy_module.dart';
import '../../features/settings/sync_privacy_port.dart';
import '../../platform/host/native_host_connector.dart';
import '../../platform/host/desktop_notification_port.dart';
import '../../platform/window/method_channel_window_chrome.dart';
import '../../platform/window/method_channel_menu_preview_window.dart';
import '../../platform/window/window_chrome_port.dart';
import '../feature_registry.dart';
import '../preferences/app_preferences_port.dart';
import '../preferences/in_memory_app_preferences.dart';
import '../shell/chrome/in_memory_shell_chrome.dart';
import '../shell/chrome/shell_chrome_port.dart';
import 'account_shell_chrome.dart';
import 'direct_message_refresh.dart';
import 'social_activity.dart';
import 'bridge_game_presence.dart';
import 'social_privacy_composition.dart';
import 'app_activity_presence.dart';
import '../../features/settings/local_privacy_controller.dart';

final class AppComposition {
  TaskbarAttentionBinding createTaskbarAttention(TaskbarAttentionScope scope) =>
      composeTaskbarAttention(
        this,
        scope: scope,
        activeGeneration: () => _nativeHost?.session.activeGeneration,
      );
  AppComposition._(
    this._accountShellChrome, {
    required this.features,
    required this.windowChrome,
    required this.shellChrome,
    required this.preferences,
    required this.account,
    required this.handleMismatch,
    required this.personalProfile,
    required this.officialFleet,
    required this.officialFleetSharedShipsPort,
    required this.officialFleetHangarSharingPort,
    required this.partyRooms,
    required this.communities,
    required this.friends,
    required this.syncPrivacy,
    this.socialPrivacy,
    this.tradeChat,
    this.tradeChatPort,
    this.localPrivacy,
    required this.notificationSettings,
    required this.notificationInbox,
    required this.applicationSupport,
    this.notificationAudio,
    this.continuousPlay,
    this.desktopNotifications,
    this.directMessageRefresh,
    this.friendRequestRefresh,
    this.socialActivity,
    this.directMessageRequests,
    this.notificationReminders = const Stream.empty(),
    required this.overlaySettings,
    required this.ownsPreferences,
    this._nativeHost,
    this.gamePresence,
    this.manualPresence,
    this.gameplayTime,
    this.gameLog,
    required this.appActivity,
    required this.remoteImages,
    required this.remoteImageOwner,
    required this.imageMaintenance,
  });

  final FeatureRegistry features;
  final WindowChromePort windowChrome;
  final ShellChromePort shellChrome;
  final AppPreferencesPort preferences;
  final AccountModule account;
  final HandleMismatchModule handleMismatch;
  final PersonalProfileModule personalProfile;
  final OfficialFleetModule officialFleet;
  final CommunityShipsPort officialFleetSharedShipsPort;
  final OrganizationHangarSharingPort? officialFleetHangarSharingPort;
  final PartyRoomsModule partyRooms;
  final CommunitiesModule communities;
  final FriendsModule friends;
  final FriendRequestRefresh? friendRequestRefresh;
  final SyncPrivacyModule syncPrivacy;
  final SocialPrivacyComposition? socialPrivacy;
  final LocalPrivacyController? localPrivacy;
  SharingStatusMonitor? _sharingStatus;
  SharingStatusMonitor? get sharingStatus => localPrivacy == null
      ? null
      : _sharingStatus ??= SharingStatusMonitor(
          controller: localPrivacy!,
          presence: manualPresence?.source.controller,
        );
  final NotificationSettingsModule notificationSettings;
  final NotificationInboxController notificationInbox;

  /// 0.7.2 G9: the app-wide SCM trade chat, shared by the trading hall (its
  /// count, 私信对方) and the messages page (交易消息). Live for the session.
  final MarketplaceChatController? tradeChat;
  final BridgeMarketplacePort? tradeChatPort;
  DirectMessagesPort _createMessagesPort(String? Function() ownAvatar) {
    final port = _nativeHost == null
        ? UnavailableDirectMessages()
        : BridgeDirectMessages(_nativeHost.session, ownAvatar: ownAvatar);
    return directMessageRefresh?.borrow(port) ?? port;
  }

  DirectMessagesPort createWindowMessagesPort() => _createMessagesPort(
    () =>
        account.projection.value.profile?.avatarImageData ??
        account.projection.value.profile?.avatarUrl,
  );
  final ApplicationSupportModule applicationSupport;
  final NotificationAudioController? notificationAudio;
  final ContinuousPlayController? continuousPlay;
  final DesktopNotificationPort? desktopNotifications;
  final DirectMessageRefresh? directMessageRefresh;
  final SocialActivity? socialActivity;
  final ValueNotifier<int>? directMessageRequests;
  final Stream<LocalRoomReminder?> notificationReminders;
  final OverlaySettingsModule overlaySettings;
  final AccountShellChrome _accountShellChrome;
  final bool ownsPreferences;
  final NativeHostLease? _nativeHost;
  final RemoteImageLoader remoteImages;
  final RemoteImageOwner remoteImageOwner;
  final ImageCacheMaintenanceController imageMaintenance;
  BridgeClientSession? get firstUseSession => _nativeHost?.session;
  MenuFriendsSession createFriendsWindowSession(
    void Function(Map<String, Object?>) publish,
  ) => composeMenuFriendsSession(
    session: _nativeHost?.session,
    account: account,
    publish: publish,
    presence: manualPresence?.source.controller,
  );
  late final userInteractions = _nativeHost == null
      ? null
      : BridgeUserInteraction(_nativeHost.session);
  DirectMessagesPort createUserMessages() =>
      _createMessagesPort(() => account.projection.value.profile?.avatarUrl);
  final BridgeGamePresence? gamePresence;
  final ConnectedManualPresence? manualPresence;
  final GameplayTimeController? gameplayTime;
  final GameLogController? gameLog;
  final AppActivityPresence appActivity;

  Future<AccountActionResult> resolveAccountIssue() {
    if (account.projection.value.sessionState ==
        AccountSessionState.reauthorizationRequired) {
      return account.beginLogin();
    }
    return account.refresh();
  }

  factory AppComposition.forProductShell({
    required AppPreferencesPort preferences,
    MenuWindowLifetime? menuLifetime,
    WindowChromePort? windowChrome,
  }) {
    return AppComposition._withAdapters(
      menuLifetime: menuLifetime,
      windowChrome: windowChrome ?? MethodChannelWindowChrome(),
      shellChrome: InMemoryShellChrome(
        initial: InMemoryShellChrome.disconnectedProjection,
      ),
      preferences: preferences,
      ownsPreferences: false,
      accountPort: HostUnavailableAccountAdapter(),
      personalProfilePort: InMemoryPersonalProfileAdapter.forReview(
        signedIn: false,
      ),
      officialFleetPort: HostUnavailableOfficialFleetAdapter(),
      officialFleetOverviewPort: UnavailableOfficialFleetOverviewAdapter(),
      officialFleetMembersPort: UnavailableOfficialFleetMembersAdapter(),
      officialFleetShipsPort: UnavailableOfficialFleetShipsAdapter(),
      syncPrivacyPort: HostUnavailableSyncPrivacyAdapter(),
      notificationSettingsPort: HostUnavailableNotificationSettingsAdapter(),
      overlaySettingsPort: HostUnavailableOverlaySettingsAdapter(),
    );
  }

  factory AppComposition.forConnectedProduct({
    required NativeHostLease nativeHost,
    MenuWindowLifetime? menuLifetime,
    required AppPreferencesPort preferences,
    WindowChromePort? windowChrome,
  }) {
    final notifications = BridgeNotificationSettingsAdapter(nativeHost.session);
    return AppComposition._withAdapters(
      menuLifetime: menuLifetime,
      windowChrome: windowChrome ?? MethodChannelWindowChrome(),
      shellChrome: InMemoryShellChrome(
        initial: InMemoryShellChrome.hostConnectedProjection,
      ),
      preferences: preferences,
      ownsPreferences: false,
      accountPort: BridgeAccountAdapter(nativeHost.session),
      personalProfilePort: createBridgePersonalProfilePort(
        nativeHost.session,
        inventoryOrigin: HangarReadOrigin.profile,
      ),
      officialFleetPort: BridgeOfficialFleetAdapter(nativeHost.session),
      partyRoomsPort: BridgePartyRoomsAdapter(
        nativeHost.session,
        onReminder: notifications.onRoomReminder,
      ),
      officialFleetOverviewPort: UnavailableOfficialFleetOverviewAdapter(),
      officialFleetMembersPort: BridgeOfficialFleetMembersAdapter(
        nativeHost.session,
      ),
      officialFleetShipsPort: UnavailableOfficialFleetShipsAdapter(),
      syncPrivacyPort: HostUnavailableSyncPrivacyAdapter(),
      socialPrivacy: SocialPrivacyComposition.connected(nativeHost.session),
      notificationSettingsPort: notifications,
      overlaySettingsPort: BridgeOverlaySettingsAdapter(nativeHost.session),
      overlayWorkspacePort: BridgeOverlayWorkspaceAdapter(nativeHost.session),
      nativeHost: nativeHost,
    );
  }

  factory AppComposition.forShellReview({
    MenuWindowLifetime? menuLifetime,
    WindowChromePort? windowChrome,
    ShellChromePort? shellChrome,
    AppPreferencesPort? preferences,
    AccountPort? accountPort,
    PersonalProfilePort? personalProfilePort,
    OfficialFleetPort? officialFleetPort,
    OfficialFleetOverviewPort? officialFleetOverviewPort,
    OfficialFleetMembersPort? officialFleetMembersPort,
    OfficialFleetShipsPort? officialFleetShipsPort,
    SyncPrivacyPort? syncPrivacyPort,
    NotificationSettingsPort? notificationSettingsPort,
    OverlaySettingsPort? overlaySettingsPort,
    OverlayWorkspacePort? overlayWorkspacePort,
  }) {
    // Keep read receipts across page navigation within this example session.
    final exampleMessages = ExampleDirectMessages();
    return AppComposition._withAdapters(
      menuLifetime: menuLifetime,
      partyRoomsPort: ExamplePartyRoomsAdapter(),
      friendsPortFactory: ExampleFriendsAdapter.new,
      communitiesPortFactory: ExampleCommunities.new,
      directMessagesPortFactory: () => exampleMessages,
      windowChrome: windowChrome ?? MethodChannelWindowChrome(),
      shellChrome: shellChrome ?? InMemoryShellChrome(),
      preferences: preferences ?? InMemoryAppPreferences(),
      ownsPreferences: true,
      accountPort:
          accountPort ??
          InMemoryAccountAdapter.forReview(AccountReviewState.signedOut),
      personalProfilePort:
          personalProfilePort ??
          InMemoryPersonalProfileAdapter.forReview(signedIn: false),
      officialFleetPort:
          officialFleetPort ??
          InMemoryOfficialFleetAdapter.forReview(signedIn: false),
      officialFleetOverviewPort:
          officialFleetOverviewPort ??
          InMemoryOfficialFleetOverviewAdapter.forReview(),
      officialFleetMembersPort:
          officialFleetMembersPort ??
          InMemoryOfficialFleetMembersAdapter.forReview(),
      officialFleetShipsPort:
          officialFleetShipsPort ??
          InMemoryOfficialFleetShipsAdapter.forReview(),
      syncPrivacyPort:
          syncPrivacyPort ?? InMemorySyncPrivacyAdapter.forReview(),
      notificationSettingsPort:
          notificationSettingsPort ??
          InMemoryNotificationSettingsAdapter.forReview(),
      overlaySettingsPort:
          overlaySettingsPort ?? InMemoryOverlaySettingsAdapter(),
      overlayWorkspacePort: overlayWorkspacePort,
    );
  }

  factory AppComposition.forTest({
    required WindowChromePort windowChrome,
    MarketplacePort Function()? marketplacePortFactory,
    RemoteImageLoader? remoteImagesOverride,
    CommunitiesPort Function()? communitiesPortFactory,
    FriendsPort Function()? friendsPortFactory,
    DesktopNotificationPort? desktopNotifications,
    ShellChromePort? shellChrome,
    AppPreferencesPort? preferences,
    AccountPort? accountPort,
    PersonalProfilePort? personalProfilePort,
    OfficialFleetPort? officialFleetPort,
    PartyRoomsPort? partyRoomsPort,
    OfficialFleetOverviewPort? officialFleetOverviewPort,
    OfficialFleetMembersPort? officialFleetMembersPort,
    OfficialFleetShipsPort? officialFleetShipsPort,
    CommunityShipsPort? officialFleetSharedShipsPort,
    OrganizationHangarSharingPort? officialFleetHangarSharingPort,
    OrganizationCommunicationFactory? officialFleetCommunicationFactory,
    SyncPrivacyPort? syncPrivacyPort,
    NotificationSettingsPort? notificationSettingsPort,
    OverlaySettingsPort? overlaySettingsPort,
    OverlayWorkspacePort? overlayWorkspacePort,
  }) {
    return AppComposition._withAdapters(
      windowChrome: windowChrome,
      officialFleetSharedShipsPort: officialFleetSharedShipsPort,
      officialFleetHangarSharingPort: officialFleetHangarSharingPort,
      officialFleetCommunicationFactory: officialFleetCommunicationFactory,
      marketplacePortFactory: marketplacePortFactory,
      remoteImagesOverride: remoteImagesOverride,
      communitiesPortFactory: communitiesPortFactory,
      friendsPortFactory: friendsPortFactory,
      desktopNotificationsOverride: desktopNotifications,
      partyRoomsPort: partyRoomsPort,
      shellChrome: shellChrome ?? InMemoryShellChrome(),
      preferences: preferences ?? InMemoryAppPreferences(),
      ownsPreferences: true,
      accountPort:
          accountPort ??
          InMemoryAccountAdapter.forReview(AccountReviewState.signedOut),
      personalProfilePort:
          personalProfilePort ??
          InMemoryPersonalProfileAdapter.forReview(signedIn: false),
      officialFleetPort:
          officialFleetPort ??
          InMemoryOfficialFleetAdapter.forReview(signedIn: false),
      officialFleetOverviewPort:
          officialFleetOverviewPort ??
          UnavailableOfficialFleetOverviewAdapter(),
      officialFleetMembersPort:
          officialFleetMembersPort ?? UnavailableOfficialFleetMembersAdapter(),
      officialFleetShipsPort:
          officialFleetShipsPort ?? UnavailableOfficialFleetShipsAdapter(),
      syncPrivacyPort:
          syncPrivacyPort ?? InMemorySyncPrivacyAdapter.forReview(),
      notificationSettingsPort:
          notificationSettingsPort ??
          InMemoryNotificationSettingsAdapter.forReview(),
      overlaySettingsPort:
          overlaySettingsPort ?? InMemoryOverlaySettingsAdapter(),
      overlayWorkspacePort: overlayWorkspacePort,
    );
  }

  factory AppComposition._withAdapters({
    MarketplacePort Function()? marketplacePortFactory,
    RemoteImageLoader? remoteImagesOverride,
    MenuWindowLifetime? menuLifetime,
    DesktopNotificationPort? desktopNotificationsOverride,
    required WindowChromePort windowChrome,
    required ShellChromePort shellChrome,
    required AppPreferencesPort preferences,
    required bool ownsPreferences,
    required AccountPort accountPort,
    required PersonalProfilePort personalProfilePort,
    required OfficialFleetPort officialFleetPort,
    PartyRoomsPort? partyRoomsPort,
    FriendsPort Function()? friendsPortFactory,
    CommunitiesPort Function()? communitiesPortFactory,
    DirectMessagesPort Function()? directMessagesPortFactory,
    required OfficialFleetOverviewPort officialFleetOverviewPort,
    required OfficialFleetMembersPort officialFleetMembersPort,
    required OfficialFleetShipsPort officialFleetShipsPort,
    CommunityShipsPort? officialFleetSharedShipsPort,
    OrganizationHangarSharingPort? officialFleetHangarSharingPort,
    OrganizationCommunicationFactory? officialFleetCommunicationFactory,
    required SyncPrivacyPort syncPrivacyPort,
    SocialPrivacyComposition? socialPrivacy,
    required NotificationSettingsPort notificationSettingsPort,
    required OverlaySettingsPort overlaySettingsPort,
    OverlayWorkspacePort? overlayWorkspacePort,
    NativeHostLease? nativeHost,
  }) {
    final account = createAccountModule(accountPort);
    unawaited(
      account.initialize(),
    ); // Claim the display root before feature reads.
    final applicationSupport = composeApplicationSupport(nativeHost?.session);
    final partyRooms = PartyRoomsModule(
      partyRoomsPort ?? UnavailablePartyRoomsPort(),
    );
    final personalProfile = createPersonalProfileModule(
      personalProfilePort,
      onSaveSettled: () => unawaited(account.refresh()),
    );
    // The lazy communication factory runs after composition has connected the
    // existing mode owner; keep a single owner, never a second mode projection.
    ConnectedManualPresence? manualPresence;
    final officialFleet = createOfficialFleetModule(
      officialFleetPort,
      officialFleetOverviewPort,
      officialFleetMembersPort,
      officialFleetShipsPort,
      communicationFactory:
          officialFleetCommunicationFactory ??
          (nativeHost == null
              ? null
              : (sourceRef) => createOfficialFleetCommunicationAdapter(
                  nativeHost.session,
                  sourceRef,
                  connectionMode: manualPresence?.connectionMode,
                  ownProfile: () => account.projection.value.profile,
                )),
      // Rally reads count this client as online unless it shows invisible or
      // offline (member board rule: manual offline is offline in the fleet).
      rally: nativeHost == null
          ? null
          : OfficialFleetRallyController(
              BridgeOfficialFleetRallyPort(
                nativeHost.session,
                onlineTrafficAllowed: () =>
                    manualPresence?.connectionMode.allowsOnlineTraffic ?? true,
              ),
              countedOnline: () => !const {
                'presence.invisible',
                'presence.offline',
              }.contains(manualPresence?.source.value.selfKey),
              hotkeys: officialFleetRallyHotkeys(nativeHost.session),
            ),
    );
    final syncPrivacy = createSyncPrivacyModule(syncPrivacyPort);
    final localPrivacy = composeLocalPrivacy(
      nativeHost?.session,
      officialFleet,
    );
    final notificationSettings = createNotificationSettingsModule(
      notificationSettingsPort,
    );
    final notificationInbox = NotificationInboxController(nativeHost?.session)
      ..start();
    final notificationAudio = nativeHost == null
        ? null
        : NotificationAudioController(
            BridgeNotificationAudio(nativeHost.session),
          );
    final continuousPlay =
        nativeHost != null &&
            nativeHost.session.hostCapabilities.contains('playReminder.read') &&
            nativeHost.session.hostCapabilities.contains('playReminder.save')
        ? ContinuousPlayController(BridgeContinuousPlay(nativeHost.session))
        : null;
    late final RemoteImageLoader remoteImages;
    GameLogController? gameLog;
    late final CommunitiesModule communities;
    late final FriendsModule friends;
    late final DirectMessageRefresh? directMessageRefresh;
    final overlaySettings = composeOverlaySettings(
      overlaySettingsPort,
      menuLifetime: menuLifetime ?? MenuWindowLifetime(),
      workspacePort: overlayWorkspacePort,
      session: nativeHost?.session,
      account: account,
      profile: personalProfile,
      rooms: partyRooms,
      createRemoteImages: () => remoteImages.fork(),
      applicationPreferences: preferences,
      menuCommunities: () => communities,
      menuNotices:
          notificationSettingsPort is! BridgeNotificationSettingsAdapter
          ? null
          : () => composeMenuNotices(
              port: notificationSettingsPort,
              settings: notificationSettings,
              account: account,
              preferences: preferences,
              session: nativeHost?.session,
            ),
      menuAttention: () => composeMenuAttention(
        account: account,
        friends: friends,
        messages: directMessageRefresh,
        rooms: partyRooms,
        communities: communities,
        session: nativeHost?.session,
      ),
      menuPresence: () => manualPresence?.source.controller,
      menuGame: () => gameLog?.value ?? const GameLogView(),
      menuLabels: () => composeMenuLabels(preferences),
    );
    final gamePresence = nativeHost == null
        ? null
        : BridgeGamePresence(nativeHost.session);
    final appActivity = AppActivityPresence();
    final gameplayTime = nativeHost == null
        ? null
        : GameplayTimeController(nativeHost.session, account.projection);
    gameLog = nativeHost == null
        ? null
        : GameLogController(
            nativeHost.session,
            account.projection,
            onIdentityChanged: () => unawaited(account.refresh()),
          );
    final handleMismatch = composeHandleMismatch(
      account,
      gameLog,
      nativeHost?.session,
    );
    final accountShellChrome = AccountShellChrome(
      base: shellChrome,
      account: account,
      gamePresence: gamePresence,
      gameLog: gameLog,
      appAway: appActivity,
      overlay: overlaySettings,
    );
    manualPresence = nativeHost == null
        ? null
        : ConnectedManualPresence(
            nativeHost.session,
            accountShellChrome.projection,
            appAway: appActivity,
          );
    accountShellChrome.observeConnectionMode(manualPresence?.connectionMode);
    bindOfficialFleetPresence(
      officialFleet.members,
      officialFleetMembersPort,
      manualPresence,
      localPrivacy,
    );
    final tradeChatPort = nativeHost == null
        ? null
        : BridgeMarketplacePort(
            nativeHost.session,
            manualPresence?.connectionMode,
          );
    final tradeChat = tradeChatPort == null
        ? null
        : MarketplaceChatController(tradeChatPort);
    final (:sharedShips, :ownSharing) = composeOfficialFleetSharing(
      nativeHost?.session,
      officialFleet,
      sharedShipsOverride: officialFleetSharedShipsPort,
      ownSharingOverride: officialFleetHangarSharingPort,
      connectionMode: manualPresence?.connectionMode,
    );
    remoteImages =
        remoteImagesOverride ??
        RemoteImageLoader(
          diskCache: NativeRemoteImageDiskCache.forSession(nativeHost?.session),
          mode: manualPresence?.connectionMode,
          session: nativeHost?.session,
          reconcileMode: manualPresence?.connectionMode.refresh,
        );
    final remoteImageOwner = RemoteImageOwner(account.projection, remoteImages);
    communities = CommunitiesModule(
      (communitiesPortFactory ??
          () => nativeHost != null
              ? composeCommunityBridge(
                  nativeHost.session,
                  account.projection,
                  manualPresence?.connectionMode,
                )
              : UnavailableCommunities())(),
      onOrganizationRenamed: (code, name) {
        personalProfile.renameCommunity(code, name);
        localPrivacy?.renameCommunity(code, name);
        overlaySettings.scenes?.renameCommunity(code, name);
      },
      onWorkspaceFocused: overlaySettings.scenes?.focusCommunity,
    );
    final imageMaintenance = ImageCacheMaintenanceController(
      nativeHost?.session,
      caches: [
        remoteImages,
        communities,
        if (overlaySettings.menuPreview case final DownloadableImageOwner owner)
          owner.downloadableImages,
      ],
    );
    final friendsPort =
        (friendsPortFactory ??
        () => nativeHost != null
            ? BridgeFriendsAdapter(nativeHost.session)
            : UnavailableFriendsPort())();
    friends = FriendsModule(
      friendsPort,
      isExample: friendsPort is ExampleFriendsAdapter,
    );
    unawaited(personalProfile.initialize());
    unawaited(officialFleet.initialize());
    unawaited(syncPrivacy.initialize());
    unawaited(socialPrivacy?.initialize());
    unawaited(notificationSettings.initialize());
    unawaited(overlaySettings.initialize());
    final directMessageRequests = ValueNotifier<int>(0);
    directMessageRefresh = nativeHost == null
        ? null
        : DirectMessageRefresh(
            BridgeDirectMessages(nativeHost.session),
            account.projection,
          );
    return AppComposition._(
      accountShellChrome,
      features: createAppFeatureRegistry(
        account,
        personalProfile,
        officialFleet,
        partyRooms,
        syncPrivacy,
        socialPrivacy,
        localPrivacy,
        notificationSettings,
        notificationInbox,
        notificationAudio,
        continuousPlay,
        overlaySettings,
        preferences,
        nativeHost,
        accountShellChrome,
        gameplayTime,
        gameLog,
        friends,
        communities,
        () {
          final port =
              (directMessagesPortFactory ??
              () => nativeHost != null
                  ? BridgeDirectMessages(
                      nativeHost.session,
                      ownAvatar: () =>
                          account.projection.value.profile?.avatarImageData ??
                          account.projection.value.profile?.avatarUrl,
                    )
                  : UnavailableDirectMessages())();
          return directMessageRefresh?.borrow(port) ?? port;
        },
        applicationSupport,
        directMessageRequests,
        directMessageRefresh?.unread,
        manualPresence?.source.controller,
        manualPresence?.connectionMode,
        marketplacePortFactory,
        sharedShips,
        ownSharing,
        imageMaintenance,
        tradeChat,
      ),
      windowChrome: windowChrome,
      shellChrome: accountShellChrome,
      preferences: preferences,
      account: account,
      personalProfile: personalProfile,
      officialFleet: officialFleet,
      officialFleetSharedShipsPort: sharedShips,
      officialFleetHangarSharingPort: ownSharing,
      partyRooms: partyRooms,
      communities: communities,
      friends: friends,
      syncPrivacy: syncPrivacy,
      socialPrivacy: socialPrivacy,
      localPrivacy: localPrivacy,
      notificationSettings: notificationSettings,
      applicationSupport: applicationSupport,
      directMessageRequests: directMessageRequests,
      socialActivity: nativeHost == null
          ? null
          : SocialActivity(nativeHost.session),
      directMessageRefresh: directMessageRefresh,
      friendRequestRefresh: nativeHost == null
          ? null
          : FriendRequestRefresh(
              BridgeFriendsAdapter(nativeHost.session),
              account.projection,
            ),
      notificationAudio: notificationAudio,
      notificationInbox: notificationInbox,
      tradeChat: tradeChat,
      tradeChatPort: tradeChatPort,
      continuousPlay: continuousPlay,
      desktopNotifications:
          desktopNotificationsOverride ??
          (nativeHost == null
              ? null
              : BridgeDesktopNotificationPort(nativeHost.session)),
      notificationReminders:
          notificationSettingsPort is BridgeNotificationSettingsAdapter
          ? notificationSettingsPort.reminders
          : const Stream.empty(),
      overlaySettings: overlaySettings,
      ownsPreferences: ownsPreferences,
      nativeHost: nativeHost,
      gamePresence: gamePresence,
      manualPresence: manualPresence,
      appActivity: appActivity,
      remoteImages: remoteImages,
      remoteImageOwner: remoteImageOwner,
      imageMaintenance: imageMaintenance,
      gameplayTime: gameplayTime,
      gameLog: gameLog,
      handleMismatch: handleMismatch,
    );
  }

  void dispose() {
    disposeAppComposition(
      this,
      releaseSharingStatus: _sharingStatus?.dispose,
      releaseAccountShellChrome: _accountShellChrome.dispose,
      closeNativeHost: _nativeHost?.close,
    );
  }
}
