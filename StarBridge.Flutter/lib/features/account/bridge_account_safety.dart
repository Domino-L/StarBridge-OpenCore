import 'dart:async';

import '../../platform/bridge/bridge_account_access.dart';
import '../../platform/bridge/bridge_client_session.dart';
import '../../platform/bridge/bridge_envelope.dart';
import 'account_safety.dart';

final class BridgeAccountSafety implements AccountSafetyPort {
  BridgeAccountSafety(this._session) {
    _subscription = _session?.events.listen((event) {
      if (event.name == 'account.changed' ||
          event.name == 'bootstrap.invalidated') {
        _epoch++;
        unawaited(_pending?.cancel());
        _invalidations.add(null);
      }
    });
  }
  final BridgeClientSession? _session;
  StreamSubscription<BridgeEnvelope>? _subscription;
  BridgeRequestOperation? _pending;
  final _invalidations = StreamController<void>.broadcast();
  bool _closed = false;
  int _epoch = 0;
  @override
  Stream<void> get invalidations => _invalidations.stream;

  @override
  bool get canSubmit =>
      !_closed &&
      (_session?.hostCapabilities.contains('accountSafety.appeal') ?? false);

  @override
  Future<AccountAppealOutcome> submit(
    String sanctionId,
    String details,
    String requestId,
  ) async {
    final session = _session;
    if (!canSubmit || session == null) return AccountAppealOutcome.rejected;
    final epoch = ++_epoch;
    try {
      _pending = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      if (_closed || epoch != _epoch || !hasRelayAccount(account)) {
        return AccountAppealOutcome.sessionChanged;
      }
      _pending = session.beginRequest(
        'accountSafety.appeal',
        accountContext: account.accountContext,
        payload: {
          'schemaVersion': 1,
          'sanctionId': sanctionId,
          'details': details,
          'clientRequestId': requestId,
        },
        timeout: const Duration(seconds: 30),
      );
      final response = await _pending!.future;
      if (_closed || epoch != _epoch) {
        return AccountAppealOutcome.sessionChanged;
      }
      if (response.payload['schemaVersion'] != 1) {
        return AccountAppealOutcome.unknown;
      }
      return switch (response.payload['outcome']) {
        'submitted' => AccountAppealOutcome.submitted,
        'alreadySubmitted' => AccountAppealOutcome.alreadySubmitted,
        _ => AccountAppealOutcome.unknown,
      };
    } on BridgeClientException catch (error) {
      return switch (error.code) {
        'accountSafety.rejected' ||
        'accountSafety.forbidden' ||
        'accountSafety.target_unavailable' ||
        'accountSafety.invalid_request' => AccountAppealOutcome.rejected,
        _ => AccountAppealOutcome.unknown,
      };
    } catch (_) {
      return AccountAppealOutcome.unknown;
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  Future<AccountSafetySnapshot> read() async {
    final session = _session;
    if (_closed ||
        session == null ||
        !session.hostCapabilities.contains('accountSafety.read')) {
      throw const AccountSafetyException(AccountSafetyFailure.unavailable);
    }
    final epoch = ++_epoch;
    void current() {
      if (_closed || epoch != _epoch) {
        throw const AccountSafetyException(AccountSafetyFailure.signedOut);
      }
    }

    try {
      _pending = session.beginRequest(
        'account.getCurrent',
        payload: const {'schemaVersion': 1},
      );
      final account = await _pending!.future;
      current();
      if (!hasRelayAccount(account)) {
        throw const AccountSafetyException(AccountSafetyFailure.signedOut);
      }
      _pending = session.beginRequest(
        'accountSafety.read',
        accountContext: account.accountContext,
        payload: const {'schemaVersion': 1},
        timeout: const Duration(seconds: 18),
      );
      final response = await _pending!.future;
      current();
      return AccountSafetySnapshot.parse(response.payload);
    } on BridgeClientException catch (error) {
      throw AccountSafetyException(switch (error.code) {
        'accountSafety.identity_unavailable' ||
        'account.reauthorization_required' => AccountSafetyFailure.signedOut,
        'accountSafety.forbidden' => AccountSafetyFailure.forbidden,
        'accountSafety.data_invalid' => AccountSafetyFailure.invalid,
        _ => AccountSafetyFailure.connection,
      });
    } on FormatException {
      throw const AccountSafetyException(AccountSafetyFailure.invalid);
    } finally {
      if (epoch == _epoch) _pending = null;
    }
  }

  @override
  void dispose() {
    _closed = true;
    _epoch++;
    unawaited(_pending?.cancel());
    unawaited(_subscription?.cancel());
    unawaited(_invalidations.close());
  }
}
