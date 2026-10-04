import 'dart:convert';

import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';
import 'menu_feature_session.dart';

/// Shared command context: uncertainty locks all room writes until reconciled.
/// Each composed module retains its own aliases, drafts and scope retirement.
final class MenuRoomCommandState {
  String? selected;
  bool uncertain = false;
  String notice = '';
}

final class _RoomManagementState {
  final ids = <String, String>{};
  int serial = 0;
  int scopeEpoch = 0;
  Map<String, Object?>? reply;
  String alias(String type, String id) =>
      ids.putIfAbsent('$type/$id', () => 'm${++serial}');
  String? resolve(String type, Object? alias) => ids.entries
      .where((e) => e.value == alias && e.key.startsWith('$type/'))
      .firstOrNull
      ?.key
      .substring(type.length + 1);
  void clear() {
    scopeEpoch++;
    ids.clear();
    reply = null;
  }
}

final class MenuRoomManagementSession {
  MenuRoomManagementSession(this._session, this.port, this._state);
  final MenuFeatureSession _session;
  final PartyRoomsPort port;
  final MenuRoomCommandState _state;
  final _management = _RoomManagementState();
  void clear() => _management.clear();

  Map<String, Object?> projection(RoomDirectory directory, PartyRoom room) {
    final active = directory.currentRoomId == room.id;
    final scopeEpoch = _management.scopeEpoch;
    final commands =
        port is RoomCommandsPort && (port as RoomCommandsPort).supportsCommands;
    final manage =
        active &&
        room.viewerIsHost &&
        port is RoomManagementPort &&
        (port as RoomManagementPort).supportsManagement;
    final invite =
        port is RoomInvitationsPort &&
        (port as RoomInvitationsPort).supportsInvitations;
    if (!manage && _management.reply?['status'] == 'targets') {
      _management.reply = null;
    }
    Map<String, Object?> invitation(RoomInvitation item) => {
      'id': _management.alias('invitation', item.id),
      'room': _management.alias('room', item.roomId),
      'title': item.title,
      'inviter': item.inviter,
      'recipient': item.recipient,
      'expires': item.expiresAt.toUtc().toIso8601String(),
    };
    return {
      'current': active,
      'currentRoomAlias': _management.alias('room', room.id),
      'reply': _management.reply,
      'applications': [
        if (manage)
          for (final a in room.pendingApplications)
            {
              'id': _management.alias('application', a.id),
              'name': a.displayName,
              'time': a.createdAt.toUtc().toIso8601String(),
            },
      ],
      'received': [
        if (active && invite)
          for (final i in directory.receivedInvitations) invitation(i),
      ],
      'sent': [
        if (manage && invite)
          for (final i in directory.sentInvitations.where(
            (i) => i.roomId == room.id,
          ))
            invitation(i),
      ],
      'actions': {
        if (active && commands && !_state.uncertain)
          for (final op in [
            if (manage) RoomOperation.close,
            if (manage) RoomOperation.decide,
            if (invite) RoomOperation.inviteDecline,
            if (manage && invite) ...[
              RoomOperation.inviteTargets,
              RoomOperation.invite,
              RoomOperation.inviteRevoke,
            ],
          ])
            op.name: _managementAction(room.id, op, scopeEpoch),
      },
    };
  }

  String _managementAction(String roomId, RoomOperation op, int scopeEpoch) {
    late Map<String, Object?> action;
    action = _session.button(op.name, (value) async {
      if (_management.scopeEpoch != scopeEpoch) {
        _session.emit({
          ..._session.currentView,
          'rejectedAction': action['key'],
        });
        return;
      }
      await _manageRoom(roomId, op, value);
    }, limit: 2048);
    return action['key'] as String;
  }

  Future<void> _manageRoom(
    String roomId,
    RoomOperation operation,
    String value,
  ) async {
    final account = _session.accountEpoch, epoch = _session.generation;
    bool valid() =>
        _session.currentAccount(account) &&
        _session.current(epoch) &&
        _state.selected == roomId;
    final raw = jsonDecode(value);
    if (raw is! Map ||
        raw.keys.any((k) => k != 'request' && k != 'data') ||
        raw['request'] is! String ||
        !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(raw['request']) ||
        raw['data'] is! Map) {
      return;
    }
    final data = raw['data'] as Map;
    final allowed = switch (operation) {
      RoomOperation.decide => {'applicationId', 'approve'},
      RoomOperation.invite => {'targetRef'},
      RoomOperation.inviteDecline ||
      RoomOperation.inviteRevoke => {'invitationId'},
      _ => <String>{},
    };
    var result = const RoomCommandResult('rejected', error: 'invalidInput');
    var dispatched = false;
    try {
      if (!_state.uncertain &&
          data.length == allowed.length &&
          data.keys.every(allowed.contains)) {
        final fresh = await port.read().timeout(const Duration(seconds: 4));
        if (!valid()) return;
        final d = fresh.directory;
        final room = d?.rooms.where((r) => r.id == roomId).singleOrNull;
        if (fresh.state != RoomReadState.ready || d == null) {
          result = const RoomCommandResult('rejected', error: 'unavailable');
        } else if (d.currentRoomId != roomId || room == null) {
          result = const RoomCommandResult('stale', error: 'contextChanged');
        } else if (port is! RoomCommandsPort ||
            !(port as RoomCommandsPort).supportsCommands) {
          result = const RoomCommandResult('rejected', error: 'unavailable');
        } else if (operation != RoomOperation.inviteDecline &&
            (!room.viewerIsHost ||
                port is! RoomManagementPort ||
                !(port as RoomManagementPort).supportsManagement)) {
          result = const RoomCommandResult('rejected', error: 'notHost');
        } else if (operation.name.startsWith('invite') &&
            (port is! RoomInvitationsPort ||
                !(port as RoomInvitationsPort).supportsInvitations)) {
          result = const RoomCommandResult('rejected', error: 'unavailable');
        } else {
          Map<String, Object?>? command;
          if (operation == RoomOperation.close ||
              operation == RoomOperation.inviteTargets) {
            command = {'roomId': roomId};
          }
          if (operation == RoomOperation.decide && data['approve'] is bool) {
            final id = _management.resolve(
              'application',
              data['applicationId'],
            );
            if (id != null && room.pendingApplications.any((a) => a.id == id)) {
              command = {
                'roomId': roomId,
                'applicationId': id,
                'approve': data['approve'],
              };
            }
          }
          if (operation == RoomOperation.inviteDecline ||
              operation == RoomOperation.inviteRevoke) {
            final id = _management.resolve('invitation', data['invitationId']);
            final source = operation == RoomOperation.inviteDecline
                ? d.receivedInvitations
                : d.sentInvitations;
            final item = source
                .where(
                  (i) =>
                      i.id == id &&
                      (operation == RoomOperation.inviteDecline ||
                          i.roomId == roomId),
                )
                .singleOrNull;
            if (item != null) {
              command = {'roomId': item.roomId, 'invitationId': item.id};
            }
          }
          if (operation == RoomOperation.invite) {
            final target = _management.resolve('target', data['targetRef']);
            if (target != null) {
              final targets = await (port as RoomCommandsPort)
                  .execute(
                    RoomCommand(RoomOperation.inviteTargets, {
                      'roomId': roomId,
                    }),
                  )
                  .timeout(const Duration(seconds: 3));
              if (!valid()) return;
              if (targets.status == 'targets' &&
                  targets.targets.any(
                    (t) => t.reference == target && !t.alreadyInvited,
                  )) {
                command = {'roomId': roomId, 'targetRef': target};
              }
            }
          }
          if (command != null && valid()) {
            dispatched = operation != RoomOperation.inviteTargets;
            if (dispatched) _state.uncertain = true;
            result = await (port as RoomCommandsPort)
                .execute(RoomCommand(operation, command))
                .timeout(const Duration(seconds: 6));
          }
        }
      }
    } on Object {
      result = RoomCommandResult(
        dispatched ? 'unknown' : 'rejected',
        error: dispatched ? 'outcomeUnknown' : 'unavailable',
      );
    }
    if (!valid()) return;
    if (!const {
      'closed',
      'approved',
      'declined',
      'targets',
      'invited',
      'revoked',
      'rejected',
      'stale',
      'unknown',
    }.contains(result.status)) {
      result = const RoomCommandResult('unknown', error: 'outcomeUnknown');
    }
    _state.uncertain = result.status == 'unknown';
    _state.notice = _state.uncertain ? '操作结果未确认，请刷新核对，不要重复提交。' : '';
    _management.reply = {
      'request': raw['request'],
      'status': result.status,
      'error': result.error,
      'targets': [
        for (final target in result.targets.take(256))
          {
            'id': _management.alias('target', target.reference),
            'name': target.name,
            'invited': target.alreadyInvited,
          },
      ],
    };
    final room = _session.currentView['room'];
    if (room is Map && room['management'] is Map) {
      _session.emit({
        ..._session.currentView,
        'room': {
          ...room,
          'management': {
            ...room['management'] as Map,
            'reply': _management.reply,
          },
        },
      });
    }
  }
}
