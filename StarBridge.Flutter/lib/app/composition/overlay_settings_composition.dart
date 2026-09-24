import '../../features/account/account_module.dart';
import '../product_features.dart';
import '../../features/account/account_models.dart';
import '../../features/personal_profile/personal_profile_module.dart';
import '../../features/personal_profile/bridge_local_personal_profile.dart';
import '../../features/personal_profile/bridge_personal_profile_adapter.dart';
import '../../features/hangar/bridge_local_hangar.dart';
import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/overlay_settings/overlay_settings_module.dart';
import '../../features/overlay_settings/overlay_settings_port.dart';
import '../../features/overlay_settings/overlay_workspace_port.dart';
import '../../features/overlay_settings/overlay_scene_controller.dart';
import '../../features/overlay_settings/bridge_overlay_scenes.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/window/method_channel_overlay_editor_window.dart';
import '../../platform/window/method_channel_menu_preview_window.dart';
import 'overlay_preview_identity_adapter.dart';
import '../../features/friends/bridge_friends_adapter.dart';
import '../menu_overlay/menu_friends_session.dart';
import '../menu_overlay/menu_comms_session.dart';
import '../menu_overlay/menu_chat_archive.dart';
import '../menu_overlay/menu_comms_invitations.dart';
import '../../features/settings/bridge_local_privacy.dart';
import '../../features/direct_messages/bridge_direct_messages.dart';
import '../../features/common/bridge_user_interaction.dart';
import '../menu_overlay/menu_profiles_session.dart';
import '../presence/manual_presence.dart';
import '../../features/communities/bridge_communities.dart';
import '../../features/party_rooms/bridge_party_rooms_adapter.dart';
import '../menu_overlay/menu_rooms_session.dart';
import '../menu_overlay/menu_organizations_session.dart';
import '../menu_overlay/menu_hud_session.dart';
import '../../platform/window/menu_window_preferences.dart';
import '../../features/game_log/game_log_controller.dart';

OverlaySettingsModule composeOverlaySettings(
  OverlaySettingsPort port, {
  required OverlayWorkspacePort? workspacePort,
  required BridgeClientSession? session,
  required AccountModule account,
  required PersonalProfileModule profile,
  required PartyRoomsModule rooms,
  ManualPresenceController? Function()? menuPresence,
  GameLogView Function()? menuGame,
}) {
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
            contextValues: () {
              final game = menuGame?.call() ?? const GameLogView();
              final scene = module.scenes?.projection.value;
              final room = rooms.directory?.rooms
                  .where((item) => item.id == rooms.directory?.currentRoomId)
                  .firstOrNull;
              final org = scene?.targets
                  .where((item) => 'org:${item.code}' == scene.actualId)
                  .firstOrNull;
              final name =
                  org?.name ??
                  (scene?.actualId == 'room' ? room?.title : null) ??
                  '暂无协作场景';
              final valid =
                  game.visible &&
                  game.match == 'match' &&
                  game.state == 'identified';
              final active = valid && game.sessionState == 'ready';
              return [
                name,
                scene?.actualId == 'room' && room != null
                    ? '${room.members.length} 人'
                    : '—',
                active ? game.shipDisplayName('zh', 'CN') ?? '暂无飞船信息' : '未进入游戏',
                active
                    ? game.locationDisplayName('zh', 'CN') ?? '暂无位置信息'
                    : '未进入游戏',
                active
                    ? [game.serverRegion, game.serverShard]
                          .whereType<String>()
                          .where((v) => v.isNotEmpty)
                          .join(' · ')
                    : '未进入游戏',
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
                    ),
                    'rooms': (publish) => MenuRoomsSession(
                      BridgePartyRoomsAdapter(session),
                      publish,
                    ),
                    'organizationChat': (publish) => MenuOrganizationsSession(
                      BridgeCommunities(session, ownAvatar: ownAvatar),
                      publish,
                      chatOnly: true,
                      archive: BridgeMenuChatArchive(session),
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
                    invitations: (publish) => MenuCommsInvitations(
                      BridgeCommunities(session),
                      publish,
                      createPrivacy: () => BridgeLocalPrivacy(session),
                    ),
                  ),
            profiles: session == null
                ? null
                : (publish) => MenuProfilesSession(
                    () => BridgeUserInteraction(session),
                    publish,
                    createOwnPort: () => BridgeLocalPersonalProfile(
                      session,
                      remote: BridgePersonalProfileAdapter(session),
                      hangar: () => BridgeLocalHangar(session),
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
