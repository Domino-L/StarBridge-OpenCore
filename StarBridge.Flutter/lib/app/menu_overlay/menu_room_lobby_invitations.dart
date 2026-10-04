import 'dart:convert';

import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_invitations.dart';
import 'menu_feature_session.dart';
import 'menu_room_management_session.dart';
import 'menu_room_lobby_projection.dart';
import 'menu_organization_avatars.dart';

final class _LobbyInvitations {
  final aliases = <String, String>{};
  int serial = 0, epoch = 0;
  Map<String, Object?>? reply;
  String alias(String id) => aliases.putIfAbsent(id, () => 'i${++serial}');
  void clear() {
    aliases.clear();
    reply = null;
    epoch++;
  }
}

final class MenuRoomLobbyInvitations {
  MenuRoomLobbyInvitations(
    this._session,
    this.port,
    this._state,
    this._lobby,
    this._images,
  );
  final MenuFeatureSession _session;
  final PartyRoomsPort port;
  final MenuRoomCommandState _state;
  final MenuRoomLobbyProjection _lobby;
  final MenuOrganizationAvatars _images;
  final _lobbyInvitations = _LobbyInvitations();
  Map<String, Object?>? get reply => _lobbyInvitations.reply;
  void clear() => _lobbyInvitations.clear();

  bool get _lobbyInvitationsSupported =>
      port is RoomInvitationsPort &&
      (port as RoomInvitationsPort).supportsInvitations &&
      port is RoomCommandsPort &&
      (port as RoomCommandsPort).supportsCommands;

  List<Map<String, Object?>> rows(RoomDirectory directory) => [
    if (_lobbyInvitationsSupported && directory.currentRoomId == null)
      for (final item in directory.receivedInvitations.take(256))
        {
          'id': _lobbyInvitations.alias(item.id),
          'room': _lobby.key(item.roomId),
          'title': item.title,
          'inviter': item.inviter,
          'recipient': item.recipient,
          'expires': item.expiresAt.toUtc().toIso8601String(),
        },
  ];

  Map<String, Object?> actions() {
    final epoch = _lobbyInvitations.epoch;
    String grant(RoomOperation operation) {
      late Map<String, Object?> action;
      action = _session.button(operation.name, (value) async {
        if (_lobbyInvitations.epoch != epoch) {
          _session.emit({
            ..._session.currentView,
            'rejectedAction': action['key'],
          });
          return;
        }
        await _lobbyInvitation(operation, value);
      }, limit: 2048);
      return action['key'] as String;
    }

    return {
      if (_lobbyInvitationsSupported && !_state.uncertain)
        for (final op in [
          RoomOperation.invitePreview,
          RoomOperation.inviteJoin,
          RoomOperation.inviteDecline,
        ])
          op.name: grant(op),
    };
  }

  Future<void> _lobbyInvitation(RoomOperation operation, String value) async {
    final account = _session.accountEpoch,
        generationAtStart = _session.generation,
        epoch = _lobbyInvitations.epoch;
    bool valid() =>
        _session.currentAccount(account) &&
        _session.current(generationAtStart) &&
        epoch == _lobbyInvitations.epoch &&
        _state.selected == null;
    Object? raw;
    try {
      raw = jsonDecode(value);
    } on FormatException {
      return;
    }
    if (raw is! Map ||
        raw.keys.any((k) => k != 'request' && k != 'data') ||
        raw['request'] is! String ||
        !RegExp(r'^q[1-9][0-9]{0,13}$').hasMatch(raw['request']) ||
        raw['data'] is! Map) {
      return;
    }
    final data = raw['data'] as Map;
    var result = const RoomCommandResult('rejected', error: 'invalidInput');
    var wrote = false;
    Map<String, Object?>? preview;
    try {
      if (!_state.uncertain &&
          data.length == 2 &&
          data.keys.every(const {'roomId', 'invitationId'}.contains)) {
        final id = _lobbyInvitations.aliases.entries
            .where((e) => e.value == data['invitationId'])
            .singleOrNull
            ?.key;
        if (id != null) {
          final fresh = await port.read().timeout(const Duration(seconds: 4));
          if (!valid()) return;
          final d = fresh.directory;
          final invitation = d?.receivedInvitations
              .where(
                (i) => i.id == id && _lobby.key(i.roomId) == data['roomId'],
              )
              .singleOrNull;
          if (fresh.state != RoomReadState.ready ||
              d == null ||
              !_lobbyInvitationsSupported) {
            result = const RoomCommandResult('rejected', error: 'unavailable');
          } else if (d.currentRoomId != null) {
            result = const RoomCommandResult('stale', error: 'contextChanged');
          } else if (invitation == null ||
              !invitation.expiresAt.isAfter(d.serverTime)) {
            result = const RoomCommandResult(
              'rejected',
              error: 'invitationGone',
            );
          } else {
            wrote = operation != RoomOperation.invitePreview;
            if (wrote) _state.uncertain = true;
            result = await (port as RoomCommandsPort)
                .execute(
                  RoomCommand(operation, {
                    'roomId': invitation.roomId,
                    'invitationId': invitation.id,
                  }),
                )
                .timeout(const Duration(seconds: 6));
            if (!valid()) return;
            if (operation == RoomOperation.invitePreview) {
              if (result.status == 'resolved' &&
                  result.preview?.id == invitation.roomId) {
                preview = {
                  'schemaVersion': 1,
                  'currentRoomId': null,
                  'serverTime': d.serverTime.toUtc().toIso8601String(),
                  'rooms': [
                    await _lobby
                        .room(result.preview!, _images, authorizeJoin: false)
                        .timeout(const Duration(seconds: 2)),
                  ],
                };
              } else {
                result = const RoomCommandResult(
                  'rejected',
                  error: 'unavailable',
                );
              }
            } else if (!{
              'rejected',
              'stale',
              'unknown',
              operation == RoomOperation.inviteJoin ? 'joined' : 'declined',
            }.contains(result.status)) {
              result = const RoomCommandResult(
                'unknown',
                error: 'outcomeUnknown',
              );
            }
          }
        }
      }
    } on Object {
      result = RoomCommandResult(
        wrote ? 'unknown' : 'rejected',
        error: wrote ? 'outcomeUnknown' : 'unavailable',
      );
    }
    if (!valid()) return;
    if (operation != RoomOperation.invitePreview) {
      _state.uncertain = result.status == 'unknown';
      _state.notice = _state.uncertain ? '操作结果未确认，请刷新核对，不要重复提交。' : '';
    }
    _lobbyInvitations.reply = {
      'request': raw['request'],
      'status': result.status,
      'error': result.error,
      'preview': ?preview,
    };
    final lobby = _session.currentView['lobby'];
    if (lobby is Map) {
      _session.emit({
        ..._session.currentView,
        'lobby': {...lobby, 'invitationReply': _lobbyInvitations.reply},
      });
    }
  }
}
