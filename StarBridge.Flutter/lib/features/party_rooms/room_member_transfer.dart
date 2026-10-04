import 'package:flutter/material.dart';

import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_commands.dart';
import 'room_member_policy.dart';

String roomTransferText(BuildContext context, String key) {
  final locale = Localizations.localeOf(context);
  final index = locale.languageCode != 'zh'
      ? 2
      : locale.countryCode == 'TW'
      ? 1
      : 0;
  return (switch (key) {
    'transfer' => ['转移房主', '轉移房主', 'Transfer host'],
    'hint' => [
      '将房主交给此成员？你将留在房间，但不再拥有房主管理权限；原房主发出的待处理邀请将失效。',
      '將房主交給此成員？你將留在房間，但不再擁有房主管理權限；原房主發出的待處理邀請將失效。',
      'Make this member the host? You will stay in the room but lose host management permissions. Pending invitations sent by the previous host will expire.',
    ],
    _ => throw ArgumentError.value(key),
  })[index];
}

Future<void> transferRoomHost(
  BuildContext context,
  PartyRoomsModule module,
  RoomMember member,
) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  if (!module.canTransferHost ||
      room == null ||
      !canRemoveRoomMember(room, member)) {
    return;
  }
  final accepted = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      title: Text(roomTransferText(context, 'transfer')),
      content: Text(
        '${member.displayName}\n\n${roomTransferText(context, 'hint')}',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(roomActionText(context, 'cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, true),
          child: Text(roomTransferText(context, 'transfer')),
        ),
      ],
    ),
  );
  if (accepted == true && context.mounted) {
    await module.execute(
      RoomCommand(RoomOperation.transferHost, {
        'roomId': room.id,
        'memberToken': member.removalToken,
      }),
      expectedRevision: revision,
    );
  }
}
