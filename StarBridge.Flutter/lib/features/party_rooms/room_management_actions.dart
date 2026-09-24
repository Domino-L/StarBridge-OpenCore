import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_commands.dart';
import 'room_feedback.dart';

class RoomManagementActions extends StatelessWidget {
  const RoomManagementActions({super.key, required this.module});
  final PartyRoomsModule module;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      OutlinedButton(
        onPressed: module.canManage
            ? () => editRoomDialog(context, module)
            : null,
        child: Text(roomActionText(context, 'edit')),
      ),
      OutlinedButton(
        onPressed: module.canManage
            ? () => _applications(context, module)
            : null,
        style: semanticActionStyle(
          context,
          ActionTone.info,
          emphasis: ActionEmphasis.outlined,
        ),
        child: Text(
          '${roomActionText(context, 'applications')} · ${module.selectedRoom?.pendingApplications.length ?? 0}',
        ),
      ),
      OutlinedButton(
        onPressed: module.canManage ? () => _closeRoom(context, module) : null,
        style: semanticActionStyle(
          context,
          ActionTone.danger,
          emphasis: ActionEmphasis.outlined,
        ),
        child: Text(roomActionText(context, 'close')),
      ),
    ],
  );
}

Future<void> _closeRoom(BuildContext context, PartyRoomsModule module) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  if (room == null || !module.canManage) return;
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (context) => AlertDialog(
      icon: StarBridgeIcon(
        StarBridgeIconSemantic.warning,
        color: context.tokens.colors.danger,
      ),
      title: Text(roomActionText(context, 'close')),
      content: Text('${room.title}\n\n${roomActionText(context, 'closeHint')}'),
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
          child: Text(roomActionText(context, 'close')),
        ),
      ],
    ),
  );
  if (confirmed == true) {
    await module.execute(
      RoomCommand(RoomOperation.close, {'roomId': room.id}),
      expectedRevision: revision,
    );
  }
}

Future<void> _applications(
  BuildContext context,
  PartyRoomsModule module,
) async {
  final roomId = module.directory?.currentRoomId;
  final revision = module.contextRevision;
  if (roomId == null || !module.canManage) return;
  await showDialog<void>(
    context: context,
    barrierDismissible: false,
    builder: (context) => ListenableBuilder(
      listenable: module,
      builder: (context, _) {
        final valid =
            revision == module.contextRevision &&
            module.directory?.currentRoomId == roomId &&
            module.selectedRoom?.viewerIsHost == true;
        final items = valid
            ? module.selectedRoom!.pendingApplications
            : <RoomApplication>[];
        return PopScope(
          canPop: !module.busy,
          child: AlertDialog(
            title: Text(roomActionText(context, 'applications')),
            content: SizedBox(
              width: 540,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!valid)
                      Text(
                        roomActionText(
                          context,
                          module.commandNeedsRefresh
                              ? 'refreshRequired'
                              : 'contextChanged',
                        ),
                      )
                    else if (items.isEmpty)
                      Text(roomActionText(context, 'noApplications')),
                    for (final item in items)
                      Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(
                          children: [
                            Expanded(child: Text(item.displayName)),
                            TextButton(
                              key: ValueKey('decline-${item.id}'),
                              style: semanticActionStyle(
                                context,
                                ActionTone.danger,
                              ),
                              onPressed: module.canManage
                                  ? () => module.execute(
                                      RoomCommand(RoomOperation.decide, {
                                        'roomId': roomId,
                                        'applicationId': item.id,
                                        'approve': false,
                                      }),
                                      expectedRevision: revision,
                                    )
                                  : null,
                              child: Text(roomActionText(context, 'decline')),
                            ),
                            FilledButton(
                              key: ValueKey('approve-${item.id}'),
                              style: semanticActionStyle(
                                context,
                                ActionTone.success,
                                emphasis: ActionEmphasis.filled,
                              ),
                              onPressed: module.canManage
                                  ? () => module.execute(
                                      RoomCommand(RoomOperation.decide, {
                                        'roomId': roomId,
                                        'applicationId': item.id,
                                        'approve': true,
                                      }),
                                      expectedRevision: revision,
                                    )
                                  : null,
                              child: Text(roomActionText(context, 'approve')),
                            ),
                          ],
                        ),
                      ),
                    if (module.commandMessage != null)
                      RoomFeedback(module.commandMessage!),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: module.busy ? null : () => Navigator.pop(context),
                child: Text(roomActionText(context, 'done')),
              ),
            ],
          ),
        );
      },
    ),
  );
}
