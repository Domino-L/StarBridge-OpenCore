import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import 'party_rooms_module.dart';
import 'room_commands.dart';
import 'room_action_dialogs.dart';
import 'room_member_policy.dart';

String roomRemovalText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final index = locale.languageCode != 'zh'
      ? 2
      : locale.countryCode == 'TW'
      ? 1
      : 0;
  return (switch (key) {
    'remove' => ['移出房间', '移出房間', 'Remove from room'],
    'hint' => [
      '移出后，对方将离开当前房间。',
      '移出後，對方將離開目前房間。',
      'This member will leave the current room.',
    ],
    _ => throw ArgumentError.value(key),
  })[index];
}

Future<void> removeRoomMember(
  BuildContext context,
  PartyRoomsModule module,
  RoomMember member, {
  InteractionSource? source,
}) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  final token = member.removalToken;
  if (!module.canManage || room == null || !canRemoveRoomMember(room, member)) {
    return;
  }
  final accepted = await showStarBridgeDialog<bool>(
    context,
    source: source,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: Text(roomRemovalText(context, 'remove')),
      content: Text(
        '${member.displayName}\n\n${roomRemovalText(context, 'hint')}',
      ),
      actions: [
        StarBridgeActionButton(
          kind: StarBridgeActionKind.quiet,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source, result: false),
          child: Text(roomActionText(context, 'cancel')),
        ),
        StarBridgeActionButton(
          kind: StarBridgeActionKind.primary,
          tone: ActionTone.danger,
          onActivate: (source) =>
              dismissStarBridgeDialog(context, source: source, result: true),
          child: Text(roomRemovalText(context, 'remove')),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    await module.execute(
      RoomCommand(RoomOperation.remove, {
        'roomId': room.id,
        'removalToken': token,
      }),
      expectedRevision: revision,
    );
  }
}
