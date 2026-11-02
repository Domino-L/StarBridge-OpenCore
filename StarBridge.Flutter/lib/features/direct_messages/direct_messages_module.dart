import 'dart:async';

import 'package:flutter/foundation.dart';

import 'direct_conversation_memory.dart';
import 'direct_messages_contract.dart';
import 'direct_message_receive_polling.dart';
import 'direct_message_directory_comparison.dart';
import 'direct_message_send_queue.dart';
import 'direct_message_selected_row.dart';

export 'direct_messages_contract.dart';
export 'direct_message_send_queue.dart'
    show DirectMessageSendQueue, DirectOutgoing, DirectOutgoingState;
export 'direct_message_receive_polling.dart'
    show DirectMessageReceiveLease, DirectMessageReceiveResult;

/// Shared conversation state. Only a visible viewport may request a read receipt.
final class DirectMessagesModule extends ChangeNotifier {
  DirectMessagesModule(
    this.port, {
    this.sendRetryDelays = DirectMessageSendQueue.defaultRetryDelays,
  }) {
    addListener(_drainActivity);
    if (port is DirectMessageActivityPort) {
      _activity = (port as DirectMessageActivityPort).changes.listen((_) {
        _activityPending = true;
        _drainActivity();
      });
    }
    if (port is DirectMessageDirectoryActivityPort) {
      _directoryActivity = (port as DirectMessageDirectoryActivityPort)
          .directoryChanges
          .listen((_) => _drainActivity(directory: true));
    }
    _subscription = port.invalidations.listen((_) {
      _discardReadContext();
      unawaited(refresh());
    });
  }

  void _discardReadContext({String? failure}) {
    if (_disposed) return;
    _epoch++;
    _receivePolling?.invalidate();
    _activityPending = false;
    port.cancel();
    selected = null;
    rows = [];
    messages = [];
    error = failure;
    directoryError = null;
    historySyncError = null;
    lastDirectorySyncUtc = null;
    readError = null;
    busy = false;
    loaded = false;
    requests = false;
    directoryRefreshing = false;
    _directoryRefreshToken = null;
    scrollOffset = 0;
    hasOlder = false;
    hasNewer = false;
    _readRef = null;
    _readThrough = 0;
    _readAttempt = null;
    _readFailures = 0;
    _readRetry?.cancel();
    _readRetry = null;
    state = 'none';
    clearDraft();
    // Account/session boundary: queued sends never move to another context,
    // and no conversation's history or draft survives into it.
    outbox.clear();
    _memory.clear();
    notifyListeners();
  }

  final DirectMessagesPort port;
  DirectMessageReceivePolling? _receivePolling;
  DirectMessageReceiveLease observeVisibleReception(bool Function() visible) {
    final receiver = port;
    if (!_disposed && receiver is DirectMessageReceptionPort) {
      return (receiver as DirectMessageReceptionPort).observeVisibleReception(
        visible,
      );
    }
    final polling = _receivePolling ??= DirectMessageReceivePolling(
      read: receive,
      isHealthy: () => directMessageReceptionHealthy(port),
    );
    if (_disposed) polling.dispose();
    return polling.observe(visible);
  }

  double scrollOffset = 0;
  StreamSubscription<void>? _activity, _directoryActivity;
  bool get supportsSending =>
      port is DirectMessageSender &&
      (port as DirectMessageSender).supportsSending;
  bool canSend = false;
  String draft = '';
  String? sendStatus;
  Timer? _confirmedSendHint;
  int draftRevision = 0;

  /// The user's own messages until history returns them (2026-10-21 "A2").
  late final outbox = DirectMessageSendQueue(
    sender: () =>
        _disposed || !supportsSending ? null : port as DirectMessageSender,
    changed: () {
      if (!_disposed) notifyListeners();
    },
    onResult: _sendFinished,
    retryDelays: sendRetryDelays,
  );
  final List<Duration> sendRetryDelays;
  List<DirectOutgoing> get outgoing => outbox.forConversation(selected);
  bool get hasDraft => draft.isNotEmpty;
  bool get readyToSend =>
      supportsSending &&
      canSend &&
      !busy &&
      draft.trim().isNotEmpty &&
      draft.trim().length <= 1000;
  void editDraft(String value) {
    draft = value;
    if (const {'sent', 'request_sent'}.contains(sendStatus)) {
      _confirmedSendHint?.cancel();
      _confirmedSendHint = null;
      sendStatus = null;
    }
    notifyListeners();
  }

  void clearDraft() {
    _confirmedSendHint?.cancel();
    _confirmedSendHint = null;
    draft = '';
    draftRevision++;
    sendStatus = null;
    canSend = false;
  }

  /// A2: the message appears at once and the composer clears for the next
  /// one. Delivery, order and bounded retries belong to [outbox].
  Future<void> send() async {
    final target = selected;
    if (_disposed || target == null || !readyToSend) return;
    final text = draft.trim();
    draft = '';
    draftRevision++;
    _confirmedSendHint?.cancel();
    _confirmedSendHint = null;
    sendStatus = null;
    outbox.enqueue(target, text);
  }

  void retrySend(String id) => outbox.retry(id);

  /// B1: the live connection came back; queued messages go out now.
  void connectionRestored() => outbox.connectionRestored();

  void _sendFinished(DirectOutgoing message, DirectSendResult result) {
    if (_disposed) return;
    final current = selected != null && message.belongsTo(selected!);
    if (result.status != 'rejected') {
      // Fetch the server copy; the outbox drops its own once history has it.
      _activityPending = true;
      _drainActivity();
      if (current && result.status == 'request_sent') {
        _showConfirmedSendHint('request_sent');
      }
      return;
    }
    if (!current) return;
    sendStatus = result.error ?? 'rejected';
    if (const {
      'forbidden',
      'request_pending',
      'identity_unavailable',
      'target_changed',
    }.contains(sendStatus)) {
      canSend = false;
    }
    notifyListeners();
    if (sendStatus == 'target_changed') {
      unawaited(_renewRejectedSendTarget(_epoch, message.ref));
    }
  }

  Future<void> _renewRejectedSendTarget(int epoch, String rejectedRef) async {
    final target = selected;
    final key = target?.conversationKey;
    if (_disposed ||
        epoch != _epoch ||
        target?.ref != rejectedRef ||
        key == null ||
        key.isEmpty) {
      return;
    }
    try {
      // The send was explicitly rejected. Refresh only the capability and
      // permission; never replay the POST or discard its unsent draft.
      final directory = await port.directory();
      if (_disposed || epoch != _epoch || selected?.ref != rejectedRef) return;
      final matches = directory
          .where((row) => row.conversationKey == key)
          .toList();
      if (matches.length != 1 || matches.single.ref == rejectedRef) return;
      rows = List.unmodifiable(directory);
      selected = matches.single;
      // Failed messages stay failed; a user retry goes to the renewed target.
      outbox.renewReference(matches.single);
      messages = [];
      hasOlder = false;
      hasNewer = false;
      canSend = false;
      _readRef = null;
      _readThrough = 0;
      _readAttempt = null;
      _readFailures = 0;
      _readRetry?.cancel();
      await load(recoverTarget: false);
      if (!_disposed &&
          selected?.ref == matches.single.ref &&
          error == null &&
          canSend) {
        sendStatus = null;
        notifyListeners();
      }
    } catch (_) {
      // An unavailable directory leaves sending disabled and the draft intact.
    }
  }

  void _showConfirmedSendHint(String status) {
    _confirmedSendHint?.cancel();
    sendStatus = status;
    _confirmedSendHint = Timer(const Duration(seconds: 3), () {
      _confirmedSendHint = null;
      if (_disposed || sendStatus != status) return;
      sendStatus = null;
      notifyListeners();
    });
    notifyListeners();
  }

  bool get supportsReadReceipts =>
      port is DirectReadReceiptPort &&
      (port as DirectReadReceiptPort).supportsReadReceipts;
  bool _markingRead = false;
  int _directoryReadRevision = 0;
  String? _readRef, _readAttempt;
  int _readThrough = 0;
  String? readError;
  Timer? _readRetry;
  bool Function()? isViewportCurrent;
  int _readFailures = 0;

  Future<void> markVisibleRead(int through) async {
    final target = selected;
    if (_disposed ||
        busy ||
        _markingRead ||
        _receiving ||
        hasNewer ||
        target == null ||
        !supportsReadReceipts ||
        through <= 0 ||
        !messages.any((m) => m.incoming && m.sequence == through)) {
      return;
    }
    if (_readRef == target.ref && through <= _readThrough) return;
    final epoch = _epoch;
    final directoryRevision = _directoryReadRevision;
    final attempt = '$epoch:${target.ref}:$through';
    if (_readAttempt == attempt) return;
    _readAttempt = attempt;
    _markingRead = true;
    readError = null;
    try {
      final receipt = await (port as DirectReadReceiptPort).markRead(
        target.ref,
        through,
      );
      if (_disposed ||
          epoch != _epoch ||
          directoryRevision != _directoryReadRevision ||
          selected?.ref != target.ref) {
        return;
      }
      if (receipt.through < through || receipt.unread < 0) {
        throw const DirectReadFailure('data_invalid');
      }
      _readRef = target.ref;
      _readThrough = receipt.through;
      _readFailures = 0;
      Conversation update(Conversation row) => Conversation(
        row.ref,
        row.name,
        row.preview,
        row.time,
        receipt.unread,
        row.state,
        avatar: row.avatar,
        conversationKey: row.conversationKey,
        gameId: row.gameId,
        presence: row.presence,
      );
      rows = List.unmodifiable(
        rows.map(
          (row) =>
              row.ref == target.ref ||
                  (target.conversationKey != null &&
                      row.conversationKey == target.conversationKey)
              ? update(row)
              : row,
        ),
      );
      selected = update(selected!);
    } catch (e) {
      if (!_disposed &&
          epoch == _epoch &&
          directoryRevision == _directoryReadRevision) {
        final failure = _failure(e);
        // Reopening revalidates even a fully read conversation; with nothing
        // unread a failed receipt is no sync problem to show (DL-139).
        if ((selected?.unread ?? 0) > 0) readError = failure;
        if (failure == 'unavailable' && _readFailures < 3) {
          _readFailures++;
          _readRetry?.cancel();
          _readRetry = Timer(Duration(seconds: 1 << _readFailures), () {
            if (_disposed || epoch != _epoch || selected?.ref != target.ref) {
              return;
            }
            _readAttempt = null;
            // Reconsider only the currently visible viewport, not the old cursor.
            notifyListeners();
          });
        }
      }
    } finally {
      _markingRead = false;
      if (!_disposed) notifyListeners();
    }
  }

  String? get viewerAvatar => port is DirectViewerAvatarPort
      ? (port as DirectViewerAvatarPort).viewerAvatar
      : null;
  late final StreamSubscription<void> _subscription;
  int _epoch = 0;
  bool _disposed = false,
      busy = false,
      loaded = false,
      requests = false,
      hasOlder = false,
      hasNewer = false;
  String? error;
  String? directoryError;
  String? historySyncError;
  DateTime? lastDirectorySyncUtc;
  bool directoryRefreshing = false;
  Object? _directoryRefreshToken;
  String state = 'none';
  List<Conversation> rows = [];
  List<DirectMessage> messages = [];
  Conversation? selected;
  List<Conversation> get visible =>
      rows.where((row) => row.request == requests).toList();
  Future<void> refresh({bool retainDirectory = false}) async {
    if (_disposed || busy) return;
    // A directory refresh is independent of the current history and composer.
    // Reuse the same incremental path used by live activity; never retry a send.
    if (loaded) {
      if (_receiving) return;
      final refreshToken = Object();
      _directoryRefreshToken = refreshToken;
      _readRef = null;
      _readThrough = 0;
      _readAttempt = null;
      _readRetry?.cancel();
      _readFailures = 0;
      readError = null;
      directoryRefreshing = true;
      notifyListeners();
      try {
        await receive(directoryOnly: true, freshDirectory: true);
      } finally {
        if (!_disposed && identical(_directoryRefreshToken, refreshToken)) {
          _directoryRefreshToken = null;
          directoryRefreshing = false;
          notifyListeners();
        }
      }
      return;
    }
    clearDraft();
    final epoch = ++_epoch;
    port.cancel();
    busy = true;
    if (!retainDirectory) {
      loaded = false;
      rows = [];
    }
    selected = null;
    scrollOffset = 0;
    messages = [];
    error = null;
    directoryError = null;
    historySyncError = null;
    readError = null;
    notifyListeners();
    try {
      final value = await port.directory();
      if (_disposed || epoch != _epoch) return;
      rows = List.unmodifiable(value);
      loaded = true;
      lastDirectorySyncUtc = DateTime.now().toUtc();
    } catch (e) {
      if (!_disposed && epoch == _epoch) error = _failure(e);
    }
    if (!_disposed && epoch == _epoch) {
      busy = false;
      notifyListeners();
    }
  }

  /// Open only a Host-issued friend chat reference. Account invalidation clears
  /// it normally; the server still decides current history/send permission.
  Future<void> openFriend(Conversation friend) async {
    if (_disposed) return;
    if (selected?.ref == friend.ref) return;
    // Opening a verified target supersedes any background directory read.
    rows = [friend];
    requests = false;
    loaded = true;
    await open(friend);
  }

  void group(bool value) {
    if (busy) return;
    requests = value;
    back();
  }

  // DL-06: recent history and drafts per conversation, display only.
  final _memory = DirectConversationMemory();
  void _keepSelected() =>
      _memory.keep(selected?.conversationKey, draft: draft, messages: messages);

  void back() {
    _keepSelected();
    clearDraft();
    _epoch++;
    port.cancel();
    selected = null;
    messages = [];
    busy = false;
    error = null;
    historySyncError = null;
    readError = null;
    hasOlder = false;
    hasNewer = false;
    notifyListeners();
  }

  Future<void> open(Conversation row) async {
    if (!rows.contains(row) || _disposed) return;
    if (selected?.ref == row.ref) return;
    _keepSelected();
    clearDraft();
    draft = _memory.draft(row.conversationKey);
    scrollOffset = 0;
    // A new viewport must confirm its visible cursor again. A previous visit's
    // acknowledgement cannot suppress reconciliation of a refreshed directory.
    _readRef = null;
    _readThrough = 0;
    _readAttempt = null;
    _readFailures = 0;
    _readRetry?.cancel();
    _epoch++;
    port.cancel();
    selected = row;
    // Shown until the latest page replaces it; never a cursor or permission.
    messages = _memory.history(row.conversationKey);
    historySyncError = null;
    hasOlder = false;
    hasNewer = false;
    busy = false;
    state = row.state;
    await load();
  }

  bool _receiving = false;
  bool _activityPending = false;

  bool _directoryPending = false;
  void _drainActivity({bool directory = false}) {
    if (directory) _directoryPending = true;
    if (_disposed || _receiving || busy) return;
    if (_activityPending && !_markingRead) {
      _activityPending = _directoryPending = false;
      unawaited(receive());
    } else if (_directoryPending && !_activityPending) {
      // Another conversation changed the directory; keep the open history.
      _directoryPending = false;
      unawaited(receive(directoryOnly: true));
    }
  }

  /// Incremental receipt must not clear a draft or put the composer in loading.
  Future<DirectMessageReceiveResult> receive({
    bool directoryOnly = false,
    bool freshDirectory = false,
  }) async {
    if (_receiving || (_markingRead && !directoryOnly) || _disposed || busy) {
      return DirectMessageReceiveResult.skipped;
    }
    _receiving = true;
    final epoch = _epoch, beforeRows = rows, beforeMessages = messages;
    final before = (selected?.ref, state, canSend, hasOlder, hasNewer);
    var failed = false;
    try {
      // Directory/unread authority remains independent of history and receipts.
      if (loaded) {
        try {
          _directoryReadRevision++;
          final reader = port;
          final value =
              !freshDirectory && reader is DirectMessageDirectoryUpdatesPort
              ? await (reader as DirectMessageDirectoryUpdatesPort)
                    .receiveDirectory()
              : await port.directory();
          if (_disposed || epoch != _epoch) {
            return DirectMessageReceiveResult.invalidated;
          }
          rows = List.unmodifiable(value);
          directoryError = null;
          lastDirectorySyncUtc = DateTime.now().toUtc();
          selected = refreshSelectedFromDirectory(selected, rows);
          // The directory is the unread authority: nothing left to sync.
          if (selected?.unread == 0) readError = null;
          notifyListeners();
        } catch (e) {
          if (!_disposed &&
              epoch == _epoch &&
              const {
                'forbidden',
                'identity_unavailable',
                'target_changed',
              }.contains(_failure(e))) {
            _discardReadContext(failure: _failure(e));
            return DirectMessageReceiveResult.invalidated;
          }
          failed = true;
          // Transient directory failure must not stop independently available
          // history or keep claiming a peer's former live presence.
          if (!_disposed && epoch == _epoch) {
            directoryError = _failure(e);
            rows = List.unmodifiable(rows.map((row) => row.withoutPresence()));
            selected = selected?.withoutPresence();
            notifyListeners();
          }
        }
      }
      if (_disposed || epoch != _epoch) {
        return DirectMessageReceiveResult.invalidated;
      }
      if (selected != null && !directoryOnly) {
        final deadline = DateTime.now().add(const Duration(seconds: 30));
        for (var page = 0; page < 10; page++) {
          final previous = messages.lastOrNull?.sequence ?? 0;
          final historySucceeded = await _loadHistory(newer: true, quiet: true);
          if (_disposed || epoch != _epoch) {
            return DirectMessageReceiveResult.invalidated;
          }
          failed = failed || !historySucceeded;
          if (!historySucceeded || !hasNewer) break;
          if ((messages.lastOrNull?.sequence ?? 0) <= previous) {
            historySyncError = 'data_invalid';
            failed = true;
            break;
          }
          if (DateTime.now().isAfter(deadline)) break;
        }
      }
      if (_disposed || epoch != _epoch) {
        return DirectMessageReceiveResult.invalidated;
      }
      if (failed) return DirectMessageReceiveResult.failed;
      final unchanged =
          sameDirectMessageDirectory(beforeRows, rows) &&
          listEquals(beforeMessages, messages) &&
          before == (selected?.ref, state, canSend, hasOlder, hasNewer);
      return unchanged
          ? DirectMessageReceiveResult.unchanged
          : DirectMessageReceiveResult.changed;
    } catch (_) {
      return _disposed || epoch != _epoch
          ? DirectMessageReceiveResult.invalidated
          : DirectMessageReceiveResult.failed;
    } finally {
      _receiving = false;
      if (!_disposed && epoch == _epoch) notifyListeners();
      _drainActivity();
    }
  }

  Future<void> load({
    bool older = false,
    bool newer = false,
    bool quiet = false,
    bool recoverTarget = true,
  }) async {
    await _loadHistory(
      older: older,
      newer: newer,
      quiet: quiet,
      recoverTarget: recoverTarget,
    );
  }

  Future<bool> _loadHistory({
    bool older = false,
    bool newer = false,
    bool quiet = false,
    bool recoverTarget = true,
  }) async {
    if (_disposed || busy || selected == null) return false;
    if (older && !hasOlder) return false;
    final target = selected!;
    final epoch = quiet ? _epoch : ++_epoch;
    var succeeded = false;
    final before = older && messages.isNotEmpty ? messages.first.sequence : 0;
    final after = newer && messages.isNotEmpty ? messages.last.sequence : 0;
    if (!quiet) {
      busy = true;
      error = null;
      readError = null;
      _readRef = null;
      _readThrough = 0;
      _readAttempt = null;
      notifyListeners();
    }
    try {
      final page = await port.history(target.ref, before: before, after: after);
      if (_disposed || epoch != _epoch) return false;
      if (page.ref != target.ref ||
          page.messages.any(
            (m) => (before > 0 && m.sequence >= before) || m.sequence <= after,
          )) {
        throw const DirectReadFailure('data_invalid');
      }
      var merged = before > 0
          ? [...page.messages, ...messages]
          : after > 0
          ? [...messages, ...page.messages]
          : page.messages;
      final trimmed = (after > 0 || before > 0) && merged.length > 1000;
      if (!trimmed && merged.length > 1000) {
        throw const DirectReadFailure('limit');
      }
      if (merged.map((m) => m.id).toSet().length != merged.length ||
          merged.map((m) => m.sequence).toSet().length != merged.length) {
        throw const DirectReadFailure('data_invalid');
      }
      if (trimmed) {
        merged = before > 0 ? merged.sublist(0, 1000) : merged.sublist(merged.length - 1000);
      }
      messages = List.unmodifiable(merged);
      // History advances the summary; directory/receipts own unread counts.
      final latest = messages.lastOrNull;
      if (latest != null) {
        Conversation advance(Conversation row) =>
            row.ref != target.ref || latest.time.isBefore(row.time)
            ? row
            : Conversation(
                row.ref,
                row.name,
                latest.text,
                latest.time,
                row.unread,
                row.state,
                avatar: row.avatar,
                conversationKey: row.conversationKey,
                gameId: row.gameId,
                presence: row.presence,
              );
        rows = List.unmodifiable(rows.map(advance));
        selected = advance(selected!);
      }
      error = null;
      if (!older) historySyncError = null;
      if (after == 0) hasOlder = page.hasOlder;
      if (trimmed && after > 0) hasOlder = true;
      hasNewer = page.latest > (messages.lastOrNull?.sequence ?? 0);
      state = page.state;
      canSend =
          page.canSend &&
          const {
            'none',
            'friend',
            'accepted',
            'request_incoming',
            'request_outgoing',
          }.contains(state);
      // History now carries these sends: drop their local copies (A2).
      outbox.reconcile(messages);
      succeeded = true;
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        // Capabilities expire independently of the conversation. Reacquire only
        // a unique, Host-issued target with the same scoped identity, and retry
        // the read once without carrying cursors across capabilities. Never
        // retry a send or discard the user's draft as part of read recovery.
        if (!older && recoverTarget &&
            _failure(e) == 'target_changed' &&
            target.conversationKey?.isNotEmpty == true) {
          try {
            final directory = await port.directory();
            if (_disposed || epoch != _epoch) return false;
            final matches = directory
                .where((row) => row.conversationKey == target.conversationKey)
                .toList();
            if (matches.length == 1 && matches.single.ref != target.ref) {
              rows = List.unmodifiable(directory);
              selected = matches.single;
              messages = [];
              hasOlder = false;
              hasNewer = false;
              canSend = false;
              readError = null;
              _readRef = null;
              _readThrough = 0;
              _readAttempt = null;
              busy = false;
              return await _loadHistory(quiet: quiet, recoverTarget: false);
            }
          } catch (_) {
            // Preserve the original identity failure if renewal is unavailable.
          }
          if (_disposed || epoch != _epoch) return false;
        }
        // A transient background failure cannot revoke a confirmed permission.
        // Explicit permission/identity failures still clear inaccessible data.
        if (quiet &&
            !const {
              'forbidden',
              'identity_unavailable',
              'target_changed',
            }.contains(_failure(e))) {
          historySyncError = _failure(e);
          notifyListeners();
          return false;
        }
        historySyncError = null;
        error = _failure(e);
        canSend = false;
        if (error == 'forbidden' ||
            error == 'identity_unavailable' ||
            (error == 'target_changed' && !older)) {
          messages = [];
          hasOlder = false;
          hasNewer = false;
        }
      }
    }
    if (!_disposed && epoch == _epoch) {
      if (!quiet) busy = false;
      notifyListeners();
    }
    return succeeded && !_disposed && epoch == _epoch;
  }

  String _failure(Object e) => e is DirectReadFailure ? e.code : 'unavailable';
  @override
  void dispose() {
    _receivePolling?.dispose();
    _readRetry?.cancel();
    _confirmedSendHint?.cancel();
    outbox.dispose();
    _disposed = true;
    _epoch++;
    port.cancel();
    unawaited(_subscription.cancel());
    unawaited(_activity?.cancel());
    unawaited(_directoryActivity?.cancel());
    unawaited(port.close());
    super.dispose();
  }
}
