import 'dart:async';
import 'dart:math';

import 'package:flutter/foundation.dart';

import '../communities/community_invitation_attachment.dart';

final class Conversation {
  const Conversation(
    this.ref,
    this.name,
    this.preview,
    this.time,
    this.unread,
    this.state, {
    this.avatar,
    this.conversationKey,
    this.gameId = '',
  });
  final String ref, name, preview, state;
  final String? avatar;
  final String? conversationKey;
  final String gameId;
  final DateTime time;
  final int unread;
  bool get request =>
      state == 'request_incoming' || state == 'request_outgoing';
}

final class DirectMessage {
  const DirectMessage(
    this.sequence,
    this.id,
    this.incoming,
    this.text,
    this.time,
    this.attachment, {
    this.communityInvitation,
  });
  final int sequence;
  final String id, text;
  final bool incoming;
  final DateTime time;
  final String? attachment;
  final CommunityInvitationAttachment? communityInvitation;
}

final class DirectPage {
  const DirectPage(
    this.ref,
    this.messages,
    this.oldest,
    this.latest,
    this.hasOlder,
    this.state, {
    this.canSend = false,
    this.localHistoryUnavailable = false,
  });
  final String ref, state;
  final List<DirectMessage> messages;
  final int oldest, latest;
  final bool hasOlder;
  final bool canSend;
  final bool localHistoryUnavailable;
}

final class DirectSendResult {
  const DirectSendResult(this.status, {this.error, this.message});
  final String status;
  final String? error;
  final DirectMessage? message;
}

/// A receipt alone is insufficient: it must identify this exact outgoing text.
bool confirmedDirectSend(DirectSendResult result, String id, String text) {
  final message = result.message;
  return const {'sent', 'duplicate', 'request_sent'}.contains(result.status) &&
      message != null &&
      message.id == id &&
      !message.incoming &&
      message.text == text &&
      message.sequence > 0 &&
      message.attachment == null;
}

abstract interface class DirectMessageSender {
  bool get supportsSending;
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  );
}

abstract interface class DirectMessagesPort {
  Stream<void> get invalidations;
  Future<List<Conversation>> directory();
  Future<DirectPage> history(String ref, {int before = 0, int after = 0});
  void cancel();
  Future<void> close();
}

final class DirectReadReceipt {
  const DirectReadReceipt(this.through, this.unread);
  final int through, unread;
}

abstract interface class DirectReadReceiptPort {
  bool get supportsReadReceipts;
  Future<DirectReadReceipt> markRead(String ref, int through);
}

abstract interface class DirectViewerAvatarPort {
  String? get viewerAvatar;
}

final class DirectReadFailure implements Exception {
  const DirectReadFailure(this.code);
  final String code;
}

final class UnavailableDirectMessages implements DirectMessagesPort {
  @override
  Stream<void> get invalidations => const Stream.empty();
  @override
  Future<List<Conversation>> directory() async =>
      throw const DirectReadFailure('unavailable');
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => throw const DirectReadFailure('unavailable');
  @override
  void cancel() {}
  @override
  Future<void> close() async {}
}

/// Shared conversation state. Only a visible viewport may request a read receipt.
final class DirectMessagesModule extends ChangeNotifier {
  DirectMessagesModule(this.port) {
    _subscription = port.invalidations.listen((_) {
      _epoch++;
      port.cancel();
      selected = null;
      rows = [];
      messages = [];
      error = null;
      readError = null;
      busy = false;
      loaded = false;
      requests = false;
      clearDraft();
      notifyListeners();
      unawaited(refresh());
    });
  }
  final DirectMessagesPort port;
  bool get supportsSending =>
      port is DirectMessageSender &&
      (port as DirectMessageSender).supportsSending;
  bool canSend = false, sending = false;
  String draft = '';
  String? sendStatus;
  String? _pendingId, _pendingText;
  int draftRevision = 0;
  bool get awaitingConfirmation => _pendingId != null;
  bool get hasDraft => draft.isNotEmpty || awaitingConfirmation;
  bool get readyToSend =>
      supportsSending &&
      canSend &&
      !busy &&
      !awaitingConfirmation &&
      draft.trim().isNotEmpty &&
      draft.trim().length <= 1000;
  void editDraft(String value) {
    draft = value;
    notifyListeners();
  }

  void clearDraft() {
    draft = '';
    draftRevision++;
    sendStatus = null;
    _pendingId = null;
    _pendingText = null;
    canSend = false;
    sending = false;
  }

  Future<void> send() async {
    if (_disposed || selected == null || !readyToSend) return;
    final epoch = ++_epoch, ref = selected!.ref;
    final text = draft.trim();
    final random = Random.secure();
    final id = List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
    _pendingId = id;
    _pendingText = text;
    sending = true;
    busy = true;
    sendStatus = 'sending';
    notifyListeners();
    DirectSendResult result;
    try {
      result = await (port as DirectMessageSender).send(ref, text, id);
    } catch (_) {
      result = const DirectSendResult('unknown');
    }
    if (_disposed || epoch != _epoch) return;
    sending = false;
    busy = false;
    if (confirmedDirectSend(result, id, text)) {
      clearDraft();
      sendStatus = result.status == 'request_sent' ? 'request_sent' : 'sent';
      // Reload latest instead of advancing past messages that arrived during POST.
      await load();
    } else if (result.status == 'rejected') {
      _pendingId = null;
      _pendingText = null;
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
    } else {
      sendStatus = 'outcome_unknown';
      notifyListeners();
    }
  }

  bool get supportsReadReceipts =>
      port is DirectReadReceiptPort &&
      (port as DirectReadReceiptPort).supportsReadReceipts;
  bool _markingRead = false;
  String? _readRef, _readAttempt;
  int _readThrough = 0;
  String? readError;

  Future<void> markVisibleRead(int through) async {
    final target = selected;
    if (_disposed ||
        busy ||
        sending ||
        _markingRead ||
        target == null ||
        !supportsReadReceipts ||
        through <= 0 ||
        !messages.any((m) => m.incoming && m.sequence == through)) {
      return;
    }
    if (_readRef == target.ref && through <= _readThrough) return;
    final epoch = _epoch;
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
      if (_disposed || epoch != _epoch || selected?.ref != target.ref) return;
      if (receipt.through < through || receipt.unread < 0) {
        throw const DirectReadFailure('data_invalid');
      }
      _readRef = target.ref;
      _readThrough = receipt.through;
      Conversation update(Conversation row) => Conversation(
        row.ref,
        row.name,
        row.preview,
        row.time,
        receipt.unread,
        row.state,
        avatar: row.avatar,
        conversationKey: row.conversationKey,
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
      if (!_disposed && epoch == _epoch) readError = _failure(e);
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
  String state = 'none';
  List<Conversation> rows = [];
  List<DirectMessage> messages = [];
  Conversation? selected;
  List<Conversation> get visible =>
      rows.where((row) => row.request == requests).toList();
  Future<void> refresh({bool retainDirectory = false}) async {
    if (_disposed || sending) return;
    clearDraft();
    final epoch = ++_epoch;
    port.cancel();
    busy = true;
    if (!retainDirectory) {
      loaded = false;
      rows = [];
    }
    selected = null;
    messages = [];
    error = null;
    readError = null;
    notifyListeners();
    try {
      final value = await port.directory();
      if (_disposed || epoch != _epoch) return;
      rows = List.unmodifiable(value);
      loaded = true;
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
    if (_disposed || sending) return;
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

  void back() {
    if (sending) return;
    clearDraft();
    _epoch++;
    port.cancel();
    selected = null;
    messages = [];
    busy = false;
    error = null;
    readError = null;
    hasOlder = false;
    hasNewer = false;
    notifyListeners();
  }

  Future<void> open(Conversation row) async {
    if (!rows.contains(row) || _disposed || sending) return;
    clearDraft();
    _epoch++;
    port.cancel();
    selected = row;
    messages = [];
    hasOlder = false;
    hasNewer = false;
    busy = false;
    state = row.state;
    await load();
  }

  Future<void> load({bool older = false, bool newer = false}) async {
    if (_disposed || busy || selected == null) return;
    if (older && !hasOlder) return;
    final target = selected!;
    final epoch = ++_epoch;
    final before = older && messages.isNotEmpty ? messages.first.sequence : 0;
    final after = newer && messages.isNotEmpty ? messages.last.sequence : 0;
    busy = true;
    error = null;
    readError = null;
    notifyListeners();
    try {
      final page = await port.history(target.ref, before: before, after: after);
      if (_disposed || epoch != _epoch) return;
      if (page.ref != target.ref ||
          page.messages.any(
            (m) => (before > 0 && m.sequence >= before) || m.sequence <= after,
          )) {
        throw const DirectReadFailure('data_invalid');
      }
      final merged = before > 0
          ? [...page.messages, ...messages]
          : after > 0
          ? [...messages, ...page.messages]
          : page.messages;
      if (merged.length > 1000) throw const DirectReadFailure('limit');
      if (merged.map((m) => m.id).toSet().length != merged.length ||
          merged.map((m) => m.sequence).toSet().length != merged.length) {
        throw const DirectReadFailure('data_invalid');
      }
      messages = List.unmodifiable(merged);
      if (after == 0) hasOlder = page.hasOlder;
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
      if (_pendingId != null &&
          messages.any(
            (m) =>
                m.id == _pendingId &&
                !m.incoming &&
                m.text == _pendingText &&
                m.attachment == null,
          )) {
        final permission = canSend;
        clearDraft();
        canSend = permission;
        sendStatus = 'sent';
      }
    } catch (e) {
      if (!_disposed && epoch == _epoch) {
        error = _failure(e);
        canSend = false;
        if (error == 'forbidden' ||
            error == 'identity_unavailable' ||
            error == 'target_changed') {
          messages = [];
          hasOlder = false;
          hasNewer = false;
        }
      }
    }
    if (!_disposed && epoch == _epoch) {
      busy = false;
      notifyListeners();
    }
  }

  String _failure(Object e) => e is DirectReadFailure ? e.code : 'unavailable';
  @override
  void dispose() {
    _disposed = true;
    _epoch++;
    port.cancel();
    unawaited(_subscription.cancel());
    unawaited(port.close());
    super.dispose();
  }
}
