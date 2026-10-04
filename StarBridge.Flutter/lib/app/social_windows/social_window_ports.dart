import 'dart:async';

import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import 'social_window_codec.dart';

typedef WindowRequest = Future<Object?> Function(String, Map<String, Object?>);

class WindowMessagesPort
    implements
        DirectMessagesPort,
        DirectMessageSender,
        DirectReadReceiptPort,
        DirectViewerAvatarPort,
        DirectMessageActivityPort {
  WindowMessagesPort(this.request, this.view);
  final WindowRequest request;
  final Map Function() view;
  final activity = StreamController<void>.broadcast();
  @override
  Stream<void> get changes => activity.stream;
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  bool get supportsSending => view()['supportsSending'] == true;
  @override
  bool get supportsReadReceipts => view()['supportsRead'] == true;
  @override
  String? get viewerAvatar => view()['viewerAvatar'] as String?;
  @override
  Future<List<Conversation>> directory() async =>
      ((await request('directory', {})) as List)
          .map((v) => decodeConversation(v as Map))
          .toList();
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    final p = await request('history', {
      'ref': ref,
      'before': before,
      'after': after,
    }) as Map;
    return DirectPage(
      p['ref'] as String,
      (p['messages'] as List).map((m) => decodeMessage(m as Map)).toList(),
      p['oldest'] as int,
      p['latest'] as int,
      p['hasOlder'] as bool,
      p['state'] as String,
      canSend: p['canSend'] == true,
      localHistoryUnavailable: p['localHistoryUnavailable'] == true,
    );
  }

  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) async {
    final s = await request('send', {
      'ref': ref,
      'text': text,
      'id': clientMessageId,
    }) as Map;
    return DirectSendResult(
      s['status'] as String,
      error: s['error'] as String?,
      message: s['message'] is Map ? decodeMessage(s['message'] as Map) : null,
    );
  }

  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    final r =
        await request('markRead', {'ref': ref, 'through': through}) as Map;
    return DirectReadReceipt(r['through'] as int, r['unread'] as int);
  }

  @override
  void cancel() {} // Module epoch rejects stale results; never cancel another reader.
  @override
  Future<void> close() async {
    await activity.close();
  }
}

class WindowInboxController extends NotificationInboxController {
  WindowInboxController(this.request) : super(null);
  final WindowRequest request;
  bool _closed = false;
  Future<bool> _call(String op, Map<String, Object?> args) async {
    if (busy || _closed) return false;
    busy = true;
    notifyListeners();
    try {
      final result = await request(op, args) as Map;
      if (_closed) return false;
      items = (result['items'] as List)
          .map((i) => InboxItem.parse(Map<String, Object?>.from(i as Map)))
          .toList();
      ready = result['ready'] == true;
      error = result['error'] as String?;
      unread.value = items.where((i) => !i.read).length;
      return error == null;
    } catch (_) {
      if (!_closed) error = op == 'markRead' ? 'write' : 'read';
      return false;
    } finally {
      if (!_closed) {
        busy = false;
        notifyListeners();
      }
    }
  }

  @override
  Future<bool> refresh({bool quiet = false, bool reuseFresh = false}) =>
      _call('refresh', {'reuseFresh': reuseFresh});
  @override
  Future<bool> markRead(List<InboxItem> selected) => _call('markRead', {
    'refs': selected
        .where((i) => items.contains(i) && !i.read)
        .map((i) => i.reference)
        .toList(),
  });
  @override
  void dispose() {
    _closed = true;
    super.dispose();
  }
}
