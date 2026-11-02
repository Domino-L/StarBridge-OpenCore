import 'direct_messages_contract.dart';

// Cadence comparison only. Capability validation and cursor ownership remain
// in the original receive/read path. Host-issued references may rotate.
bool sameDirectMessageDirectory(List<Conversation> a, List<Conversation> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    final x = a[i], y = b[i];
    if ((
          x.conversationKey?.isNotEmpty == true ? x.conversationKey : x.ref,
          x.name,
          x.preview,
          x.time,
          x.unread,
          x.state,
          x.avatar,
          x.conversationKey,
          x.gameId,
          x.presence,
        ) !=
        (
          y.conversationKey?.isNotEmpty == true ? y.conversationKey : y.ref,
          y.name,
          y.preview,
          y.time,
          y.unread,
          y.state,
          y.avatar,
          y.conversationKey,
          y.gameId,
          y.presence,
        )) {
      return false;
    }
  }
  return true;
}
