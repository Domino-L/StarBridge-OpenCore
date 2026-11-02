import '../direct_messages/bridge_direct_messages.dart'
    show readConversationKey;
import 'friends_module.dart';

FriendsSnapshot parseFriendsSnapshot(
  Map<String, Object?> value, {
  bool avatarContext = false,
}) {
  if (value['schemaVersion'] != 1) throw const FormatException();
  String text(Object? value, int max) {
    if (value is! String ||
        value.length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException();
    }
    return value;
  }

  List<FriendRow> rows(String key, int max) {
    final items = value[key];
    if (items is! List || items.length > max) throw const FormatException();
    return items.map((raw) {
      final item = Map<String, Object?>.from(raw as Map);
      final relation = text(item['relationship'], 64);
      if (!(avatarContext && relation == 'self') &&
          !const {
            'none',
            'friend',
            'incoming',
            'outgoing',
            'blocked',
            'unknown',
          }.contains(relation)) {
        throw const FormatException();
      }
      final avatar = item['avatarImageData'];
      final reference = item['targetRef'];
      final chatReference = item['chatTargetRef'];
      if (chatReference != null &&
          (!(relation == 'friend' ||
                  avatarContext &&
                      const [
                        'none',
                        'incoming',
                        'outgoing',
                      ].contains(relation)) ||
              chatReference is! String ||
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(chatReference))) {
        throw const FormatException();
      }
      final actions = item['actions'];
      if (reference != null &&
          (reference is! String ||
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(reference))) {
        throw const FormatException();
      }
      final approved = actions == null
          ? <String>[]
          : (actions as List).cast<String>();
      if (approved.length > 3 ||
          approved.toSet().length != approved.length ||
          approved.any((a) => !friendActionsFor(relation).contains(a)) ||
          (approved.isNotEmpty && reference == null)) {
        throw const FormatException();
      }
      return FriendRow(
        text(item['callsign'], 512),
        text(item['gameId'], 512),
        relation,
        DateTime.parse(item['updatedAt'] as String),
        targetRef: reference as String?,
        chatTargetRef: chatReference as String?,
        conversationKey: relation == 'friend' || avatarContext
            ? readConversationKey(item['conversationKey'])
            : null,
        actions: List.unmodifiable(approved),
        shared: relation == 'friend' ? _readShared(item['shared']) : const {},
        sharedLabels: relation == 'friend'
            ? _readLabels(item['sharedLabels'])
            : const {},
        avatar:
            avatar is String &&
                avatar.length <= ((512 * 1024 + 2) ~/ 3 * 4) + 24 &&
                (avatar.startsWith('data:image/png;base64,') ||
                    avatar.startsWith('data:image/jpeg;base64,'))
            ? avatar
            : null,
      );
    }).toList();
  }

  final query = value['query'] == null ? null : text(value['query'], 128);
  final groups = {
    for (final section in FriendsSection.values)
      section: rows(section.name, 2000),
  };
  final results = rows('results', 20);
  if ((!avatarContext && query == null && results.isNotEmpty) ||
      // A search may carry the friends it also applies to, nothing else listed.
      (query != null &&
          groups.entries.any(
            (group) =>
                group.key != FriendsSection.friends && group.value.isNotEmpty,
          ))) {
    throw const FormatException();
  }
  return FriendsSnapshot(
    groups: groups,
    results: results,
    query: query,
    refreshedAt: value['refreshedAt'] == null
        ? null
        : DateTime.parse(value['refreshedAt'] as String),
  );
}

Map<String, Object?> _readShared(Object? raw) {
  if (raw == null) return const {};
  final data = (raw as Map).cast<String, Object?>();
  if (data.keys.any(
    (key) => !const {
      'presence',
      'sameServer',
      'serverId',
      'serverRegion',
      'ship',
      'location',
      'lastOnlineAt',
    }.contains(key),
  )) {
    throw const FormatException();
  }
  for (final key in const [
    'presence',
    'serverId',
    'serverRegion',
    'ship',
    'location',
    'lastOnlineAt',
  ]) {
    final value = data[key];
    if (value != null &&
        (value is! String ||
            value.length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))) {
      throw const FormatException();
    }
  }
  if (data['sameServer'] != null && data['sameServer'] is! bool) {
    throw const FormatException();
  }
  if (data['presence'] != null &&
      !const {
        'AppOnline',
        'InGame',
        'Away',
        'Offline',
      }.contains(data['presence'])) {
    throw const FormatException();
  }
  if (data['lastOnlineAt'] != null &&
      DateTime.tryParse(data['lastOnlineAt'] as String) == null) {
    throw const FormatException();
  }
  return Map.unmodifiable(data);
}

Map<String, Map<String, String>> _readLabels(Object? raw) {
  if (raw == null) return const {};
  if (raw is! Map ||
      raw.keys.any((key) => !const {'ship', 'location'}.contains(key))) {
    throw const FormatException();
  }
  final result = <String, Map<String, String>>{};
  for (final entry in raw.entries) {
    if (entry.value == null) continue;
    final names = entry.value;
    if (names is! Map ||
        names.keys.any(
          (key) => !const {'en', 'zhHans', 'zhHant'}.contains(key),
        )) {
      throw const FormatException();
    }
    final translated = <String, String>{};
    for (final name in names.entries) {
      if (name.value == null) continue;
      if (name.value is! String ||
          (name.value as String).length > 512 ||
          RegExp(r'[\x00-\x1f\x7f]').hasMatch(name.value as String)) {
        throw const FormatException();
      }
      if ((name.value as String).trim().isNotEmpty) {
        translated[name.key as String] = name.value as String;
      }
    }
    result[entry.key as String] = Map.unmodifiable(translated);
  }
  return Map.unmodifiable(result);
}
