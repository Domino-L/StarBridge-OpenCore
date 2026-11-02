import 'package:flutter/material.dart';

import '../common/social_identity_text.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';
import '../../design_system/interaction/starbridge_interaction_theme.dart';
import '../../design_system/icons/starbridge_icon.dart';
import '../../design_system/icons/icon_semantic.dart';
import '../../design_system/tokens/starbridge_tokens.dart';

import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_commands.dart';
import 'room_feedback.dart';
import 'room_display.dart';

class RoomManagementActions extends StatelessWidget {
  const RoomManagementActions({super.key, required this.module});
  final PartyRoomsModule module;
  @override
  Widget build(BuildContext context) => Wrap(
    spacing: 8,
    runSpacing: 8,
    children: [
      StarBridgeActionButton(
        controlKey: const ValueKey('menu-room-settings'),
        onActivate: module.canManage
            ? (source) => editRoomDialog(context, module, source: source)
            : null,
        child: Text(roomActionText(context, 'edit')),
      ),
      StarBridgeActionButton(
        controlKey: const Key('room-applications-open'),
        onActivate: module.canManage
            ? (source) => _applications(context, module, source)
            : null,
        tone: ActionTone.info,
        child: Text(
          '${roomActionText(context, 'applications')} · ${module.selectedRoom?.pendingApplications.length ?? 0}',
        ),
      ),
      StarBridgeActionButton(
        controlKey: const Key('room-close-open'),
        onActivate: module.canManage
            ? (source) => _closeRoom(context, module, source)
            : null,
        tone: ActionTone.danger,
        child: Text(roomActionText(context, 'close')),
      ),
    ],
  );
}

Future<void> _closeRoom(
  BuildContext context,
  PartyRoomsModule module,
  InteractionSource source,
) async {
  final room = module.selectedRoom;
  final revision = module.contextRevision;
  if (room == null || !module.canManage) return;
  final confirmed = await showStarBridgeDialog<bool>(
    context,
    source: source,
    useRootNavigator: false,
    builder: (context) => AlertDialog(
      icon: StarBridgeIcon(
        StarBridgeIconSemantic.warning,
        color: context.tokens.colors.danger,
      ),
      title: Text(roomActionText(context, 'close')),
      content: Text('${room.title}\n\n${roomActionText(context, 'closeHint')}'),
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
  InteractionSource source,
) async {
  final roomId = module.directory?.currentRoomId;
  final revision = module.contextRevision;
  if (roomId == null || !module.canManage) return;
  await showStarBridgeDialog<void>(
    context,
    source: source,
    useRootNavigator: false,
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
          canPop: !module.writing,
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
                            RoomIdentityAvatar(
                              key: ValueKey('applicant-avatar-${item.id}'),
                              name: item.displayName,
                              gameId: item.gameId,
                              avatarData: item.avatarData,
                              userRef: item.userRef,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: SocialIdentityText(
                                callsign: item.callsign,
                                gameId: item.gameId,
                                callsignStyle: Theme.of(context)
                                    .textTheme
                                    .bodyMedium,
                                gameIdColor: Theme.of(context)
                                    .colorScheme
                                    .onSurfaceVariant,
                                maxLines: 2,
                              ),
                            ),
                            StarBridgeActionButton(
                              controlKey: ValueKey('decline-${item.id}'),
                              kind: StarBridgeActionKind.quiet,
                              tone: ActionTone.danger,
                              onActivate: module.canManage
                                  ? (_) => module.execute(
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
                            StarBridgeActionButton(
                              controlKey: ValueKey('approve-${item.id}'),
                              kind: StarBridgeActionKind.primary,
                              tone: ActionTone.success,
                              onActivate: module.canManage
                                  ? (_) => module.execute(
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
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                onActivate: module.writing
                    ? null
                    : (source) =>
                          dismissStarBridgeDialog(context, source: source),
                child: Text(roomActionText(context, 'done')),
              ),
            ],
          ),
        );
      },
    ),
  );
}
