import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'recently_played_privacy_module.dart';

final class BridgeRecentlyPlayedPrivacy implements RecentlyPlayedPrivacyPort {
  BridgeRecentlyPlayedPrivacy(
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
      _session.hostCapabilities.contains('recentlyPlayed.privacyRead');
  bool get _canWrite =>
      !_closed &&
      _session.hostCapabilities.contains('recentlyPlayed.privacyWrite');

  @override
  Future<RecentlyPlayedPrivacySnapshot> read() async {
    if (!_canRead) {
      return const RecentlyPlayedPrivacySnapshot.unavailable(
        RecentlyPlayedPrivacyFailure.hostUnavailable,
      );
    }
    try {
      return _snapshot(await _request('recentlyPlayed.privacyRead'));
    } on _SignedOut {
      return const RecentlyPlayedPrivacySnapshot.signedOut();
    } on BridgeClientException catch (error) {
      return RecentlyPlayedPrivacySnapshot.unavailable(_failure(error.code));
    } on FormatException {
      return const RecentlyPlayedPrivacySnapshot.unavailable(
        RecentlyPlayedPrivacyFailure.invalidResponse,
      );
    } catch (_) {
      return const RecentlyPlayedPrivacySnapshot.unavailable(
        RecentlyPlayedPrivacyFailure.readFailed,
      );
    }
  }

  @override
  Future<RecentlyPlayedPrivacyWriteResult> save(
    bool enabled,
    int expectedRevision,
  ) async {
    if (!_canWrite) {
      return const RecentlyPlayedPrivacyWriteResult.rejected(
        RecentlyPlayedPrivacyFailure.hostUnavailable,
      );
    }
    try {
      final snapshot = _snapshot(
        await _request(
          'recentlyPlayed.privacyWrite',
          fields: {'enabled': enabled, 'expectedRevision': expectedRevision},
        ),
      );
      if (snapshot.enabled != enabled ||
          snapshot.revision == null ||
          snapshot.revision! < expectedRevision) {
        return await _confirmUncertainWrite(enabled, expectedRevision);
      }
      return RecentlyPlayedPrivacyWriteResult.completed(snapshot);
    } on _SignedOut {
      return const RecentlyPlayedPrivacyWriteResult.rejected(
        RecentlyPlayedPrivacyFailure.identityUnavailable,
      );
    } on BridgeClientException catch (error) {
      if (error.code == 'recentlyPlayed.privacy_outcome_unknown') {
        return _confirmUncertainWrite(enabled, expectedRevision);
      }
      return RecentlyPlayedPrivacyWriteResult.rejected(_failure(error.code));
    } on FormatException {
      return _confirmUncertainWrite(enabled, expectedRevision);
    } catch (_) {
      return _confirmUncertainWrite(enabled, expectedRevision);
    }
  }

  Future<RecentlyPlayedPrivacyWriteResult> _confirmUncertainWrite(
    bool expectedValue,
    int expectedRevision,
  ) async {
    var expectedEpoch = _epoch;
    for (final delay in _confirmationDelays) {
      if (!await _waitForConfirmation(delay, expectedEpoch)) {
        return const RecentlyPlayedPrivacyWriteResult.rejected(
          RecentlyPlayedPrivacyFailure.identityUnavailable,
        );
      }
      try {
        final snapshot = _snapshot(
          await _request(
            'recentlyPlayed.privacyRead',
            timeout: confirmationRequestTimeout,
          ),
        );
        expectedEpoch = _epoch;
        if (snapshot.enabled == expectedValue &&
            snapshot.revision != null &&
            snapshot.revision! >= expectedRevision) {
          return RecentlyPlayedPrivacyWriteResult.completed(snapshot);
        }
      } on _SignedOut {
        return const RecentlyPlayedPrivacyWriteResult.rejected(
          RecentlyPlayedPrivacyFailure.identityUnavailable,
        );
      } on BridgeClientException catch (error) {
        if (_failure(error.code) ==
            RecentlyPlayedPrivacyFailure.identityUnavailable) {
          return const RecentlyPlayedPrivacyWriteResult.rejected(
            RecentlyPlayedPrivacyFailure.identityUnavailable,
          );
        }
        expectedEpoch = _epoch;
      } catch (_) {
        expectedEpoch = _epoch;
      }
    }
    return const RecentlyPlayedPrivacyWriteResult.unknown();
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

  static RecentlyPlayedPrivacySnapshot _snapshot(Map<String, Object?> payload) {
    if (payload.length != 5 ||
        payload['schemaVersion'] != 1 ||
        payload['enabled'] is! bool ||
        payload['revision'] is! int ||
        (payload['enabledAt'] != null && payload['enabledAt'] is! String) ||
        (payload['disabledAt'] != null && payload['disabledAt'] is! String)) {
      throw const FormatException();
    }
    final revision = payload['revision']! as int;
    if (revision < 0) throw const FormatException();
    return RecentlyPlayedPrivacySnapshot.available(
      enabled: payload['enabled']! as bool,
      enabledAt: _date(payload['enabledAt']),
      disabledAt: _date(payload['disabledAt']),
      revision: revision,
    );
  }

  static DateTime? _date(Object? value) {
    if (value == null) return null;
    final parsed = DateTime.tryParse(value as String);
    if (parsed == null) throw const FormatException();
    return parsed;
  }

  static RecentlyPlayedPrivacyFailure _failure(String code) => switch (code) {
    'recentlyPlayed.identity_unavailable' ||
    'account.reauthorization_required' =>
      RecentlyPlayedPrivacyFailure.identityUnavailable,
    'recentlyPlayed.data_invalid' =>
      RecentlyPlayedPrivacyFailure.invalidResponse,
    'recentlyPlayed.write_conflict' =>
      RecentlyPlayedPrivacyFailure.writeConflict,
    'recentlyPlayed.privacy_outcome_unknown' =>
      RecentlyPlayedPrivacyFailure.outcomeUnknown,
    _ => RecentlyPlayedPrivacyFailure.readFailed,
  };

  void _cancel() {
    _epoch++;
    final delay = _confirmationDelay;
    _confirmationDelay = null;
    if (delay != null) {
      delay.timer.cancel();
      if (!delay.completer.isCompleted) delay.completer.complete(false);
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
