import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';
import 'community_chat_media_cache.dart';
import 'community_avatar_cache.dart';

/// Local presentation only: never participates in server cursors or receipts.
final class CommunityLocalMessage {
  CommunityLocalMessage(this.intent, this.createdAt);
  CommunityChatSendIntent intent;
  final DateTime createdAt;
  String state = 'sending';
  String? error;
  int? sequence;
}

/// Account-scoped presentation state, never a server cursor or read receipt.
final class CommunityChatViewport {
  const CommunityChatViewport({
    required this.pixels,
    required this.followLatest,
    required this.observedLatest,
    this.anchorSequence,
    this.anchorOffset = 0,
  });
  final double pixels, anchorOffset;
  final bool followLatest;
  final int observedLatest;
  final int? anchorSequence;
}

/// Owns one organization conversation. The widget measures its viewport and must
/// report actual visible messages, not a page's advertised server watermark.
final class CommunityChatController extends ChangeNotifier {
  CommunityChatController(
    this.port,
    this._targetRef, {
    DateTime Function()? now,
    this.localEcho = false,
  }) : _now = now ?? DateTime.now {
    _subscription = port.invalidations.listen((_) => invalidate());
  }
  final CommunityChatPort port;
  // Opt in only when the renderer can retain and present local delivery states.
  final bool localEcho;
  final _localMessages = <CommunityLocalMessage>[];
  List<CommunityLocalMessage> get localMessages =>
      List.unmodifiable(_localMessages);
  bool get hasLocalDelivery => _localMessages.isNotEmpty;
  CommunityChatViewport? _viewport;
  CommunityChatViewport? get viewport => _viewport;
  void rememberViewport(CommunityChatViewport value) {
    if (_active) _viewport = value;
  }

  String _targetRef;
  bool _referenceRenewed = false;
  String get targetRef => _targetRef;
  bool get hasLoaded => _loaded;
  CommunityChatMediaCache? _media;
  CommunityChatMediaCache media({CommunityAvatarCache? avatars}) {
    if (_closed) throw StateError('Closed conversation');
    final cache = _media ??= CommunityChatMediaCache(
      port,
      targetRef,
      avatars: avatars,
    );
    if (invalidated) cache.invalidate();
    return cache;
  }

  /// The caller must verify unchanged account and organization membership.
  /// Keep history, receipts and pending send reconciliation; only future reads
  /// and new intents use this handle. Existing sends retain their exact intent.
  void renewVerifiedReference(String target) {
    if (!_active || !RegExp(r'^[a-f0-9]{32}$').hasMatch(target)) return;
    if (target == _targetRef) return;
    _targetRef = target;
    _media?.dispose();
    _media = null;
    _referenceRenewed = true;
  }

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
  int _epoch = 0,
      latestSequence = 0,
      confirmedReadThrough = 0,
      _unreadCount = 0;
  int _visibleReadThrough = 0;
  // Presentation only: the server cursor remains confirmedReadThrough.
  int get displayedReadThrough => markingRead
      ? max(confirmedReadThrough, _visibleReadThrough)
      : confirmedReadThrough;
  int get unreadCount =>
      latestSequence <= displayedReadThrough ? 0 : _unreadCount;
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
      _canSendRequest && (!localEcho || _localMessages.length < 20);
  bool canRetry(CommunityLocalMessage message) =>
      _canSendRequest &&
      _localMessages.contains(message) &&
      message.state == 'failed';
  bool canRestore(CommunityLocalMessage message) =>
      _active &&
      !sending &&
      _draft.isEmpty &&
      _draftAttachment == null &&
      _localMessages.contains(message) &&
      message.state == 'failed';
  void restoreLocalDraft(CommunityLocalMessage message) {
    if (!canRestore(message)) return;
    _draft = message.intent.text;
    _draftAttachment = message.intent.attachment;
    _draftRevision++;
    _localMessages.remove(message);
    sendError = null;
    notifyListeners();
  }

  bool get _canSendRequest =>
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
    if (!localEcho) {
      _pendingSend = null;
      sendError = null;
    }
    _draftRevision++;
    notifyListeners();
  }

  void setDraftAttachment(Map<String, Object?>? value) {
    if (!_active) return;
    _draftAttachment = value == null ? null : Map.unmodifiable(value);
    _draftRevision++;
    notifyListeners();
  }

  Future<void> submit({CommunityLocalMessage? retry}) async {
    if (retry == null ? !canSubmit : !canRetry(retry)) return;
    final epoch = _epoch;
    final random = Random.secure();
    try {
      _pendingSend = CommunityChatSendIntent(
        targetRef: targetRef,
        requestId: List.generate(
          16,
          (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
        ).join(),
        text: retry?.intent.text ?? _draft,
        attachment: retry?.intent.attachment ?? _draftAttachment,
      );
    } on FormatException {
      sendError = 'dataInvalid';
      notifyListeners();
      return;
    }
    final intent = _pendingSend!;
    _sentRevision = _draftRevision;
    if (localEcho) {
      if (retry == null) {
        _localMessages.add(CommunityLocalMessage(intent, _now()));
        _draft = '';
        _draftAttachment = null;
        _draftRevision++;
      } else {
        retry.intent = intent;
        retry.state = 'sending';
        retry.error = null;
      }
    }
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
        _confirmSend(sequence: result.sequence);
      } else if (result.status == 'rejected') {
        _pendingSend = null;
        sendError = result.error ?? 'unavailable';
        _localResult(intent, 'failed', error: sendError);
        if ({
          'identityUnavailable',
          'notAllowed',
          'notFound',
        }.contains(sendError)) {
          _failure(sendError!);
        }
      } else {
        sendError = result.error ?? 'outcomeUnknown';
        _localResult(intent, 'unknown', error: sendError);
      }
    } catch (_) {
      if (_current(epoch) && _pendingSend == intent) {
        sendError = 'outcomeUnknown';
        _localResult(intent, 'unknown', error: sendError);
      }
    } finally {
      if (_current(epoch)) {
        sending = false;
        notifyListeners();
      }
    }
    if (_current(epoch) && _pendingSend == null) {
      if (loading) {
        _sendReadbackPending = true;
      } else {
        await refresh(silent: localEcho);
      }
    }
  }

  void _localResult(
    CommunityChatSendIntent intent,
    String state, {
    String? error,
    int? sequence,
  }) {
    final local = _localMessages
        .where((m) => identical(m.intent, intent))
        .firstOrNull;
    if (local == null) return;
    local.state = state;
    local.error = error;
    local.sequence = sequence;
  }

  void _confirmSend({int? sequence}) {
    if (_pendingSend case final intent?) {
      _localResult(intent, 'sent', sequence: sequence);
    }
    if (!localEcho && _draftRevision == _sentRevision) {
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
  bool _sendReadbackPending = false;
  bool get showProgress => loading && !_silentRead;
  Future<void> refresh({bool silent = false}) =>
      _load(older: false, silent: silent);
  Future<void> loadOlder() => _load(older: true);
  Future<void> _load({required bool older, bool silent = false}) async {
    if (!_active || loading || older && (!hasOlder || _messages.isEmpty)) {
      return;
    }
    final epoch = _epoch;
    final renewed = !older && _referenceRenewed;
    var after = !older && !renewed && _messages.isNotEmpty
        ? _messages.last.sequence
        : 0;
    final before = older ? _messages.first.sequence : 0;
    loading = true;
    _silentRead = silent && _loaded;
    error = null;
    notifyListeners();
    try {
      if (!port.chatAvailable) throw const CommunityFailure('unavailable');
      final readTarget = targetRef;
      var page = await port.readChat(readTarget, after: after, before: before);
      if (!_current(epoch)) return;
      if (page.targetRef != readTarget) {
        throw const CommunityFailure('dataInvalid');
      }
      if (renewed &&
          _messages.isNotEmpty &&
          page.hasOlder &&
          page.messages.isNotEmpty &&
          page.messages.first.sequence > _messages.last.sequence) {
        // Latest-page revalidation must not jump over a busy channel's unseen
        // middle. Resume at the existing cursor with one bounded catch-up read.
        after = _messages.last.sequence;
        page = await port.readChat(readTarget, after: after);
        if (!_current(epoch)) return;
      }
      if (page.targetRef != readTarget ||
          page.messages.any(
            (m) =>
                after > 0 && m.sequence <= after ||
                before > 0 && m.sequence >= before,
          )) {
        throw const CommunityFailure('dataInvalid');
      }
      final refreshed = page.messages.map((m) => m.sequence).toSet();
      final merged = [
        ..._messages.where((m) => !renewed || !refreshed.contains(m.sequence)),
        ...page.messages,
      ]..sort((a, b) => a.sequence.compareTo(b.sequence));
      if (merged.map((m) => m.sequence).toSet().length != merged.length ||
          merged.map((m) => m.messageRef).toSet().length != merged.length) {
        throw const CommunityFailure('dataInvalid');
      }
      // The service retains 500 messages. Bound stale local history too.
      final trimmed = merged.length > 500;
      _messages = trimmed ? merged.sublist(merged.length - 500) : merged;
      if (renewed && targetRef == readTarget) _referenceRenewed = false;
      if (_pendingSend != null &&
          page.messages.any(
            (m) => m.isSelf && m.localRequestId == _pendingSend!.requestId,
          )) {
        _confirmSend();
      }
      // Only authenticated self-authored history can replace a local bubble.
      _localMessages.removeWhere(
        (local) => _messages.any(
          (message) =>
              message.isSelf &&
              (message.localRequestId == local.intent.requestId ||
                  local.sequence != null && message.sequence == local.sequence),
        ),
      );
      if (older || after == 0 && !renewed) hasOlder = page.hasOlder;
      if (trimmed) hasOlder = false;
      if (page.latestSequence > latestSequence) {
        latestSequence = page.latestSequence;
      }
      canSend = page.canSend;
      localHistoryUnavailable = page.localHistoryUnavailable;
      _loaded = true;
      _lastSuccessfulRead = _now();
      _unreadCount = latestSequence <= confirmedReadThrough
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
        if (_sendReadbackPending) {
          _sendReadbackPending = false;
          unawaited(refresh(silent: true));
        }
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
    if (markingRead && message.sequence <= _visibleReadThrough) return;
    final pending = _messages
        .where((m) => m.messageRef == _pendingVisibleRef)
        .firstOrNull;
    if (pending == null || pending.sequence < message.sequence) {
      _pendingVisibleRef = messageRef;
    }
    _visibleReadThrough = max(_visibleReadThrough, message.sequence);
    if (markingRead) {
      notifyListeners();
      return;
    }
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
        if (latestSequence <= confirmedReadThrough) _unreadCount = 0;
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
        _visibleReadThrough = confirmedReadThrough;
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
    _media?.invalidate();
    _messages = [];
    _viewport = null;
    _pendingVisibleRef = receiptError = null;
    _draft = '';
    _draftAttachment = null;
    _pendingSend = null;
    _localMessages.clear();
    _sendReadbackPending = false;
    sendError = null;
    sending = false;
    latestSequence = confirmedReadThrough = _unreadCount = _visibleReadThrough =
        0;
    hasOlder = canSend = loading = markingRead = false;
    error = code;
    notifyListeners();
  }

  @override
  void dispose() {
    _media?.dispose();
    _media = null;
    _closed = true;
    _epoch++;
    _messages = [];
    _viewport = null;
    _pendingVisibleRef = null;
    _draft = '';
    _draftAttachment = null;
    _pendingSend = null;
    _localMessages.clear();
    _sendReadbackPending = false;
    unawaited(_subscription.cancel());
    super.dispose();
  }
}
