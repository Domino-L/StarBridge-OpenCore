import 'dart:async';
import 'dart:math';

import 'direct_messages_contract.dart';

/// Where an outgoing private message is (2026-10-21 user choice "A2"): it is
/// shown at once, a clock marks it while sending, failures keep the text and
/// can be retried. [confirmed] stays visible until history returns its copy.
enum DirectOutgoingState { sending, failed, confirmed }

final class DirectOutgoing {
  DirectOutgoing._(
    this.id,
    this.ref,
    this.conversationKey,
    this.text,
    this.time,
  );
  final String id, text;
  String ref;
  final String? conversationKey;
  final DateTime time;
  DirectOutgoingState state = DirectOutgoingState.sending;

  /// Rejection reason of a failed message ('unknown' when delivery stayed
  /// unconfirmed after the automatic retries).
  String? error;
  int attempts = 0;

  bool belongsTo(Conversation row) =>
      row.ref == ref ||
      (conversationKey?.isNotEmpty == true &&
          row.conversationKey == conversationKey);
}

/// Per-conversation, in-order sending of the user's own messages.
///
/// A retry is never a blind replay: the same `clientMessageId` and text are
/// sent again, and the relay deduplicates exactly on (sender, id) and returns
/// `duplicate` for a message that already arrived. Only transport-uncertain
/// outcomes retry automatically (bounded); explicit rejections fail at once
/// and wait for the user.
final class DirectMessageSendQueue {
  DirectMessageSendQueue({
    required this.sender,
    required this.changed,
    required this.onResult,
    this.retryDelays = defaultRetryDelays,
    DateTime Function()? now,
  }) : _now = now ?? DateTime.now;

  /// About half a minute of automatic retries, then the message shows failed.
  static const defaultRetryDelays = [
    Duration(seconds: 1),
    Duration(seconds: 2),
    Duration(seconds: 4),
    Duration(seconds: 8),
    Duration(seconds: 16),
  ];

  final DirectMessageSender? Function() sender;
  final void Function() changed;

  /// Module side effects of a final send outcome (permissions, reload).
  final void Function(DirectOutgoing message, DirectSendResult result) onResult;
  final List<Duration> retryDelays;
  final DateTime Function() _now;
  final _entries = <DirectOutgoing>[];
  final _inFlight = <String>{};
  final _retryTimers = <String, Timer>{};
  int _generation = 0;
  bool _disposed = false;

  List<DirectOutgoing> forConversation(Conversation? row) => row == null
      ? const []
      : List.unmodifiable(_entries.where((entry) => entry.belongsTo(row)));

  bool get hasPending =>
      _entries.any((entry) => entry.state == DirectOutgoingState.sending);

  DirectOutgoing enqueue(Conversation row, String text) {
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    final message = DirectOutgoing._(
      id,
      row.ref,
      row.conversationKey,
      text,
      _now(),
    );
    _entries.add(message);
    changed();
    _pump();
    return message;
  }

  /// User retry of a failed message: same id and text, fresh retry budget.
  void retry(String id) {
    final message = _entries.where((entry) => entry.id == id).firstOrNull;
    if (_disposed || message == null) return;
    if (message.state != DirectOutgoingState.failed) return;
    message
      ..state = DirectOutgoingState.sending
      ..error = null
      ..attempts = 0;
    changed();
    _pump();
  }

  /// The live connection came back: resend waiting messages without backoff.
  void connectionRestored() {
    if (_disposed || _retryTimers.isEmpty) return;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _pump();
  }

  /// A Host-issued conversation reference was renewed for the same key.
  void renewReference(Conversation row) {
    for (final entry in _entries.where((entry) => entry.belongsTo(row))) {
      entry.ref = row.ref;
    }
  }

  /// History is authoritative: a message present there is done (sent or not
  /// this attempt). Its local copy is dropped so it is never shown twice.
  void reconcile(Iterable<DirectMessage> history) {
    final ids = {
      for (final message in history)
        if (!message.incoming) message.id,
    };
    final before = _entries.length;
    _entries.removeWhere((entry) {
      if (!ids.contains(entry.id)) return false;
      _retryTimers.remove(entry.id)?.cancel();
      return true;
    });
    if (_entries.length != before) {
      changed();
      _pump();
    }
  }

  /// Account or session boundary: nothing carries over.
  void clear() {
    _generation++;
    for (final timer in _retryTimers.values) {
      timer.cancel();
    }
    _retryTimers.clear();
    _inFlight.clear();
    _entries.clear();
  }

  void dispose() {
    _disposed = true;
    clear();
  }

  void _pump() {
    if (_disposed) return;
    // One message in flight per conversation keeps the order the user typed.
    final heads = <String, DirectOutgoing>{};
    for (final entry in _entries) {
      if (entry.state != DirectOutgoingState.sending) continue;
      heads.putIfAbsent(entry.conversationKey ?? entry.ref, () => entry);
    }
    for (final head in heads.values) {
      if (_inFlight.contains(head.id) || _retryTimers.containsKey(head.id)) {
        continue;
      }
      unawaited(_send(head));
    }
  }

  Future<void> _send(DirectOutgoing message) async {
    final port = sender();
    final generation = _generation;
    if (port == null || !port.supportsSending) {
      _fail(message, 'unavailable');
      return;
    }
    _inFlight.add(message.id);
    message.attempts++;
    DirectSendResult result;
    try {
      result = await port.send(message.ref, message.text, message.id);
    } catch (_) {
      result = const DirectSendResult('unknown');
    }
    if (_disposed || generation != _generation) return;
    _inFlight.remove(message.id);
    if (!_entries.contains(message)) return;
    if (confirmedDirectSend(result, message.id, message.text)) {
      message.state = DirectOutgoingState.confirmed;
      onResult(message, result);
    } else if (result.status == 'rejected') {
      _fail(message, result.error ?? 'rejected');
      onResult(message, result);
    } else if (message.attempts <= retryDelays.length) {
      final delay = retryDelays[message.attempts - 1];
      _retryTimers[message.id] = Timer(delay, () {
        _retryTimers.remove(message.id);
        _pump();
      });
    } else {
      _fail(message, 'unknown');
    }
    changed();
    _pump();
  }

  void _fail(DirectOutgoing message, String error) {
    message
      ..state = DirectOutgoingState.failed
      ..error = error;
    changed();
  }
}
