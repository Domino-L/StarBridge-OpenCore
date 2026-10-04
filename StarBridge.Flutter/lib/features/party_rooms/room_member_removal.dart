import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
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
  RoomMember member,
) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  final token = member.removalToken;
  if (!module.canManage || room == null || !canRemoveRoomMember(room, member)) {
    return;
  }
  final accepted = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: Text(roomRemovalText(context, 'remove')),
      content: Text(
        '${member.displayName}\n\n${roomRemovalText(context, 'hint')}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(roomActionText(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          style: semanticActionStyle(
            context,
            ActionTone.danger,
            emphasis: ActionEmphasis.filled,
          ),
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
