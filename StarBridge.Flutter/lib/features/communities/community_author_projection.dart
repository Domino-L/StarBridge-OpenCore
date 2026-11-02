import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// An official content address is not permission to disclose its author.
/// The old wire stays usable while optional identity negotiation is absent.
Map<String, Object?> neutralOfficialChatPage(Map<String, Object?> row) {
  final messages = row['messages'];
  return {
    ...row,
    if (messages is List)
      'messages': [
        for (final value in messages)
          if (value is Map<String, Object?>)
            {
              ...value,
              'senderCallsign': '',
              'senderGameId': '',
              'senderRoleTitle': '',
              'senderRoleColor': '#9DAAB3',
              'hasAvatar': false,
              'avatarVersion': null,
            }
          else
            value,
      ],
    'authorUpdates': <Object?>[],
  };
}

/// Retain authorized announcement content while disclosing no person facts.
/// Opaque member references remain content addresses, never profile authority.
Map<String, Object?> neutralOfficialAnnouncementsPage(
  Map<String, Object?> row,
) {
  Object? neutralRecord(Object? value) {
    if (value is! Map<String, Object?>) return value;

    return {
      ...value,
      'author': _announcementPerson(value['author'], neutral: true),
      'editor': _announcementPerson(value['editor'], neutral: true),
    };
  }

  final history = row['history'];
  return {
    ...row,
    'current': neutralRecord(row['current']),
    if (history is List) 'history': history.map(neutralRecord).toList(),
    'authorUpdates': <Object?>[],
  };
}

enum CommunityAuthorState { visible, lastSeen, hidden, unavailable }

/// A received observation is admitted before publication, never renewed.
/// It conveys no membership, profile action or management authority.
final class CommunityAuthorProjection {
  const CommunityAuthorProjection.unavailable()
    : state = CommunityAuthorState.unavailable,
      callsign = '',
      avatarVersion = null,
      version = null,
      observedAt = null,
      validUntil = null;
  const CommunityAuthorProjection.hidden()
    : state = CommunityAuthorState.hidden,
      callsign = '',
      avatarVersion = null,
      version = null,
      observedAt = null,
      validUntil = null;
  /// A name this viewer saw before, unconfirmed: grants no profile or avatar
  /// read, and never counts as [visible].
  const CommunityAuthorProjection.lastSeen(this.callsign)
    : state = CommunityAuthorState.lastSeen,
      avatarVersion = null,
      version = null,
      observedAt = null,
      validUntil = null;
  const CommunityAuthorProjection._(
    this.callsign,
    this.avatarVersion,
    this.version,
    this.observedAt,
    this.validUntil,
  ) : state = CommunityAuthorState.visible;
  final CommunityAuthorState state;
  final String callsign;
  final String? avatarVersion, version;
  final DateTime? observedAt, validUntil;
  bool get visible => state == CommunityAuthorState.visible;
  bool get hasAvatar => visible && avatarVersion != null;

  factory CommunityAuthorProjection.chat(Map<String, Object?> row) =>
      CommunityAuthorProjection._read(row, chat: true);
  factory CommunityAuthorProjection.person(Map<String, Object?> row) =>
      CommunityAuthorProjection._read(row, chat: false);
  factory CommunityAuthorProjection._read(
    Map<String, Object?> row, {
    required bool chat,
  }) {
    final state = row[chat ? 'authorIdentityState' : 'identityState'];
    if (state == 'hidden') return const CommunityAuthorProjection.hidden();
    if (state != 'visible') {
      return const CommunityAuthorProjection.unavailable();
    }
    try {
      final name = row[chat ? 'senderCallsign' : 'callsign'];
      final avatar = row['avatarVersion'];
      final version = row[chat ? 'authorIdentityVersion' : 'identityVersion'];
      final observed = _utc(row['identityObservedAtUtc']);
      final until = _utc(row['identityValidUntilUtc']);
      if (name is! String ||
          name.isEmpty ||
          name.trim() != name ||
          name.length > 128 ||
          name.contains(RegExp(r'[\x00-\x1f\x7f-\x9f]')) ||
          !_hash(version) ||
          row['hasAvatar'] is! bool ||
          row['hasAvatar'] != (avatar != null) ||
          avatar != null && !_hash(avatar) ||
          observed == null ||
          until == null ||
          !until.isAfter(observed) ||
          until.difference(observed) > const Duration(seconds: 5)) {
        return const CommunityAuthorProjection.unavailable();
      }
      return CommunityAuthorProjection._(
        name,
        avatar as String?,
        version as String,
        observed,
        until,
      );
    } on Object {
      return const CommunityAuthorProjection.unavailable();
    }
  }
  CommunityAuthorProjection admit(DateTime now) =>
      visible &&
          (observedAt!.isAfter(now.toUtc().add(const Duration(seconds: 1))) ||
              !validUntil!.isAfter(now.toUtc()))
      ? const CommunityAuthorProjection.unavailable()
      : this;
  bool sameIdentityAs(CommunityAuthorProjection other) =>
      visible &&
      other.visible &&
      callsign == other.callsign &&
      version == other.version &&
      avatarVersion == other.avatarVersion;
  bool sameObservationAs(CommunityAuthorProjection other) =>
      sameIdentityAs(other) &&
      observedAt == other.observedAt &&
      validUntil == other.validUntil;
  Map<String, Object?> get personFields => {
    'callsign': callsign,
    'gameId': '',
    'roleTitle': '',
    'roleColor': '#9DAAB3',
    'hasAvatar': hasAvatar,
    'avatarVersion': avatarVersion,
    'identityState': state.name,
    'identityVersion': version,
    'identityObservedAtUtc': observedAt?.toIso8601String(),
    'identityValidUntilUtc': validUntil?.toIso8601String(),
  };
  Map<String, Object?> get chatFields => {
    'senderCallsign': callsign,
    'senderGameId': '',
    'senderRoleTitle': '',
    'senderRoleColor': '#9DAAB3',
    'hasAvatar': hasAvatar,
    'avatarVersion': avatarVersion,
    'authorIdentityState': state.name,
    'authorIdentityVersion': version,
    'identityObservedAtUtc': observedAt?.toIso8601String(),
    'identityValidUntilUtc': validUntil?.toIso8601String(),
  };
}

final class CommunityChatAuthorUpdate {
  CommunityChatAuthorUpdate.parse(Map<String, Object?> row)
    : messageRef = _reference(row['messageRef']),
      senderRef = _reference(row['senderRef']),
      sequence = row['sequence'] as int,
      found = row['recordState'] == 'found',
      identity = row['recordState'] == 'found'
          ? CommunityAuthorProjection.chat(row)
          : const CommunityAuthorProjection.unavailable() {
    if (sequence <= 0 ||
        !{'found', 'notRetained'}.contains(row['recordState'])) {
      throw const FormatException();
    }
  }
  final String messageRef, senderRef;
  final int sequence;
  final bool found;
  final CommunityAuthorProjection identity;
}

/// Malformed optional identity metadata never revokes an authorized body.
Map<String, Object?> checkedOfficialChatPage(
  Map<String, Object?> row,
  List<String> observed,
) {
  try {
    final raw = row['authorUpdates'];
    if (row['authorIdentitySchemaVersion'] != 1 ||
        row['authorRefreshRequired'] is! bool ||
        raw is! List ||
        raw.length > 50 ||
        utf8.encode(jsonEncode(raw)).length > 64 * 1024) {
      throw const FormatException();
    }
    final seen = <String>{};
    for (final value in raw) {
      final update = CommunityChatAuthorUpdate.parse(
        Map<String, Object?>.from(value as Map),
      );
      if (!seen.add(update.messageRef) ||
          !observed.contains(update.messageRef)) {
        throw const FormatException();
      }
    }
    final messages = row['messages'];
    return {
      ...row,
      if (messages is List)
        'messages': [
          for (final value in messages)
            if (value is Map<String, Object?>)
              {...value, ...CommunityAuthorProjection.chat(value).chatFields}
            else
              value,
        ],
    };
  } on Object {
    return {...neutralOfficialChatPage(row), 'authorRefreshRequired': true};
  }
}

List<CommunityChatAuthorUpdate> officialChatUpdates(Object? value) {
  try {
    if (value is! List || value.length > 50) return const [];
    return List.unmodifiable(
      value.map(
        (row) => CommunityChatAuthorUpdate.parse(
          Map<String, Object?>.from(row as Map),
        ),
      ),
    );
  } on Object {
    return const [];
  }
}

bool _hash(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{64}$').hasMatch(value);
String _reference(Object? value) =>
    value is String && RegExp(r'^[0-9a-f]{32}$').hasMatch(value)
    ? value
    : throw const FormatException();
DateTime? _utc(Object? value) =>
    value is String && RegExp(r'(Z|\+00:00)$').hasMatch(value)
    ? DateTime.tryParse(value)?.toUtc()
    : null;

final class CommunityAnnouncementAuthorUpdate {
  CommunityAnnouncementAuthorUpdate.parse(Map<String, Object?> row)
    : announcementRef = _reference(row['announcementRef']),
      revision = row['revision'] as int,
      found = row['recordState'] == 'found',
      author = row['recordState'] == 'found'
          ? CommunityAuthorProjection.person(_announcementPerson(row['author']))
          : const CommunityAuthorProjection.unavailable(),
      editor = row['recordState'] == 'found'
          ? CommunityAuthorProjection.person(_announcementPerson(row['editor']))
          : const CommunityAuthorProjection.unavailable() {
    if (revision < 1 ||
        revision > 0x7fffffff ||
        !{'found', 'notRetained'}.contains(row['recordState']) ||
        row.length != 5 ||
        !row.keys.every(
          {
            'announcementRef',
            'revision',
            'recordState',
            'author',
            'editor',
          }.contains,
        )) {
      throw const FormatException();
    }
  }
  final String announcementRef;
  final int revision;
  final bool found;
  final CommunityAuthorProjection author, editor;
}

Map<String, Object?> _announcementPerson(
  Object? value, {
  bool neutral = false,
}) {
  final row = value is Map<String, Object?> ? value : const <String, Object?>{};
  final reference = row['memberRef'];
  final validReference =
      reference == null ||
      reference is String && RegExp(r'^[a-f0-9]{32}$').hasMatch(reference);
  final identity = neutral || !validReference
      ? const CommunityAuthorProjection.unavailable()
      : CommunityAuthorProjection.person(row);
  return {
    'memberRef': validReference ? reference : null,
    ...identity.personFields,
  };
}

/// Optional person protocol errors cannot revoke otherwise authorized content.
Map<String, Object?> checkedOfficialAnnouncementsPage(
  Map<String, Object?> row,
  List<String> observed,
) {
  try {
    final raw = row['authorUpdates'];
    if (row['authorIdentitySchemaVersion'] is! int ||
        row['authorIdentitySchemaVersion'] != 1 ||
        row['authorRefreshRequired'] is! bool ||
        raw is! List ||
        raw.length > 21 ||
        utf8.encode(jsonEncode(raw)).length > 64 * 1024) {
      throw const FormatException();
    }
    final seen = <String>{};
    for (final value in raw) {
      final update = CommunityAnnouncementAuthorUpdate.parse(
        Map<String, Object?>.from(value as Map),
      );
      if (!seen.add(update.announcementRef) ||
          !observed.contains(update.announcementRef)) {
        throw const FormatException();
      }
    }
    Object? record(Object? value) => value is Map<String, Object?>
        ? {
            ...value,
            'author': _announcementPerson(value['author']),
            'editor': _announcementPerson(value['editor']),
          }
        : value;
    final history = row['history'];
    return {
      ...row,
      'current': record(row['current']),
      if (history is List) 'history': history.map(record).toList(),
    };
  } on Object {
    return {
      ...neutralOfficialAnnouncementsPage(row),
      'authorRefreshRequired': true,
    };
  }
}

List<CommunityAnnouncementAuthorUpdate> officialAnnouncementUpdates(
  Object? value,
) {
  try {
    if (value is! List ||
        value.length > 21 ||
        utf8.encode(jsonEncode(value)).length > 64 * 1024) {
      return const [];
    }
    return List.unmodifiable(
      value.map(
        (row) => CommunityAnnouncementAuthorUpdate.parse(
          Map<String, Object?>.from(row as Map),
        ),
      ),
    );
  } on Object {
    return const [];
  }
}

/// A malformed optional hint retires only this identity sub-protocol, never
/// otherwise authorized content. A valid true hint preserves each valid person.
({
  CommunityAuthorProjection author,
  CommunityAuthorProjection editor,
  bool refresh,
})
officialAnnouncementDetailPeople(Map<String, Object?> row) {
  if (row['authorRefreshRequired'] is! bool) {
    return (
      author: const CommunityAuthorProjection.unavailable(),
      editor: const CommunityAuthorProjection.unavailable(),
      refresh: true,
    );
  }
  return (
    author: CommunityAuthorProjection.person(
      _announcementPerson(row['author']),
    ),
    editor: CommunityAuthorProjection.person(
      _announcementPerson(row['editor']),
    ),
    refresh: row['authorRefreshRequired'] as bool,
  );
}

Map<String, Object?> neutralOfficialAnnouncementDetail(
  Map<String, Object?> row,
) => {
  ...row,
  'author': _announcementPerson(row['author'], neutral: true),
  'editor': _announcementPerson(row['editor'], neutral: true),
  'authorRefreshRequired': true,
};
({CommunityAuthorProjection author, bool refresh}) officialChatDetailPerson(
  Map<String, Object?> row,
  String senderRef,
) {
  final person = row['author'];
  if (row['authorRefreshRequired'] is! bool ||
      person is! Map<String, Object?> ||
      person['senderRef'] != senderRef) {
    return (
      author: const CommunityAuthorProjection.unavailable(),
      refresh: true,
    );
  }
  return (
    author: CommunityAuthorProjection.person(person),
    refresh: row['authorRefreshRequired'] as bool,
  );
}

Map<String, Object?> neutralOfficialChatDetail(Map<String, Object?> row) => {
  ...row,
  'authorRefreshRequired': true,
  'author': {
    if (row['author'] is Map) 'senderRef': (row['author'] as Map)['senderRef'],
    ...(const CommunityAuthorProjection.unavailable()).personFields,
  },
};

/// Official thumbnails bind the complete URI, never a legacy account image.
/// The avatar this answer names, proven by its version and not by the clock.
Uint8List? officialAuthorAvatarBytes(Object? value, String version) {
  try {
    if (value is! String ||
        value.length > 4096 ||
        !RegExp(r'^data:image/(png|jpeg);base64,').hasMatch(value) ||
        sha256.convert(utf8.encode(value)).toString() != version) {
      return null;
    }
    final bytes = base64Decode(value.split(',').last);
    return bytes.length >= 8 && bytes.length <= 3 * 1024 ? bytes : null;
  } on Object {
    return null;
  }
}

String? officialAuthorAvatar(
  Object? value,
  CommunityAuthorProjection observed,
  DateTime now,
) {
  if (!observed.admit(now).hasAvatar) return null;
  try {
    if (value is! String ||
        value.length > 4096 ||
        !RegExp(r'^data:image/(png|jpeg);base64,').hasMatch(value) ||
        sha256.convert(utf8.encode(value)).toString() !=
            observed.avatarVersion) {
      return null;
    }
    final bytes = base64Decode(value.split(',').last);
    return bytes.length >= 8 && bytes.length <= 3 * 1024 ? value : null;
  } on Object {
    return null;
  }
}
