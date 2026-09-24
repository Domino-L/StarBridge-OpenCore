import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'friends_module.dart';
import '../direct_messages/bridge_direct_messages.dart'
    show readConversationKey;

final class BridgeFriendsAdapter implements FriendsPort, FriendsCommandPort {
  BridgeFriendsAdapter(this._session) {
    _subscription = _session.events.listen(
      (event) {
        if (event.name == 'account.changed' ||
            event.name == 'account.avatarChanged' ||
            event.name == 'bootstrap.invalidated') {
          cancelPending();
          _invalidations.add(null);
        }
      },
      onDone: () {
        if (!_closed) _invalidations.add(null);
      },
    );
  }
  final BridgeClientSession _session;
  final _invalidations = StreamController<void>.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  BridgeRequestOperation? _pending;
  int _epoch = 0;
  bool _closed = false;
  @override
  bool get commandsAvailable =>
      !_closed && _session.hostCapabilities.contains('friends.commands');
  @override
  Stream<void> get invalidations => _invalidations.stream;
  @override
  void cancelPending() {
    _epoch++;
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(pending.cancel());
  }

  @override
  Future<FriendsReadResult> read({String? query}) async {
    final epoch = ++_epoch;
    if (_closed || !_session.hostCapabilities.contains('friends.read')) {
      return const FriendsReadResult(
        FriendsReadState.unavailable,
        failure: 'hostUnavailable',
      );
    }
    try {
      _pending = _session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (_closed || epoch != _epoch) {
        return const FriendsReadResult(FriendsReadState.idle);
      }
      if (account.payload['schemaVersion'] != 1) throw const FormatException();
      if (account.payload['state'] == 'signedOut' ||
          account.payload['state'] == 'reauthorizationRequired') {
        return const FriendsReadResult(FriendsReadState.signedOut);
      }
      if (!hasRelayAccount(account) || account.accountContext == null) {
        return const FriendsReadResult(
          FriendsReadState.unavailable,
          failure: 'identityUnavailable',
        );
      }
      _pending = _session.beginRequest(
        'friends.read',
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, 'query': ?query},
      );
      final response = await _pending!.future;
      if (_closed || epoch != _epoch) {
        return const FriendsReadResult(FriendsReadState.idle);
      }
      final snapshot = parseFriendsSnapshot(response.payload);
      if (snapshot.query != query) throw const FormatException();
      return FriendsReadResult(FriendsReadState.ready, snapshot: snapshot);
    } on BridgeClientException catch (error) {
      return FriendsReadResult(
        FriendsReadState.unavailable,
        failure: switch (error.code) {
          'friends.identity_unavailable' ||
          'account.reauthorization_required' => 'identityUnavailable',
          'friends.forbidden' => 'forbidden',
          'friends.data_invalid' => 'invalidResponse',
          'host.capability_missing' ||
          'bridge.disconnected' => 'hostUnavailable',
          _ => 'unavailable',
        },
      );
    } on Object {
      return const FriendsReadResult(
        FriendsReadState.unavailable,
        failure: 'invalidResponse',
      );
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async {
    if (!commandsAvailable) {
      return const FriendCommandResult('rejected', error: 'hostUnavailable');
    }
    final epoch = ++_epoch;
    var dispatched = false;
    try {
      _pending = _session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (_closed ||
          epoch != _epoch ||
          account.payload['schemaVersion'] != 1 ||
          !hasRelayAccount(account) ||
          account.accountContext == null) {
        return const FriendCommandResult(
          'rejected',
          error: 'identityUnavailable',
        );
      }
      dispatched = true;
      _pending = _session.beginRequest(
        'friends.execute',
        accountContext: account.accountContext,
        payload: {'schemaVersion': 1, 'action': action, 'targetRef': targetRef},
      );
      final response = await _pending!.future;
      if (_closed || epoch != _epoch) {
        return const FriendCommandResult('unknown', error: 'outcomeUnknown');
      }
      final body = response.payload;
      if (body['schemaVersion'] != 1) throw const FormatException();
      final status = body['status'];
      if (status == 'accepted') {
        final directory = parseFriendsSnapshot(
          Map<String, Object?>.from(body['directory'] as Map),
        );
        if (directory.query != null) throw const FormatException();
        return FriendCommandResult('accepted', directory: directory);
      }
      if (status != 'rejected' && status != 'unknown') {
        throw const FormatException();
      }
      final error = body['error'];
      return FriendCommandResult(
        status as String,
        error:
            const {
              'busy',
              'targetChanged',
              'identityUnavailable',
              'forbidden',
              'refreshRequired',
              'cooldown',
              'tooManyPending',
              'rateLimited',
              'rejected',
              'outcomeUnknown',
            }.contains(error)
            ? error as String
            : 'outcomeUnknown',
      );
    } catch (_) {
      return FriendCommandResult(
        dispatched ? 'unknown' : 'rejected',
        error: dispatched ? 'outcomeUnknown' : 'identityUnavailable',
      );
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cancelPending();
    await _subscription.cancel();
    await _invalidations.close();
  }
}

FriendsSnapshot parseFriendsSnapshot(Map<String, Object?> value, {bool avatarContext = false}) {
  if (value['schemaVersion'] != 1) throw const FormatException();
  String text(Object? value, int max) {
    if (value is! String ||
        value.length > max ||
        RegExp(r'[\x00-\x1f\x7f]').hasMatch(value)) {
      throw const FormatException();
    }
    return value;
  }

  List<FriendRow> rows(String key, int max) {
    final items = value[key];
    if (items is! List || items.length > max) throw const FormatException();
    return items.map((raw) {
      final item = Map<String, Object?>.from(raw as Map);
      final relation = text(item['relationship'], 64);
      if (!(avatarContext && relation == 'self') && !const {
        'none',
        'friend',
        'incoming',
        'outgoing',
        'blocked',
        'unknown',
      }.contains(relation)) {
        throw const FormatException();
      }
      final avatar = item['avatarImageData'];
      final reference = item['targetRef'];
      final chatReference = item['chatTargetRef'];
      if (chatReference != null &&
          (!(relation == 'friend' || avatarContext && const ['none', 'incoming', 'outgoing'].contains(relation)) ||
              chatReference is! String ||
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(chatReference))) {
        throw const FormatException();
      }
      final actions = item['actions'];
      if (reference != null &&
          (reference is! String ||
              !RegExp(r'^[a-fA-F0-9]{32}$').hasMatch(reference))) {
        throw const FormatException();
      }
      final approved = actions == null
          ? <String>[]
          : (actions as List).cast<String>();
      if (approved.length > 3 ||
          approved.toSet().length != approved.length ||
          approved.any((a) => !friendActionsFor(relation).contains(a)) ||
          (approved.isNotEmpty && reference == null)) {
        throw const FormatException();
      }
      return FriendRow(
        text(item['callsign'], 512),
        text(item['gameId'], 512),
        relation,
        DateTime.parse(item['updatedAt'] as String),
        targetRef: reference as String?,
        chatTargetRef: chatReference as String?,
        conversationKey: relation == 'friend' || avatarContext
            ? readConversationKey(item['conversationKey'])
            : null,
        actions: List.unmodifiable(approved),
        shared: relation == 'friend' ? _readShared(item['shared']) : const {},
        avatar:
            avatar is String &&
                avatar.length <= 128 * 1024 &&
                (avatar.startsWith('data:image/png;base64,') ||
                    avatar.startsWith('data:image/jpeg;base64,'))
            ? avatar
            : null,
      );
    }).toList();
  }

  final query = value['query'] == null ? null : text(value['query'], 128);
  final groups = {
    for (final section in FriendsSection.values)
      section: rows(section.name, 2000),
  };
  final results = rows('results', 20);
  if ((!avatarContext && query == null && results.isNotEmpty) ||
      (query != null && groups.values.any((g) => g.isNotEmpty))) {
    throw const FormatException();
  }
  return FriendsSnapshot(
    groups: groups,
    results: results,
    query: query,
    refreshedAt: value['refreshedAt'] == null
        ? null
        : DateTime.parse(value['refreshedAt'] as String),
  );
}

Map<String, Object?> _readShared(Object? raw) {
  if (raw == null) return const {};
  final data = (raw as Map).cast<String, Object?>();
  if (data.keys.any(
    (key) => !const {
      'presence',
      'sameServer',
      'serverId',
      'serverRegion',
      'ship',
      'location',
      'lastOnlineAt',
    }.contains(key),
  )) {
    throw const FormatException();
  }
  for (final key in const [
    'presence',
    'serverId',
    'serverRegion',
    'ship',
    'location',
    'lastOnlineAt',
  ]) {
    final value = data[key];
    if (value != null &&
        (value is! String ||
            value.length > 512 ||
            RegExp(r'[\x00-\x1f\x7f]').hasMatch(value))) {
      throw const FormatException();
    }
  }
  if (data['sameServer'] != null && data['sameServer'] is! bool) {
    throw const FormatException();
  }
  if (data['presence'] != null &&
      !const {
        'AppOnline',
        'InGame',
        'Away',
        'Offline',
      }.contains(data['presence'])) {
    throw const FormatException();
  }
  if (data['lastOnlineAt'] != null &&
      DateTime.tryParse(data['lastOnlineAt'] as String) == null) {
    throw const FormatException();
  }
  return Map.unmodifiable(data);
}
