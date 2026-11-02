import 'dart:async';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'friends_cached_display.dart';
import 'friends_module.dart';

final class FriendsOnlineDisplay {
  FriendsOnlineDisplay(this.session, this.current, this.publish, {this.owner})
    : generation = session.activeGeneration {
    _unobserve = session.observeGenerationChanges((_, _) => _clear());
    _unregister = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          if (_disposed) return;
          final operation = _operation;
          _clear();
          await operation?.cancel();
        },
        reconcile: () async {},
      ),
    );
  }
  final BridgeClientSession session;
  final BridgeAccountContext? owner;
  final bool Function() current;
  final void Function(FriendsCachedDisplay?) publish;
  BridgeRequestOperation? _operation;
  BridgeRequestOperation? _pageOperation;
  bool _collecting = false;
  final int generation;
  void Function() _unobserve = () {}, _unregister = () {};
  bool _disposed = false, _retired = false;
  FriendsCachedDisplay? value;
  BridgeDisplayProgress get observer =>
      BridgeDisplayProgress('friends.readDisplay', _accept);
  void attach(BridgeRequestOperation operation) {
    _operation = operation;
    if (_disposed || _retired) unawaited(operation.cancel());
  }

  void _accept(BridgeEnvelope frame) {
    if (_disposed ||
        _retired ||
        !current() ||
        generation != session.activeGeneration ||
        frame.sessionGeneration != generation ||
        frame.accountContext != null) {
      return;
    }
    try {
      if ((frame.payload['directory'] as Map?)?.containsKey('page') == true) {
        if (_collecting ||
            owner == null ||
            !session.hostCapabilities.contains('friends.readPages')) {
          throw const FormatException();
        }
        _collecting = true;
        unawaited(_collect(frame.payload));
        return;
      }
      value = decodeFriendsCachedDisplay(frame.payload);
      publish(value);
    } on Object {
      _clear();
    }
  }

  bool get _live =>
      !_disposed &&
      !_retired &&
      current() &&
      generation == session.activeGeneration &&
      !session.connectionModeChanging;

  Future<void> _collect(Map<String, Object?> first) async {
    try {
      final pages = FriendsCachedPages();
      var complete = pages.add(first);
      while (complete == null) {
        if (!_live) return;
        final operation = session.beginRequest(
          'friends.readPage',
          accountContext: owner,
          payload: {
            'schemaVersion': 1,
            'snapshotId': pages.snapshotId,
            'offset': pages.nextOffset,
            'displayRequestId': first['requestCorrelationId'],
          },
        );
        _pageOperation = operation;
        if (!_live) unawaited(operation.cancel());
        final response = await operation.future;
        if (!identical(_pageOperation, operation) || !_live) return;
        _pageOperation = null;
        final context = response.accountContext;
        if (response.name != 'friends.readPage' ||
            response.sessionGeneration != generation ||
            context == null ||
            context.environment != owner!.environment ||
            context.authority != owner!.authority ||
            context.subject != owner!.subject) {
          throw const FormatException();
        }
        complete = pages.add({...first, 'directory': response.payload});
      }
      if (!_live) return;
      value = complete;
      publish(value);
    } on Object {
      // A completed authoritative HTTP read may retire an unfinished cache
      // transfer. Discard private pages, preserving any earlier full display.
    } finally {
      final operation = _pageOperation;
      _pageOperation = null;
      if (operation != null) unawaited(operation.cancel());
    }
  }

  void _clear() {
    if (_disposed || _retired) return;
    _retired = true;
    final operation = _pageOperation;
    _pageOperation = null;
    if (operation != null) unawaited(operation.cancel());
    value = null;
    if (current()) publish(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    final operation = _operation;
    _operation = null;
    if (operation != null) unawaited(operation.cancel());
    final pageOperation = _pageOperation;
    _pageOperation = null;
    if (pageOperation != null) unawaited(pageOperation.cancel());
    value = null;
    _unobserve();
    _unregister();
  }
}
