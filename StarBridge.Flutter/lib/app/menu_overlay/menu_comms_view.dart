import 'dart:convert';

import 'menu_feature_view.dart';

typedef MenuConversation = ({
  String key,
  String name,
  DateTime time,
  int unread,
  bool request,
});
typedef MenuMessage = ({
  bool incoming,
  String text,
  DateTime time,
  bool attachment,
});

/// Validated display projection, not a domain snapshot or command authority.
final class MenuCommsView {
  const MenuCommsView(
    this.state, {
    this.rows = const [],
    this.name,
    this.avatar,
    this.ownAvatar,
    this.refreshing = false,
    this.profileKey,
    this.request = false,
    this.hasOlder = false,
    this.olderPage = false,
    this.messages = const [],
    this.compose = false,
    this.canSend = false,
    this.locked = false,
    this.draft = '',
    this.draftRevision = 0,
    this.delivery = 'idle',
    this.receipts = const {},
    this.readStatus = '',
    this.previews = const {},
    this.avatars = const {},
    this.notice = '',
    this.busy = false,
    this.conversationState = '',
    this.pageKey = '',
    this.attachments = const {},
    this.attachmentKeys = const {},
    this.invitation,
    this.inviteAvailable = false,
    this.archiveAvailable = false,
  });
  final String state;
  final List<MenuConversation> rows;
  final String? name, avatar, profileKey;
  final String? ownAvatar;
  final bool refreshing;
  final bool request, hasOlder, olderPage;
  final List<MenuMessage> messages;
  final bool compose, canSend, locked;
  final String draft, delivery;
  final int draftRevision;
  final Map<int, String> receipts;
  final String readStatus;
  final Map<String, String> previews, avatars;
  final Map<int, String> attachments;
  final Map<int, String> attachmentKeys;
  final MenuFeatureView? invitation;
  final bool inviteAvailable;
  final bool archiveAvailable;
  final String notice, conversationState, pageKey;
  final bool busy;

  static MenuCommsView parse(Object? wire) {
    try {
      if (wire is! String || wire.length > 1048576) {
        throw const FormatException();
      }
      final data = jsonDecode(wire);
      if (data is! Map ||
          !const [
            'idle',
            'loading',
            'ready',
            'restricted',
            'unavailable',
          ].contains(data['state'])) {
        throw const FormatException();
      }
      if (data['state'] != 'ready') {
        return MenuCommsView(data['state'] as String);
      }
      final rows = data['rows'] ?? const [];
      if (rows is! List || rows.length > 5000) throw const FormatException();
      final keys = <String>{};
      final previews = <String, String>{}, avatars = <String, String>{};
      final directory = List<MenuConversation>.unmodifiable(
        rows.map((row) {
          if (row is! Map ||
              row['unread'] is! int ||
              (row['unread'] as int) < 0) {
            throw const FormatException();
          }
          final key = _text(row, 'key', 64);
          if (key.isEmpty || !keys.add(key)) throw const FormatException();
          previews[key] = _text(
            {'preview': row['preview'] ?? ''},
            'preview',
            256,
          );
          final portrait = row['avatar'];
          if (portrait != null) {
            if (portrait is! String ||
                portrait.length > 28000 ||
                !portrait.startsWith('data:image/png;base64,')) {
              throw const FormatException();
            }
            avatars[key] = portrait;
          }
          return (
            key: key,
            name: _text(row, 'name', 128),
            time: DateTime.parse(_text(row, 'time', 64)),
            unread: row['unread'] as int,
            request: _bool(row, 'request'),
          );
        }),
      );
      final notice = _text({'notice': data['notice'] ?? ''}, 'notice', 512);
      final ownAvatar = data['ownAvatar'];
      if (ownAvatar != null &&
          (ownAvatar is! String ||
              ownAvatar.length > 28000 ||
              !ownAvatar.startsWith('data:image/png;base64,'))) {
        throw const FormatException();
      }
      if (data['name'] == null) {
        return MenuCommsView(
          'ready',
          rows: directory,
          previews: previews,
          avatars: avatars,
          notice: notice,
          refreshing: data['refreshing'] == true,
          ownAvatar: ownAvatar as String?,
          busy: data['busy'] == true,
          invitation: data['invitation'] == null
              ? null
              : MenuFeatureView.parse(data['invitation']),
          inviteAvailable: data['inviteAvailable'] == true,
          archiveAvailable: data['archiveAvailable'] == true,
        );
      }
      final messages = data['messages'], avatar = data['avatar'];
      final profileKey = data['profileKey'];
      if (profileKey != null &&
          (profileKey is! String ||
              profileKey.isEmpty ||
              profileKey.length > 64)) {
        throw const FormatException();
      }
      if (messages is! List ||
          messages.length > 50 ||
          (avatar != null &&
              (avatar is! String ||
                  avatar.length > 128 * 1024 ||
                  !(avatar.startsWith('data:image/png;base64,') ||
                      avatar.startsWith('data:image/jpeg;base64,'))))) {
        throw const FormatException();
      }
      final receipts = <int, String>{};
      final attachments = <int, String>{};
      final attachmentKeys = <int, String>{};
      for (var i = 0; i < messages.length; i++) {
        if (messages[i] is! Map) throw const FormatException();
        final key = messages[i]['attachmentKey'];
        if (key != null) {
          if (key is! String || !RegExp(r'^i[1-9][0-9]{0,13}$').hasMatch(key)) {
            throw const FormatException();
          }
          attachmentKeys[i] = key;
        }
        attachments[i] = _text(
          {'detail': messages[i]['attachmentDetail'] ?? ''},
          'detail',
          512,
        );
      }
      final rawReceipts = data['receipts'] ?? const {};
      if (rawReceipts is! Map ||
          rawReceipts.length > 50 ||
          !const ['', 'failed'].contains(data['readStatus'] ?? '')) {
        throw const FormatException();
      }
      for (final entry in rawReceipts.entries) {
        final index = int.tryParse('${entry.key}');
        if (index == null ||
            index < 0 ||
            index >= messages.length ||
            messages[index]['incoming'] != true ||
            entry.value is! String ||
            !RegExp(r'^r[1-9][0-9]{0,13}$').hasMatch(entry.value as String)) {
          throw const FormatException();
        }
        receipts[index] = entry.value as String;
      }
      return MenuCommsView(
        'ready',
        name: _text(data, 'name', 128),
        rows: directory,
        previews: previews,
        avatars: avatars,
        notice: notice,
        refreshing: data['refreshing'] == true,
        ownAvatar: ownAvatar as String?,
        busy: data['busy'] == true,
        attachments: attachments,
        attachmentKeys: attachmentKeys,
        invitation: data['invitation'] == null
            ? null
            : MenuFeatureView.parse(data['invitation']),
        inviteAvailable: data['inviteAvailable'] == true,
        archiveAvailable: data['archiveAvailable'] == true,
        conversationState: _text(
          {'value': data['conversationState'] ?? ''},
          'value',
          64,
        ),
        pageKey: _text({'value': data['pageKey'] ?? ''}, 'value', 64),
        receipts: Map.unmodifiable(receipts),
        readStatus: data['readStatus'] as String? ?? '',
        compose: data['compose'] == true,
        canSend: data['compose'] == true && _bool(data, 'canSend'),
        locked: data['compose'] == true && _bool(data, 'locked'),
        draft: data['compose'] == true ? _text(data, 'draft', 1000) : '',
        draftRevision: data['compose'] == true
            ? _revision(data['draftRevision'])
            : 0,
        delivery: data['compose'] == true
            ? _delivery(data['delivery'])
            : 'idle',
        avatar: avatar as String?,
        profileKey: profileKey as String?,
        request: _bool(data, 'request'),
        hasOlder: _bool(data, 'hasOlder'),
        olderPage: _bool(data, 'olderPage'),
        messages: List.unmodifiable(
          messages.map((row) {
            if (row is! Map) throw const FormatException();
            return (
              incoming: _bool(row, 'incoming'),
              text: _text(row, 'text', 4096),
              time: DateTime.parse(_text(row, 'time', 64)),
              attachment: _bool(row, 'attachment'),
            );
          }),
        ),
      );
    } on Object {
      return const MenuCommsView('unavailable');
    }
  }

  static String _text(Map data, String key, int max) {
    final value = data[key];
    if (value is! String || value.length > max) throw const FormatException();
    return value;
  }

  static bool _bool(Map data, String key) {
    final value = data[key];
    if (value is! bool) throw const FormatException();
    return value;
  }

  static int _revision(Object? v) =>
      v is int && v >= 0 && v <= 1000000000 ? v : throw const FormatException();
  static String _delivery(Object? v) =>
      const {
        'idle',
        'sending',
        'unknown',
        'sent',
        'request_sent',
        'rejected',
        'limit',
      }.contains(v)
      ? v as String
      : throw const FormatException();
}
