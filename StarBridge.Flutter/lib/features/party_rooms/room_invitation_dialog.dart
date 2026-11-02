import 'package:flutter/material.dart';
import 'package:starbridge_interaction/starbridge_interaction.dart';

import '../../design_system/controls/semantic_action_style.dart';
import '../../design_system/interaction/starbridge_action_button.dart';
import '../../design_system/interaction/starbridge_dialog.dart';

import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_commands.dart';
import 'room_invitations.dart';
import 'room_feedback.dart';
import 'room_invitation_card.dart';
import '../common/chat_room_invitation.dart';

Future<void> showRoomInvitations(
  BuildContext context,
  PartyRoomsModule module, {
  bool host = false,
  String? invitationId,
  InteractionSource? source,
}) => showStarBridgeDialog<void>(
  context,
  source: source,
  useRootNavigator: false,
  barrierDismissible: false,
  builder: (_) =>
      _InvitationDialog(module: module, host: host, invitationId: invitationId),
);

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({
    required this.module,
    required this.host,
    this.invitationId,
  });
  final PartyRoomsModule module;
  final bool host;
  final String? invitationId;
  @override
  State<_InvitationDialog> createState() => _InvitationDialogState();
}

class _InvitationDialogState extends State<_InvitationDialog> {
  late final int _revision = widget.module.contextRevision;
  late final String? _roomId = widget.module.directory?.currentRoomId;
  List<RoomInviteTarget> _targets = const [];
  String? _error;
  bool _loading = false;
  final Map<String, PartyRoom> _previews = {};
  final Set<String> _previewLoading = {};
  bool get _valid =>
      widget.module.contextRevision == _revision &&
      (!widget.host ||
          (widget.module.directory?.currentRoomId == _roomId &&
              widget.module.selectedRoom?.viewerIsHost == true));
  @override
  void initState() {
    super.initState();
    if (widget.host && widget.invitationId == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreviews());
    }
  }

  Future<void> _loadPreviews() async {
    final invitations =
        (widget.host
            ? widget.module.directory?.sentInvitations
            : widget.module.directory?.receivedInvitations) ??
        const [];
    for (final item in invitations) {
      if (widget.invitationId != null && widget.invitationId != item.id) {
        continue;
      }
      if (!mounted || !_valid) return;
      if (widget.module.directory?.rooms.any((r) => r.id == item.roomId) ==
          true) {
        continue;
      }
      setState(() => _previewLoading.add(item.id));
      try {
        final room = await widget.module.previewInvitation(item);
        if (!mounted || !_valid) return;
        if (room != null) _previews[item.id] = room;
      } catch (_) {
        // A failed optional read never accepts, rejects or hides the invitation.
      } finally {
        if (mounted) setState(() => _previewLoading.remove(item.id));
      }
    }
  }

  Future<void> _load() async {
    if (!mounted || !_valid || _loading) return;
    setState(() {
      _loading = true;
      _error = null;
    });
    final result = await widget.module.execute(
      RoomCommand(RoomOperation.inviteTargets, {'roomId': _roomId}),
      expectedRevision: _revision,
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _targets = _valid ? result.targets : const [];
      _error = result.error;
    });
  }

  Future<void> _action(
    RoomOperation operation,
    Map<String, Object?> data, {
    InteractionSource source = InteractionSource.pointer,
  }) async {
    if (!_valid) return;
    final result = await widget.module.execute(
      RoomCommand(operation, data),
      expectedRevision: _revision,
    );
    if (!mounted) return;
    setState(() => _error = result.error);
    if (result.accepted && operation == RoomOperation.inviteJoin) {
      dismissStarBridgeDialog(context, source: source);
    } else if (result.accepted && widget.host && _valid) {
      await _load();
    }
  }

  Future<void> _accept(RoomInvitation item, InteractionSource source) async {
    var confirmationSource = source;
    final confirmed = await showStarBridgeDialog<bool>(
      context,
      source: source,
      useRootNavigator: false,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Text(roomActionText(context, 'acceptInvitation')),
        actions: [
          StarBridgeActionButton(
            kind: StarBridgeActionKind.quiet,
            onActivate: (source) =>
                dismissStarBridgeDialog(context, source: source, result: false),
            child: Text(roomActionText(context, 'cancel')),
          ),
          StarBridgeActionButton(
            kind: StarBridgeActionKind.primary,
            onActivate: (source) {
              confirmationSource = source;
              dismissStarBridgeDialog(context, source: source, result: true);
            },
            child: Text(roomActionText(context, 'join')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action(RoomOperation.inviteJoin, {
        'roomId': item.roomId,
        'invitationId': item.id,
      }, source: confirmationSource);
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.module,
    builder: (context, _) {
      final module = widget.module;
      String t(String key) => roomActionText(context, key);
      final source = !_valid
          ? <RoomInvitation>[]
          : widget.host
          ? module.directory?.sentInvitations ?? const []
          : module.directory?.receivedInvitations ?? const [];
      final items = source
          .where(
            (item) =>
                widget.invitationId == null || item.id == widget.invitationId,
          )
          .toList();
      return PopScope(
        canPop: !module.busy && !_loading,
        child: AlertDialog(
          title: Text(t(widget.host ? 'inviteFriends' : 'invitations')),
          content: SizedBox(
            width: 560,
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(t('inviteHint')),
                  const SizedBox(height: 12),
                  if (!_valid) Text(t('contextChanged')),
                  if (_valid && widget.host && widget.invitationId == null) ...[
                    if (_loading) const LinearProgressIndicator(),
                    if (!_loading && _error == null && _targets.isEmpty)
                      Text(t('noTargets')),
                    for (final target in _targets)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(target.name),
                        trailing: StarBridgeActionButton(
                          kind: StarBridgeActionKind.quiet,
                          onActivate: module.canInvite && !target.alreadyInvited
                              ? (source) => _action(RoomOperation.invite, {
                                  'roomId': _roomId,
                                  'targetRef': target.reference,
                                }, source: source)
                              : null,
                          child: Text(
                            t(
                              target.alreadyInvited
                                  ? 'alreadyInvited'
                                  : 'invite',
                            ),
                          ),
                        ),
                      ),
                    const Divider(),
                    Text(t('sent')),
                  ],
                  if (_valid && items.isEmpty)
                    Text(
                      widget.invitationId == null
                          ? t('noInvitations')
                          : roomInvitationText(context, 'unavailable'),
                    ),
                  for (final item in items)
                    RoomInvitationCard(
                      invitation: item,
                      sent: widget.host,
                      room:
                          module.directory?.rooms
                              .where((r) => r.id == item.roomId)
                              .firstOrNull ??
                          _previews[item.id],
                      loading: _previewLoading.contains(item.id),
                      actions: Wrap(
                        spacing: 8,
                        children: [
                          if (!widget.host &&
                              module.directory?.currentRoomId != null)
                            Text(
                              roomInvitationText(
                                context,
                                module.directory?.currentRoomId == item.roomId
                                    ? 'alreadyJoined'
                                    : 'inAnotherRoom',
                              ),
                            ),
                          if (!item.expiresAt.isAfter(DateTime.now()))
                            Text(roomInvitationText(context, 'expired')),
                          StarBridgeActionButton(
                            kind: StarBridgeActionKind.quiet,
                            tone: widget.host ? ActionTone.warning : null,
                            onActivate: module.canCommand
                                ? (source) => _action(
                                    widget.host
                                        ? RoomOperation.inviteRevoke
                                        : RoomOperation.inviteDecline,
                                    {
                                      'roomId': item.roomId,
                                      'invitationId': item.id,
                                    },
                                    source: source,
                                  )
                                : null,
                            child: Text(t(widget.host ? 'revoke' : 'decline')),
                          ),
                          if (!widget.host)
                            StarBridgeActionButton(
                              kind: StarBridgeActionKind.primary,
                              onActivate:
                                  module.canCommand &&
                                      item.expiresAt.isAfter(DateTime.now()) &&
                                      module.directory?.currentRoomId == null
                                  ? (source) => _accept(item, source)
                                  : null,
                              child: Text(t('join')),
                            ),
                        ],
                      ),
                    ),
                  if (_error != null) RoomFeedback(_error!),
                ],
              ),
            ),
          ),
          actions: [
            if (widget.host)
              StarBridgeActionButton(
                kind: StarBridgeActionKind.quiet,
                onActivate: module.busy || !_valid ? null : (_) => _load(),
                child: Text(t('refreshList')),
              ),
            StarBridgeActionButton(
              kind: StarBridgeActionKind.quiet,
              onActivate: module.busy || _loading
                  ? null
                  : (source) =>
                        dismissStarBridgeDialog(context, source: source),
              child: Text(t('done')),
            ),
          ],
        ),
      );
    },
  );
}
