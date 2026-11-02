import 'dart:async';

import '../../app/composition/social_activity.dart';

import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import '../../platform/bridge/bridge_account_access.dart';
import 'friends_module.dart';
import 'friends_retained_display.dart';
import 'friends_online_display.dart';
import 'friends_snapshot_decoder.dart';
import 'friends_directory_read.dart';
import 'friends_command_directory.dart';
export 'friends_snapshot_decoder.dart' show parseFriendsSnapshot;

final class BridgeFriendsAdapter
    implements
        FriendsPort,
        FriendsCommandPort,
        FriendsActivityPort,
        FriendsCachedDisplayPort {
  BridgeFriendsAdapter(this._session) {
    _subscription = _session.events.listen(
      (event) {
        _retained?.observeEvent(event);
        if (event.name == 'account.changed' ||
            event.name == 'account.avatarChanged' ||
            event.name == 'bootstrap.invalidated') {
          if (event.name == 'account.changed' &&
              _retained?.hasHandoff == true) {
            return;
          }
          cancelPending();
          _publishCached(null);
          _invalidations.add(null);
        } else if (event.name == 'account.avatarChanged') {
          notifySocialReadChanged(_session);
        }
      },
      onDone: () {
        if (!_closed) {
          cancelPending();
          _publishCached(null);
          _invalidations.add(null);
        }
      },
    );
  }
  final BridgeClientSession _session;
  // Progress must reach the module before the same read's terminal result.
  final _cachedDisplays = StreamController<FriendsCachedDisplay?>.broadcast(
    sync: true,
  );
  bool _publishingCached = false, _queuedCached = false;
  FriendsCachedDisplay? _queuedDisplay;
  void _publishCached(FriendsCachedDisplay? value) {
    if (_closed) return;
    if (_publishingCached) {
      _queuedCached = true;
      _queuedDisplay = value;
      return;
    }
    _publishingCached = true;
    try {
      var next = value;
      do {
        _queuedCached = false;
        _cachedDisplays.add(next);
        next = _queuedDisplay;
      } while (_queuedCached && !_closed);
    } finally {
      _publishingCached = false;
      _queuedCached = false;
      _queuedDisplay = null;
    }
  }

  @override
  Stream<FriendsCachedDisplay?> get cachedDisplays => _cachedDisplays.stream;
  FriendsRetainedDisplay? _retained;
  FriendsOnlineDisplay? _onlineDisplay;
  FriendsDirectoryRead? _directoryRead;
  FriendsCommandDirectory? _commandDirectory;
  @override
  Stream<void> get changes => socialActivityChanges(_session);
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
    _commandDirectory?.dispose();
    _commandDirectory = null;
    _directoryRead?.dispose();
    _directoryRead = null;
    _retained?.dispose();
    _retained = null;
    _onlineDisplay?.dispose();
    _onlineDisplay = null;
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(pending.cancel());
  }

  @override
  Future<FriendsReadResult> read({String? query}) async {
    final epoch = ++_epoch;
    _commandDirectory?.dispose();
    _commandDirectory = null;
    _directoryRead?.dispose();
    _directoryRead = null;
    _retained?.dispose();
    _retained = null;
    _onlineDisplay?.dispose();
    _onlineDisplay = null;
    if (_session.connectionModeChanging) {
      return const FriendsReadResult(FriendsReadState.idle);
    }
    if (_closed || !_session.hostCapabilities.contains('friends.read')) {
      return const FriendsReadResult(
        FriendsReadState.unavailable,
        failure: 'hostUnavailable',
      );
    }
    try {
      final useRetained =
          query == null &&
          _session.hostCapabilities.contains('account.restoreDisplay');
      final retained = useRetained
          ? FriendsRetainedDisplay(
              _session,
              () => !_closed && epoch == _epoch,
              _publishCached,
            )
          : null;
      _retained = retained;
      _pending = retained == null
          ? _session.beginRequest(
              'account.getCurrent',
              payload: const {'schemaVersion': 1},
            )
          : null;
      final account = retained == null
          ? await _pending!.future
          : await retained.read();
      if (_closed || epoch != _epoch || _session.connectionModeChanging) {
        return const FriendsReadResult(FriendsReadState.idle);
      }
      if (account.payload['schemaVersion'] != 1) throw const FormatException();
      if (account.payload['state'] == 'signedOut' ||
          account.payload['state'] == 'reauthorizationRequired') {
        return const FriendsReadResult(FriendsReadState.signedOut);
      }
      if (!hasRelayAccount(account) || account.accountContext == null) {
        if (account.payload['state'] == 'credentialTemporarilyUnavailable' &&
            retained != null) {
          await retained.prepared;
          if (_closed || epoch != _epoch) {
            return const FriendsReadResult(FriendsReadState.idle);
          }
          if (retained.value != null) {
            return const FriendsReadResult(
              FriendsReadState.unavailable,
              failure: 'unavailable',
              transientFailure: true,
            );
          }
        }
        return const FriendsReadResult(
          FriendsReadState.unavailable,
          failure: 'identityUnavailable',
        );
      }
      final online =
          query == null &&
              _session.hostCapabilities.contains('friends.readDisplay')
          ? FriendsOnlineDisplay(
              _session,
              () => !_closed && epoch == _epoch,
              _publishCached,
              owner: account.accountContext,
            )
          : null;
      _onlineDisplay = online;
      final directoryRead = FriendsDirectoryRead(
        _session,
        account.accountContext!,
        () => !_closed && epoch == _epoch,
      );
      _directoryRead = directoryRead;
      final body = await directoryRead.read(
        query: query,
        displayProgress: online?.observer,
        onInitial: online?.attach,
      );
      if (body == null || _closed || epoch != _epoch) {
        return const FriendsReadResult(FriendsReadState.idle);
      }
      final snapshot = parseFriendsSnapshot(body);
      if (snapshot.query != query) throw const FormatException();
      online?.dispose();
      _onlineDisplay = null;
      return FriendsReadResult(FriendsReadState.ready, snapshot: snapshot);
    } on BridgeClientException catch (error) {
      return FriendsReadResult(
        FriendsReadState.unavailable,
        transientFailure:
            error is BridgeDisconnectedException ||
            error.code == 'bridge.timeout' ||
            error.code == 'friends.read_transient' && error.retryable,
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
      if (epoch == _epoch) {
        _pending = null;
        _directoryRead?.dispose();
        _directoryRead = null;
      }
    }
  }

  @override
  Future<FriendCommandResult> execute(String action, String targetRef) async {
    if (_session.connectionModeChanging) {
      return const FriendCommandResult('cancelled');
    }
    if (!commandsAvailable) {
      return const FriendCommandResult('rejected', error: 'hostUnavailable');
    }
    final epoch = ++_epoch;
    _commandDirectory?.dispose();
    _commandDirectory = null;
    _directoryRead?.dispose();
    _directoryRead = null;
    _retained?.dispose();
    _retained = null;
    _onlineDisplay?.dispose();
    _onlineDisplay = null;
    var dispatched = false;
    try {
      _pending = _session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (_session.connectionModeChanging) {
        return const FriendCommandResult('cancelled');
      }
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
      final directory = FriendsCommandDirectory(
        _session,
        account.accountContext!,
        () => !_closed && epoch == _epoch,
      );
      _commandDirectory = directory;
      final result = await directory.execute(action, targetRef);
      if (_closed || epoch != _epoch) {
        return const FriendCommandResult('unknown', error: 'outcomeUnknown');
      }
      return result;
    } catch (_) {
      return FriendCommandResult(
        dispatched ? 'unknown' : 'rejected',
        error: dispatched ? 'outcomeUnknown' : 'identityUnavailable',
      );
    } finally {
      if (epoch == _epoch) {
        _pending = null;
        _commandDirectory?.dispose();
        _commandDirectory = null;
      }
    }
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    cancelPending();
    await _subscription.cancel();
    await _invalidations.close();
    await _cachedDisplays.close();
  }
}
