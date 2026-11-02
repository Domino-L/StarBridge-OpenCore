import 'direct_messages_contract.dart';

/// Refreshes the open conversation from a newly read directory. The selected
/// ref (capability) and history cursor stay; display fields follow the row.
/// Without a matching row the old live presence is dropped, not kept.
Conversation? refreshSelectedFromDirectory(
  Conversation? current,
  List<Conversation> rows,
) {
  if (current == null) return null;
  for (final row in rows) {
    if (row.ref == current.ref ||
        (current.conversationKey?.isNotEmpty == true &&
            row.conversationKey == current.conversationKey)) {
      return Conversation(
        current.ref,
        row.name,
        row.preview,
        row.time,
        row.unread,
        row.state,
        avatar: row.avatar,
        conversationKey: row.conversationKey,
        gameId: row.gameId,
        presence: row.presence,
      );
    }
  }
  return current.withoutPresence();
}
