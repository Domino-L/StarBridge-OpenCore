import 'dart:async';

import 'package:flutter/services.dart';

import '../../features/direct_messages/direct_messages_module.dart';
import '../../features/marketplace/marketplace_port.dart';
import '../../features/notifications/notification_inbox_controller.dart';
import 'social_window_codec.dart';
import 'window_message_health.dart';

typedef WindowRequest = Future<Object?> Function(String, Map<String, Object?>);

class WindowMessagesPort
    implements
        DirectMessagesPort,
        DirectMessageDirectoryUpdatesPort,
        DirectMessageSender,
        DirectReadReceiptPort,
        DirectViewerAvatarPort,
        DirectMessageActivityPort,
        DirectMessageActivityHealthPort {
  WindowMessagesPort(this.request, this.view);
  final WindowRequest request;
  Future<Object?> _read(String op, Map<String, Object?> args) async {
    try {
      return await request(op, args);
    } on PlatformException catch (failure) {
      const codes = {
        'forbidden',
        'identity_unavailable',
        'target_changed',
        'data_invalid',
        'unavailable',
        'limit',
      };
      const prefix = 'messages.read.';
      if (failure.code.startsWith(prefix)) {
        final code = failure.code.substring(prefix.length);
        if (codes.contains(code)) throw DirectReadFailure(code);
      }
      rethrow;
    }
  }

  final Map Function() view;
  final _health = WindowMessageHealth();
  void bindActivityWindow(int opening, String scope) =>
      _health.bind(opening, scope);
  bool acceptActivityHealth(Object? packet) => _health.accept(packet);
  @override
  bool get activityHealthy => _health.healthy;
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
      ((await _read('directory', {})) as List)
          .map((v) => decodeConversation(v as Map))
          .toList();
  @override
  Future<List<Conversation>> receiveDirectory() async =>
      ((await _read('directory', {'published': true})) as List)
          .map((v) => decodeConversation(v as Map))
          .toList();
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async {
    final p = await _read('history', {
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
    _health.dispose();
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

/// 交易消息 in the detached messages window (0.7.2 G9): every read and send
/// goes to the primary engine's trade chat through the window rpc; live
/// pushes arrive inside snapshots and are replayed here once each.
class WindowTradeChatPort
    implements MarketplaceChatPort, MarketplaceRecordsPort {
  WindowTradeChatPort(this.request);
  final WindowRequest request;
  final _pushes = StreamController<MarketRow>.broadcast();
  int _seen = 0;
  bool _baseline = false;

  @override
  bool get chatSupported => true;
  @override
  Stream<MarketRow> get chatPushes => _pushes.stream;
  @override
  bool get recordsSupported => true;

  @override
  Future<MarketRow> chat(String operation, [MarketRow input = const {}]) =>
      _relay({'operation': operation, 'input': input});

  /// Only 解除拉黑 from a conversation; the primary refuses anything else.
  @override
  Future<MarketRow> records(String operation, [MarketRow input = const {}]) =>
      _relay({'records': true, 'operation': operation, 'input': input});

  Future<MarketRow> _relay(Map<String, Object?> args) async {
    try {
      final result = await request('trade', args);
      return result is Map ? _row(result) : const {};
    } on PlatformException catch (failure) {
      // The primary's MarketplaceTradeError codes travel as the error code.
      throw MarketplaceTradeError(failure.code);
    }
  }

  /// Replays the pushes this window has not seen yet (each has a serial).
  /// The first snapshot only sets the baseline: the window reads the current
  /// state through rpc anyway, and replaying old pushes would recount unread.
  /// A gap (more than the snapshot keeps) asks the chat to read again.
  void accept(Object? pushes) {
    if (pushes is! List) return;
    final entries = [
      for (final entry in pushes)
        if (entry is Map && entry['serial'] is int && entry['push'] is Map)
          entry,
    ];
    if (!_baseline) {
      _baseline = true;
      _seen = entries.isEmpty ? 0 : entries.last['serial'] as int;
      return;
    }
    if (entries.isEmpty) return;
    final first = entries.first['serial'] as int;
    if (first > _seen + 1 && !_pushes.isClosed) {
      _pushes.add(const {'kind': 'resync'});
    }
    for (final entry in entries) {
      final serial = entry['serial'] as int;
      if (serial <= _seen) continue;
      _seen = serial;
      if (!_pushes.isClosed) _pushes.add(_row(entry['push'] as Map));
    }
  }

  static MarketRow _row(Map value) => {
    for (final e in value.entries)
      '${e.key}': e.value is Map
          ? _row(e.value as Map)
          : e.value is List
          ? [for (final v in e.value as List) v is Map ? _row(v) : v]
          : e.value,
  };

  Future<void> close() => _pushes.close();
}
