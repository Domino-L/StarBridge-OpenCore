import 'dart:ui' show Locale;

import '../../features/account/account_module.dart';
import '../../shared/remote_image_loader.dart';
import '../product_features.dart';
import '../preferences/app_preferences_port.dart';
import '../preferences/app_preferences.dart';

import 'package:flutter/widgets.dart' show WidgetsBinding;

import '../localization/app_strings.dart';
import '../../platform/window/menu_interaction_presentation.dart';
import '../../features/account/account_models.dart';
import '../../features/personal_profile/personal_profile_module.dart';
import 'personal_profile_bridge_composition.dart';
import '../../features/hangar/bridge_local_hangar.dart';
import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import '../../features/overlay_settings/overlay_settings_port.dart';
import '../../features/overlay_settings/overlay_workspace_port.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../../features/overlay_settings/bridge_overlay_scenes.dart';
import '../../features/overlay_settings/overlay_roster_editor.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/window/method_channel_overlay_editor_window.dart';
import '../../platform/window/method_channel_menu_preview_window.dart';
import 'overlay_preview_identity_adapter.dart';
import '../../features/friends/bridge_friends_adapter.dart';
import '../menu_overlay/menu_friends_session.dart';
import '../menu_overlay/menu_holiday.dart';
import '../menu_overlay/menu_comms_session.dart';
import '../menu_overlay/menu_chat_archive.dart';
import '../menu_overlay/menu_comms_invitations.dart';
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/direct_messages/bridge_direct_messages.dart';
import '../../features/common/bridge_user_interaction.dart';
import '../menu_overlay/menu_profiles_session.dart';
import '../presence/manual_presence.dart';
import '../../features/communities/bridge_communities.dart';
import '../../features/communities/communities_module.dart';
import '../../features/communities/community_overview_reader.dart';
import '../../features/party_rooms/bridge_party_rooms_adapter.dart';
import '../menu_overlay/menu_rooms_session.dart';
import '../menu_overlay/menu_organizations_session.dart';
import '../menu_overlay/menu_hud_session.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../../features/game_log/game_log_controller.dart';
import '../../platform/window/menu_hotkey_port.dart';
import '../../platform/window/bridge_menu_hotkeys.dart';
import '../../platform/window/menu_attention.dart';
import '../../platform/window/menu_notice.dart';
import '../../platform/window/menu_recovery.dart';
import '../../platform/window/menu_browser_resume.dart';
import '../../platform/window/menu_screenshot_directory.dart';
import '../../features/tools/exec_hangar_port.dart';

OverlaySettingsModule composeOverlaySettings(
  OverlaySettingsPort port, {
  required MenuWindowLifetime menuLifetime,
  required OverlayWorkspacePort? workspacePort,
  required BridgeClientSession? session,
  required AccountModule account,
  required PersonalProfileModule profile,
  required PartyRoomsModule rooms,
  AppPreferencesPort? applicationPreferences,
  CommunitiesModule Function()? menuCommunities,
  ManualPresenceController? Function()? menuPresence,
  GameLogView Function()? menuGame,
  MenuOpenLabels Function()? menuLabels,
  MenuAttentionSource Function()? menuAttention,
  MenuNoticeSource Function()? menuNotices,
  RemoteImageLoader Function()? createRemoteImages,
}) {
  int? settingsGeneration;
  BridgeMenuBrowserResume? resumeSettings;
  BridgeMenuScreenshotDirectory? directorySettings;
  void bindSettingsGeneration() {
    if (session == null || settingsGeneration == session.activeGeneration) {
      return;
    }
    // Composition exists before account restoration. Acquire these ports only
    // when consumed, retaining identity within a generation while invalidating
    // old account scopes and any old pending directory picker.
    directorySettings?.dispose();
    settingsGeneration = session.activeGeneration;
    resumeSettings = BridgeMenuBrowserResume(session);
    directorySettings = BridgeMenuScreenshotDirectory(session);
  }

  String? ownAvatar() {
    final current = account.projection.value;
    return current.generation == session?.activeGeneration &&
            (current.isSignedIn ||
                current.sessionState == AccountSessionState.legacySignedIn)
        ? current.profile?.avatarImageData
        : null;
  }

  late final OverlaySettingsModule module;
  module = OverlaySettingsModule(
    port,
    workspacePort: workspacePort,
    editorWindow: const MethodChannelOverlayEditorWindow(),
    menuPreview: !menuOverlayEnabled
        ? null
        : MethodChannelMenuPreviewWindow(
            lifetime: menuLifetime,
            interaction: applicationPreferences == null
                ? null
                : MenuInteractionFeed(
                    changes: applicationPreferences.projection,
                    read: () {
                      final value =
                          applicationPreferences.projection.value.effective;
                      return MenuInteractionPresentation(
                        language: value.locale.toLanguageTag(),
                        holiday: menuHolidayId(
                          enabled: value.holidayAppearance,
                          now: DateTime.now(),
                        ),
                        style: MenuInteractionStyle.values.byName(
                          value.interactionStyle.name,
                        ),
                        reduceMotion:
                            value.motionPreference == MotionPreference.reduce,
                      );
                    },
                  ),
            execHangarProvider:
                session?.hostCapabilities.contains('execHangar.read') == true
                ? () => BridgeExecHangar(session!)
                : null,
            screenshotDirectoryProvider:
                session != null &&
                    const {
                      'menuScreenshotDirectory.read',
                      'menuScreenshotDirectory.choose',
                      'menuScreenshotDirectory.reset',
                      'menuScreenshotDirectory.open',
                    }.every(session.hostCapabilities.contains)
                ? () {
                    bindSettingsGeneration();
                    return directorySettings;
                  }
                : null,
            browserResumeProvider:
                session != null &&
                    const {
                      'menuBrowserResume.read',
                      'menuBrowserResume.update',
                      'menuBrowserResume.remember',
                    }.every(session.hostCapabilities.contains)
                ? () {
                    bindSettingsGeneration();
                    return resumeSettings;
                  }
                : null,
            attention: menuAttention,
            notices: menuNotices,
            recovery:
                session?.hostCapabilities.contains(
                      'applicationPreferences.menu.recovery',
                    ) ==
                    true
                ? BridgeMenuRecovery(session!)
                : null,
            hotkeyLabels: menuLabels,
            hotkeys:
                session?.hostCapabilities.contains('menuHotkey.runtime') == true
                ? BridgeMenuHotkeys(
                    session!,
                    activation: account.projection,
                    isActive: () {
                      final current = account.projection.value;
                      return current.generation == session.activeGeneration &&
                          (current.isSignedIn ||
                              current.sessionState ==
                                  AccountSessionState.legacySignedIn);
                    },
                  )
                : null,
            contextValues: () {
              final game = menuGame?.call() ?? const GameLogView();
              final scene = module.scenes?.projection.value;
              final room = rooms.directory?.rooms
                  .where((item) => item.id == rooms.directory?.currentRoomId)
                  .firstOrNull;
              final org = scene?.targets
                  .where((item) => 'org:${item.code}' == scene.actualId)
                  .firstOrNull;
              final locale =
                  applicationPreferences?.projection.value.effective.locale ??
                  WidgetsBinding.instance.platformDispatcher.locale;
              final strings = AppStrings.resolve(locale);
              final name =
                  org?.name ??
                  (scene?.actualId == 'room' ? room?.title : null) ??
                  (scene?.actualId == 'fleet'
                      ? scene?.fleetName ?? strings.text('overlay.source.fleet')
                      : null) ??
                  strings.text('menu.display.noScene');
              final valid =
                  game.visible &&
                  game.match == 'match' &&
                  game.state == 'identified';
              final active = valid && game.sessionState == 'ready';
              final notInGame = strings.text('menu.display.notInGame');
              return [
                name,
                scene?.actualId == 'room' && room != null
                    ? strings
                          .text('menu.display.memberCount')
                          .replaceAll('{count}', '${room.members.length}')
                    : '—',
                active
                    ? game.shipDisplayName(
                            locale.languageCode,
                            locale.countryCode,
                          ) ??
                          strings.text('menu.display.noShip')
                    : notInGame,
                active
                    ? game.locationDisplayName(
                            locale.languageCode,
                            locale.countryCode,
                          ) ??
                          strings.text('menu.display.noLocation')
                    : notInGame,
                active
                    ? [game.serverRegion, game.serverShard]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · ')
                    : notInGame,
                menuPresence?.call()?.snapshot.selfKey ?? 'presence.unknown',
              ];
            },
            preferences:
                session?.hostCapabilities.contains(
                      'applicationPreferences.menu',
                    ) ==
                    true
                ? BridgeMenuWindowPreferences(session!)
                : null,
            features: session == null
                ? const {}
                : {
                    'organizations': (publish) => MenuOrganizationsSession(
                      BridgeCommunities(session, ownAvatar: ownAvatar),
                      publish,
                      locale: () =>
                          applicationPreferences
                              ?.projection
                              .value
                              .effective
                              .locale ??
                          const Locale('zh', 'CN'),
                      overview: menuCommunities == null
                          ? null
                          : CommunityOverviewReader(menuCommunities()),
                    ),
                    'rooms': (publish) => MenuRoomsSession(
                      BridgePartyRoomsAdapter(session),
                      publish,
                      locale: () =>
                          applicationPreferences
                              ?.projection
                              .value
                              .effective
                              .locale ??
                          const Locale('zh', 'CN'),
                    ),
                    if (workspacePort != null)
                      'hud': (publish) => MenuHudSession(
                        module.workspace!,
                        module.scenes,
                        publish,
                      ),
                  },
            friends: session == null
                ? null
                : (publish) => MenuFriendsSession(
                    BridgeFriendsAdapter(session),
                    publish,
                    presence: menuPresence?.call(),
                    identityChanges: account.projection,
                    identity: () {
                      final current = account.projection.value;
                      if (current.generation != session.activeGeneration ||
                          !(current.isSignedIn ||
                              current.sessionState ==
                                  AccountSessionState.legacySignedIn)) {
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
                  ),
            comms: session == null
                ? null
                : (publish) => MenuCommsSession(
                    BridgeDirectMessages(session),
                    publish,
                    archive: BridgeMenuChatArchive(session),
                    ownAvatar: ownAvatar,
                    identityChanges: account.projection,
                    invitations: (publish) => MenuCommsInvitations(
                      BridgeCommunities(session),
                      publish,
                      locale: () =>
                          applicationPreferences
                              ?.projection
                              .value
                              .effective
                              .locale ??
                          const Locale('zh', 'CN'),
                      createPrivacy: () => BridgeLocalPrivacy(session),
                    ),
                  ),
            profiles: session == null
                ? null
                : (publish) => MenuProfilesSession(
                    () => BridgeUserInteraction(session),
                    publish,
                    createImages: createRemoteImages,
                    createOwnPort: () => createBridgePersonalProfilePort(
                      session,
                      inventoryOrigin: HangarReadOrigin.menuProfile,
                    ),
                  ),
          ),
    previewIdentity: OverlayPreviewIdentityAdapter(
      account: account.projection,
      personalProfile: profile.projection,
    ),
    scenes: session == null
        ? null
        : OverlaySceneController(BridgeOverlayScenes(session)),
    roster: session == null ? null : BridgeOverlayRoster(session),
    // Runtime facts are pushed; these still warrant one read while watched.
    languageChanges: applicationPreferences?.projection,
    language: applicationPreferences == null
        ? null
        : () => applicationPreferences.projection.value.effective.locale,
    hostInvalidations: session?.events
        .where((event) => event.name == 'bootstrap.invalidated')
        .map((_) {}),
  );
  if (session != null) {
    rooms.chat?.onPresetImported = () async {
      final workspace = module.workspace;
      if (workspace != null && !workspace.projection.value.dirty) {
        await workspace.refresh();
      }
    };
  }
  return module;
}
