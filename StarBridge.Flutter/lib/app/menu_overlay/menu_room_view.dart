import '../../features/party_rooms/party_rooms_module.dart';
import '../../features/common/runtime_name_labels.dart';
import 'menu_room_settings.dart';
import 'menu_room_management_view.dart';

/// Room presentation only: no room IDs, user refs, removal tokens or join rights.
final class MenuRoomView {
  const MenuRoomView(
    this.tab,
    this.code,
    this.goal,
    this.capacity,
    this.memberCount,
    this.members,
    this.loading,
    this.canChat, {
    this.facts = const {},
    this.memberActions = const {},
    this.memberTransferActions = const {},
    this.tags = const [],
    this.serverTime,
    this.expiresAt,
    this.recruitmentClosesAt,
    this.isPublic = false,
    this.settings,
    this.management,
  });
  final String tab, code, goal;
  final int capacity, memberCount;
  final List<RoomMember> members;
  final bool loading;
  final bool canChat;
  final Map<String, String> facts;
  final Map<int, String> memberActions;
  final Map<int, String> memberTransferActions;
  final List<RoomTag> tags;
  final DateTime? serverTime, expiresAt, recruitmentClosesAt;
  final bool isPublic;
  final MenuRoomSettingsView? settings;
  final MenuRoomManagementView? management;

  PartyRoom presentation(String title, String scope, {bool manage = false}) =>
      PartyRoom(
        id: scope,
        title: title,
        goal: goal,
        capacity: capacity,
        roomCode: code,
        isPublic: isPublic,
        eligibility: facts['eligibility'] ?? '',
        admissionMode: facts['admission'] ?? '',
        passwordRequired: facts['password'] == 'required',
        voice: facts['voice'] ?? '',
        language: facts['language'] ?? '',
        expiresAt:
            expiresAt ?? DateTime.fromMillisecondsSinceEpoch(0, isUtc: true),
        recruitmentClosesAt: recruitmentClosesAt,
        viewerIsHost: manage,
        pendingApplications: management?.applications ?? const [],
        members: members,
        tags: tags,
      );
  static MenuRoomView parse(Object? raw) {
    if (raw is! Map) throw const FormatException();
    String text(Map m, String key, [int limit = 512]) {
      final value = m[key] ?? '';
      if (value is! String || value.length > limit) {
        throw const FormatException();
      }
      return value;
    }

    final tab = text(raw, 'tab'),
        capacity = raw['capacity'],
        count = raw['memberCount'];
    final rows = raw['members'];
    if (!const {'members', 'chat'}.contains(tab) ||
        capacity is! int ||
        capacity < 1 ||
        capacity > 500 ||
        count is! int ||
        count < 0 ||
        count > capacity ||
        rows is! List ||
        rows.length > capacity) {
      throw const FormatException();
    }
    return MenuRoomView(
      tab,
      text(raw, 'code', 32),
      text(raw, 'goal', 2048),
      capacity,
      count,
      List.unmodifiable(
        rows.map((row) {
          if (row is! Map ||
              row.containsKey('userRef') ||
              row.containsKey('removalToken')) {
            throw const FormatException();
          }
          final avatar = text(row, 'avatar', 28000);
          if (avatar.isNotEmpty &&
              !avatar.startsWith('data:image/png;base64,')) {
            throw const FormatException();
          }
          return RoomMember(
            callsign: text(row, 'callsign'),
            gameId: text(row, 'gameId'),
            isHost: row['isHost'] == true,
            isSelf: row['isSelf'] == true,
            presence: text(row, 'presence'),
            presenceKey: text(row, 'presenceKey', 64),
            location: text(row, 'location'),
            ship: text(row, 'ship'),
            shard: '',
            serverRegion: text(row, 'serverRegion', 64),
            avatarData: avatar.isEmpty ? null : avatar,
            shipLabels: parseRuntimeNameLabels(row['shipLabels']),
            locationLabels: parseRuntimeNameLabels(row['locationLabels']),
            locationHiddenReason: row['locationHiddenReason'] == 'lowConfidence'
                ? 'lowConfidence'
                : null,
            arrivalPendingConfirmation:
                row['arrivalPendingConfirmation'] == true,
            arrivalTargetCode: text(row, 'arrivalTargetCode'),
            arrivalTargetLabels: parseRuntimeNameLabels(
              row['arrivalTargetLabels'],
            ),
          );
        }),
      ),
      raw['loading'] == true,
      raw['canChat'] == true,
      settings: raw['settings'] == null
          ? null
          : MenuRoomSettingsView.parse(raw['settings']),
      management: raw['management'] is Map
          ? MenuRoomManagementView(raw['management'] as Map)
          : null,
      isPublic: raw['isPublic'] == true,
      serverTime: DateTime.tryParse(text(raw, 'serverTime', 64)),
      expiresAt: DateTime.tryParse(text(raw, 'expiresAt', 64)),
      recruitmentClosesAt: DateTime.tryParse(
        text(raw, 'recruitmentClosesAt', 64),
      ),
      tags: [
        if (raw['tags'] is List && (raw['tags'] as List).length <= 32)
          for (final tag in raw['tags'] as List)
            if (tag is Map)
              RoomTag(
                id: text(tag, 'id', 128),
                text: text(tag, 'text'),
                isGameplay: tag['isGameplay'] == true,
              ),
      ],
      memberActions: {
        if (raw['memberActions'] is Map)
          for (final e in (raw['memberActions'] as Map).entries)
            if (int.tryParse('${e.key}') case final int index)
              if (index >= 0 &&
                  index < rows.length &&
                  e.value is String &&
                  RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(e.value as String))
                index: e.value as String,
      },
      memberTransferActions: {
        if (raw['memberTransferActions'] is Map)
          for (final e in (raw['memberTransferActions'] as Map).entries)
            if (int.tryParse('${e.key}') case final int index)
              if (index >= 0 &&
                  index < rows.length &&
                  e.value is String &&
                  RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(e.value as String))
                index: e.value as String,
      },
      facts: {
        if (raw['facts'] is Map)
          for (final key in const [
            'language',
            'admission',
            'voice',
            'eligibility',
            'password',
          ])
            key: text(raw['facts'] as Map, key, 64),
      },
    );
  }
}

Map<String, Object?> menuRoomMember(RoomMember member, String? avatar) => {
  'callsign': member.callsign,
  'gameId': member.gameId,
  'isHost': member.isHost,
  'isSelf': member.isSelf,
  'avatar': avatar,
  'presence': member.presence,
  'presenceKey': member.presenceKey,
  'location': member.location,
  'ship': member.ship,
  'serverRegion': member.serverRegion,
  'shipLabels': member.shipLabels,
  'locationLabels': member.locationLabels,
  'locationHiddenReason': member.locationHiddenReason,
  'arrivalPendingConfirmation': member.arrivalPendingConfirmation,
  'arrivalTargetCode': member.arrivalTargetCode ?? '',
  'arrivalTargetLabels': member.arrivalTargetLabels,
};
