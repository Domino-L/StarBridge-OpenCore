import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'friends_directory_pages.dart';
import 'friends_module.dart';
import 'friends_snapshot_decoder.dart';

/// Owns one write and its result pages. Never repeats a write to recover a view.
final class FriendsCommandDirectory {
  FriendsCommandDirectory(this.session, this.owner, this.current)
    : generation = session.activeGeneration {
    _unobserve = session.observeGenerationChanges(
      (_, _) => _retire(scope: true),
    );
    _unregister = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _retire(scope: true);
        },
        reconcile: () async {},
      ),
    );
  }
  final BridgeClientSession session;
  final BridgeAccountContext owner;
  final bool Function() current;
  final int generation;
  BridgeRequestOperation? _operation;
  void Function() _unobserve = () {}, _unregister = () {};
  bool _disposed = false, _retired = false, _scopeRetired = false;
  bool _sent = false, _accepted = false;
  bool get _scope =>
      !_scopeRetired &&
      current() &&
      generation == session.activeGeneration &&
      !session.connectionModeChanging;
  bool get _live => !_disposed && !_retired && _scope;
  static const _unavailable = FriendCommandResult(
    'accepted',
    directoryUnavailable: true,
  );

  Future<FriendCommandResult> execute(String action, String targetRef) async {
    final paged = session.hostCapabilities.contains('friends.commandPages');
    final deadline = Timer(const Duration(seconds: 15), () => _retire());
    try {
      if (!_live) return const FriendCommandResult('cancelled');
      _sent = true;
      final response = await _request('friends.execute', {
        'schemaVersion': 1,
        'action': action,
        'targetRef': targetRef,
        if (paged) 'pagedResponse': true,
      });
      if (!_scope) return const FriendCommandResult('cancelled');
      final body = response.payload;
      if (body['schemaVersion'] is! int || body['schemaVersion'] != 1) {
        throw const FormatException();
      }
      final status = body['status'];
      if (status == 'rejected' || status == 'unknown') {
        final error = body['error'];
        return FriendCommandResult(
          status! as String,
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
      }
      if (status != 'accepted') throw const FormatException();
      final state = body['directoryState'];
      if (state == 'unavailable') {
        if (body.containsKey('directory') ||
            body['directorySyncError'] != 'refreshRequired') {
          throw const FormatException();
        }
        _accepted = true;
        return _unavailable;
      }
      if (state == 'paged') {
        if (!paged) throw const FormatException();
        // The negotiated ACK confirms the write independently of its directory.
        _accepted = true;
        if (!_live) return _unavailable;
        final pages = FriendsDirectoryPages();
        var complete = pages.add(
          Map<String, Object?>.from(body['directory'] as Map),
        );
        while (complete == null) {
          if (!_live) {
            return _scope
                ? _unavailable
                : const FriendCommandResult('cancelled');
          }
          final page = await _request('friends.readPage', {
            'schemaVersion': 1,
            'snapshotId': pages.snapshotId,
            'offset': pages.nextOffset,
          });
          if (!_scope) return const FriendCommandResult('cancelled');
          if (!_live) return _unavailable;
          complete = pages.add(page.payload);
        }
        final directory = parseFriendsSnapshot(complete);
        if (directory.query != null) throw const FormatException();
        return FriendCommandResult('accepted', directory: directory);
      }
      if (state != null) throw const FormatException();
      final raw = Map<String, Object?>.from(body['directory'] as Map);
      // Never interpret an unsolicited partial page as a complete legacy list.
      if (raw.containsKey('page')) throw const FormatException();
      final directory = parseFriendsSnapshot(raw);
      if (directory.query != null) throw const FormatException();
      return FriendCommandResult('accepted', directory: directory);
    } on Object {
      if (!_scope) return const FriendCommandResult('cancelled');
      if (_accepted) return _unavailable;
      return FriendCommandResult(
        _sent ? 'unknown' : 'rejected',
        error: _sent ? 'outcomeUnknown' : 'identityUnavailable',
      );
    } finally {
      deadline.cancel();
      dispose();
    }
  }

  Future<BridgeEnvelope> _request(
    String name,
    Map<String, Object?> payload,
  ) async {
    final operation = session.beginRequest(
      name,
      accountContext: owner,
      payload: payload,
    );
    _operation = operation;
    if (!_live) unawaited(operation.cancel());
    final response = await operation.future;
    if (identical(_operation, operation)) _operation = null;
    final context = response.accountContext;
    if (response.name != name ||
        response.sessionGeneration != generation ||
        context == null ||
        context.environment != owner.environment ||
        context.authority != owner.authority ||
        context.subject != owner.subject) {
      throw const FormatException();
    }
    return response;
  }

  void _retire({bool scope = false}) {
    _retired = true;
    _scopeRetired = _scopeRetired || scope;
    final operation = _operation;
    _operation = null;
    if (operation != null) unawaited(operation.cancel());
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retire();
    _unobserve();
    _unregister();
  }
}
