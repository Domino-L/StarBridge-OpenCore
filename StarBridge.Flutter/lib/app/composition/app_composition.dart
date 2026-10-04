import 'dart:async';

import '../../platform/window/menu_attention.dart';
import 'menu_social_notice_source.dart';

import '../localization/app_strings.dart';

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
import '../../features/account/handle_mismatch_port.dart';
import '../../features/account/account_port.dart';
import '../../features/account/bridge_account_adapter.dart';
import '../../features/account/host_unavailable_account_adapter.dart';
import '../../features/account/in_memory_account_adapter.dart';
import '../../features/communities/communities_module.dart';
import '../../features/communities/bridge_communities.dart';
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
import '../../features/official_fleet/official_fleet_port.dart';
import '../../features/official_fleet/bridge_official_fleet_adapter.dart';
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
import '../../features/personal_profile/bridge_personal_profile_adapter.dart';
import '../../features/personal_profile/bridge_local_personal_profile.dart';
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
import '../../features/settings/bridge_application_support.dart';
import '../../features/settings/host_unavailable_application_support.dart';
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
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/settings/local_privacy_controller.dart';

final class AppComposition {
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
    required this.partyRooms,
    required this.communities,
    required this.friends,
    required this.syncPrivacy,
    this.socialPrivacy,
    this.localPrivacy,
    required this.notificationSettings,
    required this.notificationInbox,
    required this.applicationSupport,
    this.notificationAudio,
    this.continuousPlay,
    this.desktopNotifications,
    this.directMessageRefresh,
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
  });

  final FeatureRegistry features;
  final WindowChromePort windowChrome;
  final ShellChromePort shellChrome;
  final AppPreferencesPort preferences;
  final AccountModule account;
  final HandleMismatchModule handleMismatch;
  final PersonalProfileModule personalProfile;
  final OfficialFleetModule officialFleet;
  final PartyRoomsModule partyRooms;
  final CommunitiesModule communities;
  final FriendsModule friends;
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
  DirectMessagesPort createWindowMessagesPort() => _nativeHost == null
      ? UnavailableDirectMessages()
      : BridgeDirectMessages(
          _nativeHost.session,
          ownAvatar: () =>
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
  MenuFriendsSession createFriendsWindowSession(
    void Function(Map<String, Object?>) publish,
  ) => MenuFriendsSession(
    _nativeHost == null
        ? UnavailableFriendsPort()
        : BridgeFriendsAdapter(_nativeHost.session),
    publish,
    presence: manualPresence?.source.controller,
    identity: () {
      final current = account.projection.value;
      if (current.generation != _nativeHost?.session.activeGeneration ||
          !(current.isSignedIn ||
              current.sessionState == AccountSessionState.legacySignedIn)) {
        return null;
      }
      return (
        name:
            current.profile?.displayName ??
            current.identity.authoritativeHandle ??
            '',
        handle: current.identity.authoritativeHandle ?? '',
        avatar: current.profile?.avatarImageData,
      );
    },
  );
  late final userInteractions = _nativeHost == null
      ? null
      : BridgeUserInteraction(_nativeHost.session);
  DirectMessagesPort createUserMessages() => _nativeHost == null
      ? UnavailableDirectMessages()
      : BridgeDirectMessages(
          _nativeHost.session,
          ownAvatar: () => account.projection.value.profile?.avatarUrl,
        );
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
      personalProfilePort: BridgeLocalPersonalProfile(
        nativeHost.session,
        remote: BridgePersonalProfileAdapter(nativeHost.session),
        hangar: () => BridgeLocalHangar(nativeHost.session),
      ),
      officialFleetPort: BridgeOfficialFleetAdapter(nativeHost.session),
      partyRoomsPort: BridgePartyRoomsAdapter(
        nativeHost.session,
        onReminder: notifications.onRoomReminder,
      ),
      officialFleetOverviewPort: UnavailableOfficialFleetOverviewAdapter(),
      officialFleetMembersPort: UnavailableOfficialFleetMembersAdapter(),
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
    SyncPrivacyPort? syncPrivacyPort,
    NotificationSettingsPort? notificationSettingsPort,
    OverlaySettingsPort? overlaySettingsPort,
    OverlayWorkspacePort? overlayWorkspacePort,
  }) {
    return AppComposition._withAdapters(
      windowChrome: windowChrome,
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
    required SyncPrivacyPort syncPrivacyPort,
    SocialPrivacyComposition? socialPrivacy,
    required NotificationSettingsPort notificationSettingsPort,
    required OverlaySettingsPort overlaySettingsPort,
    OverlayWorkspacePort? overlayWorkspacePort,
    NativeHostLease? nativeHost,
  }) {
    final account = createAccountModule(accountPort);
    final applicationSupport = createApplicationSupportModule(
      nativeHost == null ||
              !nativeHost.session.hostCapabilities.contains(
                'diagnostics.safeSummary',
              )
          ? HostUnavailableApplicationSupport()
          : BridgeApplicationSupport(nativeHost.session),
    );
    final partyRooms = PartyRoomsModule(
      partyRoomsPort ?? UnavailablePartyRoomsPort(),
    );
    final personalProfile = createPersonalProfileModule(personalProfilePort);
    final officialFleet = createOfficialFleetModule(
      officialFleetPort,
      officialFleetOverviewPort,
      officialFleetMembersPort,
      officialFleetShipsPort,
    );
    final syncPrivacy = createSyncPrivacyModule(syncPrivacyPort);
    final localPrivacy = nativeHost == null
        ? null
        : LocalPrivacyController(BridgeLocalPrivacy(nativeHost.session));
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
    ConnectedManualPresence? manualPresence;
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
      menuCommunities: () => communities,
      menuNotices:
          notificationSettingsPort is! BridgeNotificationSettingsAdapter
          ? null
          : () {
              final generation = account.projection.value.generation;
              return MenuSocialNoticeSource(
                events: notificationSettingsPort.reminders,
                settings: notificationSettings.projection,
                authorization: account.projection,
                invalidations: nativeHost?.session.events
                    .where(
                      (event) =>
                          event.name == 'account.changed' ||
                          event.name == 'bootstrap.invalidated',
                    )
                    .map((_) {}),
                isCurrent: () {
                  final current = account.projection.value;
                  return current.generation == generation &&
                      current.generation ==
                          nativeHost?.session.activeGeneration &&
                      (current.isSignedIn ||
                          current.sessionState ==
                              AccountSessionState.legacySignedIn);
                },
                strings: () => AppStrings.resolve(
                  preferences.projection.value.effective.locale,
                ),
              );
            },
      menuAttention: () {
        final generation = account.projection.value.generation;
        return MenuAttentionSource(
          changes: [
            account.projection,
            friends.incomingAttention,
            if (directMessageRefresh != null) directMessageRefresh.unread,
            partyRooms.activityCount,
            communities.chatAttention,
          ],
          isCurrent: () {
            final current = account.projection.value;
            return current.generation == generation &&
                current.generation == nativeHost?.session.activeGeneration &&
                (current.isSignedIn ||
                    current.sessionState == AccountSessionState.legacySignedIn);
          },
          invalidations: nativeHost?.session.events
              .where(
                (event) =>
                    event.name == 'account.changed' ||
                    event.name == 'bootstrap.invalidated',
              )
              .map((_) {}),
          read: () => MenuAttention(
            friends: friends.incomingAttention.value,
            comms: directMessageRefresh?.unread.value ?? 0,
            rooms: partyRooms.activityCount.value,
            organizations: communities.chatAttention.totalCount,
          ),
        );
      },
      menuPresence: () => manualPresence?.source.controller,
      menuGame: () => gameLog?.value ?? const GameLogView(),
      menuLabels: () {
        final strings = AppStrings.resolve(
          preferences.projection.value.effective.locale,
        );
        return (
          contextLabel: strings.text('overlay.sections.menu'),
          returnLabel: strings.text('overlay.menu.return'),
          settingsLabel: strings.text('overlay.sections.menu'),
        );
      },
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
    final handleMismatch = HandleMismatchModule(
      account: account.projection,
      gameLog: gameLog,
      port: nativeHost == null
          ? null
          : BridgeHandleMismatchPort(nativeHost.session),
      activeGeneration: nativeHost == null
          ? null
          : () => nativeHost.session.activeGeneration,
      invalidations: nativeHost?.session.events
          .where(
            (event) =>
                event.name == 'account.changed' ||
                event.name == 'bootstrap.invalidated',
          )
          .map((_) {}),
      refresh: () async {
        await account.refresh();
        await gameLog?.run();
      },
    );
    final accountShellChrome = AccountShellChrome(
      base: shellChrome,
      account: account,
      gamePresence: gamePresence,
      gameLog: gameLog,
      appAway: appActivity,
      scenes: overlaySettings.scenes,
    );
    manualPresence = nativeHost == null
        ? null
        : ConnectedManualPresence(
            nativeHost.session,
            accountShellChrome.projection,
            appAway: appActivity,
          );
    communities = CommunitiesModule(
      (communitiesPortFactory ??
          () => nativeHost != null
              ? BridgeCommunities(
                  nativeHost.session,
                  ownAvatar: () {
                    final current = account.projection.value;
                    return current.generation ==
                                nativeHost.session.activeGeneration &&
                            (current.isSignedIn ||
                                current.sessionState ==
                                    AccountSessionState.legacySignedIn)
                        ? current.profile?.avatarImageData
                        : null;
                  },
                )
              : UnavailableCommunities())(),
      onOrganizationRenamed: (code, name) {
        personalProfile.renameCommunity(code, name);
        localPrivacy?.renameCommunity(code, name);
        overlaySettings.scenes?.renameCommunity(code, name);
      },
      onWorkspaceFocused: overlaySettings.scenes?.focusCommunity,
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
    unawaited(account.initialize());
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
        directMessagesPortFactory ??
            () => nativeHost != null
                ? BridgeDirectMessages(
                    nativeHost.session,
                    ownAvatar: () =>
                        account.projection.value.profile?.avatarImageData ??
                        account.projection.value.profile?.avatarUrl,
                  )
                : UnavailableDirectMessages(),
        applicationSupport,
        directMessageRequests,
        directMessageRefresh?.unread,
      ),
      windowChrome: windowChrome,
      shellChrome: accountShellChrome,
      preferences: preferences,
      account: account,
      personalProfile: personalProfile,
      officialFleet: officialFleet,
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
      notificationAudio: notificationAudio,
      notificationInbox: notificationInbox,
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
      gameplayTime: gameplayTime,
      gameLog: gameLog,
      handleMismatch: handleMismatch,
    );
  }

  void dispose() {
    handleMismatch.dispose();
    _sharingStatus?.dispose();
    unawaited(userInteractions?.close());
    directMessageRequests?.dispose();
    directMessageRefresh?.dispose();
    socialActivity?.dispose();
    manualPresence?.dispose();
    _accountShellChrome.dispose();
    appActivity.dispose();
    gamePresence?.dispose();
    gameplayTime?.dispose();
    gameLog?.dispose();
    account.dispose();
    personalProfile.dispose();
    officialFleet.dispose();
    partyRooms.dispose();
    communities.dispose();
    friends.dispose();
    syncPrivacy.dispose();
    socialPrivacy?.dispose();
    localPrivacy?.dispose();
    notificationSettings.dispose();
    notificationInbox.dispose();
    applicationSupport.dispose();
    notificationAudio?.dispose();
    continuousPlay?.dispose();
    overlaySettings.dispose();
    if (ownsPreferences) {
      preferences.dispose();
    }
    final nativeHost = _nativeHost;
    if (nativeHost != null) {
      unawaited(nativeHost.close());
    }
  }
}
