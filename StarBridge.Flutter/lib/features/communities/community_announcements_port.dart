import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

abstract interface class CommunityAnnouncementsPort {
  Stream<void> get invalidations;
  bool get announcementsAvailable;
  Future<CommunityAnnouncementsPage> readAnnouncements(
    String targetRef, {
    int offset = 0,
    int? expectedRevision,
  });
  Future<Map<String, Object?>> readAnnouncementDetail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version,
  );
}

final class CommunityAnnouncementAuthor {
  CommunityAnnouncementAuthor.parse(Map<String, Object?> row)
    : memberRef = row['memberRef'] == null ? null : _ref(row, 'memberRef'),
      callsign = _text(row, 'callsign', 256),
      gameId = _text(row, 'gameId', 256),
      roleTitle = _text(row, 'roleTitle', 256),
      roleColor = _text(row, 'roleColor', 7),
      hasAvatar = _flag(row, 'hasAvatar') {
    if (!RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(roleColor)) {
      throw const FormatException();
    }
  }
  final String? memberRef;
  final String callsign, gameId, roleTitle, roleColor;
  final bool hasAvatar;
}

final class CommunityAnnouncement {
  CommunityAnnouncement.parse(Map<String, Object?> row)
    : announcementRef = _ref(row, 'announcementRef'),
      title = _text(row, 'title', 48),
      content = _text(row, 'content', 1200, multiline: true),
      state = _text(row, 'state', 16),
      revision = _number(row, 'revision'),
      publishedAt = _date(row, 'publishedAt'),
      updatedAt = _date(row, 'updatedAt'),
      archivedAt = row['archivedAt'] == null ? null : _date(row, 'archivedAt'),
      withdrawnAt = row['withdrawnAt'] == null
          ? null
          : _date(row, 'withdrawnAt'),
      author = CommunityAnnouncementAuthor.parse(_map(row['author'])),
      editor = CommunityAnnouncementAuthor.parse(_map(row['editor'])) {
    if (title.trim().isEmpty ||
        revision < 1 ||
        revision > 0x7fffffff ||
        !{'published', 'archived', 'withdrawn'}.contains(state)) {
      throw const FormatException();
    }
  }
  final String announcementRef, title, content, state;
  final int revision;
  final DateTime publishedAt, updatedAt;
  final DateTime? archivedAt, withdrawnAt;
  final CommunityAnnouncementAuthor author, editor;
}

final class CommunityAnnouncementsPage {
  /// Refresh access/time without discarding already paged history when the
  /// authoritative timeline has not changed.
  CommunityAnnouncementsPage.refreshed(
    CommunityAnnouncementsPage previous,
    CommunityAnnouncementsPage newest,
  ) : targetRef = previous.targetRef,
      revision = previous.revision,
      canManage = newest.canManage,
      current = previous.current,
      history = previous.history,
      offset = previous.offset,
      next = previous.next,
      totalHistoryCount = previous.totalHistoryCount,
      refreshedAt = newest.refreshedAt {
    if (previous.targetRef != newest.targetRef ||
        previous.revision != newest.revision ||
        previous.current?.announcementRef != newest.current?.announcementRef ||
        previous.totalHistoryCount != newest.totalHistoryCount) {
      throw const FormatException();
    }
  }
  CommunityAnnouncementsPage.parse(Map<String, Object?> row)
    : targetRef = _ref(row, 'targetRef'),
      revision = _number(row, 'revision'),
      canManage = _flag(row, 'canManage'),
      current = row['current'] == null
          ? null
          : CommunityAnnouncement.parse(_map(row['current'])),
      history = List.unmodifiable(
        _rows(row['history']).map(CommunityAnnouncement.parse),
      ),
      offset = _number(row, 'offset'),
      next = row['next'] == null ? null : _number(row, 'next'),
      totalHistoryCount = _number(row, 'totalHistoryCount'),
      refreshedAt = _date(row, 'refreshedAt') {
    final records = [?current, ...history];
    if (row['schemaVersion'] != 1 ||
        totalHistoryCount > 100 ||
        offset > totalHistoryCount ||
        current != null &&
            (current!.state != 'published' || totalHistoryCount > 99) ||
        history.any((item) => item.state == 'published') ||
        records.any((item) => item.revision > revision) ||
        records.map((item) => item.announcementRef).toSet().length !=
            records.length ||
        history.length != (totalHistoryCount - offset).clamp(0, 20) ||
        next !=
            (offset + history.length < totalHistoryCount
                ? offset + history.length
                : null)) {
      throw const FormatException();
    }
    for (var i = 1; i < history.length; i++) {
      if (history[i].updatedAt.isAfter(history[i - 1].updatedAt)) {
        throw const FormatException();
      }
    }
  }
  final String targetRef;
  final int revision, offset, totalHistoryCount;
  final int? next;
  final bool canManage;
  final CommunityAnnouncement? current;
  final List<CommunityAnnouncement> history;
  final DateTime refreshedAt;
}

final class CommunityAnnouncementDetail {
  const CommunityAnnouncementDetail(
    this.authorAvatarImageData,
    this.editorAvatarImageData,
    this.canManage,
  );
  final String? authorAvatarImageData, editorAvatarImageData;
  final bool canManage;
}

Future<CommunityAnnouncementDetail> assembleCommunityAnnouncementDetail(
  CommunityAnnouncementsPort port,
  String targetRef,
  CommunityAnnouncement announcement, {
  required void Function() checkCurrent,
}) async {
  final builder = BytesBuilder(copy: false);
  String? version;
  int? total;
  var offset = 0;
  var canManage = true;
  while (true) {
    checkCurrent();
    final row = await port.readAnnouncementDetail(
      targetRef,
      announcement.announcementRef,
      offset,
      version,
    );
    checkCurrent();
    final hash = _text(row, 'version', 64), size = _number(row, 'totalBytes');
    final permission = _flag(row, 'canManage');
    canManage = canManage && permission;
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != targetRef ||
        row['announcementRef'] != announcement.announcementRef ||
        row['offset'] != offset ||
        size <= offset ||
        size > 1600 * 1024 ||
        !RegExp(r'^[a-f0-9]{64}$').hasMatch(hash) ||
        version != null && (version != hash || total != size)) {
      throw const FormatException();
    }
    final bytes = base64Decode(_text(row, 'data', 256 * 1024));
    if (bytes.length != (size - offset).clamp(0, 192 * 1024)) {
      throw const FormatException();
    }
    offset += bytes.length;
    if (row['next'] != (offset < size ? offset : null)) {
      throw const FormatException();
    }
    total = size;
    version = hash;
    builder.add(bytes);
    if (offset == size) break;
  }
  final bytes = builder.takeBytes();
  if (sha256.convert(bytes).toString() != version) {
    throw const FormatException();
  }
  final row = _map(jsonDecode(utf8.decode(bytes)));
  if (row.length != 2 ||
      !row.containsKey('authorAvatarImageData') ||
      !row.containsKey('editorAvatarImageData')) {
    throw const FormatException();
  }
  final author = _avatar(row['authorAvatarImageData']),
      editor = _avatar(row['editorAvatarImageData']);
  if ((author != null) != announcement.author.hasAvatar ||
      (editor != null) != announcement.editor.hasAvatar) {
    throw const FormatException();
  }
  checkCurrent();
  return CommunityAnnouncementDetail(author, editor, canManage);
}

String? _avatar(Object? value) {
  if (value == null) return null;
  if (value is! String ||
      value.length > 720 * 1024 ||
      !RegExp(r'^data:image/(png|jpeg|bmp|gif|webp);base64,').hasMatch(value)) {
    throw const FormatException();
  }
  final bytes = base64Decode(value.substring(value.indexOf(',') + 1));
  if (bytes.length < 8 || bytes.length > 512 * 1024) {
    throw const FormatException();
  }
  return value;
}

Map<String, Object?> _map(Object? value) =>
    value is Map<String, Object?> ? value : throw const FormatException();
List<Map<String, Object?>> _rows(Object? value) =>
    value is List && value.length <= 20
    ? value.map(_map).toList()
    : throw const FormatException();
int _number(Map<String, Object?> row, String key) =>
    row[key] is int && (row[key] as int) >= 0
    ? row[key] as int
    : throw const FormatException();
bool _flag(Map<String, Object?> row, String key) =>
    row[key] is bool ? row[key] as bool : throw const FormatException();
String _text(
  Map<String, Object?> row,
  String key,
  int maximum, {
  bool multiline = false,
}) {
  final value = row[key];
  if (value is! String ||
      value.length > maximum ||
      value.codeUnits.any(
        (c) =>
            (c < 32 || c >= 127 && c <= 159) &&
            !(multiline && {9, 10, 13}.contains(c)),
      )) {
    throw const FormatException();
  }
  return value;
}

String _ref(Map<String, Object?> row, String key) {
  final value = _text(row, key, 32);
  if (!RegExp(r'^[a-f0-9]{32}$').hasMatch(value)) throw const FormatException();
  return value;
}

DateTime _date(Map<String, Object?> row, String key) =>
    DateTime.tryParse(_text(row, key, 64)) ?? (throw const FormatException());
