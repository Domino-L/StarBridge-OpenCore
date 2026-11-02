import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'friends_directory_pages.dart';

/// One authenticated business read; pages never reacquire or cache a root read.
final class FriendsDirectoryRead {
  FriendsDirectoryRead(this.session, this.owner, this.current)
    : generation = session.activeGeneration {
    _unobserve = session.observeGenerationChanges((_, _) => _retire());
    _unregister = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _retire();
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
  bool _disposed = false, _retired = false, _timedOut = false;

  bool get _live =>
      !_disposed &&
      !_retired &&
      current() &&
      generation == session.activeGeneration &&
      !session.connectionModeChanging;

  Future<Map<String, Object?>?> read({
    String? query,
    BridgeDisplayProgress? displayProgress,
    void Function(BridgeRequestOperation)? onInitial,
  }) async {
    final paged = session.hostCapabilities.contains('friends.readPages');
    // Bound the complete transfer, not fifteen seconds for every single page.
    final deadline = Timer(const Duration(seconds: 15), () {
      _timedOut = true;
      _retire();
    });
    try {
      if (_timedOut) throw const BridgeTimeoutException('friends.read');
      if (!_live) return null;
      var response = await _request(
        'friends.read',
        {
          'schemaVersion': 1,
          'query': ?query,
          if (displayProgress != null) 'cachedDisplayProgress': true,
          if (paged) 'pagedResponse': true,
        },
        displayProgress: displayProgress,
        onInitial: onInitial,
      );
      if (_timedOut) throw const BridgeTimeoutException('friends.read');
      if (!_live) return null;
      if (!paged) return response.payload;
      final pages = FriendsDirectoryPages();
      var complete = pages.add(response.payload);
      while (complete == null) {
        if (!_live) return null;
        response = await _request('friends.readPage', {
          'schemaVersion': 1,
          'snapshotId': pages.snapshotId,
          'offset': pages.nextOffset,
        });
        if (_timedOut) throw const BridgeTimeoutException('friends.read');
        if (!_live) return null;
        complete = pages.add(response.payload);
      }
      return complete;
    } on Object {
      if (_timedOut) throw const BridgeTimeoutException('friends.read');
      if (!_live) return null;
      rethrow;
    } finally {
      deadline.cancel();
      dispose();
    }
  }

  Future<BridgeEnvelope> _request(
    String name,
    Map<String, Object?> payload, {
    BridgeDisplayProgress? displayProgress,
    void Function(BridgeRequestOperation)? onInitial,
  }) async {
    final operation = session.beginRequest(
      name,
      accountContext: owner,
      payload: payload,
      displayProgress: displayProgress,
    );
    _operation = operation;
    onInitial?.call(operation);
    // A synchronous send may pause the mode before the operation is assigned.
    if (!_live) unawaited(operation.cancel());
    final response = await operation.future;
    if (identical(_operation, operation)) _operation = null;
    final context = response.accountContext;
    if (_live &&
        (response.name != name ||
            response.sessionGeneration != generation ||
            context == null ||
            context.environment != owner.environment ||
            context.authority != owner.authority ||
            context.subject != owner.subject)) {
      throw const FormatException();
    }
    return response;
  }

  void _retire() {
    _retired = true;
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
