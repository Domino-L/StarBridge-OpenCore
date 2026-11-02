import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
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
        StarBridgeActionButton(
          tone: ActionTone.info,
          onActivate: module.canCommand
              ? (source) => showRoomInvitations(context, module, source: source)
              : null,
          child: Text(
            '${roomActionText(context, 'invitations')} · ${module.directory?.receivedInvitations.length ?? 0}',
          ),
        ),
      if (module.supportsInvitations &&
          module.selectedRoom?.viewerIsHost == true)
        StarBridgeActionButton(
          onActivate: module.canInvite
              ? (source) => showRoomInvitations(
                  context,
                  module,
                  host: true,
                  source: source,
                )
              : null,
          child: Text(roomActionText(context, 'inviteFriends')),
        ),
      leaveAction ??
          StarBridgeActionButton(
            controlKey: const Key('room-leave-open'),
            tone: roomLeaveTone(module.selectedRoom),
            onActivate: module.canCommand
                ? (source) => leaveRoomDialog(context, module, source: source)
                : null,
            child: Text(roomActionText(context, 'leave')),
          ),
      if (module.supportsManagement &&
          module.selectedRoom?.viewerIsHost == true)
        RoomManagementActions(module: module),
    ],
  );
}
