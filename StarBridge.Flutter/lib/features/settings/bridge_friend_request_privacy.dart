import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'friend_request_privacy_module.dart';

final class BridgeFriendRequestPrivacy implements FriendRequestPrivacyPort {
  BridgeFriendRequestPrivacy(
    this._session, {
    List<Duration> confirmationDelays = const [
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 1200),
    ],
    this.confirmationRequestTimeout = const Duration(seconds: 3),
  }) : _confirmationDelays = List.unmodifiable(confirmationDelays),
       assert(confirmationDelays.isNotEmpty) {
    _subscription = _session.events.listen(
      (event) {
        if (event.name == 'account.changed' ||
            event.name == 'bootstrap.invalidated') {
          _cancel();
          _invalidations.add(null);
        }
      },
      onDone: () {
        if (!_closed) _invalidations.add(null);
      },
    );
  }

  final BridgeClientSession _session;
  final List<Duration> _confirmationDelays;
  final Duration confirmationRequestTimeout;
  final StreamController<void> _invalidations = StreamController.broadcast();
  late final StreamSubscription<BridgeEnvelope> _subscription;
  BridgeRequestOperation? _pending;
  _ConfirmationDelay? _confirmationDelay;
  int _epoch = 0;
  bool _closed = false;

  @override
  Stream<void> get invalidations => _invalidations.stream;

  bool get _canRead =>
      !_closed &&
      _session.hostCapabilities.contains('friendRequests.privacyRead');

  bool get _canWrite =>
      !_closed &&
      _session.hostCapabilities.contains('friendRequests.privacyWrite');

  @override
  Future<FriendRequestPrivacySnapshot> read() async {
    if (!_canRead) {
      return const FriendRequestPrivacySnapshot.unavailable(
        FriendRequestPrivacyFailure.hostUnavailable,
      );
    }
    try {
      return _snapshot(await _request('friendRequests.privacyRead'));
    } on _SignedOut {
      return const FriendRequestPrivacySnapshot.signedOut();
    } on BridgeClientException catch (error) {
      return FriendRequestPrivacySnapshot.unavailable(_failure(error.code));
    } on FormatException {
      return const FriendRequestPrivacySnapshot.unavailable(
        FriendRequestPrivacyFailure.invalidResponse,
      );
    } catch (_) {
      return const FriendRequestPrivacySnapshot.unavailable(
        FriendRequestPrivacyFailure.readFailed,
      );
    }
  }

  @override
  Future<FriendRequestPrivacyWriteResult> save(bool allowFriendRequests) async {
    if (!_canWrite) {
      return const FriendRequestPrivacyWriteResult.rejected(
        FriendRequestPrivacyFailure.hostUnavailable,
      );
    }
    try {
      final snapshot = _snapshot(
        await _request(
          'friendRequests.privacyWrite',
          fields: {'allowFriendRequests': allowFriendRequests},
        ),
      );
      if (snapshot.allowFriendRequests != allowFriendRequests) {
        return await _confirmUncertainWrite(allowFriendRequests);
      }
      return FriendRequestPrivacyWriteResult.completed(snapshot);
    } on _SignedOut {
      return const FriendRequestPrivacyWriteResult.rejected(
        FriendRequestPrivacyFailure.identityUnavailable,
      );
    } on BridgeClientException catch (error) {
      if (error.code == 'friendRequests.privacy_outcome_unknown') {
        return _confirmUncertainWrite(allowFriendRequests);
      }
      return FriendRequestPrivacyWriteResult.rejected(_failure(error.code));
    } on FormatException {
      return _confirmUncertainWrite(allowFriendRequests);
    } catch (_) {
      return _confirmUncertainWrite(allowFriendRequests);
    }
  }

  Future<FriendRequestPrivacyWriteResult> _confirmUncertainWrite(
    bool expectedValue,
  ) async {
    var expectedEpoch = _epoch;
    for (final delay in _confirmationDelays) {
      if (!await _waitForConfirmation(delay, expectedEpoch)) {
        return const FriendRequestPrivacyWriteResult.rejected(
          FriendRequestPrivacyFailure.identityUnavailable,
        );
      }
      try {
        final snapshot = _snapshot(
          await _request(
            'friendRequests.privacyRead',
            timeout: confirmationRequestTimeout,
          ),
        );
        expectedEpoch = _epoch;
        if (snapshot.allowFriendRequests == expectedValue) {
          return FriendRequestPrivacyWriteResult.completed(snapshot);
        }
      } on _SignedOut {
        return const FriendRequestPrivacyWriteResult.rejected(
          FriendRequestPrivacyFailure.identityUnavailable,
        );
      } on BridgeClientException catch (error) {
        if (_failure(error.code) ==
            FriendRequestPrivacyFailure.identityUnavailable) {
          return const FriendRequestPrivacyWriteResult.rejected(
            FriendRequestPrivacyFailure.identityUnavailable,
          );
        }
        expectedEpoch = _epoch;
      } catch (_) {
        expectedEpoch = _epoch;
      }
    }
    return const FriendRequestPrivacyWriteResult.unknown();
  }

  Future<bool> _waitForConfirmation(Duration duration, int expectedEpoch) {
    if (_closed || expectedEpoch != _epoch) return Future.value(false);
    if (duration == Duration.zero) return Future.value(true);
    final completer = Completer<bool>();
    late final _ConfirmationDelay pending;
    final timer = Timer(duration, () {
      if (identical(_confirmationDelay, pending)) _confirmationDelay = null;
      completer.complete(!_closed && expectedEpoch == _epoch);
    });
    pending = _ConfirmationDelay(timer, completer);
    _confirmationDelay = pending;
    return completer.future;
  }

  Future<Map<String, Object?>> _request(
    String name, {
    Map<String, Object?> fields = const {},
    Duration? timeout,
  }) async {
    final epoch = ++_epoch;
    _pending = _session.beginRequest(
      'account.getCurrent',
      payload: const {'schemaVersion': 1},
      timeout: timeout,
    );
    final account = await _pending!.future;
    if (_closed || epoch != _epoch) throw const _SignedOut();
    if (account.payload['schemaVersion'] != 1 ||
        !hasRelayAccount(account) ||
        account.accountContext == null) {
      throw const _SignedOut();
    }
    _pending = _session.beginRequest(
      name,
      accountContext: account.accountContext,
      payload: {'schemaVersion': 1, ...fields},
      timeout: timeout,
    );
    final response = await _pending!.future;
    if (_closed || epoch != _epoch) throw const _SignedOut();
    return response.payload;
  }

  static FriendRequestPrivacySnapshot _snapshot(Map<String, Object?> payload) {
    if (payload.length != 3 ||
        payload['schemaVersion'] != 1 ||
        payload['allowFriendRequests'] is! bool ||
        (payload['updatedAt'] != null && payload['updatedAt'] is! String)) {
      throw const FormatException();
    }
    final rawUpdatedAt = payload['updatedAt'];
    final updatedAt = rawUpdatedAt == null
        ? null
        : DateTime.tryParse(rawUpdatedAt as String);
    if (rawUpdatedAt != null && updatedAt == null) {
      throw const FormatException();
    }
    return FriendRequestPrivacySnapshot.available(
      allowFriendRequests: payload['allowFriendRequests']! as bool,
      updatedAt: updatedAt,
    );
  }

  static FriendRequestPrivacyFailure _failure(String code) => switch (code) {
    'friendRequests.identity_unavailable' ||
    'account.reauthorization_required' =>
      FriendRequestPrivacyFailure.identityUnavailable,
    'friendRequests.data_invalid' =>
      FriendRequestPrivacyFailure.invalidResponse,
    'friendRequests.privacy_outcome_unknown' =>
      FriendRequestPrivacyFailure.outcomeUnknown,
    _ => FriendRequestPrivacyFailure.readFailed,
  };

  void _cancel() {
    _epoch++;
    final confirmationDelay = _confirmationDelay;
    _confirmationDelay = null;
    if (confirmationDelay != null) {
      confirmationDelay.timer.cancel();
      if (!confirmationDelay.completer.isCompleted) {
        confirmationDelay.completer.complete(false);
      }
    }
    final pending = _pending;
    _pending = null;
    if (pending != null) unawaited(pending.cancel());
  }

  @override
  Future<void> close() async {
    if (_closed) return;
    _closed = true;
    _cancel();
    await _subscription.cancel();
    await _invalidations.close();
  }
}

final class _SignedOut implements Exception {
  const _SignedOut();
}

final class _ConfirmationDelay {
  const _ConfirmationDelay(this.timer, this.completer);

  final Timer timer;
  final Completer<bool> completer;
}
