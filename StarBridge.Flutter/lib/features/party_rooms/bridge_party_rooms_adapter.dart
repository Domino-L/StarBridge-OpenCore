import 'dart:async';

import '../common/runtime_name_labels.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'party_rooms_module.dart';
import 'room_commands.dart';
import 'room_invitations.dart';
import 'room_chat_module.dart';
import 'bridge_room_chat.dart';

final class BridgePartyRoomsAdapter
    implements
        PartyRoomsPort,
        RoomCommandsPort,
        RoomManagementPort,
        RoomInvitationsPort,
        RoomChatProvider {
  @override
  late final RoomChatPort roomChat = BridgeRoomChat(_session);
  BridgePartyRoomsAdapter(this._session, {this.onReminder}) {
    _subscription = _session.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession _session;
  final void Function(Object?)? onReminder;
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  bool get supportsCommands =>
      _session.hostCapabilities.contains('partyRooms.commands');
  @override
  bool get supportsManagement =>
      _session.hostCapabilities.contains('partyRooms.manage');
  @override
  bool get supportsInvitations =>
      _session.hostCapabilities.contains('partyRooms.invitations');

  @override
  Future<RoomCommandResult> execute(RoomCommand command) async {
    if (command.operation.name.startsWith('invite') && !supportsInvitations) {
      return const RoomCommandResult('rejected', error: 'hostUnavailable');
    }
    if (!supportsCommands ||
        (!supportsManagement &&
            const [
              RoomOperation.update,
              RoomOperation.close,
              RoomOperation.decide,
              RoomOperation.remove,
              RoomOperation.transferHost,
            ].contains(command.operation))) {
      return const RoomCommandResult('rejected', error: 'hostUnavailable');
    }
    var dispatched = false;
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (!hasRelayAccount(account) || account.accountContext == null) {
        return const RoomCommandResult(
          'rejected',
          error: 'identityUnavailable',
        );
      }
      dispatched = true;
      final response = await _session.request(
        'partyRooms.execute',
        payload: {
          'schemaVersion': 1,
          'operation': command.operation.name,
          'data': command.data,
        },
        accountContext: account.accountContext,
      );
      final data = response.payload;
      if (data['schemaVersion'] != 1) throw const FormatException();
      final status = data['status'] as String;
      final validStatus =
          status == 'rejected' ||
          switch (command.operation) {
            RoomOperation.create => status == 'joined',
            RoomOperation.join => status == 'joined' || status == 'pending',
            RoomOperation.resolve => status == 'resolved',
            RoomOperation.leave => status == 'left' || status == 'closed',
            RoomOperation.update => status == 'updated',
            RoomOperation.close => status == 'closed',
            RoomOperation.remove => status == 'removed',
            RoomOperation.transferHost => status == 'hostTransferred',
            RoomOperation.decide =>
              status == 'approved' || status == 'declined',
            RoomOperation.inviteTargets => status == 'targets',
            RoomOperation.invite => status == 'invited',
            RoomOperation.inviteJoin => status == 'joined',
            RoomOperation.invitePreview => status == 'resolved',
            RoomOperation.inviteDecline => status == 'declined',
            RoomOperation.inviteRevoke => status == 'revoked',
          };
      if (!validStatus ||
          (status == 'resolved' && data['preview'] == null) ||
          (status != 'rejected' &&
              status != 'resolved' &&
              data['directory'] == null &&
              data['error'] != 'refreshRequired')) {
        throw const FormatException();
      }
      return RoomCommandResult(
        status,
        targets: (data['targets'] as List? ?? const []).map((raw) {
          final item = raw as Map;
          return RoomInviteTarget(
            item['targetRef'] as String,
            roomPersonName(
              item['callsign'] as String,
              item['gameId'] as String,
            ),
            alreadyInvited: item['alreadyInvited'] as bool? ?? false,
          );
        }).toList(),
        error: data['error'] as String?,
        directory: data['directory'] == null
            ? null
            : parseRoomDirectory(
                Map<String, Object?>.from(data['directory'] as Map),
              ),
        preview: data['preview'] == null
            ? null
            : parseRoomDirectory({
                'schemaVersion': 1,
                'currentRoomId': null,
                'serverTime': DateTime.now().toUtc().toIso8601String(),
                'rooms': [data['preview']],
              }).rooms.single,
      );
    } on BridgeClientException catch (error) {
      final rejection = switch (error.code) {
        'party_rooms.identity_unavailable' ||
        'account.reauthorization_required' => 'identityUnavailable',
        'party_rooms.forbidden' => 'forbidden',
        'party_rooms.data_invalid' => 'invalidInput',
        'party_rooms.command_unavailable' => 'unavailable',
        'host.capability_missing' => 'hostUnavailable',
        _ => null,
      };
      return RoomCommandResult(
        rejection != null || !dispatched ? 'rejected' : 'unknown',
        error: rejection ?? (dispatched ? 'outcomeUnknown' : 'unavailable'),
      );
    } on Object {
      return RoomCommandResult(
        dispatched ? 'unknown' : 'rejected',
        error: dispatched ? 'outcomeUnknown' : 'unavailable',
      );
    }
  }

  @override
  Future<RoomReadResult> read() async {
    if (!_session.hostCapabilities.contains('partyRooms.read')) {
      return const RoomReadResult(
        RoomReadState.unavailable,
        failure: 'hostUnavailable',
      );
    }
    try {
      final account = await _session.request(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      if (account.payload['schemaVersion'] != 1) throw const FormatException();
      final state = account.payload['state'];
      if (state == 'signedOut' || state == 'reauthorizationRequired') {
        return const RoomReadResult(RoomReadState.signedOut);
      }
      if (!hasRelayAccount(account) || account.accountContext == null) {
        return const RoomReadResult(
          RoomReadState.unavailable,
          failure: 'identityUnavailable',
        );
      }
      final result = await _session.request(
        'partyRooms.getDirectory',
        payload: const {'schemaVersion': 1},
        accountContext: account.accountContext,
      );
      final directory = parseRoomDirectory(result.payload);
      if (result.sessionGeneration == _session.activeGeneration &&
          result.accountContext?.environment ==
              account.accountContext!.environment &&
          result.accountContext?.authority ==
              account.accountContext!.authority &&
          result.accountContext?.subject == account.accountContext!.subject) {
        onReminder?.call(result.payload['localReminder']);
      }
      return RoomReadResult(RoomReadState.ready, directory: directory);
    } on BridgeClientException catch (error) {
      return RoomReadResult(
        RoomReadState.unavailable,
        failure: switch (error.code) {
          'party_rooms.identity_unavailable' => 'identityUnavailable',
          'party_rooms.forbidden' => 'forbidden',
          'account.reauthorization_required' => 'identityUnavailable',
          'party_rooms.data_invalid' => 'invalidResponse',
          'bridge.disconnected' ||
          'host.capability_missing' => 'hostUnavailable',
          _ => 'unavailable',
        },
      );
    } on Object {
      return const RoomReadResult(
        RoomReadState.unavailable,
        failure: 'invalidResponse',
      );
    }
  }

  @override
  Future<void> close() async {
    await _subscription.cancel();
    await _invalidations.close();
  }
}

RoomDirectory parseRoomDirectory(Map<String, Object?> value) {
  if (value['schemaVersion'] != 1 || !value.containsKey('currentRoomId')) {
    throw const FormatException('Unsupported room projection');
  }
  final rooms = (value['rooms'] as List).map((raw) {
    final room = raw as Map;
    final members = (room['members'] as List).map((raw) {
      final member = raw as Map;
      return RoomMember(
        userRef: member['userRef'] as String?,
        removalToken:
            room['roomId'] == value['currentRoomId'] &&
                room['viewerIsHost'] == true &&
                member['isHost'] != true &&
                member['removalToken'] is String &&
                RegExp(r'^[a-fA-F0-9]{32}$')
                    .hasMatch(member['removalToken'] as String)
            ? member['removalToken'] as String
            : null,
        isSelf: member['isSelf'] == true,
        callsign: _text(member, 'callsign'),
        gameId: _text(member, 'gameId'),
        isHost: member['isHost'] as bool,
        presence: _text(member, 'presenceText'),
        presenceKey: member['presenceKey'] as String? ?? 'presence.unknown',
        location: _text(member, 'locationText'),
        locationLabels: _locationLabels(member['locationLabels']),
        arrivalPendingConfirmation:
            member['arrivalPendingConfirmation'] == true,
        arrivalTargetCode: member['arrivalTargetCode'] as String?,
        arrivalTargetLabels: parseRuntimeNameLabels(
          member['arrivalTargetLabels'],
        ),
        locationHiddenReason: member['locationHiddenReason'] == 'lowConfidence'
            ? 'lowConfidence'
            : null,
        ship: _text(member, 'shipText'),
        shipLabels: parseRuntimeNameLabels(member['shipLabels']),
        shard: _text(member, 'shardText'),
        serverRegion: member.containsKey('serverRegion')
            ? _text(member, 'serverRegion')
            : '',
        avatarData:
            member['avatarImageData'] is String &&
                (member['avatarImageData'] as String).length <=
                    ((512 * 1024 + 2) ~/ 3 * 4) + 24
            ? member['avatarImageData'] as String
            : null,
      );
    }).toList();
    final capacity = room['capacity'] as int;
    if (capacity < 2 || capacity > 16 || members.length > capacity) {
      throw const FormatException();
    }
    return PartyRoom(
      id: _text(room, 'roomId', required: true),
      title: _text(room, 'title', required: true),
      goal: _text(room, 'goal'),
      capacity: capacity,
      members: members,
      tags: _tags(room),
      roomCode:
          value['currentRoomId'] == room['roomId'] &&
              room.containsKey('roomCode')
          ? _text(room, 'roomCode')
          : '',
      canPreviewMemberProfiles:
          room['canPreviewMemberProfiles'] == true &&
          room['passwordRequired'] == false &&
          const {'direct', 'approval'}.contains(room['admissionMode']) &&
          const {'everyone', 'friends', 'fleet'}.contains(room['eligibility']),
      pendingApplications:
          value['currentRoomId'] == room['roomId'] &&
              room['viewerIsHost'] == true
          ? _applications(room)
          : const [],
      leaderServerRegion: room.containsKey('leaderServerRegion')
          ? _text(room, 'leaderServerRegion')
          : '',
      leaderGameVersion: room.containsKey('leaderGameVersion')
          ? _text(room, 'leaderGameVersion')
          : '',
      isPublic: room['isPublic'] as bool,
      eligibility: _text(room, 'eligibility', required: true),
      admissionMode: _text(room, 'admissionMode', required: true),
      passwordRequired: room['passwordRequired'] as bool,
      voice: _text(room, 'voiceRequirement', required: true),
      language: _text(room, 'language', required: true),
      expiresAt: DateTime.parse(room['expiresAt'] as String),
      recruitmentClosesAt: room['recruitmentClosesAt'] == null
          ? null
          : DateTime.parse(room['recruitmentClosesAt'] as String),
      viewerIsHost: room['viewerIsHost'] as bool,
    );
  }).toList();
  return RoomDirectory(
    supportsHostTransfer: value['supportsHostTransfer'] == true,
    viewerPendingRoomIds: _pendingRoomIds(value['viewerPendingRoomIds']),
    receivedInvitations: parseInvitations(value['receivedInvitations']),
    sentInvitations:
        rooms.any(
          (room) => room.id == value['currentRoomId'] && room.viewerIsHost,
        )
        ? parseInvitations(value['sentInvitations'])
              .where((item) => item.roomId == value['currentRoomId'])
              .toList()
        : const [],
    rooms: rooms,
    currentRoomId: value['currentRoomId'] as String?,
    serverTime: DateTime.parse(value['serverTime'] as String),
    tagOptions: _tags(value, key: 'tagOptions', maximum: 512),
  );
}

List<String>? _pendingRoomIds(Object? value) {
  if (value == null) return null;
  if (value is! List ||
      value.length > 2000 ||
      value.any(
        (id) =>
            id is! String ||
            id.trim().isEmpty ||
            id.length > 128 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(id),
      ) ||
      value.toSet().length != value.length) {
    throw const FormatException('Invalid pending application projection');
  }
  return List<String>.from(value);
}

String _text(Map value, String key, {bool required = false}) {
  final text = value[key] as String;
  if (text.length > 4096 || (required && text.trim().isEmpty)) {
    throw const FormatException();
  }
  return text;
}

Map<String, String> _locationLabels(Object? raw) {
  if (raw is! Map) return const {};
  final labels = <String, String>{};
  for (final key in const ['en', 'zhHans', 'zhHant']) {
    final value = raw[key];
    if (value is String && value.isNotEmpty && value.length <= 256) {
      labels[key] = value;
    }
  }
  return labels;
}

List<RoomApplication> _applications(Map room) {
  if (!room.containsKey('pendingApplications')) return const [];
  final values = room['pendingApplications'] as List;
  if (values.length > 256) throw const FormatException();
  final seen = <String>{};
  return values.map((raw) {
    final item = raw as Map;
    final id = _text(item, 'applicationId', required: true);
    if (!seen.add(id)) throw const FormatException();
    return RoomApplication(
      id: id,
      callsign: _text(item, 'callsign'),
      gameId: _text(item, 'gameId'),
      createdAt: DateTime.parse(item['createdAt'] as String),
      avatarData:
          item['avatarImageData'] is String &&
              (item['avatarImageData'] as String).length <=
                  ((512 * 1024 + 2) ~/ 3 * 4) + 24
          ? item['avatarImageData'] as String
          : null,
      userRef:
          item['userRef'] is String &&
              RegExp(r'^[a-f0-9]{32}$').hasMatch(item['userRef'] as String)
          ? item['userRef'] as String
          : null,
    );
  }).toList();
}

List<RoomTag> _tags(Map room, {String key = 'tags', int maximum = 64}) {
  // Additive schema-1 fields: old Hosts remain usable without invented tags.
  if (!room.containsKey(key)) return const [];
  final values = room[key] as List;
  if (values.length > maximum) throw const FormatException();
  final seen = <String>{};
  return values.map((raw) {
    final tag = raw as Map;
    final id = _text(tag, 'id', required: true);
    if (!seen.add(id)) throw const FormatException();
    return RoomTag(
      id: id,
      text: _text(tag, 'text', required: true),
      isGameplay: tag['isGameplay'] as bool,
    );
  }).toList();
}
