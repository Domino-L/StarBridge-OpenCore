import 'dart:convert';
import 'dart:typed_data';

import '../../features/communities/community_announcements_port.dart';

/// No service identifiers or authority are accepted by the renderer.
final class MenuAnnouncementDetailsView {
  MenuAnnouncementDetailsView._(
    this.key,
    this.entry,
    this.loading,
    this.failed,
    this.author,
    this.editor,
  );
  final String key;
  final CommunityAnnouncement entry;
  final bool loading, failed;
  final Uint8List? author, editor;
  static MenuAnnouncementDetailsView? parse(Object? value) {
    if (value == null) return null;
    if (value is! Map ||
        value.keys.any(
          (k) => !const {
            'key',
            'entry',
            'loading',
            'failed',
            'authorAvatar',
            'editorAvatar',
          }.contains(k),
        ) ||
        value['key'] is! String ||
        !RegExp(r'^d[1-9][0-9]{0,13}$').hasMatch(value['key'] as String) ||
        value['loading'] is! bool ||
        value['failed'] is! bool) {
      throw const FormatException();
    }
    final raw = value['entry'];
    if (raw is! Map ||
        raw.keys.any(
          (k) => !const {
            'title',
            'content',
            'state',
            'revision',
            'publishedAt',
            'updatedAt',
            'archivedAt',
            'withdrawnAt',
            'author',
            'editor',
          }.contains(k),
        )) {
      throw const FormatException();
    }
    for (final key in ['author', 'editor']) {
      final person = raw[key];
      if (person is! Map ||
          person.keys.any(
            (k) => !const {
              'callsign',
              'gameId',
              'roleTitle',
              'roleColor',
              'hasAvatar',
            }.contains(k),
          )) {
        throw const FormatException();
      }
    }
    Uint8List? image(String key) {
      final raw = value[key];
      if (raw == null) return null;
      if (raw is! String ||
          raw.length > 28000 ||
          !raw.startsWith('data:image/png;base64,')) {
        throw const FormatException();
      }
      return base64Decode(raw.substring(22));
    }

    return MenuAnnouncementDetailsView._(
      value['key'] as String,
      CommunityAnnouncement.parse({
        ...Map<String, Object?>.from(raw),
        // Model validation requires an identifier. This constant is never a
        // service reference and is not used for navigation or commands.
        'announcementRef': '00000000000000000000000000000000',
      }),
      value['loading'] as bool,
      value['failed'] as bool,
      image('authorAvatar'),
      image('editorAvatar'),
    );
  }
}
