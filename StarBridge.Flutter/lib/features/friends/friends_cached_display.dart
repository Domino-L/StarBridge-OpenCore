import 'friends_snapshot_decoder.dart';
import 'friends_module.dart';
import 'friends_directory_pages.dart';

/// A complete read-only display, never a partially materialized directory.
final class FriendsCachedPages {
  final _pages = FriendsDirectoryPages();
  String? _cachedAt;
  bool _failed = false;
  String get snapshotId => _pages.snapshotId;
  int get nextOffset => _pages.nextOffset;

  FriendsCachedDisplay? add(Map<String, Object?> body) {
    if (_failed) throw const FormatException();
    try {
      final directory = Map<String, Object?>.from(body['directory'] as Map);
      final rows = Map<String, Object?>.from(directory)..remove('page');
      decodeFriendsCachedDisplay({...body, 'directory': rows});
      final at = body['cachedAtUtc']! as String;
      if (_cachedAt != null && _cachedAt != at) throw const FormatException();
      _cachedAt = at;
      final complete = _pages.add(directory);
      return complete == null
          ? null
          : decodeFriendsCachedDisplay({...body, 'directory': complete});
    } on Object {
      _failed = true;
      rethrow;
    }
  }
}

FriendsCachedDisplay decodeFriendsCachedDisplay(Map<String, Object?> body) {
  if (body['schemaVersion'] is! int ||
      body['schemaVersion'] != 1 ||
      body['directory'] is! Map ||
      body['cachedAtUtc'] is! String ||
      body.keys.any(
        (key) => !const {
          'schemaVersion',
          'directory',
          'cachedAtUtc',
          'requestCorrelationId',
        }.contains(key),
      )) {
    throw const FormatException();
  }
  final directory = Map<String, Object?>.from(body['directory'] as Map);
  if (directory['schemaVersion'] is! int ||
      directory.keys.any(
        (key) => !const {
          'schemaVersion',
          'refreshedAt',
          'friends',
          'incoming',
          'outgoing',
          'blocked',
          'results',
        }.contains(key),
      )) {
    throw const FormatException();
  }
  for (final section in FriendsSection.values) {
    for (final raw in directory[section.name] as List) {
      final expected = section == FriendsSection.friends
          ? 'friend'
          : section.name;
      if (raw is! Map ||
          (raw['relationship'] != expected &&
              raw['relationship'] != 'unknown') ||
          raw.keys.any(
            (key) => !const {
              'callsign',
              'gameId',
              'relationship',
              'updatedAt',
              'actions',
            }.contains(key),
          )) {
        throw const FormatException();
      }
    }
  }
  final snapshot = parseFriendsSnapshot(directory);
  final at = DateTime.parse(body['cachedAtUtc']! as String);
  if (snapshot.query != null ||
      snapshot.results.isNotEmpty ||
      !at.isUtc ||
      at.isBefore(DateTime.fromMillisecondsSinceEpoch(1, isUtc: true)) ||
      at.isAfter(DateTime.now().toUtc().add(const Duration(minutes: 5))) ||
      snapshot.groups.values
          .expand((rows) => rows)
          .any(
            (row) =>
                row.targetRef != null ||
                row.chatTargetRef != null ||
                row.conversationKey != null ||
                row.actions.isNotEmpty ||
                row.shared.isNotEmpty ||
                row.sharedLabels.isNotEmpty,
          )) {
    throw const FormatException();
  }
  return FriendsCachedDisplay(snapshot, at);
}
