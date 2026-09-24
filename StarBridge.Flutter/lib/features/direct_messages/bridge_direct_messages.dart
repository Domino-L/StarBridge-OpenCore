import 'dart:async';

import '../communities/community_invitation_attachment.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'direct_messages_module.dart';

final class BridgeDirectMessages
    implements
        DirectMessagesPort,
        DirectViewerAvatarPort,
        DirectMessageSender,
        DirectReadReceiptPort {
  BridgeDirectMessages(this.session, {this._ownAvatar}) {
    _subscription = session.events.listen(
      (event) {
        if (event.name == 'account.changed' ||
            event.name == 'account.avatarChanged' ||
            event.name == 'bootstrap.invalidated') {
          cancel();
          _events.add(null);
        }
      },
      onDone: () {
        if (!_closed) _events.add(null);
      },
    );
  }
  final BridgeClientSession session;
  final String? Function()? _ownAvatar;
  @override
  String? get viewerAvatar => _closed ? null : _ownAvatar?.call();
  final _events = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  BridgeRequestOperation? _pending;
  int _epoch = 0;
  bool _closed = false;
  @override
  Stream<void> get invalidations => _events.stream;
  @override
  void cancel() {
    _epoch++;
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(pending.cancel());
  }

  @override
  bool get supportsSending =>
      !_closed && session.hostCapabilities.contains('directMessages.send');

  Future<Map<String, Object?>> _read(
    Map<String, Object?> fields, {
    bool send = false,
    bool receipt = false,
  }) async {
    final epoch = ++_epoch;
    final name = receipt
        ? 'directMessages.markRead'
        : send
        ? 'directMessages.send'
        : 'directMessages.read';
    var submitted = false;
    if (_closed || !session.hostCapabilities.contains(name)) {
      throw const DirectReadFailure('unavailable');
    }
    try {
      _pending = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (_closed || epoch != _epoch) {
        throw const DirectReadFailure('identity_unavailable');
      }
      if (account.payload['schemaVersion'] != 1 ||
          !hasRelayAccount(account) ||
          account.accountContext == null) {
        throw const DirectReadFailure('identity_unavailable');
      }
      submitted = true;
      _pending = session.beginRequest(
        name,
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, ...fields},
      );
      final response = await _pending!.future;
      if (_closed || epoch != _epoch) {
        throw const DirectReadFailure('identity_unavailable');
      }
      if (response.payload['schemaVersion'] != 1) {
        throw const DirectReadFailure('data_invalid');
      }
      return response.payload;
    } on DirectReadFailure {
      if (send && submitted) throw const DirectReadFailure('outcome_unknown');
      rethrow;
    } on BridgeClientException catch (e) {
      if (send && submitted) throw const DirectReadFailure('outcome_unknown');
      throw DirectReadFailure(switch (e.code) {
        'directMessages.forbidden' => 'forbidden',
        'directMessages.target_changed' => 'target_changed',
        'directMessages.identity_unavailable' ||
        'account.reauthorization_required' => 'identity_unavailable',
        'directMessages.data_invalid' => 'data_invalid',
        _ => 'unavailable',
      });
    }
  }

  @override
  bool get supportsReadReceipts =>
      !_closed && session.hostCapabilities.contains('directMessages.markRead');
  @override
  Future<DirectReadReceipt> markRead(String ref, int through) async {
    final data = await _read({
      'targetRef': ref,
      'throughSequence': through,
    }, receipt: true);
    if (_ref(data) != ref || _number(data, 'readThroughSequence') < through) {
      throw const DirectReadFailure('data_invalid');
    }
    return DirectReadReceipt(
      _number(data, 'readThroughSequence'),
      _number(data, 'unreadCount'),
    );
  }

  @override
  Future<DirectSendResult> send(
    String ref,
    String text,
    String clientMessageId,
  ) async {
    Map<String, Object?> data;
    try {
      data = await _read({
        'targetRef': ref,
        'text': text,
        'clientMessageId': clientMessageId,
      }, send: true);
    } on DirectReadFailure catch (e) {
      return DirectSendResult(
        e.code == 'outcome_unknown' ? 'unknown' : 'rejected',
        error: e.code,
      );
    }
    try {
      if (_ref(data) != ref) throw const DirectReadFailure('data_invalid');
      final status = _string(data, 'status', 64);
      if (status == 'unknown') return const DirectSendResult('unknown');
      if (status == 'rejected') {
        final error = data['error'];
        return DirectSendResult(
          'rejected',
          error:
              const {
                'busy',
                'limit',
                'invalid_request',
                'unavailable',
                'forbidden',
                'identity_unavailable',
                'target_changed',
                'data_invalid',
                'rate_limited',
                'request_pending',
                'rejected',
              }.contains(error)
              ? error as String
              : 'rejected',
        );
      }
      if (!const {'sent', 'duplicate', 'request_sent'}.contains(status)) {
        throw const DirectReadFailure('data_invalid');
      }
      final row = data['message'] as Map;
      if (row['incoming'] != false ||
          row['messageId'] != clientMessageId ||
          row['text'] != text.trim() ||
          row['attachmentKind'] != null ||
          _number(row, 'sequence') == 0) {
        throw const DirectReadFailure('data_invalid');
      }
      return DirectSendResult(
        status,
        message: DirectMessage(
          _number(row, 'sequence'),
          clientMessageId,
          false,
          text.trim(),
          DateTime.parse(_string(row, 'createdAt', 64)),
          null,
        ),
      );
    } catch (_) {
      return const DirectSendResult('unknown');
    }
  }

  @override
  Future<List<Conversation>> directory() async =>
      parseConversations(await _read({}));
  @override
  Future<DirectPage> history(
    String ref, {
    int before = 0,
    int after = 0,
  }) async => parseDirectPage(
    await _read({
      'targetRef': ref,
      if (before > 0) 'before': before,
      if (after > 0) 'after': after,
    }),
  );
  @override
  Future<void> close() async {
    _closed = true;
    cancel();
    await _subscription.cancel();
    await _events.close();
  }
}

String _string(Map data, String key, [int max = 4096]) {
  final value = data[key];
  if (value is! String || value.length > max) {
    throw const DirectReadFailure('data_invalid');
  }
  return value;
}

int _number(Map data, String key) {
  final value = data[key];
  if (value is! int || value < 0) throw const DirectReadFailure('data_invalid');
  return value;
}

String _ref(Map data) {
  final value = _string(data, 'targetRef', 32);
  if (!RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(value)) {
    throw const DirectReadFailure('data_invalid');
  }
  return value;
}

String _state(Map data) {
  final value = _string(data, 'state', 64);
  return const {
        'none',
        'friend',
        'accepted',
        'request_incoming',
        'request_outgoing',
      }.contains(value)
      ? value
      : 'unknown';
}

List<Conversation> parseConversations(Map<String, Object?> data) {
  final rows = data['conversations'];
  final seen = <String>{};
  if (data['schemaVersion'] != 1 || rows is! List || rows.length > 2000) {
    throw const DirectReadFailure('data_invalid');
  }
  final result = rows.map((item) {
    final row = item as Map;
    final ref = _ref(row);
    if (!seen.add(ref)) throw const DirectReadFailure('data_invalid');
    final call = _string(row, 'callsign', 512);
    final game = _string(row, 'gameId', 512);
    return Conversation(
      ref,
      call.isEmpty
          ? game
          : game.isEmpty
          ? call
          : '$call ($game)',
      _string(row, 'preview'),
      DateTime.parse(_string(row, 'lastMessageAt', 64)),
      _number(row, 'unreadCount'),
      _state(row),
      avatar: inlineAvatar(row['avatarImageData']),
      gameId: game,
      conversationKey: readConversationKey(row['conversationKey']),
    );
  }).toList();
  if (_number(data, 'totalUnread') != result.fold(0, (n, r) => n + r.unread)) {
    throw const DirectReadFailure('data_invalid');
  }
  return List.unmodifiable(result);
}

String? readConversationKey(Object? value) {
  if (value == null) return null;
  if (value is! String || !RegExp(r'^[a-fA-F0-9]{64}$').hasMatch(value)) {
    throw const FormatException();
  }
  return value.toUpperCase();
}

String? inlineAvatar(Object? value) =>
    value is String &&
        value.length <= 128 * 1024 &&
        (value.startsWith('data:image/png;base64,') ||
            value.startsWith('data:image/jpeg;base64,'))
    ? value
    : null;

DirectPage parseDirectPage(Map<String, Object?> data) {
  if (data['schemaVersion'] != 1 ||
      data['messages'] is! List ||
      (data['messages'] as List).length > 50 ||
      data['hasOlder'] is! bool ||
      data['canSend'] is! bool) {
    throw const DirectReadFailure('data_invalid');
  }
  final ids = <String>{};
  int previous = 0;
  final rows = (data['messages'] as List).map((item) {
    final row = item as Map;
    final sequence = _number(row, 'sequence');
    final id = _string(row, 'messageId', 256);
    if (sequence <= previous ||
        id.isEmpty ||
        !ids.add(id) ||
        row['incoming'] is! bool) {
      throw const DirectReadFailure('data_invalid');
    }
    previous = sequence;
    final attachment = row['attachmentKind'];
    if (attachment != null && attachment is! String) {
      throw const DirectReadFailure('data_invalid');
    }
    final invitation = row['communityInvitation'];
    if (invitation != null &&
        (attachment != 'fleet_invitation' || invitation is! Map)) {
      throw const DirectReadFailure('data_invalid');
    }
    return DirectMessage(
      sequence,
      id,
      row['incoming'] as bool,
      _string(row, 'text'),
      DateTime.parse(_string(row, 'createdAt', 64)),
      attachment == null
          ? null
          : const {
              'overlay_preset',
              'party_room_invitation',
              'fleet_invitation',
            }.contains(attachment)
          ? attachment as String
          : 'unknown',
      communityInvitation: invitation == null
          ? null
          : CommunityInvitationAttachment.parse(invitation as Map),
    );
  }).toList();
  final oldest = _number(data, 'oldestSequence');
  final latest = _number(data, 'latestSequence');
  if (oldest != (rows.firstOrNull?.sequence ?? 0) ||
      latest < previous ||
      (data['hasOlder'] == true && oldest == 0)) {
    throw const DirectReadFailure('data_invalid');
  }
  return DirectPage(
    _ref(data),
    List.unmodifiable(rows),
    oldest,
    latest,
    data['hasOlder'] as bool,
    _state(data),
    canSend: data['canSend'] as bool,
    localHistoryUnavailable: data['localHistoryUnavailable'] == true,
  );
}
