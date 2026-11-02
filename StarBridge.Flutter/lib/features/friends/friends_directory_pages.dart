import 'dart:convert';

import 'friends_snapshot_decoder.dart';

/// Collects one bounded immutable directory. No partial rows escape this owner.
final class FriendsDirectoryPages {
  static const _groups = [
    'friends',
    'incoming',
    'outgoing',
    'blocked',
    'results',
  ];
  static const _limit = 16 * 1024 * 1024;
  final _rows = <String, List<Object?>>{for (final group in _groups) group: []};
  String? _snapshotId;
  Object? _query, _refreshedAt;
  int? _total;
  int _received = 0, _bytes = 0, _lastGroup = -1;
  bool _complete = false, _failed = false;

  String get snapshotId => _snapshotId ?? (throw const FormatException());
  int get nextOffset {
    if (_complete || _failed || _snapshotId == null) {
      throw const FormatException();
    }
    return _received;
  }

  Map<String, Object?>? add(Map<String, Object?> body) {
    try {
      return _add(body);
    } on Object {
      _failed = true;
      for (final rows in _rows.values) {
        rows.clear();
      }
      rethrow;
    }
  }

  Map<String, Object?>? _add(Map<String, Object?> body) {
    if (_complete ||
        _failed ||
        body['schemaVersion'] is! int ||
        body['schemaVersion'] != 1 ||
        body.keys.any(
          (key) => !{
            'schemaVersion',
            'query',
            'refreshedAt',
            'page',
            ..._groups,
          }.contains(key),
        ) ||
        body['page'] is! Map) {
      throw const FormatException();
    }
    final page = Map<String, Object?>.from(body['page'] as Map);
    final id = page['snapshotId'], offset = page['offset'];
    final total = page['total'], next = page['nextOffset'];
    if (page.length != 4 ||
        page.keys.any(
          (key) => !const {
            'snapshotId',
            'offset',
            'nextOffset',
            'total',
          }.contains(key),
        ) ||
        id is! String ||
        !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(id) ||
        offset is! int ||
        offset != _received ||
        total is! int ||
        total < 0 ||
        total > 8020 ||
        (next != null && next is! int)) {
      throw const FormatException();
    }
    final directory = Map<String, Object?>.from(body)..remove('page');
    // Keep the existing business decoder as the authority for row semantics.
    parseFriendsSnapshot(directory);
    if (_snapshotId == null) {
      _snapshotId = id;
      _total = total;
      _query = body['query'];
      _refreshedAt = body['refreshedAt'];
    } else if (id != _snapshotId ||
        total != _total ||
        body['query'] != _query ||
        body['refreshedAt'] != _refreshedAt) {
      throw const FormatException();
    }
    var count = 0;
    for (var index = 0; index < _groups.length; index++) {
      final group = _groups[index];
      final rows = body[group] as List;
      if (rows.isNotEmpty) {
        if (index < _lastGroup) throw const FormatException();
        _lastGroup = index;
      }
      final accumulated = _rows[group]!;
      if (accumulated.length + rows.length > (group == 'results' ? 20 : 2000)) {
        throw const FormatException();
      }
      for (final raw in rows) {
        final row = Map<String, Object?>.unmodifiable(
          Map<String, Object?>.from(raw as Map),
        );
        // Count the directory data once. Repeated transport headers must not
        // make a valid Native snapshot at the shared limit fail to assemble.
        _bytes += utf8.encode(jsonEncode(row)).length;
        if (_bytes > _limit) throw const FormatException();
        accumulated.add(row);
      }
      count += rows.length;
    }
    _received += count;
    if (_received > total ||
        (count == 0 && (total != 0 || offset != 0)) ||
        (next == null
            ? _received != total
            : next != _received || _received >= total)) {
      throw const FormatException();
    }
    if (next != null) return null;
    _complete = true;
    final result = <String, Object?>{
      'schemaVersion': 1,
      if (_query != null) 'query': _query,
      if (_refreshedAt != null) 'refreshedAt': _refreshedAt,
      for (final group in _groups)
        group: List<Object?>.unmodifiable(_rows[group]!),
    };
    parseFriendsSnapshot(result);
    return Map<String, Object?>.unmodifiable(result);
  }
}
