import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'direct_message_privacy_module.dart';

final class BridgeDirectMessagePrivacy implements DirectMessagePrivacyPort {
  BridgeDirectMessagePrivacy(
    this._session, {
    List<Duration> confirmationDelays = const [
      Duration.zero,
      Duration(milliseconds: 350),
      Duration(milliseconds: 1200),
    ],
    this._confirmationRequestTimeout = const Duration(seconds: 3),
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
  final Duration _confirmationRequestTimeout;
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
      _session.hostCapabilities.contains('directMessages.privacyRead');

  bool get _canWrite =>
      !_closed &&
      _session.hostCapabilities.contains('directMessages.privacyWrite');

  @override
  Future<DirectMessagePrivacySnapshot> read() async {
    if (!_canRead) {
      return const DirectMessagePrivacySnapshot.unavailable(
        DirectMessagePrivacyFailure.hostUnavailable,
      );
    }
    try {
      return _snapshot(await _request('directMessages.privacyRead'));
    } on _SignedOut {
      return const DirectMessagePrivacySnapshot.signedOut();
    } on BridgeClientException catch (error) {
      return DirectMessagePrivacySnapshot.unavailable(_failure(error.code));
    } on FormatException {
      return const DirectMessagePrivacySnapshot.unavailable(
        DirectMessagePrivacyFailure.invalidResponse,
      );
    } catch (_) {
      return const DirectMessagePrivacySnapshot.unavailable(
        DirectMessagePrivacyFailure.readFailed,
      );
    }
  }

  @override
  Future<DirectMessagePrivacyWriteResult> save(
    bool allowStrangerDirectMessages,
  ) async {
    if (!_canWrite) {
      return const DirectMessagePrivacyWriteResult.rejected(
        DirectMessagePrivacyFailure.hostUnavailable,
      );
    }
    try {
      final snapshot = _snapshot(
        await _request(
          'directMessages.privacyWrite',
          fields: {'allowStrangerDirectMessages': allowStrangerDirectMessages},
        ),
      );
      if (snapshot.allowStrangerDirectMessages != allowStrangerDirectMessages) {
        return await _confirmUncertainWrite(allowStrangerDirectMessages);
      }
      return DirectMessagePrivacyWriteResult.completed(snapshot);
    } on _SignedOut {
      return const DirectMessagePrivacyWriteResult.rejected(
        DirectMessagePrivacyFailure.identityUnavailable,
      );
    } on BridgeClientException catch (error) {
      if (error.code == 'directMessages.privacy_outcome_unknown') {
        return _confirmUncertainWrite(allowStrangerDirectMessages);
      }
      return DirectMessagePrivacyWriteResult.rejected(_failure(error.code));
    } on FormatException {
      return _confirmUncertainWrite(allowStrangerDirectMessages);
    } catch (_) {
      return _confirmUncertainWrite(allowStrangerDirectMessages);
    }
  }

  Future<DirectMessagePrivacyWriteResult> _confirmUncertainWrite(
    bool expectedValue,
  ) async {
    var expectedEpoch = _epoch;
    for (final delay in _confirmationDelays) {
      if (!await _waitForConfirmation(delay, expectedEpoch)) {
        return const DirectMessagePrivacyWriteResult.rejected(
          DirectMessagePrivacyFailure.identityUnavailable,
        );
      }
      try {
        final snapshot = _snapshot(
          await _request(
            'directMessages.privacyRead',
            timeout: _confirmationRequestTimeout,
          ),
        );
        expectedEpoch = _epoch;
        if (snapshot.allowStrangerDirectMessages == expectedValue) {
          return DirectMessagePrivacyWriteResult.completed(snapshot);
        }
      } on _SignedOut {
        return const DirectMessagePrivacyWriteResult.rejected(
          DirectMessagePrivacyFailure.identityUnavailable,
        );
      } on BridgeClientException catch (error) {
        if (_failure(error.code) ==
            DirectMessagePrivacyFailure.identityUnavailable) {
          return const DirectMessagePrivacyWriteResult.rejected(
            DirectMessagePrivacyFailure.identityUnavailable,
          );
        }
        expectedEpoch = _epoch;
      } catch (_) {
        expectedEpoch = _epoch;
      }
    }
    return const DirectMessagePrivacyWriteResult.unknown();
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

  static DirectMessagePrivacySnapshot _snapshot(Map<String, Object?> payload) {
    if (payload.length != 3 ||
        payload['schemaVersion'] != 1 ||
        payload['allowStrangerDirectMessages'] is! bool ||
        payload['updatedAt'] is! String) {
      throw const FormatException();
    }
    final updatedAt = DateTime.tryParse(payload['updatedAt']! as String);
    if (updatedAt == null) throw const FormatException();
    return DirectMessagePrivacySnapshot.available(
      allowStrangerDirectMessages:
          payload['allowStrangerDirectMessages']! as bool,
      updatedAt: updatedAt,
    );
  }

  static DirectMessagePrivacyFailure _failure(String code) => switch (code) {
    'directMessages.identity_unavailable' ||
    'account.reauthorization_required' =>
      DirectMessagePrivacyFailure.identityUnavailable,
    'directMessages.data_invalid' =>
      DirectMessagePrivacyFailure.invalidResponse,
    'directMessages.privacy_outcome_unknown' =>
      DirectMessagePrivacyFailure.outcomeUnknown,
    _ => DirectMessagePrivacyFailure.readFailed,
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
