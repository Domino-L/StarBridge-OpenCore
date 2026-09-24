import 'dart:math';

import '../../features/direct_messages/direct_messages_module.dart';

/// Primary-engine, account-session-only outbox. No automatic retry or disk copy.
/// Pending IDs never reach the renderer; a matching server message settles them.
final class MenuMessageDrafts {
  final _entries = <String, MenuMessageDraft>{};
  MenuMessageDraft? forTarget(String ref) {
    final existing = _entries[ref];
    if (existing != null) return existing;
    _entries.removeWhere((_, draft) => draft.text.isEmpty && !draft.locked);
    if (_entries.length >= 32) return null;
    return _entries[ref] = MenuMessageDraft();
  }

  void clear() => _entries.clear();
}

final class MenuMessageDraft {
  String text = '', status = 'idle';
  String? _id, _submitted;
  int revision = 0;
  bool get locked => _id != null;
  bool edit(String value, int version) {
    if (locked ||
        value.length > 1000 ||
        version <= revision ||
        version > 1000000000) {
      return false;
    }
    text = value;
    revision = version;
    status = 'idle';
    return true;
  }

  Future<void> send(DirectMessageSender sender, String ref) async {
    if (locked || !sender.supportsSending || text.trim().isEmpty) return;
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _id = id;
    _submitted = text.trim();
    status = 'sending';
    DirectSendResult result;
    try {
      result = await sender
          .send(ref, _submitted!, id)
          .timeout(const Duration(seconds: 15));
    } on Object {
      result = const DirectSendResult('unknown');
    }
    if (confirmedDirectSend(result, id, _submitted!)) {
      _confirm(result.status == 'request_sent' ? 'request_sent' : 'sent');
    } else if (result.status == 'rejected') {
      _id = _submitted = null;
      status = 'rejected';
      revision++;
    } else {
      status = 'unknown';
      revision++;
    }
  }

  void observe(List<DirectMessage> messages) {
    if (!locked || status == 'sending') return;
    if (messages.any(
      (m) =>
          m.id == _id &&
          !m.incoming &&
          m.text == _submitted &&
          m.attachment == null &&
          m.sequence > 0,
    )) {
      _confirm('sent');
    }
  }

  void _confirm(String state) {
    _id = _submitted = null;
    text = '';
    status = state;
    revision++;
  }
}
