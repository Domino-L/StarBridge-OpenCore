import 'dart:convert';
import 'dart:typed_data';

import 'community_author_projection.dart';

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
  CommunityAnnouncementAuthor.parse(
    Map<String, Object?> row, {
    bool officialAuthors = false,
  }) : identity = officialAuthors
           ? CommunityAuthorProjection.person(row)
           : null,
       avatarVersion = officialAuthors ? row['avatarVersion'] as String? : null,
       memberRef = row['memberRef'] == null ? null : _ref(row, 'memberRef'),
       callsign = _text(row, 'callsign', 256),
       gameId = _text(row, 'gameId', 256),
       roleTitle = _text(row, 'roleTitle', 256),
       roleColor = _text(row, 'roleColor', 7),
       hasAvatar = _flag(row, 'hasAvatar') {
    if (!RegExp(r'^#[a-fA-F0-9]{6}$').hasMatch(roleColor)) {
      throw const FormatException();
    }
  }
  CommunityAnnouncementAuthor.withIdentity(
    CommunityAnnouncementAuthor original,
    CommunityAuthorProjection projection,
  ) : identity = projection,
      memberRef = original.memberRef,
      avatarVersion = projection.avatarVersion,
      callsign = projection.callsign,
      gameId = '',
      roleTitle = '',
      roleColor = '#9DAAB3',
      hasAvatar = projection.hasAvatar;
  final CommunityAuthorProjection? identity;
  final String? memberRef, avatarVersion;
  final String callsign, gameId, roleTitle, roleColor;
  final bool hasAvatar;
}

final class CommunityAnnouncement {
  CommunityAnnouncement.parse(
    Map<String, Object?> row, {
    bool officialAuthors = false,
  }) : announcementRef = _ref(row, 'announcementRef'),
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
       author = CommunityAnnouncementAuthor.parse(
         _map(row['author']),
         officialAuthors: officialAuthors,
       ),
       editor = CommunityAnnouncementAuthor.parse(
         _map(row['editor']),
         officialAuthors: officialAuthors,
       ) {
    if (title.trim().isEmpty ||
        revision < 1 ||
        revision > 0x7fffffff ||
        !{'published', 'archived', 'withdrawn'}.contains(state)) {
      throw const FormatException();
    }
  }

  /// A presentation-only copy; immutable content authority is unchanged.
  CommunityAnnouncement.withPeople(
    CommunityAnnouncement original,
    CommunityAuthorProjection authorIdentity,
    CommunityAuthorProjection editorIdentity,
  ) : announcementRef = original.announcementRef,
      title = original.title,
      content = original.content,
      state = original.state,
      revision = original.revision,
      publishedAt = original.publishedAt,
      updatedAt = original.updatedAt,
      archivedAt = original.archivedAt,
      withdrawnAt = original.withdrawnAt,
      author = CommunityAnnouncementAuthor.withIdentity(
        original.author,
        authorIdentity,
      ),
      editor = CommunityAnnouncementAuthor.withIdentity(
        original.editor,
        editorIdentity,
      );
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
  ) : authorUpdates = newest.authorUpdates,
      authorRefreshRequired = newest.authorRefreshRequired,
      targetRef = previous.targetRef,
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
  CommunityAnnouncementsPage.parse(
    Map<String, Object?> row, {
    bool officialAuthors = false,
  }) : authorUpdates = officialAuthors
           ? officialAnnouncementUpdates(row['authorUpdates'])
           : const [],
       authorRefreshRequired =
           officialAuthors && row['authorRefreshRequired'] != false,
       targetRef = _ref(row, 'targetRef'),
       revision = _number(row, 'revision'),
       canManage = _flag(row, 'canManage'),
       current = row['current'] == null
           ? null
           : CommunityAnnouncement.parse(
               _map(row['current']),
               officialAuthors: officialAuthors,
             ),
       history = List.unmodifiable(
         _rows(row['history']).map(
           (value) => CommunityAnnouncement.parse(
             value,
             officialAuthors: officialAuthors,
           ),
         ),
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
  final List<CommunityAnnouncementAuthorUpdate> authorUpdates;
  final bool authorRefreshRequired;
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
    this.canManage, {
    this.identityScope,
    this.authorIdentity,
    this.editorIdentity,
    this.authorObservation,
    this.editorObservation,
    this.authorRefreshRequired = false,
  });
  final String? authorAvatarImageData, editorAvatarImageData;
  final bool canManage;
  final bool authorRefreshRequired;
  final Object? identityScope;
  final CommunityAuthorProjection? authorIdentity, editorIdentity;
  final CommunityAuthorProjection? authorObservation, editorObservation;
  CommunityAnnouncementDetail.withoutPeople(
    CommunityAnnouncementDetail original, {
    bool author = false,
    bool editor = false,
  }) : authorAvatarImageData = author ? null : original.authorAvatarImageData,
       editorAvatarImageData = editor ? null : original.editorAvatarImageData,
       canManage = original.canManage,
       authorRefreshRequired = original.authorRefreshRequired,
       identityScope = original.identityScope,
       authorIdentity = original.authorIdentity,
       editorIdentity = original.editorIdentity,
       authorObservation = original.authorObservation,
       editorObservation = original.editorObservation;
}

/// Request-local original page proof plus the existing detail reader. No lease
/// or observation is renewed by a later detail block or cached Future.
final class CommunityAnnouncementDetailIdentity {
  const CommunityAnnouncementDetailIdentity({
    required this.scope,
    required this.author,
    required this.editor,
    required this.now,
    required this.authorCurrent,
    required this.editorCurrent,
    required this.narrow,
    required this.read,
  });
  final Object scope;
  final CommunityAuthorProjection author, editor;
  final DateTime Function() now;
  final bool Function() authorCurrent, editorCurrent;
  final void Function(CommunityAuthorProjection, CommunityAuthorProjection)
  narrow;
  final Future<Map<String, Object?>> Function(int, String?, String?, String?)
  read;
  bool get wantsAuthor =>
      author.hasAvatar && authorCurrent() && author.admit(now()).visible;
  bool get wantsEditor =>
      editor.hasAvatar && editorCurrent() && editor.admit(now()).visible;
}

Future<CommunityAnnouncementDetail> assembleCommunityAnnouncementDetail(
  CommunityAnnouncementsPort port,
  String targetRef,
  CommunityAnnouncement announcement, {
  required void Function() checkCurrent,
  CommunityAnnouncementDetailIdentity? identity,
}) async {
  final builder = BytesBuilder(copy: false);
  String? version;
  int? total;
  var offset = 0;
  var canManage = true, restarted = false, authorRefreshRequired = false;
  var authorObservation = const CommunityAuthorProjection.unavailable();
  var editorObservation = const CommunityAuthorProjection.unavailable();
  CommunityAnnouncementDetail result(String? author, String? editor) =>
      CommunityAnnouncementDetail(
        author,
        editor,
        canManage,
        identityScope: identity?.scope,
        authorIdentity: identity?.author,
        editorIdentity: identity?.editor,
        authorObservation: identity == null ? null : authorObservation,
        editorObservation: identity == null ? null : editorObservation,
        authorRefreshRequired: authorRefreshRequired,
      );
  while (true) {
    checkCurrent();
    final row = identity == null
        ? await port.readAnnouncementDetail(
            targetRef,
            announcement.announcementRef,
            offset,
            version,
          )
        : await identity.read(
            offset,
            version,
            identity.author.version,
            identity.editor.version,
          );
    checkCurrent();
    if (row['schemaVersion'] != 1 ||
        row['targetRef'] != targetRef ||
        row['announcementRef'] != announcement.announcementRef ||
        row['offset'] != offset) {
      throw const FormatException();
    }
    var refresh = false;
    if (identity != null) {
      final people = officialAnnouncementDetailPeople(row);
      Object? memberReference(Object? person) =>
          person is Map ? person['memberRef'] : null;
      CommunityAuthorProjection admitted(
        CommunityAuthorProjection observed,
        CommunityAuthorProjection expected,
        bool current,
        Object? memberRef,
        String? expectedRef,
      ) =>
          current &&
              memberRef == expectedRef &&
              observed.sameIdentityAs(expected)
          ? observed.admit(identity.now())
          : const CommunityAuthorProjection.unavailable();
      authorObservation = admitted(
        people.author,
        identity.author,
        identity.authorCurrent(),
        memberReference(row['author']),
        announcement.author.memberRef,
      );
      editorObservation = admitted(
        people.editor,
        identity.editor,
        identity.editorCurrent(),
        memberReference(row['editor']),
        announcement.editor.memberRef,
      );
      // Narrow before byte version/size checks: an obsolete partial assembly
      // cannot keep a revoked person's pixels while another remains valid.
      identity.narrow(authorObservation, editorObservation);
      refresh = people.refresh;
      authorRefreshRequired = authorRefreshRequired || refresh;
    }
    final hash = _text(row, 'version', 64), size = _number(row, 'totalBytes');
    final permission = _flag(row, 'canManage');
    canManage = canManage && permission;
    if (identity != null &&
        version != null &&
        (version != hash || total != size) &&
        refresh) {
      if (!restarted && (identity.wantsAuthor || identity.wantsEditor)) {
        restarted = true;
        builder.clear();
        offset = 0;
        version = null;
        total = null;
        continue;
      }
      return result(null, null);
    }
    if (identity != null && !identity.wantsAuthor && !identity.wantsEditor) {
      return result(null, null);
    }
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
  if (identity == null) {
    final author = _avatar(row['authorAvatarImageData']),
        editor = _avatar(row['editorAvatarImageData']);
    if ((author != null) != announcement.author.hasAvatar ||
        (editor != null) != announcement.editor.hasAvatar) {
      throw const FormatException();
    }
    checkCurrent();
    return result(author, editor);
  }
  String? image(
    Object? value,
    CommunityAuthorProjection observation,
    bool current,
  ) {
    if (!current || !observation.admit(identity.now()).hasAvatar) return null;
    try {
      final uri = _avatar(value);
      if (uri == null ||
          uri.length > 4096 ||
          base64Decode(uri.split(',').last).length > 3 * 1024 ||
          sha256.convert(utf8.encode(uri)).toString() !=
              observation.avatarVersion) {
        return null;
      }
      return uri;
    } on Object {
      return null;
    }
  }

  final author = image(
    row['authorAvatarImageData'],
    authorObservation,
    identity.wantsAuthor,
  );
  final editor = image(
    row['editorAvatarImageData'],
    editorObservation,
    identity.wantsEditor,
  );
  if (author == null && authorObservation.hasAvatar) {
    authorObservation = const CommunityAuthorProjection.unavailable();
  }
  if (editor == null && editorObservation.hasAvatar) {
    editorObservation = const CommunityAuthorProjection.unavailable();
  }
  identity.narrow(authorObservation, editorObservation);
  checkCurrent();
  return result(author, editor);
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
