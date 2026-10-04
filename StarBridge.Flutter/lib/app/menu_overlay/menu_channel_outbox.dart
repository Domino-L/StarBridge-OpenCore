/// Menu-only display contract. It grants neither read nor send authority.
final class MenuChannelOutbox {
  const MenuChannelOutbox(this.acceptedAction, this.messages);
  final String? acceptedAction;
  final List<MenuLocalChatMessage> messages;

  static MenuChannelOutbox? parse(Map raw) {
    if (raw['outboxVersion'] == null) return null;
    if (raw['outboxVersion'] != 1) throw const FormatException();
    final accepted = action(raw['acceptedAction']);
    final rows = raw['localMessages'];
    if (rows is! List || rows.length > 20) throw const FormatException();
    final ids = <String>{};
    final messages = <MenuLocalChatMessage>[];
    for (final row in rows) {
      if (row is! Map ||
          row['id'] is! String ||
          !RegExp(r'^l[1-9][0-9]{0,13}$').hasMatch(row['id']) ||
          !ids.add(row['id']) ||
          row['text'] is! String ||
          (row['text'] as String).length > 1000 ||
          !const {
            'sending',
            'sent',
            'failed',
            'unknown',
          }.contains(row['state']) ||
          row['time'] is! String ||
          (row['error'] != null &&
              (row['error'] is! String ||
                  (row['error'] as String).length > 64))) {
        throw const FormatException();
      }
      final retry = action(row['retry']), restore = action(row['restore']);
      if (row['state'] != 'failed' && (retry != null || restore != null)) {
        throw const FormatException();
      }
      messages.add(
        MenuLocalChatMessage(
          id: row['id'],
          text: row['text'],
          state: row['state'],
          time: DateTime.parse(row['time']),
          error: row['error'],
          retry: retry,
          restore: restore,
        ),
      );
    }
    return MenuChannelOutbox(accepted, List.unmodifiable(messages));
  }

  static String? action(Object? value) {
    if (value == null) return null;
    if (value is! String || !RegExp(r'^a[1-9][0-9]{0,13}$').hasMatch(value)) {
      throw const FormatException();
    }
    return value;
  }
}

final class MenuLocalChatMessage {
  const MenuLocalChatMessage({
    required this.id,
    required this.text,
    required this.state,
    required this.time,
    this.error,
    this.retry,
    this.restore,
  });
  final String id, text, state;
  final DateTime time;
  final String? error, retry, restore;
}
