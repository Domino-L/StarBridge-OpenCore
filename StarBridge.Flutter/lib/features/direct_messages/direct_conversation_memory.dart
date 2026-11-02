import 'direct_messages_contract.dart';

/// Per-conversation display memory inside one account context (DL-06): the
/// last history and the unsent draft of recently opened conversations, keyed
/// by the stable conversation key (Host references change per directory read).
///
/// Display only. It never grants send permission, a cursor, a read receipt or
/// a Host target: reopening still reads the latest page, which replaces it.
/// The owner clears it at every account or session boundary.
final class DirectConversationMemory {
  static const conversations = 8;
  static const messagesPerConversation = 200;

  // Insertion order is recency: a kept conversation moves to the end.
  final _history = <String, List<DirectMessage>>{};
  final _drafts = <String, String>{};

  List<DirectMessage> history(String? key) =>
      key == null || key.isEmpty ? const [] : _history[key] ?? const [];

  String draft(String? key) =>
      key == null || key.isEmpty ? '' : _drafts[key] ?? '';

  void keep(
    String? key, {
    required String draft,
    required List<DirectMessage> messages,
  }) {
    if (key == null || key.isEmpty) return;
    _history.remove(key);
    if (messages.isNotEmpty) {
      _history[key] = List.unmodifiable(
        messages.length > messagesPerConversation
            ? messages.sublist(messages.length - messagesPerConversation)
            : messages,
      );
      while (_history.length > conversations) {
        _history.remove(_history.keys.first);
      }
    }
    if (draft.isEmpty) {
      _drafts.remove(key);
    } else {
      _drafts[key] = draft;
    }
  }

  void clear() {
    _history.clear();
    _drafts.clear();
  }
}
