import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'communities_module.dart';
import 'community_chat_port.dart';
import 'community_chat_send_port.dart';
import 'community_chat_media_cache.dart';
import 'community_avatar_cache.dart';
import 'community_author_projection_port.dart';
import 'community_author_projection.dart';
import 'community_chat_author_window.dart';
import 'community_chat_local_models.dart';
import 'community_chat_seen_authors.dart';

export 'community_chat_local_models.dart';

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
    if (port is CommunityAuthorProjectionPort) {
      _authorSubscription = (port as CommunityAuthorProjectionPort)
          .authorIdentityChanges
          .listen((_) {
            if (!_active) return;
            _cancelAuthorExpiry();
            _media?.retireAuthors(_messages);
            _authorWindow.suspend();
            notifyListeners();
          });
    }
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
      now: _authorNow,
      authorIsCurrent: authorIsCurrent,
      narrowAuthor: _narrowAuthor,
      onAuthorTimingChanged: _scheduleAuthorExpiry,
      onAvatarConfirmed: seenAuthors.confirmAvatar,
      onAccessLost: () => unawaited(refresh(silent: true)),
    );
    if (invalidated) cache.invalidate();
    return cache;
  }

  /// The caller verifies unchanged account and organization membership. Only
  /// future reads and new intents use this handle; existing sends keep theirs.
  void renewVerifiedReference(String target) {
    if (!_active || !RegExp(r'^[a-f0-9]{32}$').hasMatch(target)) return;
    if (target == _targetRef) return;
    seenAuthors.clear();
    retireAuthors();
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
  StreamSubscription<void>? _authorSubscription;
  List<CommunityChatMessage> _messages = [];
  List<CommunityChatMessage> get messages => List.unmodifiable(_messages);

  CommunityChatMessage presentAuthor(CommunityChatMessage message) {
    if (port is! CommunityAuthorProjectionPort) return message;
    if (!(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable) {
      seenAuthors.clear();
      return CommunityChatMessage.neutralAuthor(message);
    }
    return seenAuthors.present(
      message,
      verified: _authorWindow.canPresent(message.messageRef),
      allowed: _active && _visible && _foreground && !_readOnly,
      now: _authorNow(),
    );
  }

  /// Recheck the owner after media IO; a newer observation renews no older one.
  bool authorIsCurrent(CommunityChatMessage message) {
    if (!_active ||
        !_visible ||
        !_foreground ||
        _readOnly ||
        port is! CommunityAuthorProjectionPort ||
        !(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable ||
        !_authorWindow.canPresent(message.messageRef)) {
      return false;
    }
    final current = _messages
        .where((row) => row.messageRef == message.messageRef)
        .firstOrNull;
    final identity = current?.authorIdentity, expected = message.authorIdentity;
    return current?.senderRef == message.senderRef &&
        identity?.admit(_authorNow()).visible == true &&
        expected?.visible == true &&
        identity!.version == expected!.version &&
        identity.avatarVersion == expected.avatarVersion &&
        identity.observedAt == expected.observedAt &&
        identity.validUntil == expected.validUntil;
  }
  final _authorWindow = CommunityChatAuthorWindow();
  final seenAuthors = CommunityChatSeenAuthors();
  DateTime _authorNow() => _authorWindow.identityTime(_now());
  bool _authorContinuation = false;
  Timer? _authorExpiry;
  int _authorExpiryEpoch = 0;
  void _cancelAuthorExpiry() {
    _authorExpiryEpoch++;
    _authorExpiry?.cancel();
    _authorExpiry = null;
  }

  bool _retireAuthorProofs(Iterable<CommunityChatMessage> expired) {
    final result = _authorWindow.retireProofs(_messages, expired);
    _messages = result.messages;
    _media?.retireAuthors(result.retired);
    return result.retired.isNotEmpty;
  }

  void _narrowAuthor(
    CommunityChatMessage message,
    CommunityAuthorProjection observed,
  ) {
    if (!_active || observed.visible) return;
    final hidden = observed.state == CommunityAuthorState.hidden;
    if (hidden) seenAuthors.forget(message.senderRef, then: notifyListeners);
    if (!hidden && !authorIsCurrent(message)) return;
    // Hidden answers for the person, so every message of theirs goes with it.
    if (_retireAuthorProofs(hidden ? _messages.where((m) => m.senderRef == message.senderRef) : [message])) {
      _scheduleAuthorExpiry();
      notifyListeners();
    }
  }

  /// The original one-shot display deadline remains the only identity Timer.
  void _scheduleAuthorExpiry() {
    _cancelAuthorExpiry();
    if (!_active ||
        !_visible ||
        !_foreground ||
        _readOnly ||
        port is! CommunityAuthorProjectionPort ||
        !(port as CommunityAuthorProjectionPort).authorIdentitiesAvailable) {
      return;
    }
    final now = _authorNow();
    DateTime? earliest = _media?.nextAuthorDeadline;
    for (final message in _messages) {
      if (!_authorWindow.canPresent(message.messageRef)) continue;
      final deadline = message.authorIdentity?.validUntil;
      if (deadline != null &&
          deadline.isAfter(now) &&
          (earliest == null || deadline.isBefore(earliest))) {
        earliest = deadline;
      }
    }
    if (earliest == null) return;
    final deadline = earliest, captured = _authorExpiryEpoch;
    _authorExpiry = Timer(deadline.difference(now), () {
      if (!_active || captured != _authorExpiryEpoch) return;
      _authorExpiry = null;
      final at = _authorWindow.identityTime(_now(), reachedDeadline: deadline);
      _retireAuthorProofs([
        ..._messages.where(
          (message) => message.authorIdentity?.validUntil?.isAfter(at) == false,
        ),
        ...?_media?.retireExpiredAuthors(at),
      ]);
      notifyListeners();
      _scheduleAuthorExpiry();
    });
  }

  void retireAuthors({bool notify = false}) {
    if (port is! CommunityAuthorProjectionPort) return;
    _cancelAuthorExpiry();
    _media?.retireAuthors(_messages);
    _authorWindow.retire();
    if (notify && _active) notifyListeners();
  }

  void observeAuthors(Iterable<CommunityChatMessage> visible) {
    if (!_active ||
        _readOnly ||
        !_visible ||
        !_foreground ||
        port is! CommunityAuthorProjectionPort) {
      return;
    }
    if (_authorWindow.observe(visible) && _authorWindow.hasPending) {
      unawaited(refresh(silent: true, renewal: authorRenewalAvailable));
    }
  }
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
  bool _readOnly = false;

  /// An owner may retain display after a failed membership read. This pauses
  /// new writes without retiring drafts, references or in-flight outcomes.
  void setReadOnly(bool value) {
    if (_closed || value == _readOnly) return;
    _readOnly = value;
    if (value) {
      retireAuthors();
      _pendingVisibleRef = null;
      _visibleReadThrough = confirmedReadThrough;
    }
    notifyListeners();
  }

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
      !_readOnly &&
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
  }) => _localMessages
      .where((m) => identical(m.intent, intent))
      .firstOrNull
      ?.settle(state, error, sequence);

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
      _active &&
      !_readOnly &&
      _visible &&
      _foreground &&
      port.chatReadReceiptsAvailable;
  bool get hasNewer =>
      _messages.isNotEmpty && _messages.last.sequence < latestSequence;

  void setReadingContext({required bool visible, required bool foreground}) {
    if ((!visible || !foreground) && _visible && _foreground) retireAuthors();
    _visible = visible;
    _foreground = foreground;
    if (!canAcknowledge) _pendingVisibleRef = null;
    // Becoming foreground alone is not evidence that a message was seen.
  }

  bool _loaded = false, _silentRead = false;
  bool _sendReadbackPending = false;
  bool get showProgress => loading && !_silentRead;
  Future<ChatReadResult?> refresh({bool silent = false, bool renewal = false}) =>
      _load(older: false, silent: silent, renewal: renewal);

  bool get renewalSupported =>
      port is CommunityChatAuthorRenewalPort &&
      (port as CommunityChatAuthorRenewalPort).chatAuthorRenewalAvailable;

  bool get authorRenewalAvailable =>
      _visible && _foreground && !_readOnly && renewalSupported;

  final catchUp = CommunityChatCatchUp();
  Future<ChatReadResult?> loadOlder() => _load(older: true);
  Future<ChatReadResult?> _load({
    required bool older,
    bool silent = false,
    bool renewal = false,
  }) async {
    // A pushed read must not be lost to a renewal that happens to be running.
    final pushed = !older && !renewal && port is CommunityChatAuthorRenewalPort;
    if (_active && loading && pushed) catchUp.due = true;
    if (!_active || loading || older && (!hasOlder || _messages.isEmpty)) {
      return null;
    }
    ChatReadResult? outcome;
    final renewalPort =
        renewal && !older && !_referenceRenewed && authorRenewalAvailable
        ? port as CommunityChatAuthorRenewalPort
        : null;
    final epoch = _epoch;
    final authorPort = port is CommunityAuthorProjectionPort
        ? port as CommunityAuthorProjectionPort
        : null;
    if (!_authorContinuation) _authorWindow.refresh();
    _authorContinuation = false;
    final authorEpoch = _authorWindow.epoch;
    final observed =
        authorPort?.authorIdentitiesAvailable == true &&
            _visible &&
            _foreground &&
            !_readOnly
        ? _authorWindow.takeBatch()
        : <String>[];
    final renewed = !older && _referenceRenewed;
    var after = !older && !renewed && _messages.isNotEmpty
        ? _messages.last.sequence
        : 0;
    final before = older ? _messages.first.sequence : 0;
    loading = true;
    _silentRead = silent && _loaded;
    // A renewal says nothing about the content, so it keeps any content error.
    if (renewalPort == null) error = null;
    if (renewalPort == null && !older) catchUp.due = false;
    notifyListeners();
    try {
      if (!port.chatAvailable) throw const CommunityFailure('unavailable');
      final readTarget = targetRef;
      var page = authorPort == null
          ? await port.readChat(readTarget, after: after, before: before)
          : renewalPort != null
          ? await renewalPort.renewChatAuthors(
              readTarget,
              after: after,
              observeMessageRefs: observed,
            )
          : await authorPort.readChatAuthors(
              readTarget,
              after: after,
              before: before,
              observeMessageRefs: observed,
            );
      if (!_current(epoch)) return null;
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
        if (!_current(epoch)) return null;
      }
      final merged = mergeCommunityChatPage(
        _messages,
        page,
        target: readTarget,
        after: after,
        before: before,
        renewed: renewed,
      );
      final trimmed = merged.length > 500; // The service retains 500 too.
      _messages = trimmed ? merged.sublist(merged.length - 500) : merged;
      if (authorPort != null) {
        if (page.authorRefreshRequired) seenAuthors.clear();
        final recovery =
            page.authorRefreshRequired &&
                authorPort.authorIdentitiesAvailable &&
                _visible &&
                _foreground &&
                !_readOnly
            ? _authorWindow.beginReferenceRecovery(authorEpoch, _messages)
            : null;
        _messages = _authorWindow.applyAuthorUpdates(
          _messages,
          page,
          observed,
          _authorNow,
        );
        seenAuthors.answer(_messages, observed, page.authorUpdates);
        _authorWindow.verified(authorEpoch, observed);
        if (recovery != null) {
          // Publish the primary page's independent retirement before extra IO.
          notifyListeners();
          final root = await authorPort.readChatAuthors(
            readTarget,
            before: recovery.before,
          );
          if (!_current(epoch)) return null;
          if (root.targetRef != readTarget ||
              root.messages.any((row) => row.sequence >= recovery.before)) {
            throw const CommunityFailure('dataInvalid');
          }
          if (targetRef == readTarget &&
              authorPort.authorIdentitiesAvailable &&
              _visible &&
              _foreground &&
              !_readOnly) {
            final result = _authorWindow.recoverReferences(
              recovery,
              _messages,
              root,
              _authorNow,
            );
            _messages = result.messages;
            _media?.retireAuthors(result.retired);
          }
        }
        _scheduleAuthorExpiry();
      }
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
      if (renewalPort != null && _messages.isNotEmpty) {
        final seen = max(page.latestSequence, _messages.last.sequence);
        catchUp.renewalSaw(seen, latestSequence);
      }
      if (renewalPort == null) {
        if (page.latestSequence > latestSequence) {
          latestSequence = page.latestSequence;
        }
        canSend = page.canSend;
        localHistoryUnavailable = page.localHistoryUnavailable;
        _lastSuccessfulRead = _now();
        _unreadCount = latestSequence <= confirmedReadThrough
            ? 0
            : page.unreadCount;
      }
      _loaded = true;
      outcome = (renewal: renewalPort != null, ok: true);
      if (renewalPort == null && !older) catchUp.onFullRead?.call();
      // Do not use latestSequence as the next after cursor: a response may have
      // more than 50 messages waiting. Advance only through received messages.
    } catch (e) {
      if (_current(epoch)) {
        final code = e is CommunityFailure ? e.code : 'unavailable';
        // A failed renewal only costs names; lost access still ends the chat.
        outcome = (renewal: renewalPort != null, ok: false);
        if (code != 'unavailable') seenAuthors.clear();
        if (renewalPort == null && !older) catchUp.due = true;
        if (renewalPort == null || code != 'unavailable') _failure(code);
      }
    } finally {
      if (_current(epoch)) {
        loading = false;
        notifyListeners();
        final morePending =
            _authorWindow.hasPending &&
            authorPort?.authorIdentitiesAvailable == true &&
            _visible &&
            _foreground &&
            !_readOnly;
        // A send or owed read goes first; a full read carries the next names.
        final owed = catchUp.due ? catchUp.onDue : null;
        if (_sendReadbackPending) {
          _sendReadbackPending = false;
          _authorContinuation = morePending;
          unawaited(refresh(silent: true));
        } else if (owed != null) {
          _authorContinuation = morePending;
          owed();
        } else if (morePending) {
          _authorContinuation = true;
          unawaited(refresh(silent: true, renewal: renewalPort != null));
        }
      }
    }
    return outcome;
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
    _cancelAuthorExpiry();
    seenAuthors.clear();
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
    _cancelAuthorExpiry();
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
    unawaited(_authorSubscription?.cancel());
    super.dispose();
  }
}
