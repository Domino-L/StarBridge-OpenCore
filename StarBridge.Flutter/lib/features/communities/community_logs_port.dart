import 'dart:convert';

abstract interface class CommunityLogsPort {
  Stream<void> get invalidations;
  bool get logsAvailable;
  bool get logDeletionAvailable;
  Future<CommunityLogPage> readLogs(
    String targetRef,
    String type,
    String query,
    int offset,
  );
  Future<CommunityLogOutcome> deleteLog(String targetRef, String logRef);
}

const communityLogFilters = {'All', '成员', '公告', '舰队'};

final class CommunityLogEntry {
  const CommunityLogEntry(
    this.logRef,
    this.type,
    this.title,
    this.detail,
    this.timestamp,
    this.endTimestamp,
    this.occurrenceCount,
  );
  final String logRef, type, title, detail;
  final DateTime? timestamp, endTimestamp;
  final int occurrenceCount;
}

final class CommunityLogPage {
  const CommunityLogPage(
    this.targetRef,
    this.name,
    this.canDelete,
    this.type,
    this.query,
    this.offset,
    this.next,
    this.totalCount,
    this.matchedCount,
    this.items,
    this.fetchedAt,
  );
  final String targetRef, name, type, query;
  final bool canDelete;
  final int offset, totalCount, matchedCount;
  final int? next;
  final List<CommunityLogEntry> items;
  final DateTime fetchedAt;

  factory CommunityLogPage.parse(Map<String, Object?> value) {
    if (value['schemaVersion'] != 1 ||
        value['canDelete'] is! bool ||
        utf8.encode(jsonEncode(value)).length > 960 * 1024) {
      throw const FormatException();
    }
    String text(
      Map<String, Object?> map,
      String key,
      int max, {
      bool multiline = false,
    }) {
      final field = map[key];
      if (field is! String ||
          field.length > max ||
          RegExp(
            multiline
                ? r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'
                : r'[\x00-\x1f\x7f]',
          ).hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    String ref(Map<String, Object?> map, String key) {
      final field = text(map, key, 32);
      if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(field)) {
        throw const FormatException();
      }
      return field;
    }

    int number(Map<String, Object?> map, String key, int min, int max) {
      final field = map[key];
      if (field is! int || field < min || field > max) {
        throw const FormatException();
      }
      return field;
    }

    DateTime? time(Map<String, Object?> map, String key) {
      if (!map.containsKey(key)) throw const FormatException();
      if (map[key] == null) return null;
      final date = DateTime.tryParse(text(map, key, 64));
      if (date == null) throw const FormatException();
      return date;
    }

    final type = text(value, 'type', 16);
    if (!communityLogFilters.contains(type)) throw const FormatException();
    final raw = value['items'];
    if (raw is! List || raw.length > 20) throw const FormatException();
    final seen = <String>{};
    final items = raw
        .map((item) {
          if (item is! Map<String, Object?>) throw const FormatException();
          final id = ref(item, 'logRef');
          final start = time(item, 'timestamp'),
              end = time(item, 'endTimestamp');
          final rowType = text(item, 'type', 128);
          if (!seen.add(id) ||
              start != null && (end == null || end.isBefore(start)) ||
              type != 'All' && rowType != type) {
            throw const FormatException();
          }
          return CommunityLogEntry(
            id,
            rowType,
            text(item, 'title', 8192, multiline: true),
            text(item, 'detail', 32768, multiline: true),
            start,
            end,
            number(item, 'occurrenceCount', 1, 2147483647),
          );
        })
        .toList(growable: false);
    final total = number(value, 'totalCount', 0, 100000);
    final matched = number(value, 'matchedCount', 0, total);
    final offset = number(value, 'offset', 0, matched);
    if (!value.containsKey('next')) throw const FormatException();
    final next = value['next'] == null
        ? null
        : number(value, 'next', 0, matched);
    final remaining = matched - offset;
    if (items.length != (remaining < 20 ? remaining : 20) ||
        next !=
            (offset + items.length < matched ? offset + items.length : null)) {
      throw const FormatException();
    }
    return CommunityLogPage(
      ref(value, 'targetRef'),
      text(value, 'name', 512),
      value['canDelete'] as bool,
      type,
      text(value, 'query', 128),
      offset,
      next,
      total,
      matched,
      List.unmodifiable(items),
      time(value, 'fetchedAt') ?? (throw const FormatException()),
    );
  }
}

final class CommunityLogOutcome {
  const CommunityLogOutcome(this.status, {this.error});
  final String status;
  final String? error;
  factory CommunityLogOutcome.parse(Map<String, Object?> value) {
    final status = value['status'], error = value['error'];
    if (value['schemaVersion'] != 1 ||
        !{'accepted', 'rejected', 'unknown'}.contains(status) ||
        status == 'accepted' && error != null ||
        status == 'unknown' && error != 'outcomeUnknown' ||
        status == 'rejected' &&
            !{
              'busy',
              'refreshRequired',
              'identityUnavailable',
              'unavailable',
            }.contains(error)) {
      throw const FormatException();
    }
    return CommunityLogOutcome(status as String, error: error as String?);
  }
}
