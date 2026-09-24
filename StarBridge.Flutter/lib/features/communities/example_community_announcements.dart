import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'communities_module.dart';
import 'community_announcement_write_port.dart';
import 'community_announcements_port.dart';
import 'community_workspace_port.dart';

/// Session-only example state. Uses the same bounded projections as the Host;
/// it never connects to a host or supplies a fallback for an unavailable service.
final class ExampleCommunityAnnouncements {
  final _timelines = <String, _Timeline>{};
  final _receipts =
      <(String, String), (String, CommunityAnnouncementOutcome)>{};
  int _sequence = 1000;
  bool _closed = false;
  String _reference() => (++_sequence).toRadixString(16).padLeft(32, '0');

  Future<CommunityWorkspace> _access(
    String targetRef,
    Future<CommunityWorkspace> Function() workspace,
  ) async {
    if (_closed) throw const CommunityFailure('unavailable');
    final page = await workspace();
    if (_closed) throw const CommunityFailure('unavailable');
    if (page.targetRef != targetRef) {
      throw const CommunityFailure('notAllowed');
    }
    return page;
  }

  Map<String, Object?> _author(
    CommunityWorkspace page, {
    bool original = false,
  }) {
    final member = original
        ? page.members.where((m) => m.isOwner).firstOrNull
        : page.members.where((m) => m.isSelf).firstOrNull;
    return {
      'memberRef': member?.memberRef,
      'callsign': member?.callsign ?? '示例发布者',
      'gameId': member?.gameName ?? '',
      'roleTitle': member?.roleTitle ?? '成员',
      'roleColor': member?.roleColor ?? '#A0AEC0',
      'hasAvatar': false,
    };
  }

  _Timeline _timeline(CommunityWorkspace page, bool seed) =>
      _timelines.putIfAbsent(page.targetRef, () {
        final timeline = _Timeline();
        if (!seed) return timeline;
        final now = DateTime.now().toUtc();
        final author = _author(page, original: true);
        Map<String, Object?> record(String title, String state, int days) => {
          'announcementRef': _reference(),
          'title': title,
          'content': '示例公告：请在组织聊天中交流，并在出发前确认安排。',
          'state': state,
          'revision': 1,
          'publishedAt': now
              .subtract(Duration(days: days + 1))
              .toIso8601String(),
          'updatedAt': now.subtract(Duration(days: days)).toIso8601String(),
          'archivedAt': state == 'archived'
              ? now.subtract(Duration(days: days)).toIso8601String()
              : null,
          'withdrawnAt': state == 'withdrawn'
              ? now.subtract(Duration(days: days)).toIso8601String()
              : null,
          'author': author,
          'editor': author,
        };
        timeline.current = record('${page.name} · 本周安排', 'published', 0);
        timeline.history.addAll([
          record('上期安排', 'archived', 2),
          record('已取消的集合', 'withdrawn', 4),
        ]);
        timeline.revision = 3;
        return timeline;
      });

  Future<CommunityAnnouncementsPage> read(
    String targetRef, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
    int offset = 0,
    int? expectedRevision,
  }) async {
    final page = await _access(targetRef, workspace);
    final timeline = _timeline(page, seed);
    if (expectedRevision != null && expectedRevision != timeline.revision) {
      throw const CommunityFailure('announcementsChanged');
    }
    if (offset < 0 || offset > timeline.history.length) {
      throw const CommunityFailure('refreshRequired');
    }
    return CommunityAnnouncementsPage.parse({
      'schemaVersion': 1,
      'targetRef': targetRef,
      'revision': timeline.revision,
      'canManage': page.access['canManageAnnouncements'] == true,
      'current': timeline.current,
      'history': timeline.history.skip(offset).take(20).toList(),
      'offset': offset,
      'next': offset + 20 < timeline.history.length ? offset + 20 : null,
      'totalHistoryCount': timeline.history.length,
      'refreshedAt': DateTime.now().toUtc().toIso8601String(),
    });
  }

  Future<Map<String, Object?>> detail(
    String targetRef,
    String announcementRef,
    int offset,
    String? version, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
  }) async {
    final page = await _access(targetRef, workspace);
    final timeline = _timeline(page, seed);
    if (![
      ?timeline.current,
      ...timeline.history,
    ].any((row) => row['announcementRef'] == announcementRef)) {
      throw const CommunityFailure('announcementsChanged');
    }
    final bytes = utf8.encode(
      jsonEncode({
        'authorAvatarImageData': null,
        'editorAvatarImageData': null,
      }),
    );
    final hash = sha256.convert(bytes).toString();
    if (offset != 0 || version != null && version != hash) {
      throw const CommunityFailure('announcementsChanged');
    }
    return {
      'schemaVersion': 1,
      'targetRef': targetRef,
      'announcementRef': announcementRef,
      'offset': 0,
      'next': null,
      'totalBytes': bytes.length,
      'data': base64Encode(bytes),
      'version': hash,
      'canManage': page.access['canManageAnnouncements'] == true,
    };
  }

  Future<CommunityAnnouncementOutcome> manage(
    CommunityAnnouncementIntent intent, {
    required Future<CommunityWorkspace> Function() workspace,
    required bool seed,
  }) async {
    CommunityWorkspace page;
    try {
      page = await _access(intent.targetRef, workspace);
    } on CommunityFailure catch (error) {
      return CommunityAnnouncementOutcome('rejected', error: error.code);
    }
    if (page.access['canManageAnnouncements'] != true) {
      return const CommunityAnnouncementOutcome(
        'rejected',
        error: 'notAllowed',
      );
    }
    final key = (intent.targetRef, intent.requestId);
    final fingerprint = jsonEncode(intent.toPayload());
    final receipt = _receipts[key];
    if (receipt != null) {
      return receipt.$1 == fingerprint
          ? receipt.$2
          : const CommunityAnnouncementOutcome(
              'rejected',
              error: 'intentConflict',
            );
    }
    final timeline = _timeline(page, seed);
    final old = timeline.current;
    if (intent.action != 'publish' &&
        (old == null || old['announcementRef'] != intent.announcementRef)) {
      return const CommunityAnnouncementOutcome(
        'rejected',
        error: 'announcementsChanged',
      );
    }
    final now = DateTime.now().toUtc().toIso8601String();
    final editor = _author(page);
    timeline.revision++;
    if (intent.action == 'withdraw' ||
        intent.action == 'publish' && old != null) {
      timeline.history.insert(0, {
        ...old!,
        'state': intent.action == 'withdraw' ? 'withdrawn' : 'archived',
        'revision': (old['revision'] as int) + 1,
        'updatedAt': now,
        if (intent.action == 'withdraw')
          'withdrawnAt': now
        else
          'archivedAt': now,
        'editor': editor,
      });
    }
    timeline.current = intent.action == 'withdraw'
        ? null
        : {
            'announcementRef': _reference(),
            'title': intent.title,
            'content': intent.content,
            'state': 'published',
            'revision': intent.action == 'edit'
                ? (old!['revision'] as int) + 1
                : 1,
            'publishedAt': intent.action == 'edit' ? old!['publishedAt'] : now,
            'updatedAt': now,
            'archivedAt': null,
            'withdrawnAt': null,
            'author': intent.action == 'edit' ? old!['author'] : editor,
            'editor': editor,
          };
    final maximum = timeline.current == null ? 100 : 99;
    if (timeline.history.length > maximum) {
      timeline.history.removeRange(maximum, timeline.history.length);
    }
    final result = CommunityAnnouncementOutcome(
      'accepted',
      revision: timeline.revision,
    );
    _receipts[key] = (fingerprint, result);
    return result;
  }

  void close() {
    _closed = true;
    _timelines.clear();
    _receipts.clear();
  }
}

final class _Timeline {
  int revision = 0;
  Map<String, Object?>? current;
  final history = <Map<String, Object?>>[];
}
