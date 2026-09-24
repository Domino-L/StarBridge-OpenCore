import 'package:flutter/material.dart';

import '../../design_system/controls/semantic_action_style.dart';

import 'party_rooms_module.dart';
import 'room_action_dialogs.dart';
import 'room_commands.dart';
import 'room_invitations.dart';
import 'room_feedback.dart';
import 'room_invitation_card.dart';

Future<void> showRoomInvitations(
  BuildContext context,
  PartyRoomsModule module, {
  bool host = false,
}) => showDialog<void>(
  context: context,
  barrierDismissible: false,
  builder: (_) => _InvitationDialog(module: module, host: host),
);

class _InvitationDialog extends StatefulWidget {
  const _InvitationDialog({required this.module, required this.host});
  final PartyRoomsModule module;
  final bool host;
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
    if (widget.host) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _load());
    } else {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadPreviews());
    }
  }

  Future<void> _loadPreviews() async {
    final invitations =
        widget.module.directory?.receivedInvitations ?? const [];
    for (final item in invitations) {
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
    Map<String, Object?> data,
  ) async {
    if (!_valid) return;
    final result = await widget.module.execute(
      RoomCommand(operation, data),
      expectedRevision: _revision,
    );
    if (!mounted) return;
    setState(() => _error = result.error);
    if (result.accepted && operation == RoomOperation.inviteJoin) {
      Navigator.pop(context);
    } else if (result.accepted && widget.host && _valid) {
      await _load();
    }
  }

  Future<void> _accept(RoomInvitation item) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(item.title),
        content: Text(roomActionText(context, 'acceptInvitation')),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(roomActionText(context, 'cancel')),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(roomActionText(context, 'join')),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      await _action(RoomOperation.inviteJoin, {
        'roomId': item.roomId,
        'invitationId': item.id,
      });
    }
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: widget.module,
    builder: (context, _) {
      final module = widget.module;
      String t(String key) => roomActionText(context, key);
      final items = !_valid
          ? <RoomInvitation>[]
          : widget.host
          ? module.directory?.sentInvitations ?? const []
          : module.directory?.receivedInvitations ?? const [];
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
                  if (_valid && widget.host) ...[
                    if (_loading) const LinearProgressIndicator(),
                    if (!_loading && _targets.isEmpty) Text(t('noTargets')),
                    for (final target in _targets)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(target.name),
                        trailing: TextButton(
                          onPressed: module.canInvite && !target.alreadyInvited
                              ? () => _action(RoomOperation.invite, {
                                  'roomId': _roomId,
                                  'targetRef': target.reference,
                                })
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
                  if (_valid && items.isEmpty) Text(t('noInvitations')),
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
                          TextButton(
                            style: widget.host
                                ? semanticActionStyle(
                                    context,
                                    ActionTone.warning,
                                  )
                                : null,
                            onPressed: module.canCommand
                                ? () => _action(
                                    widget.host
                                        ? RoomOperation.inviteRevoke
                                        : RoomOperation.inviteDecline,
                                    {
                                      'roomId': item.roomId,
                                      'invitationId': item.id,
                                    },
                                  )
                                : null,
                            child: Text(t(widget.host ? 'revoke' : 'decline')),
                          ),
                          if (!widget.host)
                            FilledButton(
                              onPressed:
                                  module.canCommand &&
                                      module.directory?.currentRoomId == null
                                  ? () => _accept(item)
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
              TextButton(
                onPressed: module.busy || !_valid ? null : _load,
                child: Text(t('refreshList')),
              ),
            TextButton(
              onPressed: module.busy || _loading
                  ? null
                  : () => Navigator.pop(context),
              child: Text(t('done')),
            ),
          ],
        ),
      );
    },
  );
}
