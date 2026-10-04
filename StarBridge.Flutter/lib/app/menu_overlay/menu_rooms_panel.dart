import 'package:flutter/material.dart';

import '../../design_system/surfaces/starbridge_surface.dart';
import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/tokens/color_tokens.dart';
import '../../design_system/tokens/starbridge_tokens.dart';
import '../../features/party_rooms/room_members_panel.dart';
import '../../features/party_rooms/room_display.dart';
import '../../features/party_rooms/room_feedback.dart';
import '../../features/party_rooms/room_action_dialogs.dart';
import '../../features/party_rooms/room_current_toolbar.dart';
import '../../features/party_rooms/room_workspace_layout.dart';
import 'menu_feature_view.dart';
import 'menu_channel_panel.dart';
import 'menu_inline_avatar.dart';
import 'menu_room_lobby_panel.dart';
import 'menu_room_settings.dart';
import 'menu_room_member_menu.dart';

/// Client room components and geometry, with authority in the primary engine.
class MenuRoomsPanel extends StatelessWidget {
  const MenuRoomsPanel({
    super.key,
    required this.view,
    required this.onAction,
    this.active = false,
  });
  final MenuFeatureView view;
  final void Function(String, String) onAction;
  final bool active;

  @override
  Widget build(BuildContext context) {
    final room = view.room;
    if (room == null) {
      final lobby = view.lobby;
      if (lobby == null) {
        return MenuFeaturePanel(view: view, onAction: onAction);
      }
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (view.notice.isNotEmpty) Text(view.notice),
          for (final action in view.buttons)
            MenuFeatureAction(
              action: action,
              enabled: !view.busy,
              onAction: onAction,
            ),
          Expanded(
            child: MenuRoomLobbyPanel(
              key: ValueKey('lobby/${view.scope}'),
              view: lobby,
              onAction: onAction,
            ),
          ),
        ],
      );
    }
    final members = RoomMembersPanel(
      key: ValueKey('members/${view.scope}'),
      listKey: const ValueKey('menu-room-members'),
      room: room.presentation(view.title, view.scope),
      serverTime: room.serverTime ?? DateTime.now().toUtc(),
      memberBuilder: (context, index, member) {
        final actions = [
          ...view.buttons,
          if (!room.canChat && index < view.rows.length)
            ...view.rows[index].buttons,
        ];
        final transfer = actions
            .where((b) => b.key == room.memberTransferActions[index])
            .firstOrNull;
        final action = actions
            .where((b) => b.key == room.memberActions[index])
            .firstOrNull;
        return RoomMemberBanner(
          member: member,
          portrait: MenuInlineAvatar(
            source: member.avatarData,
            name: member.displayName,
          ),
          trailing: action == null && transfer == null
              ? null
              : MenuRoomMemberMenu(
                  key: ValueKey('member-actions-${view.scope}-$index'),
                  action: action,
                  transferAction: transfer,
                  enabled: !view.busy,
                  dispatch: onAction,
                ),
        );
      },
    );
    final chat = StarBridgeSurface(
      role: SurfaceRole.panel,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  roomActionText(context, 'chat'),
                  style: Theme.of(context).textTheme.titleMedium,
                ),
              ),
              TextButton(
                onPressed: view.busy ? null : () => onAction('refresh', ''),
                child: Text(roomActionText(context, 'refreshMessages')),
              ),
            ],
          ),
          Expanded(
            child: MenuChannelPanel(
              view: view,
              onAction: onAction,
              active: active,
              embeddedRoom: true,
            ),
          ),
        ],
      ),
    );
    return MenuRoomSettingsHost(
      key: ValueKey('settings/${view.scope}'),
      view: view,
      dispatch: onAction,
      builder: (context, module) => Padding(
        padding: EdgeInsets.all(context.tokens.space.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    roomText(context, room.canChat ? 'current' : 'roomDetails'),
                    style: Theme.of(context).textTheme.headlineSmall,
                  ),
                ),
                TextButton(
                  onPressed: view.busy ? null : () => onAction('refresh', ''),
                  child: Text(roomText(context, 'refresh')),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (room.management?.current == true)
              RoomCurrentToolbar(
                module: module,
                leaveAction: view.buttons
                    .where((b) => b.label == '退出房间')
                    .map(
                      (action) => MenuFeatureAction(
                        key: const ValueKey('退出房间'),
                        action: action,
                        enabled: !view.busy,
                        onAction: onAction,
                        outlined: true,
                        buttonStyle: semanticActionStyle(
                          context,
                          roomLeaveTone(module.selectedRoom),
                          emphasis: ActionEmphasis.outlined,
                        ),
                      ),
                    )
                    .firstOrNull,
              )
            else
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  for (final action in view.buttons.where(
                    (b) =>
                        !const {
                          '成员',
                          '聊天',
                          '发送消息',
                          '较早消息',
                          '最新消息',
                        }.contains(b.label) &&
                        !room.memberActions.containsValue(b.key) &&
                        !room.memberTransferActions.containsValue(b.key),
                  ))
                    MenuFeatureAction(
                      key: ValueKey(action.label),
                      action: action,
                      enabled: !view.busy,
                      onAction: onAction,
                      outlined: true,
                      buttonStyle: action.label == '退出房间'
                          ? semanticActionStyle(
                              context,
                              roomLeaveTone(
                                room.presentation(view.title, view.scope),
                              ),
                              emphasis: ActionEmphasis.outlined,
                            )
                          : null,
                    ),
                  if (room.settings?.action != null)
                    OutlinedButton(
                      key: const ValueKey('menu-room-settings'),
                      onPressed: view.busy
                          ? null
                          : () => editRoomDialog(context, module),
                      child: Text(roomActionText(context, 'edit')),
                    ),
                ],
              ),
            if (view.notice.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(view.notice),
              ),
            const SizedBox(height: 12),
            Expanded(
              child: room.canChat && view.chat != null
                  ? RoomWorkspaceLayout(
                      key: ValueKey('workspace/${view.scope}'),
                      compactTabs: true,
                      members: members,
                      chat: chat,
                    )
                  : members,
            ),
          ],
        ),
      ),
    );
  }
}
