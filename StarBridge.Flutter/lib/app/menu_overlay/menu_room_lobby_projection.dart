import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/party_rooms/room_commands.dart';
import '../../features/party_rooms/room_member_policy.dart';
import 'menu_organization_avatars.dart';

/// Real service identifiers never leave the primary engine.
final class MenuRoomLobbyProjection {
  final _ids = <String, String>{};
  final _rooms = <String, PartyRoom>{};
  int _serial = 0;
  String? previewId;
  DateTime? serverTime;
  Set<String> pending = {};
  void clear() {
    _ids.clear();
    _rooms.clear();
    previewId = null;
    serverTime = null;
    pending.clear();
  }

  String key(String id) => _ids.putIfAbsent(id, () => 'r${++_serial}');
  String? resolve(String? value) => _rooms[value]?.id;
  Future<Map<String, Object?>> room(
    PartyRoom room,
    MenuOrganizationAvatars images, {
    bool authorizeJoin = true,
  }) async {
    final id = key(room.id);
    if (authorizeJoin) _rooms[id] = room;
    return {
      'roomId': id,
      'title': room.title,
      'goal': room.goal,
      'capacity': room.capacity,
      'isPublic': room.isPublic,
      'eligibility': room.eligibility,
      'admissionMode': room.admissionMode,
      'passwordRequired': room.passwordRequired,
      'voiceRequirement': room.voice,
      'language': room.language,
      'expiresAt': room.expiresAt.toUtc().toIso8601String(),
      'recruitmentClosesAt': room.recruitmentClosesAt
          ?.toUtc()
          .toIso8601String(),
      'viewerIsHost': false,
      'leaderServerRegion': room.leaderServerRegion,
      'leaderGameVersion': room.leaderGameVersion,
      'tags': tags(room.tags),
      'members': [
        for (final m in room.members)
          {
            'callsign': m.callsign,
            'gameId': m.gameId,
            'isHost': m.isHost,
            'isSelf': m.isSelf,
            'presenceText': m.presence,
            'presenceKey': m.presenceKey,
            'locationText': '',
            'shipText': '',
            'shardText': '',
            'avatarImageData': await images.logo(m.avatarData),
          },
      ],
    };
  }

  static List<Map<String, Object?>> tags(List<RoomTag> values) => [
    for (final t in values)
      {'id': t.id, 'text': t.text, 'isGameplay': t.isGameplay},
  ];
  Future<Map<String, Object?>> directory(
    RoomDirectory directory,
    MenuOrganizationAvatars images,
  ) async {
    if (_ids.length > 1000) clear();
    serverTime = directory.serverTime;
    pending = (directory.viewerPendingRoomIds ?? const <String>[]).toSet();
    final active = directory.rooms.map((r) => r.id).toSet();
    _rooms.removeWhere((_, r) => !active.contains(r.id) && r.id != previewId);
    return {
      'schemaVersion': 1,
      'serverTime': directory.serverTime.toUtc().toIso8601String(),
      'currentRoomId': null,
      'tagOptions': tags(directory.tagOptions),
      'viewerPendingRoomIds': [
        for (final id in directory.viewerPendingRoomIds ?? <String>[]) key(id),
      ],
      'rooms': [for (final r in directory.rooms) await room(r, images)],
    };
  }

  RoomCommand? command(RoomOperation op, Map<String, Object?> data) {
    final allowed = switch (op) {
      RoomOperation.create => const {
        'title',
        'goal',
        'capacity',
        'isPublic',
        'eligibility',
        'admissionMode',
        'passwordEnabled',
        'password',
        'voiceRequirement',
        'language',
        'autoDisbandHours',
        'recruitmentDurationMinutes',
        'gameplayTagNodeIds',
        'contextTagIds',
      },
      RoomOperation.resolve => const {'roomCode'},
      RoomOperation.join => const {'roomId', 'password'},
      _ => const <String>{},
    };
    if (allowed.isEmpty || data.keys.any((k) => !allowed.contains(k))) {
      return null;
    }
    if (data.values.any((v) => v is String && v.length > 512)) return null;
    if (op == RoomOperation.resolve &&
        (data['roomCode'] is! String ||
            (data['roomCode'] as String).trim().isEmpty ||
            (data['roomCode'] as String).length > 32)) {
      return null;
    }
    if (data['password'] != null &&
        (data['password'] is! String ||
            (data['password'] as String).length > 32)) {
      return null;
    }
    if (op == RoomOperation.join) {
      final id = data['roomId'];
      if (id is! String || resolve(id) == null) return null;
      final room = _rooms[id]!;
      if (room.members.length >= room.capacity ||
          pending.contains(room.id) ||
          roomRecruitmentClosed(room, serverTime ?? DateTime.now().toUtc())) {
        return null;
      }
      return RoomCommand(op, {...data, 'roomId': resolve(id)});
    }
    return RoomCommand(op, data);
  }
}
