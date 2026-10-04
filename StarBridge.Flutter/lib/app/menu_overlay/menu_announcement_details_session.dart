import 'dart:async';
import 'dart:convert';

import '../../features/communities/community_announcements_port.dart';
import '../../features/communities/communities_module.dart';
import 'menu_organization_avatars.dart';

typedef AnnouncementGrant = Map<String, Object?> Function(
  Future<void> Function(),
);

/// Main-engine-only bindings. Ordinary polls retain the same display identity;
/// scope retirement and changed announcement metadata retire every old closure.
final class MenuAnnouncementDetailsSession {
  MenuAnnouncementDetailsSession({
    required this.grant,
    required this.changed,
    required this.denied,
    required this.isCurrent,
  });
  final AnnouncementGrant grant;
  final void Function() changed, denied;
  final bool Function(String target) isCurrent;
  final _images = MenuOrganizationAvatars();
  final _entries = <String, _Entry>{};
  final _recentMedia = <_Entry>[];
  int _epoch = 0, _serial = 0;
  String? _target;

  void clear() {
    _epoch++;
    _target = null;
    _entries.clear();
    _recentMedia.clear();
    _images.clear();
  }

  void sync(
    CommunityAnnouncementsPort port,
    String target,
    List<CommunityAnnouncement> items,
  ) {
    if (_target != target) clear();
    _target = target;
    final refs = items.map((e) => e.announcementRef).toSet();
    _entries.removeWhere((ref, _) => !refs.contains(ref));
    for (final item in items) {
      final display = _display(item);
      final signature = jsonEncode(display);
      var entry = _entries[item.announcementRef];
      if (entry == null || entry.signature != signature) {
        entry = _Entry('d${++_serial}', signature, display);
        _entries[item.announcementRef] = entry;
      }
      entry.port = port;
      entry.item = item;
      _grant(target, entry);
    }
  }

  Map<String, Object?> binding(CommunityAnnouncement item) => {
    'key': _entries[item.announcementRef]!.key,
  };

  void _grant(String target, _Entry entry) {
    final epoch = _epoch;
    late final Map<String, Object?> action;
    action = grant(() async {
      final port = entry.port, item = entry.item;
      bool valid() =>
          epoch == _epoch &&
          _target == target &&
          isCurrent(target) &&
          identical(_entries[item.announcementRef], entry);
      if (!valid() || entry.action?['key'] != action['key'] || entry.loading) {
        return;
      }
      if (entry.loaded) return;
      entry.loading = true;
      entry.failed = false;
      final request = ++entry.request;
      changed();
      try {
        void check() {
          if (!valid() || request != entry.request) throw StateError('retired');
        }

        final detail = await assembleCommunityAnnouncementDetail(
          port,
          target,
          item,
          checkCurrent: check,
        ).timeout(const Duration(seconds: 6));
        check();
        final photos = await Future.wait([
          _images.logo(detail.authorAvatarImageData),
          _images.logo(detail.editorAvatarImageData),
        ]).timeout(const Duration(seconds: 2));
        check();
        entry.author = photos[0];
        entry.editor = photos[1];
        entry.loaded = true;
        // The complete menu frame is limited to 1 MiB. Keep only a small
        // recent media working set; all announcement text remains available.
        _recentMedia.remove(entry);
        _recentMedia.add(entry);
        while (_recentMedia.length > 6) {
          final retired = _recentMedia.removeAt(0);
          retired.author = retired.editor = null;
          retired.loaded = false;
          if (identical(_entries[retired.item.announcementRef], retired)) {
            _grant(target, retired);
          }
        }
      } catch (error) {
        if (!valid()) return;
        if (error is CommunityFailure &&
            const {
              'notAllowed',
              'identityUnavailable',
              'notFound',
              'refreshRequired',
            }.contains(error.code)) {
          clear();
          denied();
          return;
        }
        entry.failed = true;
      } finally {
        // Future.timeout does not cancel the underlying assembler. Retiring
        // this request prevents late chunks from scheduling further reads.
        if (entry.request == request) entry.request++;
        if (valid()) {
          entry.loading = false;
          // A successful list refresh may have replaced the binding meanwhile.
          // Always regrant from the latest authorized item/port, never a stale
          // closure captured before that refresh.
          _grant(target, entry);
          changed();
        }
      }
    });
    entry.action = action;
  }

  Map<String, Object?> project(Map<String, Object?> view) {
    final org = view['organization'], rows = view['rows'];
    if (org is! Map ||
        org['tab'] != 'announcements' ||
        org['rows'] is! List ||
        rows is! List) {
      return view;
    }
    final presentation = org['rows'] as List;
    if (presentation.length != rows.length) return view;
    final nextRows = <Object?>[], nextPresentation = <Object?>[];
    for (var i = 0; i < rows.length; i++) {
      final row = rows[i], data = presentation[i];
      final binding = data is Map ? data['announcement'] : null;
      final entry = binding is Map
          ? _entries.values.where((e) => e.key == binding['key']).firstOrNull
          : null;
      if (entry == null || row is! Map || data is! Map) {
        if (binding is Map && row is Map && data is Map) {
          final stripped = <String, Object?>{...data}..remove('announcement');
          final buttons = row['buttons'];
          nextRows.add({
            ...row,
            if (buttons is List)
              'buttons': buttons
                  .where((button) => button is! Map || button['label'] != '详情')
                  .toList(),
          });
          nextPresentation.add(stripped);
          continue;
        }
        nextRows.add(row);
        nextPresentation.add(data);
        continue;
      }
      nextRows.add({
        ...row,
        'buttons': [entry.action],
      });
      nextPresentation.add({
        ...data,
        'announcement': {
          'key': entry.key,
          'entry': entry.display,
          'loading': entry.loading,
          'failed': entry.failed,
          'authorAvatar': entry.author,
          'editorAvatar': entry.editor,
        },
      });
    }
    return {
      ...view,
      'rows': nextRows,
      'organization': {...org, 'rows': nextPresentation},
    };
  }

  Map<String, Object?> _display(CommunityAnnouncement item) {
    Map<String, Object?> person(CommunityAnnouncementAuthor value) => {
      'callsign': value.callsign,
      'gameId': value.gameId,
      'roleTitle': value.roleTitle,
      'roleColor': value.roleColor,
      'hasAvatar': value.hasAvatar,
    };
    return {
      'title': item.title,
      'content': item.content,
      'state': item.state,
      'revision': item.revision,
      'publishedAt': item.publishedAt.toUtc().toIso8601String(),
      'updatedAt': item.updatedAt.toUtc().toIso8601String(),
      'archivedAt': item.archivedAt?.toUtc().toIso8601String(),
      'withdrawnAt': item.withdrawnAt?.toUtc().toIso8601String(),
      'author': person(item.author),
      'editor': person(item.editor),
    };
  }
}

final class _Entry {
  _Entry(this.key, this.signature, this.display);
  final String key, signature;
  final Map<String, Object?> display;
  Map<String, Object?>? action;
  late CommunityAnnouncementsPort port;
  late CommunityAnnouncement item;
  int request = 0;
  bool loading = false, loaded = false, failed = false;
  String? author, editor;
}
