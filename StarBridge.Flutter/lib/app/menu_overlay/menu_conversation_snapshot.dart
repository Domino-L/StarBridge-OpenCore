import '../../features/direct_messages/direct_messages_module.dart';
import 'menu_organization_avatars.dart';

String menuChatText(String value, int limit) {
  final text = value.replaceAll(
    RegExp(r'[\x00-\x08\x0b\x0c\x0e-\x1f\x7f]'),
    '',
  );
  return text.length <= limit ? text : text.substring(0, limit);
}

bool sameMenuConversation(Conversation a, Conversation b) =>
    a.ref == b.ref ||
    (a.conversationKey != null && a.conversationKey == b.conversationKey);

/// Retained display history never keeps receipt/attachment command grants or
/// a previous read's transient provenance. The session still owns the cache.
Map<String, Object?> menuCachedHistory(Map<String, Object?> view) => {
  ...view,
  'receipts': <String, String>{},
  'readFeedback': null,
  'messages': [
    for (final raw in view['messages'] as List)
      {...raw as Map<String, Object?>, 'attachmentKey': null},
  ],
};

List<Map<String, Object?>> menuConversationRows(
  Map<String, Conversation> targets,
  Map<String, String?> portraits,
) => [
  for (final row in targets.entries)
    {
      'key': row.key,
      'name': menuChatText(row.value.name, 128),
      'preview': menuChatText(row.value.preview, 256),
      'avatar': portraits[row.key],
      'time': row.value.time.toUtc().toIso8601String(),
      'unread': row.value.unread,
      'request': row.value.request,
    },
];

/// Directory presentation only; selected-history grants remain in the session.
Future<({Map<String, Conversation> targets, Map<String, String?> portraits})>
readMenuConversationSnapshot(
  List<Conversation> rows,
  Map<String, Conversation> previous,
  MenuOrganizationAvatars avatars,
  String Function() nextKey, {
  Conversation? selected,
  String? selectedKey,
}) async {
  final seen = <String>{}, identities = <String>{};
  if (rows.length > 5000 ||
      rows.any(
        (row) =>
            row.ref.isEmpty ||
            !seen.add(row.ref) ||
            (row.conversationKey != null &&
                !identities.add(row.conversationKey!)),
      )) {
    throw const DirectReadFailure('data_invalid');
  }
  final targets = <String, Conversation>{};
  for (final row in rows) {
    if (selected != null && sameMenuConversation(row, selected)) continue;
    final old = previous.entries
        .where((e) => sameMenuConversation(e.value, row))
        .firstOrNull;
    targets[old?.key ?? nextKey()] = row;
  }
  // A new friend conversation need not exist in the server directory yet.
  if (selected != null && selectedKey != null) targets[selectedKey] = selected;
  final portraitRows = targets.entries.take(16).toList();
  final decoded = await Future.wait(
    portraitRows.map((e) => avatars.logo(e.value.avatar)),
  );
  final portraits = <String, String?>{};
  var bytes = 0;
  for (final (i, row) in portraitRows.indexed) {
    final portrait = decoded[i];
    if (portrait == null || bytes + portrait.length > 180000) continue;
    bytes += portrait.length;
    portraits[row.key] = portrait;
  }
  return (targets: targets, portraits: portraits);
}
