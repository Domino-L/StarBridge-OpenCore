import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_feedback.dart';
import 'room_invitation_dialog.dart';
import 'room_management_actions.dart';

/// The client and menu render the same current-room actions and ordering.
class RoomCurrentToolbar extends StatelessWidget {
  const RoomCurrentToolbar({super.key, required this.module, this.leaveAction});
  final PartyRoomsModule module;
  final Widget? leaveAction;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      if (module.supportsInvitations)
        OutlinedButton(
          style: semanticActionStyle(
            context,
            ActionTone.info,
            emphasis: ActionEmphasis.outlined,
          ),
          onPressed: module.canCommand
              ? () => showRoomInvitations(context, module)
              : null,
          child: Text(
            '${roomActionText(context, 'invitations')} · ${module.directory?.receivedInvitations.length ?? 0}',
          ),
        ),
      if (module.supportsInvitations &&
          module.selectedRoom?.viewerIsHost == true)
        OutlinedButton(
          onPressed: module.canInvite
              ? () => showRoomInvitations(context, module, host: true)
              : null,
          child: Text(roomActionText(context, 'inviteFriends')),
        ),
      leaveAction ??
          OutlinedButton(
            style: semanticActionStyle(
              context,
              roomLeaveTone(module.selectedRoom),
              emphasis: ActionEmphasis.outlined,
            ),
            onPressed: module.canCommand
                ? () => leaveRoomDialog(context, module)
                : null,
            child: Text(roomActionText(context, 'leave')),
          ),
      if (module.supportsManagement &&
          module.selectedRoom?.viewerIsHost == true)
        RoomManagementActions(module: module),
    ],
  );
}
