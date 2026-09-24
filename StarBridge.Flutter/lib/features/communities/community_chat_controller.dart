import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';

/// Owns one organization conversation. The widget owns scroll position and must
/// report actual visible messages, not a page's advertised server watermark.
final class CommunityChatController extends ChangeNotifier {
  CommunityChatController(this.port, this.targetRef, {DateTime Function()? now})
    : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityChatPort port;
  final String targetRef;
  final DateTime Function() _now;
  DateTime? _lastSuccessfulRead;
  Future<void> enter() async {
    final age = _lastSuccessfulRead == null
        ? null
        : _now().difference(_lastSuccessfulRead!);
    if (_loaded &&
        error == null &&
        age != null &&
        !age.isNegative &&
        age < const Duration(seconds: 10)) {
      return;
    }
    await refresh(silent: _loaded);
  }

  late final StreamSubscription<void> _subscription;
  List<CommunityChatMessage> _messages = [];
  List<CommunityChatMessage> get messages => List.unmodifiable(_messages);
  bool loading = false, markingRead = false, invalidated = false;
  bool hasOlder = false, canSend = false;
  bool localHistoryUnavailable = false;
  bool _closed = false, _visible = false, _foreground = false;
  int _epoch = 0, latestSequence = 0, confirmedReadThrough = 0, unreadCount = 0;
  String? error, receiptError, _pendingVisibleRef;
  String _draft = '';
  Map<String, Object?>? _draftAttachment;
  String get draft => _draft;
  Map<String, Object?>? get draftAttachment => _draftAttachment;
  bool sending = false;
  String? sendError;
  CommunityChatSendIntent? _pendingSend;
  int _draftRevision = 0, _sentRevision = 0;
  bool get sendUncertain => _pendingSend != null && !sending;
  bool get canSubmit =>
      _active &&
      canSend &&
      !sending &&
      _pendingSend == null &&
      port is CommunityChatSendPort &&
      (port as CommunityChatSendPort).chatSendAvailable;

  void updateDraft(String value) {
    if (!_active || value == _draft) return;
    _draft = value;
    _draftRevision++;
    notifyListeners();
  }

  /// Called only after the user confirms the existing discard warning.
  void discardDraft() {
    if (!_active || sending) return;
    _draft = '';
    _draftAttachment = null;
    _pendingSend = null;
    sendError = null;
    _draftRevision++;
    notifyListeners();
  }

  void setDraftAttachment(Map<String, Object?>? value) {
    if (!_active) return;
    _draftAttachment = value == null ? null : Map.unmodifiable(value);
    _draftRevision++;
    notifyListeners();
  }

  Future<void> submit() async {
    if (!canSubmit) return;
    final epoch = _epoch;
    final random = Random.secure();
    try {
      _pendingSend = CommunityChatSendIntent(
        targetRef: targetRef,
        requestId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        text: _draft,
        attachment: _draftAttachment,
      );
    } on FormatException {
      sendError = 'dataInvalid';
      notifyListeners();
      return;
    }
    final intent = _pendingSend!;
    _sentRevision = _draftRevision;
    sending = true;
    sendError = null;
    notifyListeners();
    try {
      final result = await (port as CommunityChatSendPort).sendChat(intent);
      if (!_current(epoch)) return;
      // A parallel authenticated history read may have already reconciled this
      // request. Its confirmation must not be undone by a late lost reply.
      if (_pendingSend != intent) return;
      if (result.status == 'accepted' &&
          result.sequence != null &&
          result.sequence! > 0) {
        _confirmSend();
      } else if (result.status == 'rejected') {
        _pendingSend = null;
        sendError = result.error ?? 'unavailable';
        if ({
          'identityUnavailable',
          'notAllowed',
          'notFound',
        }.contains(sendError)) {
          _failure(sendError!);
        }
      } else {
        sendError = result.error ?? 'outcomeUnknown';
      }
    } catch (_) {
      if (_current(epoch) && _pendingSend == intent) {
        sendError = 'outcomeUnknown';
      }
    } finally {
      if (_current(epoch)) {
        sending = false;
        notifyListeners();
      }
    }
    if (_current(epoch) && _pendingSend == null) await refresh();
  }

  void _confirmSend() {
    if (_draftRevision == _sentRevision) {
      _draft = '';
      _draftAttachment = null;
      _draftRevision++;
    }
    _pendingSend = null;
    sendError = null;
  }

  bool get _active => !_closed && !invalidated;
  bool _current(int epoch) => _active && epoch == _epoch;
  bool get canAcknowledge =>
      _active && _visible && _foreground && port.chatReadReceiptsAvailable;
  bool get hasNewer =>
      _messages.isNotEmpty && _messages.last.sequence < latestSequence;

  void setReadingContext({required bool visible, required bool foreground}) {
    _visible = visible;
    _foreground = foreground;
    if (!canAcknowledge) _pendingVisibleRef = null;
    // Becoming foreground alone is not evidence that a message was seen.
  }

  bool _loaded = false, _silentRead = false;
  bool get showProgress => loading && !_silentRead;
  Future<void> refresh({bool silent = false}) =>
      _load(older: false, silent: silent);
  Future<void> loadOlder() => _load(older: true);
  Future<void> _load({required bool older, bool silent = false}) async {
    if (!_active || loading || older && (!hasOlder || _messages.isEmpty)) {
      return;
    }
    final epoch = _epoch;
    final after = !older && _messages.isNotEmpty ? _messages.last.sequence : 0;
    final before = older ? _messages.first.sequence : 0;
    loading = true;
    _silentRead = silent && _loaded;
    error = null;
    notifyListeners();
    try {
      if (!port.chatAvailable) throw const CommunityFailure('unavailable');
      final page = await port.readChat(targetRef, after: after, before: before);
      if (!_current(epoch)) return;
      if (page.targetRef != targetRef ||
          page.messages.any(
            (m) =>
                after > 0 && m.sequence <= after ||
                before > 0 && m.sequence >= before,
          )) {
        throw const CommunityFailure('dataInvalid');
      }
      final merged = [..._messages, ...page.messages]
        ..sort((a, b) => a.sequence.compareTo(b.sequence));
      if (merged.map((m) => m.sequence).toSet().length != merged.length ||
          merged.map((m) => m.messageRef).toSet().length != merged.length) {
        throw const CommunityFailure('dataInvalid');
      }
      // The service retains 500 messages. Bound stale local history too.
      final trimmed = merged.length > 500;
      _messages = trimmed ? merged.sublist(merged.length - 500) : merged;
      if (_pendingSend != null &&
          page.messages.any(
            (m) => m.isSelf && m.localRequestId == _pendingSend!.requestId,
          )) {
        _confirmSend();
      }
      if (older || after == 0) hasOlder = page.hasOlder;
      if (trimmed) hasOlder = false;
      if (page.latestSequence > latestSequence) {
        latestSequence = page.latestSequence;
      }
      canSend = page.canSend;
      localHistoryUnavailable = page.localHistoryUnavailable;
      _loaded = true;
      _lastSuccessfulRead = _now();
      unreadCount = latestSequence <= confirmedReadThrough
          ? 0
          : page.unreadCount;
      // Do not use latestSequence as the next after cursor: a response may have
      // more than 50 messages waiting. Advance only through received messages.
    } catch (e) {
      if (_current(epoch)) {
        _failure(e is CommunityFailure ? e.code : 'unavailable');
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> acknowledgeVisible(
    String messageRef, {
    bool retry = false,
  }) async {
    if (!canAcknowledge || receiptError != null && !retry) return;
    final message = _messages
        .where((m) => m.messageRef == messageRef)
        .firstOrNull;
    if (message == null || message.sequence <= confirmedReadThrough) return;
    final pending = _messages
        .where((m) => m.messageRef == _pendingVisibleRef)
        .firstOrNull;
    if (pending == null || pending.sequence < message.sequence) {
      _pendingVisibleRef = messageRef;
    }
    if (markingRead) return;
    final epoch = _epoch;
    markingRead = true;
    receiptError = null;
    notifyListeners();
    try {
      while (_current(epoch) && canAcknowledge && _pendingVisibleRef != null) {
        final visible = _messages
            .where((m) => m.messageRef == _pendingVisibleRef)
            .firstOrNull;
        _pendingVisibleRef = null;
        if (visible == null || visible.sequence <= confirmedReadThrough) {
          continue;
        }
        final result = await port.markChatRead(targetRef, visible);
        if (!_current(epoch)) return;
        if (result.status != 'accepted' ||
            result.readThrough == null ||
            result.readThrough! < visible.sequence) {
          receiptError = result.error ?? 'outcomeUnknown';
          _pendingVisibleRef = null;
          if ({
            'identityUnavailable',
            'notAllowed',
            'notFound',
          }.contains(receiptError)) {
            _failure(receiptError!);
          }
          break;
        }
        if (result.readThrough! > confirmedReadThrough) {
          confirmedReadThrough = result.readThrough!;
        }
        if (latestSequence <= confirmedReadThrough) unreadCount = 0;
        // Do not clear newer unseen messages. A refresh supplies the exact count
        // when only part of this conversation has been acknowledged.
      }
    } catch (_) {
      if (_current(epoch)) {
        receiptError = 'outcomeUnknown';
        _pendingVisibleRef = null;
      }
    } finally {
      if (_current(epoch)) {
        markingRead = false;
        notifyListeners();
      }
    }
  }

  void _failure(String code) {
    error = code;
    if ({'identityUnavailable', 'notAllowed', 'notFound'}.contains(code)) {
      invalidate(code: code);
    }
  }

  void invalidate({String code = 'identityUnavailable'}) {
    if (_closed) return;
    _epoch++;
    invalidated = true;
    _messages = [];
    _pendingVisibleRef = receiptError = null;
    _draft = '';
    _draftAttachment = null;
    _pendingSend = null;
    sendError = null;
    sending = false;
    latestSequence = confirmedReadThrough = unreadCount = 0;
    hasOlder = canSend = loading = markingRead = false;
    error = code;
    notifyListeners();
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    _messages = [];
    _pendingVisibleRef = null;
    _draft = '';
    _draftAttachment = null;
    _pendingSend = null;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
