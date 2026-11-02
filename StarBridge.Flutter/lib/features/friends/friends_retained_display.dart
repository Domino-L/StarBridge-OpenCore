import 'dart:async';

import '../account/account_models.dart';
import '../account/account_payload_decoder.dart';
import '../account/account_restore_display.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'friends_cached_display.dart';
import 'friends_module.dart';

/// Borrows the original root read's presentation lease, never a login owner.
final class FriendsRetainedDisplay {
  FriendsRetainedDisplay(this.session, this.current, this.publish) {
    account = AccountRestoreDisplay(session)..addListener(_changed);
    _unobserve = session.observeGenerationChanges((generation, accountEvent) {
      if (!accountEvent ||
          account.value?.displayHandoff?.generation != generation) {
        _clear();
      }
    });
    _unregister = session.registerConnectionModeNetworkWork(
      ConnectionModeNetworkWork(
        pause: () async {
          _clear();
        },
        reconcile: () async {},
      ),
    );
  }
  final BridgeClientSession session;
  final bool Function() current;
  final void Function(FriendsCachedDisplay?) publish;
  late final AccountRestoreDisplay account;
  void Function() _unregister = () {};
  void Function() _unobserve = () {};
  BridgeRequestOperation? _reading;
  Future<void>? _task;
  String? _id, _completedId;
  FriendsCachedDisplay? value;
  bool _disposed = false;
  int _readEpoch = 0;

  bool get hasHandoff => !_disposed && account.value?.hasDisplayHandoff == true;
  void observeEvent(BridgeEnvelope event) => account.observeEvent(event);

  Future<BridgeEnvelope> read() => account.read(
    const Duration(seconds: 15),
    onResponse: (response) {
      if (_disposed ||
          !current() ||
          response.status != 'ok' ||
          response.accountContext != null ||
          response.sessionGeneration != session.activeGeneration ||
          response.payload['state'] != 'credentialTemporarilyUnavailable') {
        return;
      }
      try {
        final display = AccountPayloadDecoder.retainedDisplay(
          response,
          AccountSessionState.credentialTemporarilyUnavailable,
        );
        if (display?.readId != null) {
          _completedId = display!.readId;
          _load(display.readId!, response.sessionGeneration);
        }
      } on BridgeFormatException {
        _clear();
      }
    },
  );

  Future<void> get prepared => _task ?? Future.value();

  void _changed() {
    if (_disposed || !current()) return;
    final display = account.value;
    if (display?.hasRetainedDisplayRead == true) {
      _load(display!.retainedReadId!, display.generation);
    } else if (display?.hasDisplayHandoff == true) {
      _retireRead();
      if (_id != display!.displayHandoff!.displayKey) _clear();
    } else if (_completedId == null) {
      _clear();
    }
  }

  void _load(String id, int generation) {
    if (_disposed || !current() || session.connectionModeChanging) return;
    if (_disposed ||
        !current() ||
        !session.hostCapabilities.contains('account.offlineData.read')) {
      return;
    }
    if (_id == id && (value != null || _reading != null)) return;
    _retireRead();
    if (_id != null && _id != id) {
      value = null;
      publish(null);
    }
    _id = id;
    final epoch = _readEpoch;
    bool live() =>
        !_disposed &&
        current() &&
        _id == id &&
        epoch == _readEpoch &&
        generation == session.activeGeneration &&
        !session.connectionModeChanging;
    final paged = session.hostCapabilities.contains('friends.readPages');
    var operation = session.beginRequest(
      'account.offlineData.read',
      payload: {
        'schemaVersion': 1,
        'kind': 'friends',
        'readId': id,
        if (paged) 'pagedResponse': true,
      },
    );
    _reading = operation;
    if (!live()) unawaited(operation.cancel());
    _task = () async {
      final deadline = Timer(const Duration(seconds: 15), () {
        if (live()) _clear();
      });
      try {
        final pages = paged ? FriendsCachedPages() : null;
        while (true) {
          final response = await operation.future;
          if (!identical(_reading, operation) || !live()) return;
          if (response.name != 'account.offlineData.read' ||
              response.accountContext != null ||
              response.sessionGeneration != generation) {
            throw const FormatException();
          }
          final complete = pages == null
              ? decodeFriendsCachedDisplay(response.payload)
              : pages.add(response.payload);
          if (complete != null) {
            value = complete;
            publish(value);
            return;
          }
          if (pages == null) throw const FormatException();
          operation = session.beginRequest(
            'account.offlineData.read',
            payload: {
              'schemaVersion': 1,
              'kind': 'friends',
              'readId': id,
              'pagedResponse': true,
              'snapshotId': pages.snapshotId,
              'offset': pages.nextOffset,
            },
          );
          _reading = operation;
          if (!live()) unawaited(operation.cancel());
        }
      } catch (_) {
        if (identical(_reading, operation) && live()) _clear();
      } finally {
        deadline.cancel();
        if (identical(_reading, operation)) _reading = null;
      }
    }();
  }

  void _retireRead() {
    _readEpoch++;
    final reading = _reading;
    _reading = null;
    if (reading != null) unawaited(reading.cancel());
  }

  void _clear() {
    _retireRead();
    _id = null;
    _completedId = null;
    value = null;
    if (!_disposed && current()) publish(null);
  }

  void dispose() {
    if (_disposed) return;
    _disposed = true;
    _retireRead();
    _unregister();
    _unobserve();
    account.removeListener(_changed);
    account.dispose();
  }
}
